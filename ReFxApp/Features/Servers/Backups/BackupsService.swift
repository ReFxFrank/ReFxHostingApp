import Foundation

/// REST surface for backups, confirmed against `backups.controller.ts`.
/// Permissions: backup.read / create / restore / download / delete.
struct BackupsService {
    let client: APIClient

    func list(_ serverId: String, page: Int = 1, pageSize: Int = 50) async throws -> Page<Backup> {
        try await client.sendPaginated(.get("servers/\(serverId)/backups", query: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ]))
    }

    func create(_ serverId: String, name: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/backups", body: CreateBody(name: name)))
    }

    func restore(_ serverId: String, backupId: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/backups/\(backupId)/restore"))
    }

    func delete(_ serverId: String, backupId: String) async throws {
        try await client.sendVoid(.delete("servers/\(serverId)/backups/\(backupId)"))
    }

    /// `PATCH /servers/:id/backups/:backupId { isLocked }`. Locking protects a
    /// backup from deletion/rotation. Permission: backup.delete.
    func setLock(_ serverId: String, backupId: String, isLocked: Bool) async throws {
        try await client.sendVoid(
            .patch("servers/\(serverId)/backups/\(backupId)", body: LockBody(isLocked: isLocked)))
    }

    func downloadURL(_ serverId: String, backupId: String) async throws -> URL? {
        let signed: SignedURL = try await client.send(
            .get("servers/\(serverId)/backups/\(backupId)/download"))
        return URL(string: signed.url)
    }

    private struct CreateBody: Encodable { let name: String }
    private struct LockBody: Encodable { let isLocked: Bool }
}
