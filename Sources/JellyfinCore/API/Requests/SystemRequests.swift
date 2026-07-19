import Foundation
import Alamofire

// MARK: - Public (no auth required)

struct SystemInfoPublicRequest: JFRequest {
    typealias Response = SystemInfoPublicDTO
    let method: HTTPMethod = .get
    var path: String { "/System/Info/Public" }
}

// MARK: - Authed

struct SystemInfoRequest: JFRequest {
    typealias Response = SystemInfoDTO
    let method: HTTPMethod = .get
    var path: String { "/System/Info" }
}

struct EncodingOptionsRequest: JFRequest {
    typealias Response = EncodingOptionsDTO
    let method: HTTPMethod = .get
    var path: String { "/System/Configuration/encoding" }
}

struct ActiveSessionsRequest: JFRequest {
    typealias Response = [ActiveSessionDTO]
    let method: HTTPMethod = .get
    var path: String { "/Sessions" }
    let activeWithinSeconds: Int?

    init(activeWithinSeconds: Int? = nil) {
        self.activeWithinSeconds = activeWithinSeconds
    }

    var query: [String: String?] {
        var q: [String: String?] = [:]
        if let activeWithinSeconds {
            q["ActiveWithinSeconds"] = "\(activeWithinSeconds)"
        }
        return q
    }
}
