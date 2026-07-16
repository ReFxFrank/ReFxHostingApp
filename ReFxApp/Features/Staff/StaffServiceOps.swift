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
}
