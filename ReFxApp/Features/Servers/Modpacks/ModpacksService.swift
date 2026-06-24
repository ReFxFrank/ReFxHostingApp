import Foundation

/// Modrinth modpacks for a Minecraft server (servers.controller.ts).
/// Permissions: files.read (browse), control.reinstall (install/uninstall).
struct ModpacksService {
    let client: APIClient

    func search(_ serverId: String, query: String) async throws -> [ModSearchResult] {
        try await client.send(.get("servers/\(serverId)/modpacks/search",
                                    query: [URLQueryItem(name: "q", value: query)]))
    }

    func versions(_ serverId: String, projectId: String) async throws -> [ModpackVersion] {
        try await client.send(.get("servers/\(serverId)/modpacks/versions",
                                    query: [URLQueryItem(name: "projectId", value: projectId)]))
    }

    func installed(_ serverId: String) async throws -> InstalledModpack? {
        let res: InstalledModpackResponse = try await client.send(
            .get("servers/\(serverId)/modpacks/installed"))
        return res.installed
    }

    func install(_ serverId: String, versionId: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/modpacks/install",
                                         body: InstallBody(versionId: versionId)))
    }

    func uninstall(_ serverId: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/modpacks/uninstall"))
    }

    private struct InstallBody: Encodable { let versionId: String }
}
