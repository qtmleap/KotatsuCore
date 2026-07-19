import Foundation
import Alamofire
import os

/// The set of dynamic values needed to construct a Jellyfin
/// `Authorization: MediaBrowser ...` header. Mutable so we can swap the
/// access token in place after a Quick Connect authentication succeeds.
public struct JellyfinCredentials: Sendable {
    public var server: Server
    public var accessToken: String?
    public var userId: String?
    public var deviceId: String
    public var deviceName: String
    public var clientName: String
    public var clientVersion: String

    public init(
        server: Server,
        accessToken: String? = nil,
        userId: String? = nil,
        deviceId: String = DeviceProfileBuilder.persistentDeviceId(),
        deviceName: String = "Apple TV",
        clientName: String = "Jellyfin-tvOS",
        clientVersion: String = "1.0.0"
    ) {
        self.server = server
        self.accessToken = accessToken
        self.userId = userId
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.clientName = clientName
        self.clientVersion = clientVersion
    }

    /// The value for the `Authorization` request header. Jellyfin still
    /// accepts the legacy `MediaBrowser` scheme; sending Client / Device /
    /// DeviceId / Version is mandatory even when no token is present
    /// (needed for `/Users/AuthenticateByName` and Quick Connect).
    public var authorizationHeader: String {
        var parts: [String] = [
            "Client=\"\(clientName)\"",
            "Device=\"\(deviceName)\"",
            "DeviceId=\"\(deviceId)\"",
            "Version=\"\(clientVersion)\""
        ]
        if let accessToken, !accessToken.isEmpty {
            parts.insert("Token=\"\(accessToken)\"", at: 0)
        }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }
}

/// Thread-safe mutable state box used by the HTTP client. All access is
/// serialised via `OSAllocatedUnfairLock`.
final class JellyfinHTTPState: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<Storage>(initialState: Storage())

    struct Storage {
        var credentials = JellyfinCredentials(server: Server(id: "", name: "", url: URL(string: "about:blank")!))
        var onUnauthorized: (@Sendable () -> Void)?
    }

    init(credentials: JellyfinCredentials) {
        lock.withLock { $0.credentials = credentials }
    }

    var credentials: JellyfinCredentials { lock.withLock { $0.credentials } }

    func updateCredentials(_ transform: @Sendable (inout JellyfinCredentials) -> Void) {
        lock.withLock { transform(&$0.credentials) }
    }

    func setOnUnauthorized(_ callback: (@Sendable () -> Void)?) {
        lock.withLock { $0.onUnauthorized = callback }
    }

    func fireUnauthorized() {
        let cb = lock.withLock { $0.onUnauthorized }
        cb?()
    }
}

/// Alamofire adapter that injects the Jellyfin `Authorization` header, the
/// `X-Emby-Token` shortcut header (still honoured by all supported server
/// versions and cheaper for the server to parse), and standard `Accept` /
/// `Content-Type` defaults.
final class JellyfinRequestInterceptor: RequestInterceptor, @unchecked Sendable {
    private let state: JellyfinHTTPState
    init(state: JellyfinHTTPState) { self.state = state }

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var request = urlRequest
        let creds = state.credentials
        request.setValue(creds.authorizationHeader, forHTTPHeaderField: "Authorization")
        if let token = creds.accessToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        if request.httpBody != nil, request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        completion(.success(request))
    }

    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
        if let statusCode = request.response?.statusCode, statusCode == 401 {
            state.fireUnauthorized()
        }
        completion(.doNotRetry)
    }
}

/// A shared JSONDecoder that handles Jellyfin's PascalCase field names and
/// ISO8601 dates (with and without fractional seconds).
public enum JellyfinJSON {
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            // ISO8601DateFormatter is not Sendable, so build one per call.
            // Jellyfin can send either with or without fractional seconds
            // depending on version/setting.
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = withFrac.date(from: str) { return d }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let d = plain.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(str)")
        }
        return d
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

/// The core HTTP surface. All Jellyfin service implementations go through
/// this one type so we have exactly one place that knows about auth,
/// error mapping, decoding, and cancellation.
public final class JellyfinHTTPClient: @unchecked Sendable {
    private let session: Session
    private let state: JellyfinHTTPState

    public init(
        server: Server,
        accessToken: String? = nil,
        userId: String? = nil,
        deviceId: String = DeviceProfileBuilder.persistentDeviceId(),
        deviceName: String = "Apple TV",
        clientName: String = "Jellyfin-tvOS",
        clientVersion: String = "1.0.0"
    ) {
        let creds = JellyfinCredentials(
            server: server,
            accessToken: accessToken,
            userId: userId,
            deviceId: deviceId,
            deviceName: deviceName,
            clientName: clientName,
            clientVersion: clientVersion
        )
        let state = JellyfinHTTPState(credentials: creds)
        self.state = state
        let config = URLSessionConfiguration.af.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        // Sized so a full home refresh (shelves + a couple of series detail
        // fetches) fits comfortably in memory, plus a disk backing that
        // survives a relaunch. Serves as a safety net for the ~120s
        // Cloudflare read timeout: subsequent same-URL fetches can fall
        // back to the last-good response instead of a decode failure.
        config.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
        config.requestCachePolicy = .useProtocolCachePolicy
        // Jellyfin rarely emits Cache-Control on JSON endpoints, so URLSession
        // wouldn't store the response by default. `ResponseCacher.cache`
        // forces every 2xx into `URLCache` regardless of server headers.
        self.session = Session(
            configuration: config,
            interceptor: JellyfinRequestInterceptor(state: state),
            cachedResponseHandler: ResponseCacher.cache
        )
    }

    // MARK: - Credentials

    public var server: Server { state.credentials.server }
    public var userId: String? { state.credentials.userId }
    public var accessToken: String? { state.credentials.accessToken }
    public var deviceId: String { state.credentials.deviceId }

    /// The `Authorization: MediaBrowser …` header value that would be sent
    /// with the current credentials. Exposed so non-Alamofire callers (e.g.
    /// the image loader that hits `/Users/{id}/Images/Primary` on its own
    /// `URLSession`) can attach the same auth as the API client.
    public var authorizationHeaderValue: String {
        state.credentials.authorizationHeader
    }

    public func setOnUnauthorized(_ callback: (@Sendable () -> Void)?) {
        state.setOnUnauthorized(callback)
    }

    public func updateCredentials(accessToken: String?, userId: String?) {
        state.updateCredentials { creds in
            creds.accessToken = accessToken
            creds.userId = userId
        }
    }

    public func updateServer(_ server: Server) {
        state.updateCredentials { $0.server = server }
    }

    // MARK: - Request

    public func request<T: Decodable & Sendable>(
        _ method: HTTPMethod,
        path: String,
        query: [String: String?] = [:],
        body: (any Encodable & Sendable)? = nil,
        as type: T.Type = T.self,
        decoder: JSONDecoder = JellyfinJSON.decoder
    ) async throws -> T {
        let request = try buildRequest(method: method, path: path, query: query, body: body)
        return try await performDecoding(request, as: type, decoder: decoder)
    }

    /// Void response (2xx accepted, body discarded). Used for POST/DELETE
    /// endpoints like `/Sessions/Playing`, favourites, watched state, etc.
    public func send(
        _ method: HTTPMethod,
        path: String,
        query: [String: String?] = [:],
        body: (any Encodable & Sendable)? = nil
    ) async throws {
        let request = try buildRequest(method: method, path: path, query: query, body: body)
        _ = try await performRaw(request)
    }

    /// Raw request that returns the response body bytes; useful when the
    /// caller wants to decode with a bespoke strategy.
    public func requestData(
        _ method: HTTPMethod,
        path: String,
        query: [String: String?] = [:],
        body: (any Encodable & Sendable)? = nil
    ) async throws -> Data {
        let request = try buildRequest(method: method, path: path, query: query, body: body)
        return try await performRaw(request)
    }

    /// Post an arbitrary JSON dictionary. Used for endpoints like
    /// `/Items/{id}/PlaybackInfo` where the body includes the DeviceProfile,
    /// which is expressed as `[String: Any]` rather than a Codable struct.
    public func requestJSON<T: Decodable & Sendable>(
        _ method: HTTPMethod,
        path: String,
        query: [String: String?] = [:],
        jsonBody: [String: Any],
        as type: T.Type = T.self,
        decoder: JSONDecoder = JellyfinJSON.decoder
    ) async throws -> T {
        let bodyData = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
        var request = try buildRequest(method: method, path: path, query: query, body: nil)
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await performDecoding(request, as: type, decoder: decoder)
    }

    // MARK: - Internals

    private func buildRequest(
        method: HTTPMethod,
        path: String,
        query: [String: String?],
        body: (any Encodable & Sendable)?
    ) throws -> URLRequest {
        let baseURL = state.credentials.server.url
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw JellyfinAPIError.invalidURL
        }
        var basePath = baseURL.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        let normalisedPath = path.hasPrefix("/") ? path : "/" + path
        components.path = basePath + normalisedPath
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty {
            components.queryItems = items
        }
        guard let finalURL = components.url else { throw JellyfinAPIError.invalidURL }
        var request = URLRequest(url: finalURL)
        request.httpMethod = method.rawValue
        if let body {
            request.httpBody = try JellyfinJSON.encoder.encode(AnyEncodable(body))
        }
        return request
    }

    private func performRaw(_ urlRequest: URLRequest) async throws -> Data {
        let method = urlRequest.httpMethod ?? "?"
        let url = urlRequest.url?.absoluteString ?? "<no-url>"
        AppLogger.debug("→ \(method) \(url)")
        return try await withCheckedThrowingContinuation { [session] continuation in
            session.request(urlRequest)
                .validate(statusCode: 200..<300)
                .responseData(queue: .global(qos: .userInitiated)) { response in
                    switch response.result {
                    case let .success(data):
                        let status = response.response?.statusCode ?? 0
                        AppLogger.debug("← \(status) \(method) \(url) (\(data.count) bytes)")
                        continuation.resume(returning: data)
                    case let .failure(error):
                        let status = response.response?.statusCode ?? 0
                        let body = response.data.flatMap { String(data: $0, encoding: .utf8) }
                        let bodyExcerpt = body.map { String($0.prefix(400)) } ?? "<no-body>"
                        if status >= 400 {
                            AppLogger.warning("← \(status) \(method) \(url) body=\(bodyExcerpt)")
                            continuation.resume(throwing: JellyfinAPIError.fromStatus(status, body: body))
                        } else {
                            AppLogger.error("✕ \(method) \(url) transport=\(error.localizedDescription)")
                            continuation.resume(throwing: JellyfinAPIError.transport(underlying: error.localizedDescription))
                        }
                    }
                }
        }
    }

    private func performDecoding<T: Decodable & Sendable>(
        _ urlRequest: URLRequest,
        as type: T.Type,
        decoder: JSONDecoder
    ) async throws -> T {
        let data = try await performRaw(urlRequest)
        if data.isEmpty {
            // Some Jellyfin endpoints return 204 with no body on success.
            if let empty = try? decoder.decode(T.self, from: Data("null".utf8)) {
                return empty
            }
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            AppLogger.error("Decoding failed for \(String(describing: T.self)): \(String(describing: error))")
            throw JellyfinAPIError.decoding(underlying: String(describing: error))
        }
    }

    // MARK: - Unauthenticated

    /// One-off request against an arbitrary URL that doesn't need auth (used
    /// for `/System/Info/Public` during server discovery).
    public static func discover(url: URL) async throws -> SystemInfoPublicDTO {
        try await withCheckedThrowingContinuation { continuation in
            let full = url.appendingPathComponent("System/Info/Public")
            AF.request(full)
                .validate(statusCode: 200..<300)
                .responseData(queue: .global(qos: .userInitiated)) { response in
                    switch response.result {
                    case let .success(data):
                        do {
                            let info = try JellyfinJSON.decoder.decode(SystemInfoPublicDTO.self, from: data)
                            continuation.resume(returning: info)
                        } catch {
                            continuation.resume(throwing: JellyfinAPIError.decoding(underlying: String(describing: error)))
                        }
                    case let .failure(error):
                        let status = response.response?.statusCode ?? 0
                        let body = response.data.flatMap { String(data: $0, encoding: .utf8) }
                        if status >= 400 {
                            continuation.resume(throwing: JellyfinAPIError.fromStatus(status, body: body))
                        } else {
                            continuation.resume(throwing: JellyfinAPIError.transport(underlying: error.localizedDescription))
                        }
                    }
                }
        }
    }
}

/// Type-erased Encodable used so we can accept any Encodable body without
/// making every service generic on its request type.
struct AnyEncodable: Encodable {
    let base: any Encodable
    init(_ base: any Encodable) { self.base = base }
    func encode(to encoder: Encoder) throws { try base.encode(to: encoder) }
}

// MARK: - JFRequest send

public extension JellyfinHTTPClient {
    /// Execute a `JFRequest` and decode the response into `R.Response`.
    /// For endpoints that return no body, use `Response = JFEmptyResponse` and
    /// the response is discarded.
    func send<R: JFRequest>(_ request: R, decoder: JSONDecoder = JellyfinJSON.decoder) async throws -> R.Response {
        let urlRequest = try makeURLRequest(for: request)
        if R.Response.self == JFEmptyResponse.self {
            _ = try await performRawPublic(urlRequest)
            // Safe: the compile-time == on metatypes guarantees the cast.
            return JFEmptyResponse() as! R.Response
        }
        return try await performDecodingPublic(urlRequest, as: R.Response.self, decoder: decoder)
    }

    /// Build the `URLRequest` for a JFRequest without sending it. Exposed for
    /// tests that want to verify path/method/body encoding end-to-end.
    func makeURLRequest<R: JFRequest>(for request: R) throws -> URLRequest {
        let url = try request.buildURL(baseURL: state.credentials.server.url)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        if let body = try request.bodyData() {
            urlRequest.httpBody = body
            if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        return urlRequest
    }
}

// Bridge private performRaw / performDecoding to the extension above.
extension JellyfinHTTPClient {
    fileprivate func performRawPublic(_ urlRequest: URLRequest) async throws -> Data {
        try await performRaw(urlRequest)
    }
    fileprivate func performDecodingPublic<T: Decodable & Sendable>(
        _ urlRequest: URLRequest,
        as type: T.Type,
        decoder: JSONDecoder
    ) async throws -> T {
        try await performDecoding(urlRequest, as: type, decoder: decoder)
    }
}
