import Foundation

/// 1.3 staff/admin operations endpoints (database hosts, network, growth, staff,
/// incidents/webhooks, homepage alerts, bugs, support settings, settings hub,
/// server transfers). Each is permission-gated server-side.
extension StaffService {

    // MARK: Database hosts  (nodes.read / nodes.manage)

    func databaseHosts() async throws -> [DatabaseHost] {
        try await client.send(.get("admin/database-hosts"))
    }

    @discardableResult
    func createDatabaseHost(_ body: CreateDatabaseHostBody) async throws -> DatabaseHost {
        try await client.send(.post("admin/database-hosts", body: body))
    }

    @discardableResult
    func updateDatabaseHost(_ id: String, _ body: UpdateDatabaseHostBody) async throws -> DatabaseHost {
        try await client.send(.patch("admin/database-hosts/\(id)", body: body))
    }

    func deleteDatabaseHost(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/database-hosts/\(id)"))
    }

    /// `POST /admin/database-hosts/:id/test` → `{ ok: true }` on success; a
    /// connection failure throws (non-2xx), surfaced as the error message.
    func testDatabaseHost(_ id: String) async throws {
        try await client.sendVoid(.post("admin/database-hosts/\(id)/test"))
    }

    // MARK: Network overview  (nodes.read)

    func network() async throws -> NetworkOverview {
        try await client.send(.get("admin/network"))
    }

    // MARK: Growth analytics  (billing.read)

    func growth(days: Int = 30) async throws -> GrowthReport {
        try await client.send(.get("admin/growth",
                                    query: [URLQueryItem(name: "days", value: String(days))]))
    }

    // MARK: Staff members  (content.manage)

    func staffMembers() async throws -> [StaffMember] {
        try await client.send(.get("admin/staff"))
    }

    @discardableResult
    func createStaffMember(_ body: StaffMemberBody) async throws -> StaffMember {
        try await client.send(.post("admin/staff", body: body))
    }

    @discardableResult
    func updateStaffMember(_ id: String, _ body: StaffMemberBody) async throws -> StaffMember {
        try await client.send(.patch("admin/staff/\(id)", body: body))
    }

    func deleteStaffMember(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/staff/\(id)"))
    }

    // MARK: Homepage alerts  (content.manage)

    func homepageAlerts() async throws -> [HomepageAlert] {
        try await client.send(.get("admin/homepage-alerts"))
    }

    @discardableResult
    func createHomepageAlert(_ body: HomepageAlertBody) async throws -> HomepageAlert {
        try await client.send(.post("admin/homepage-alerts", body: body))
    }

    @discardableResult
    func updateHomepageAlert(_ id: String, _ body: HomepageAlertBody) async throws -> HomepageAlert {
        try await client.send(.patch("admin/homepage-alerts/\(id)", body: body))
    }

    func deleteHomepageAlert(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/homepage-alerts/\(id)"))
    }

    // MARK: Bug reports (staff triage)

    func bugs(page: Int = 1, status: BugStatus? = nil, query: String? = nil) async throws -> Page<BugReport> {
        var items = [URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "pageSize", value: "25")]
        if let status, status != .unknown { items.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await client.sendPaginated(.get("bugs", query: items))
    }

    /// `GET /bugs/staff` — assignee picker (staff users).
    func bugStaff() async throws -> [BugUserRef] {
        try await client.send(.get("bugs/staff"))
    }

    func bug(_ id: String) async throws -> BugReport {
        try await client.send(.get("bugs/\(id)"))
    }

    @discardableResult
    func updateBug(_ id: String, _ body: UpdateBugBody) async throws -> BugReport {
        try await client.send(.patch("bugs/\(id)", body: body))
    }

    func addBugComment(_ id: String, body: String, isInternal: Bool) async throws {
        try await client.sendVoid(.post("bugs/\(id)/comments", body: BugCommentBody(body: body, isInternal: isInternal)))
    }

    private struct BugCommentBody: Encodable { let body: String; let isInternal: Bool }
}
