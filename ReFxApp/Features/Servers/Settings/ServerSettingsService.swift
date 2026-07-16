import Foundation

/// REST surface for the server Settings page: startup command, environment
/// variables, and reinstall. Confirmed against `servers.controller.ts`.
/// Permissions: startup.update (startup), settings.update (variables),
/// control.reinstall (reinstall).
struct ServerSettingsService {
    let client: APIClient

    func startup(_ serverId: String) async throws -> StartupConfig {
        try await client.send(.get("servers/\(serverId)/startup"))
    }

    func setStartup(_ serverId: String, command: String) async throws {
        try await client.sendVoid(
            .patch("servers/\(serverId)/startup", body: StartupBody(startupCommand: command)))
    }

    func variables(_ serverId: String) async throws -> [ServerVariable] {
        try await client.send(.get("servers/\(serverId)/variables"))
    }

    func setVariable(_ serverId: String, envName: String, value: String) async throws {
        try await client.sendVoid(
            .patch("servers/\(serverId)/variables", body: VariableBody(envName: envName, value: value)))
    }

    func deleteVariable(_ serverId: String, envName: String) async throws {
        try await client.sendVoid(.delete("servers/\(serverId)/variables/\(envName)"))
    }

    func reinstall(_ serverId: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/reinstall"))
    }

    /// `POST /servers/:id/update` — pull the latest game build (data preserved).
    /// Permission: control.reinstall.
    func updateGame(_ serverId: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/update"))
    }

    // MARK: Allocations / ports

    /// `GET /servers/:id/allocations` → the server's port allocations. The
    /// `Allocation` shape is the same one embedded as `primaryAllocation`.
    func allocations(_ serverId: String) async throws -> [Allocation] {
        try await client.send(.get("servers/\(serverId)/allocations"))
    }

    /// `POST /servers/:id/allocations` — assign an additional port from the
    /// node's pool (no body; the node picks a free port). Permission:
    /// allocation.create.
    func addAllocation(_ serverId: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/allocations"))
    }

    /// `DELETE /servers/:id/allocations/:allocationId`. Permission:
    /// allocation.delete. The primary allocation can't be removed.
    func deleteAllocation(_ serverId: String, allocationId: String) async throws {
        try await client.sendVoid(.delete("servers/\(serverId)/allocations/\(allocationId)"))
    }

    private struct StartupBody: Encodable { let startupCommand: String }
    private struct VariableBody: Encodable { let envName: String; let value: String }
}
