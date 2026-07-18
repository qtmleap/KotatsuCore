import Foundation

public enum JellyfinAPIError: Error, Sendable, CustomStringConvertible {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case server(status: Int, body: String?)
    case decoding(underlying: String)
    case transport(underlying: String)
    case invalidResponse
    case missingField(String)

    public var description: String {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unauthorized: return "Unauthorized (401)"
        case .forbidden: return "Forbidden (403)"
        case .notFound: return "Not Found (404)"
        case .rateLimited: return "Rate Limited (429)"
        case let .server(status, body):
            return "Server error (\(status))" + (body.map { ": \($0)" } ?? "")
        case let .decoding(underlying): return "Decoding error: \(underlying)"
        case let .transport(underlying): return "Transport error: \(underlying)"
        case .invalidResponse: return "Invalid response"
        case let .missingField(name): return "Missing required field: \(name)"
        }
    }

    static func fromStatus(_ status: Int, body: String?) -> JellyfinAPIError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429: return .rateLimited
        default: return .server(status: status, body: body)
        }
    }
}
