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

    /// `POST /servers/:id/allocations` — attach a specific `ip:port` allocation
    /// to the server. There is no auto-assign; the caller supplies a free port on
    /// the server's node (the primary allocation's IP is the usual choice).
    /// Permission: allocation.create. 409 if the port belongs to another server.
    func addAllocation(_ serverId: String, ip: String, port: Int) async throws {
        try await client.sendVoid(
            .post("servers/\(serverId)/allocations", body: AllocationBody(ip: ip, port: port)))
    }

    /// `DELETE /servers/:id/allocations/:allocationId`. Permission:
    /// allocation.delete. The primary allocation can't be removed.
    func deleteAllocation(_ serverId: String, allocationId: String) async throws {
        try await client.sendVoid(.delete("servers/\(serverId)/allocations/\(allocationId)"))
    }

    // MARK: Auto-restart

    /// `PATCH /servers/:id/auto-restart { enabled }`. Permission: settings.update.
    func setAutoRestart(_ serverId: String, enabled: Bool) async throws {
        try await client.sendVoid(
            .patch("servers/\(serverId)/auto-restart", body: AutoRestartBody(enabled: enabled)))
    }

    // MARK: Java version (Minecraft)

    /// `GET /servers/:id/java-version`. Returns 400 for non-Java servers.
    func javaVersion(_ serverId: String) async throws -> JavaVersionSelector {
        try await client.send(.get("servers/\(serverId)/java-version"))
    }

    /// `PUT /servers/:id/java-version { version }` — "auto" or a major like "21".
    func setJavaVersion(_ serverId: String, version: String) async throws {
        try await client.sendVoid(
            .put("servers/\(serverId)/java-version", body: JavaVersionBody(version: version)))
    }

    // MARK: Custom domains (WEB_APP servers only — 400 otherwise)

    /// `GET /servers/:id/domains` → the server's custom domains.
    func domains(_ serverId: String) async throws -> [ServerDomain] {
        try await client.send(.get("servers/\(serverId)/domains"))
    }

    /// `POST /servers/:id/domains { hostname }` → created domain (+ `dnsTarget`).
    func addDomain(_ serverId: String, hostname: String) async throws -> ServerDomain {
        try await client.send(.post("servers/\(serverId)/domains", body: HostnameBody(hostname: hostname)))
    }

    /// `POST /servers/:id/domains/:domainId/verify` → domain (+ `dnsTarget`, `verified`).
    func verifyDomain(_ serverId: String, domainId: String) async throws -> ServerDomain {
        try await client.send(.post("servers/\(serverId)/domains/\(domainId)/verify"))
    }

    /// `DELETE /servers/:id/domains/:domainId`.
    func deleteDomain(_ serverId: String, domainId: String) async throws {
        try await client.sendVoid(.delete("servers/\(serverId)/domains/\(domainId)"))
    }

    // MARK: Vanity address

    /// `GET /servers/:id/vanity-address` status card.
    func vanityStatus(_ serverId: String) async throws -> VanityStatus {
        try await client.send(.get("servers/\(serverId)/vanity-address"))
    }

    /// `POST /servers/:id/vanity-address { label }` — "applied" (paid from credit)
    /// or "invoiced" (payment needed). Owner-only.
    func setVanity(_ serverId: String, label: String) async throws -> VanityPurchaseResult {
        try await client.send(.post("servers/\(serverId)/vanity-address", body: VanityBody(label: label)))
    }

    /// `DELETE /servers/:id/vanity-address` → `{ removed }`. Owner-only.
    func removeVanity(_ serverId: String) async throws {
        try await client.sendVoid(.delete("servers/\(serverId)/vanity-address"))
    }

    private struct StartupBody: Encodable { let startupCommand: String }
    private struct VariableBody: Encodable { let envName: String; let value: String }
    private struct AllocationBody: Encodable { let ip: String; let port: Int }
    private struct AutoRestartBody: Encodable { let enabled: Bool }
    private struct JavaVersionBody: Encodable { let version: String }
    private struct HostnameBody: Encodable { let hostname: String }
    private struct VanityBody: Encodable { let label: String }
}

/// `GET /servers/:id/java-version` selector.
struct JavaVersionSelector: Decodable, Equatable {
    let selected: String   // "auto" or a major as string
    let effective: Int     // major actually used now
    let auto: Int          // what auto-selection would pick
    let options: [Int]     // available majors
}
