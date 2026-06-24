import Foundation

/// `GET /servers/:serverId/sub-users`.
struct SubUser: Codable, Identifiable, Equatable {
    let id: String
    let state: String?
    let permissions: [String]
    let user: SubUserAccount?

    var email: String { user?.email ?? "—" }
    var isActive: Bool { (state ?? "ACTIVE") == "ACTIVE" }
}

struct SubUserAccount: Codable, Equatable {
    let id: String
    let email: String
}
