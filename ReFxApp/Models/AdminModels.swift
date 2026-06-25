import Foundation
import SwiftUI

enum NodeState: String, Codable, Equatable {
    case provisioning = "PROVISIONING"
    case online = "ONLINE"
    case offline = "OFFLINE"
    case maintenance = "MAINTENANCE"
    case degraded = "DEGRADED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NodeState(rawValue: raw) ?? .unknown
    }

    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .online: return .appSuccess
        case .degraded, .maintenance, .provisioning: return .appWarning
        case .offline: return .appDestructive
        case .unknown: return .appMuted
        }
    }
}

struct RegionRef: Codable, Equatable {
    let name: String?
    let code: String?
}

/// `GET /admin/nodes` (admin). Decoded permissively — only what the UI shows.
struct NodeAdmin: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let fqdn: String?
    let state: NodeState
    let agentVersion: String?
    let maintenance: Bool?
    let region: RegionRef?
}

/// `GET /admin/nodes/:id/ping`.
struct NodePing: Decodable {
    let ms: Double?
    let reachable: Bool
    let heartbeatAgeMs: Double?
}

/// `GET /admin/users` (admin).
struct AdminUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let globalRole: UserRole?
    let state: String?

    var role: UserRole { globalRole ?? .unknown }
    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? email : name
    }
    var isSuspended: Bool { (state ?? "") == "SUSPENDED" || (state ?? "") == "BANNED" }
}
