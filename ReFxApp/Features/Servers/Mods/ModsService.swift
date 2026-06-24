import Foundation

/// Modrinth-backed mods/plugins for a Minecraft server (servers.controller.ts).
/// Permissions: files.read (browse), files.write (install/remove).
struct ModsService {
    let client: APIClient

    func context(_ serverId: String) async throws -> ModContext {
        try await client.send(.get("servers/\(serverId)/mods/context"))
    }

    func search(_ serverId: String, query: String) async throws -> [ModSearchResult] {
        try await client.send(.get("servers/\(serverId)/mods/search",
                                    query: [URLQueryItem(name: "q", value: query)]))
    }

    func installed(_ serverId: String) async throws -> InstalledModsResponse {
        try await client.send(.get("servers/\(serverId)/mods/installed"))
    }

    func install(_ serverId: String, projectId: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/mods/install",
                                         body: InstallBody(projectId: projectId)))
    }

    func remove(_ serverId: String, filename: String) async throws {
        try await client.sendVoid(.delete("servers/\(serverId)/mods/\(filename)"))
    }

    private struct InstallBody: Encodable { let projectId: String }
}

/// TeamSpeak voice admin (servers.controller.ts). Permissions: files.read
/// (info/status), control.start (accept license), settings.update (rename).
struct VoiceService {
    let client: APIClient

    func info(_ serverId: String) async throws -> VoiceInfo {
        try await client.send(.get("servers/\(serverId)/voice"))
    }

    func status(_ serverId: String) async throws -> VoiceStatus {
        try await client.send(.get("servers/\(serverId)/voice/status"))
    }

    func acceptLicense(_ serverId: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/voice/accept-license"))
    }

    func rename(_ serverId: String, name: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/voice/rename", body: RenameBody(name: name)))
    }

    private struct RenameBody: Encodable { let name: String }
}
