import Foundation

enum DbEngine: String, Codable, CaseIterable, Identifiable, Equatable {
    case mysql = "MYSQL"
    case mariadb = "MARIADB"
    case postgresql = "POSTGRESQL"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DbEngine(rawValue: raw) ?? .unknown
    }

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mysql: return "MySQL"
        case .mariadb: return "MariaDB"
        case .postgresql: return "PostgreSQL"
        case .unknown: return "Unknown"
        }
    }
}

/// `GET /servers/:id/databases` (password stripped). Create/rotate additionally
/// return a one-time `password`.
struct ServerDatabase: Codable, Identifiable, Equatable {
    let id: String
    let engine: DbEngine
    let name: String
    let username: String
    let host: String
    let port: Int
    let remoteAccess: String?
    let createdAt: Date?
    /// Present only in the create/rotate response (shown once).
    let password: String?

    var connection: String { "\(host):\(port)" }
}

/// `{ password }` from rotate.
struct DatabasePassword: Decodable { let password: String }
