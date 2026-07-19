import Foundation

/// Response for `GET /QuickConnect/Initiate`. `Secret` is used to poll,
/// `Code` is displayed to the user for confirmation on another device.
public struct QuickConnectResultDTO: Codable, Sendable {
    public let authenticated: Bool?
    public let secret: String
    public let code: String
    public let deviceId: String?
    public let deviceName: String?
    public let appName: String?
    public let appVersion: String?
    public let dateAdded: Date?

    private enum CodingKeys: String, CodingKey {
        case authenticated = "Authenticated"
        case secret = "Secret"
        case code = "Code"
        case deviceId = "DeviceId"
        case deviceName = "DeviceName"
        case appName = "AppName"
        case appVersion = "AppVersion"
        case dateAdded = "DateAdded"
    }

    public func toDomain() -> QuickConnectSession {
        QuickConnectSession(
            code: code,
            secret: secret,
            // Jellyfin does not send an explicit expiry; documented default is 10 minutes.
            expiresAt: (dateAdded ?? Date()).addingTimeInterval(600)
        )
    }
}

/// Response for `POST /Users/AuthenticateWithQuickConnect` (and legacy
/// `AuthenticateByName`). Contains the freshly-minted access token plus the
/// authenticated user's profile.
public struct AuthenticationResultDTO: Codable, Sendable {
    public let user: UserDTO?
    public let sessionInfo: SessionInfoDTO?
    public let accessToken: String
    public let serverId: String?

    private enum CodingKeys: String, CodingKey {
        case user = "User"
        case sessionInfo = "SessionInfo"
        case accessToken = "AccessToken"
        case serverId = "ServerId"
    }
}

public struct UserDTO: Codable, Sendable {
    public let id: String
    public let name: String
    public let serverId: String?
    public let primaryImageTag: String?
    public let hasPassword: Bool?
    public let policy: UserPolicyDTO?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case serverId = "ServerId"
        case primaryImageTag = "PrimaryImageTag"
        case hasPassword = "HasPassword"
        case policy = "Policy"
    }

    public func toDomain(server: Server) -> UserProfile {
        var imageURL: URL?
        if let tag = primaryImageTag, !tag.isEmpty {
            imageURL = server.url
                .appendingPathComponent("Users")
                .appendingPathComponent(id)
                .appendingPathComponent("Images")
                .appendingPathComponent("Primary")
            var comps = URLComponents(url: imageURL!, resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "tag", value: tag), URLQueryItem(name: "quality", value: "90")]
            imageURL = comps.url
        }
        return UserProfile(
            id: id,
            name: name,
            serverId: serverId ?? server.id,
            primaryImageURL: imageURL,
            hasParentalControls: policy?.hasParentalControls ?? false
        )
    }
}

/// Subset of `UserPolicy` from the OpenAPI spec. The removed
/// `IsParentalScheduleAllowed` field does **not** exist in Jellyfin 10.x —
/// the actual parental knobs are `MaxParentalRating` and `AccessSchedules`.
public struct UserPolicyDTO: Codable, Sendable {
    public let isAdministrator: Bool?
    public let maxParentalRating: Int?
    public let accessSchedules: [AccessScheduleDTO]?

    private enum CodingKeys: String, CodingKey {
        case isAdministrator = "IsAdministrator"
        case maxParentalRating = "MaxParentalRating"
        case accessSchedules = "AccessSchedules"
    }

    /// A user is considered "parental-controlled" when the admin has set
    /// either an age-rating cap or a time-of-day access schedule.
    var hasParentalControls: Bool {
        (maxParentalRating != nil) || !(accessSchedules ?? []).isEmpty
    }
}

/// Time-of-day access restriction attached to a user policy. We decode only
/// what we need to detect that a schedule exists.
public struct AccessScheduleDTO: Codable, Sendable {
    public let dayOfWeek: String?
    public let startHour: Double?
    public let endHour: Double?

    private enum CodingKeys: String, CodingKey {
        case dayOfWeek = "DayOfWeek"
        case startHour = "StartHour"
        case endHour = "EndHour"
    }
}

public struct SessionInfoDTO: Codable, Sendable {
    public let id: String?
    public let userId: String?
    public let deviceId: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case userId = "UserId"
        case deviceId = "DeviceId"
    }
}
