import Foundation

/// `/servers/:id/databases` (databases.controller.ts). Permissions:
/// database.read / create / delete. Create + rotate return a one-time password.
struct DatabasesService {
    let client: APIClient

    func list(_ serverId: String) async throws -> [ServerDatabase] {
        try await client.send(.get("servers/\(serverId)/databases"))
    }

    func create(_ serverId: String, engine: DbEngine, name: String,
                remoteAccess: String?) async throws -> ServerDatabase {
        try await client.send(.post("servers/\(serverId)/databases",
                                     body: CreateBody(engine: engine.rawValue, name: name,
                                                      remoteAccess: remoteAccess)))
    }

    func delete(_ serverId: String, dbId: String) async throws {
        try await client.sendVoid(.delete("servers/\(serverId)/databases/\(dbId)"))
    }

    func rotate(_ serverId: String, dbId: String) async throws -> String {
        let result: DatabasePassword = try await client.send(
            .post("servers/\(serverId)/databases/\(dbId)/rotate"))
        return result.password
    }

    private struct CreateBody: Encodable {
        let engine: String; let name: String; let remoteAccess: String?
    }
}
