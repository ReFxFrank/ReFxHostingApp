import Foundation

/// `/servers/:id/workshop` (servers.controller.ts). Steam Workshop content.
/// Permissions: files.read (list), files.write (add/toggle/remove),
/// control.reinstall (apply).
struct WorkshopService {
    let client: APIClient

    func list(_ serverId: String) async throws -> [WorkshopMod] {
        try await client.send(.get("servers/\(serverId)/workshop"))
    }

    func add(_ serverId: String, input: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/workshop", body: AddBody(input: input)))
    }

    func toggle(_ serverId: String, modId: String, enabled: Bool) async throws {
        try await client.sendVoid(
            .patch("servers/\(serverId)/workshop/\(modId)", body: ToggleBody(enabled: enabled)))
    }

    func remove(_ serverId: String, modId: String) async throws {
        try await client.sendVoid(.delete("servers/\(serverId)/workshop/\(modId)"))
    }

    func apply(_ serverId: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/workshop/apply"))
    }

    /// `PATCH /servers/:id/workshop/reorder { ids }` — WorkshopMod row ids in the
    /// new display order (sortOrder = array index). Permission: files.write.
    func reorder(_ serverId: String, ids: [String]) async throws {
        try await client.sendVoid(
            .patch("servers/\(serverId)/workshop/reorder", body: ReorderBody(ids: ids)))
    }

    private struct AddBody: Encodable { let input: String }
    private struct ToggleBody: Encodable { let enabled: Bool }
    private struct ReorderBody: Encodable { let ids: [String] }
}

/// `/servers/:id/minecraft` (servers.controller.ts). Unified Minecraft egg:
/// set loader + version (+ loader build), then reinstall. Permission
/// startup.update.
struct MinecraftService {
    let client: APIClient

    func setConfig(_ serverId: String, loader: String, version: String?,
                   loaderVersion: String?) async throws {
        try await client.sendVoid(.patch("servers/\(serverId)/minecraft",
                                          body: ConfigBody(loader: loader, version: version,
                                                           loaderVersion: loaderVersion)))
    }

    private struct ConfigBody: Encodable {
        let loader: String; let version: String?; let loaderVersion: String?
    }

    /// `GET /servers/:id/world/level-dat-status` — detect a corrupt world.
    func levelDatStatus(_ serverId: String) async throws -> LevelDatStatus {
        try await client.send(.get("servers/\(serverId)/world/level-dat-status"))
    }

    /// `POST /servers/:id/world/restore-level-dat` — restore from the backup copy.
    func restoreLevelDat(_ serverId: String) async throws -> LevelDatRestoreResult {
        try await client.send(.post("servers/\(serverId)/world/restore-level-dat"))
    }
}

/// `GET /servers/:id/world/level-dat-status`.
struct LevelDatStatus: Decodable, Equatable {
    let world: String
    let hasLevelDat: Bool
    let levelDatBytes: Int?
    let hasBackup: Bool
    let backupBytes: Int?
    let looksCorrupt: Bool
    let restorable: Bool
}

/// `POST /servers/:id/world/restore-level-dat`.
struct LevelDatRestoreResult: Decodable, Equatable {
    let world: String
    let restored: Bool
    let preservedAs: String?
    let restoredBytes: Int?
}
