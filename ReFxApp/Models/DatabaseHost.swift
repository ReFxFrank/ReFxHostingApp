import Foundation

enum DbEngine: String, Codable, CaseIterable, Identifiable {
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

/// `GET /admin/database-hosts` (and create/update). The admin password is never
/// returned (`passwordEnc` is dropped server-side). `databaseCount` is present
/// only on the LIST response.
struct DatabaseHost: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let engine: DbEngine
    let host: String
    let port: Int
    let username: String
    let publicHost: String
    let maxDatabases: Int
    let isActive: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let databaseCount: Int?
}

/// `POST /admin/database-hosts`. `engine` is fixed at creation (not updatable).
struct CreateDatabaseHostBody: Encodable {
    let name: String
    let engine: String
    let host: String
    let port: Int
    let username: String
    let password: String
    let publicHost: String
    let maxDatabases: Int
    let isActive: Bool
}

/// `PATCH /admin/database-hosts/:id`. Only non-nil fields are written; an empty
/// `password` leaves the stored one unchanged (send a value to rotate it).
struct UpdateDatabaseHostBody: Encodable {
    var name: String?
    var host: String?
    var port: Int?
    var username: String?
    var password: String?
    var publicHost: String?
    var maxDatabases: Int?
    var isActive: Bool?
}
