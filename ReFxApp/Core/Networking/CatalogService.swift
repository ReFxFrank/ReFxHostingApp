import Foundation

/// Public catalog endpoints (no auth) used by the Minecraft version pickers.
/// Mirrors the web's `api.catalog.minecraftVersions/minecraftBuilds`
/// (catalog.controller.ts). Each loader exposes its own supported Minecraft
/// versions; "builds" are the loader-specific sub-version (Fabric loader /
/// Forge build / NeoForge build) and are empty for vanilla/paper.
struct CatalogService {
    let client: APIClient

    /// Minecraft versions for a loader, newest first.
    func minecraftVersions(loader: String) async throws -> [String] {
        let res: VersionsResponse = try await client.send(
            .get("catalog/minecraft-versions",
                 query: [URLQueryItem(name: "loader", value: loader)]))
        return res.versions
    }

    /// Loader build versions for a loader + Minecraft version, newest first.
    func minecraftBuilds(loader: String, version: String) async throws -> [String] {
        let res: BuildsResponse = try await client.send(
            .get("catalog/minecraft-builds",
                 query: [URLQueryItem(name: "loader", value: loader),
                         URLQueryItem(name: "version", value: version)]))
        return res.builds
    }

    private struct VersionsResponse: Decodable { let versions: [String] }
    private struct BuildsResponse: Decodable { let builds: [String] }
}
