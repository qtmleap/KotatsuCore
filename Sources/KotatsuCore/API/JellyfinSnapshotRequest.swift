import Foundation

/// One-shot request built from an immutable (server, token) snapshot. It never
/// touches the shared `JellyfinHTTPClient`, so a slow response can neither
/// observe nor mutate the active session. Requests are ephemeral, 8 seconds,
/// uncached, cookie-less, and refuse redirects outside the server's
/// scheme/host/port/base-path scope.
struct JellyfinSnapshotRequest: Sendable {
    static let timeout: TimeInterval = 8

    let server: Server
    let accessToken: String?
    let deviceId: String

    private final class ScopedRedirectDelegate: NSObject, URLSessionTaskDelegate,
        @unchecked Sendable
    {
        let scope: ServerScope
        init(scope: ServerScope) { self.scope = scope }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            completionHandler(scope.contains(request.url) ? request : nil)
        }
    }

    /// `path` must already be percent-encoded and start with `/`.
    func perform(
        _ method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil
    ) async throws -> Data {
        guard let scope = ServerScope(url: server.url),
            var components = URLComponents(url: server.url, resolvingAgainstBaseURL: false)
        else { throw JellyfinAPIError.invalidURL }
        components.user = nil
        components.password = nil
        components.queryItems = query.isEmpty ? nil : query
        components.fragment = nil
        components.percentEncodedPath = scope.basePath + path
        guard let url = components.url, scope.contains(url) else {
            throw JellyfinAPIError.invalidURL
        }

        let credentials = JellyfinCredentials(
            server: server, accessToken: accessToken, deviceId: deviceId)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.httpShouldHandleCookies = false
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(credentials.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken, !accessToken.isEmpty {
            request.setValue(accessToken, forHTTPHeaderField: "X-Emby-Token")
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.timeout
        config.timeoutIntervalForResource = Self.timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil
        let session = URLSession(
            configuration: config, delegate: ScopedRedirectDelegate(scope: scope),
            delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw JellyfinAPIError.transport(underlying: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw JellyfinAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if (300..<400).contains(http.statusCode) {
                throw JellyfinAPIError.transport(
                    underlying: "Redirected outside the server address; enter the canonical URL")
            }
            throw JellyfinAPIError.fromStatus(
                http.statusCode, body: String(data: data.prefix(400), encoding: .utf8))
        }
        return data
    }

    /// Percent-encodes one raw id as a single path segment.
    static func pathSegment(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }
}
