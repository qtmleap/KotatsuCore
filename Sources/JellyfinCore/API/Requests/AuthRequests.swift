import Foundation
import Alamofire

// MARK: - Quick Connect

struct QuickConnectInitiateRequest: JFRequest {
    typealias Response = QuickConnectResultDTO
    let method: HTTPMethod = .post
    var path: String { "/QuickConnect/Initiate" }
}

struct QuickConnectPollRequest: JFRequest {
    typealias Response = QuickConnectResultDTO
    let method: HTTPMethod = .get
    var path: String { "/QuickConnect/Connect" }
    let secret: String
    var query: [String: String?] {
        ["Secret": secret]
    }
}

struct AuthenticateWithQuickConnectRequest: JFRequest {
    typealias Response = AuthenticationResultDTO
    let method: HTTPMethod = .post
    var path: String { "/Users/AuthenticateWithQuickConnect" }
    let secret: String
    var body: JFBody { .encodable(Body(secret: secret)) }

    struct Body: Encodable, Sendable {
        let secret: String
        enum CodingKeys: String, CodingKey { case secret = "Secret" }
    }
}

// MARK: - User

struct GetUserRequest: JFRequest {
    typealias Response = UserDTO
    let method: HTTPMethod = .get
    let userId: String
    var path: String { "/Users/\(userId)" }
}

// MARK: - Session

struct LogoutRequest: JFRequest {
    typealias Response = JFEmptyResponse
    let method: HTTPMethod = .post
    var path: String { "/Sessions/Logout" }
}
