import Foundation
import Alamofire

/// Empty response marker for void endpoints (POST /Sessions/Playing etc.).
public struct JFEmptyResponse: Decodable, Sendable {
    public init() {}
    public init(from decoder: Decoder) throws {}
}

/// A single Jellyfin REST endpoint bound to the response type it returns.
///
/// Modelled on SplatNet3's `RequestType`: each concrete request struct declares
/// its `Response`, path, query and body, so callers no longer have to name the
/// response type at the call site. `JellyfinHTTPClient.send(_:)` picks up the
/// binding via the associated type.
public protocol JFRequest: Sendable {
    associatedtype Response: Decodable & Sendable = JFEmptyResponse
    var method: HTTPMethod { get }
    var path: String { get }
    var query: [String: String?] { get }
    var body: JFBody { get }
}

public extension JFRequest {
    var query: [String: String?] { [:] }
    var body: JFBody { .none }
}

/// Body payload for a `JFRequest`. Encodable covers the common Codable-DTO
/// case; `rawJSON` is an escape hatch for endpoints like
/// `/Items/{id}/PlaybackInfo` whose DeviceProfile is an arbitrary `[String: Any]`.
public enum JFBody: Sendable {
    case none
    case encodable(any Encodable & Sendable)
    case rawJSON(Data)

    public static func json(_ dict: [String: Any]) -> JFBody {
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [])) ?? Data("{}".utf8)
        return .rawJSON(data)
    }
}

public extension JFRequest {
    /// Compose the fully-qualified request URL against a server's base URL.
    /// Exposed so tests can verify path/query construction without hitting
    /// the network.
    func buildURL(baseURL: URL) throws -> URL {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw JellyfinAPIError.invalidURL
        }
        var basePath = baseURL.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        let normalisedPath = path.hasPrefix("/") ? path : "/" + path
        comps.path = basePath + normalisedPath
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty {
            // Sort for deterministic ordering (helps test assertions).
            comps.queryItems = items.sorted { $0.name < $1.name }
        }
        guard let url = comps.url else { throw JellyfinAPIError.invalidURL }
        return url
    }

    /// Encode the body into `Data`, returning nil when the request has no body.
    func bodyData(encoder: JSONEncoder = JellyfinJSON.encoder) throws -> Data? {
        switch body {
        case .none:
            return nil
        case .encodable(let value):
            return try encoder.encode(AnyEncodable(value))
        case .rawJSON(let data):
            return data
        }
    }
}
