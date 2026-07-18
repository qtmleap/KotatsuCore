import Foundation

public struct QuickConnectSession: Sendable, Codable, Hashable {
    public let code: String
    public let secret: String
    public let expiresAt: Date

    public init(code: String, secret: String, expiresAt: Date) {
        self.code = code
        self.secret = secret
        self.expiresAt = expiresAt
    }
}

public enum QuickConnectStatus: Sendable, Codable, Hashable {
    case pending
    case authenticated(UserProfile, accessToken: String)
    case expired
}
