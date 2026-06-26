import Foundation

/// Staff/admin REST surface (`admin.controller.ts`). Role/permission-gated
/// server-side; the UI only shows what the role allows but the API is
/// authoritative (every route declares a granular @RequirePerm).
struct StaffService {
    let client: APIClient

    // MARK: Overview

    func metrics() async throws -> AdminMetrics {
        try await client.send(.get("admin/metrics"))
    }

    // MARK: Servers (platform-wide)

    func servers(page: Int = 1, query: String? = nil) async throws -> Page<Server> {
        var items = [URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "pageSize", value: "25")]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await client.sendPaginated(.get("admin/servers", query: items))
    }

    func deleteServer(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/servers/\(id)"))
    }

    /// Admin direct-provision: create a server for any owner on a chosen node from
    /// a game template, sizing by explicit resources or by slot count (voice).
    /// Mirrors the panel's Admin → Servers → Create. Returns the new server.
    @discardableResult
    func createServer(_ body: AdminCreateServerBody) async throws -> Server {
        try await client.send(.post("admin/servers", body: body))
    }

    // MARK: Nodes

    func nodes() async throws -> [NodeAdmin] {
        let page: Page<NodeAdmin> = try await client.sendPaginated(
            .get("admin/nodes", query: [URLQueryItem(name: "pageSize", value: "100")]))
        return page.items
    }

    func node(_ id: String) async throws -> NodeAdmin {
        try await client.send(.get("admin/nodes/\(id)"))
    }

    /// Admin add-node: registers a node and returns its one-time bootstrap token
    /// (the operator runs the installer with it). Mirrors Admin → Nodes → Add.
    func createNode(_ body: CreateNodeBody) async throws -> CreateNodeResult {
        try await client.send(.post("admin/nodes", body: body))
    }

    func pingNode(_ id: String) async throws -> NodePing {
        try await client.send(.get("admin/nodes/\(id)/ping"))
    }

    func restartAgent(_ id: String) async throws {
        try await client.sendVoid(.post("admin/nodes/\(id)/restart-agent"))
    }

    func updateAgent(_ id: String) async throws {
        try await client.sendVoid(.post("admin/nodes/\(id)/update-agent"))
    }

    func clearSteamCache(_ id: String) async throws {
        try await client.sendVoid(.post("admin/nodes/\(id)/steam-cache/clear"))
    }

    /// Latest published agent release tag (for the "update available" badge).
    func agentLatest() async throws -> String? {
        let r: AgentLatest = try await client.send(.get("admin/nodes/agent-latest"))
        return r.latest
    }

    // MARK: Users

    func users(page: Int = 1, query: String? = nil) async throws -> Page<AdminUser> {
        var items = [URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "pageSize", value: "25")]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await client.sendPaginated(.get("admin/users", query: items))
    }

    func userDetail(_ id: String) async throws -> AdminUserDetail {
        try await client.send(.get("admin/users/\(id)"))
    }

    /// Account state transitions go through the admin PATCH (BANNED / SUSPENDED /
    /// ACTIVE), which the server maps to ban/suspend/reactivate.
    func setUserState(_ id: String, state: String) async throws {
        try await client.sendVoid(.patch("admin/users/\(id)", body: StateBody(state: state)))
    }
    func suspendUser(_ id: String) async throws { try await setUserState(id, state: "SUSPENDED") }
    func reactivateUser(_ id: String) async throws { try await setUserState(id, state: "ACTIVE") }
    func banUser(_ id: String) async throws { try await setUserState(id, state: "BANNED") }

    func verifyEmail(_ id: String) async throws {
        try await client.sendVoid(.post("admin/users/\(id)/verify-email"))
    }

    func setRole(_ id: String, role: String) async throws {
        try await client.sendVoid(.patch("admin/users/\(id)/role", body: RoleBody(role: role)))
    }

    // MARK: Audit log

    func auditLogs(page: Int = 1) async throws -> Page<AuditEntry> {
        try await client.sendPaginated(.get("admin/audit-logs", query: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: "40"),
        ]))
    }

    // MARK: Platform alerts (banner)

    func alerts() async throws -> [AdminAlert] {
        try await client.send(.get("admin/alerts"))
    }

    func createAlert(severity: AlertSeverity, title: String, body: String) async throws {
        try await client.sendVoid(.post("admin/alerts",
            body: CreateAlertBody(severity: severity.rawValue, title: title, body: body, isActive: true)))
    }

    func setAlertActive(_ id: String, isActive: Bool) async throws {
        try await client.sendVoid(.patch("admin/alerts/\(id)", body: AlertActiveBody(isActive: isActive)))
    }

    func deleteAlert(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/alerts/\(id)"))
    }

    // MARK: Bodies

    private struct StateBody: Encodable { let state: String }
    private struct RoleBody: Encodable { let role: String }
    private struct CreateAlertBody: Encodable {
        let severity: String; let title: String; let body: String; let isActive: Bool
    }
    private struct AlertActiveBody: Encodable { let isActive: Bool }
}
