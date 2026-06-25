import Foundation

/// Plan/tier/slot change endpoints (`/servers/:id/upgrade*`). A tier-change
/// preview MUST use POST — the GET variant drops `hardwareTierId`.
extension ServersService {
    func upgradeOptions(_ serverId: String) async throws -> UpgradeOptions {
        try await client.send(.get("servers/\(serverId)/upgrade/options"))
    }

    func upgradePreview(_ serverId: String, _ dto: UpgradeServerDTO) async throws -> UpgradePreview {
        try await client.send(.post("servers/\(serverId)/upgrade/preview", body: dto))
    }

    func applyUpgrade(_ serverId: String, _ dto: UpgradeServerDTO) async throws -> PlanChangeResult {
        try await client.send(.post("servers/\(serverId)/upgrade", body: dto))
    }

    @discardableResult
    func cancelUpgrade(_ serverId: String) async throws -> CancelPlanChangeResult {
        try await client.send(.delete("servers/\(serverId)/upgrade"))
    }
}
