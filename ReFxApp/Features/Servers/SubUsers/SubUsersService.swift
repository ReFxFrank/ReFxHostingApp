import Foundation

/// `/servers/:serverId/sub-users` (servers.controller.ts). Permissions:
/// user.read / create / update / delete.
struct SubUsersService {
    let client: APIClient

    func list(_ serverId: String) async throws -> [SubUser] {
        try await client.send(.get("servers/\(serverId)/sub-users"))
    }

    func add(_ serverId: String, email: String, permissions: [String]) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/sub-users",
                                         body: AddBody(email: email, permissions: permissions)))
    }

    func update(_ serverId: String, subUserId: String, permissions: [String]) async throws {
        try await client.sendVoid(.patch("servers/\(serverId)/sub-users/\(subUserId)",
                                          body: PermsBody(permissions: permissions)))
    }

    func remove(_ serverId: String, subUserId: String) async throws {
        try await client.sendVoid(.delete("servers/\(serverId)/sub-users/\(subUserId)"))
    }

    private struct AddBody: Encodable { let email: String; let permissions: [String] }
    private struct PermsBody: Encodable { let permissions: [String] }
}
