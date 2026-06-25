import Foundation

/// Staff/admin REST surface (admin.controller.ts, nodes via /admin/nodes,
/// users.controller). Role-gated server-side (SUPPORT for queue, ADMIN for the
/// rest); the UI only shows what the role allows but the API is authoritative.
struct StaffService {
    let client: APIClient

    // MARK: Servers (platform-wide)

    func servers(page: Int = 1, query: String? = nil) async throws -> Page<Server> {
        var items = [URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "pageSize", value: "25")]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await client.sendPaginated(.get("admin/servers", query: items))
    }

    // MARK: Nodes

    func nodes() async throws -> [NodeAdmin] {
        let page: Page<NodeAdmin> = try await client.sendPaginated(
            .get("admin/nodes", query: [URLQueryItem(name: "pageSize", value: "100")]))
        return page.items
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

    // MARK: Users

    func users(page: Int = 1, query: String? = nil) async throws -> Page<AdminUser> {
        var items = [URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "pageSize", value: "25")]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await client.sendPaginated(.get("admin/users", query: items))
    }

    func suspendUser(_ id: String) async throws {
        try await client.sendVoid(.post("users/\(id)/suspend"))
    }

    func reactivateUser(_ id: String) async throws {
        try await client.sendVoid(.post("users/\(id)/reactivate"))
    }

    func setRole(_ id: String, role: String) async throws {
        try await client.sendVoid(.patch("admin/users/\(id)/role", body: RoleBody(role: role)))
    }

    private struct RoleBody: Encodable { let role: String }
}
