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

    /// Assign/unassign a bug. `assigneeId: nil` sends an explicit null to clear it.
    @discardableResult
    func assignBug(_ id: String, assigneeId: String?) async throws -> BugReport {
        try await client.send(.patch("bugs/\(id)", body: AssignBugBody(assigneeId: assigneeId)))
    }

    func addBugComment(_ id: String, body: String, isInternal: Bool) async throws {
        try await client.sendVoid(.post("bugs/\(id)/comments", body: BugCommentBody(body: body, isInternal: isInternal)))
    }

    private struct BugCommentBody: Encodable { let body: String; let isInternal: Bool }

    // MARK: Status incidents  (content.manage)

    func incidents() async throws -> [StatusIncident] {
        try await client.send(.get("admin/status/incidents"))
    }

    @discardableResult
    func createIncident(_ body: CreateIncidentBody) async throws -> StatusIncident {
        try await client.send(.post("admin/status/incidents", body: body))
    }

    @discardableResult
    func addIncidentUpdate(_ id: String, _ body: AddIncidentUpdateBody) async throws -> StatusIncident {
        try await client.send(.post("admin/status/incidents/\(id)/updates", body: body))
    }

    @discardableResult
    func updateIncident(_ id: String, _ body: UpdateIncidentBody) async throws -> StatusIncident {
        try await client.send(.patch("admin/status/incidents/\(id)", body: body))
    }

    func deleteIncident(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/status/incidents/\(id)"))
    }

    // MARK: Status webhooks  (content.manage)

    func statusWebhooks() async throws -> [StatusWebhook] {
        try await client.send(.get("admin/status/webhooks"))
    }

    /// Returns the created webhook including its one-time `secret`.
    func createStatusWebhook(_ body: CreateWebhookBody) async throws -> StatusWebhook {
        try await client.send(.post("admin/status/webhooks", body: body))
    }

    @discardableResult
    func updateStatusWebhook(_ id: String, _ body: UpdateWebhookBody) async throws -> StatusWebhook {
        try await client.send(.patch("admin/status/webhooks/\(id)", body: body))
    }

    func deleteStatusWebhook(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/status/webhooks/\(id)"))
    }

    // MARK: Support settings — canned responses  (support.read / support.manage)

    func cannedResponses() async throws -> [CannedResponse] {
        try await client.send(.get("support/canned-responses"))
    }
    @discardableResult
    func createCannedResponse(_ body: CannedResponseBody) async throws -> CannedResponse {
        try await client.send(.post("support/canned-responses", body: body))
    }
    @discardableResult
    func updateCannedResponse(_ id: String, _ body: CannedResponseBody) async throws -> CannedResponse {
        try await client.send(.patch("support/canned-responses/\(id)", body: body))
    }
    func deleteCannedResponse(_ id: String) async throws {
        try await client.sendVoid(.delete("support/canned-responses/\(id)"))
    }

    // MARK: Support settings — KB articles (slug-keyed; no delete route)

    func kbArticles() async throws -> [KbArticle] {
        try await client.send(.get("support/kb-articles"))
    }
    @discardableResult
    func createKbArticle(_ body: CreateKbArticleBody) async throws -> KbArticle {
        try await client.send(.post("support/kb-articles", body: body))
    }
    @discardableResult
    func updateKbArticle(_ slug: String, _ body: UpdateKbArticleBody) async throws -> KbArticle {
        try await client.send(.patch("support/kb-articles/\(slug)", body: body))
    }

    // MARK: Support settings — ticket categories

    func ticketCategories() async throws -> [TicketCategory] {
        try await client.send(.get("support/categories"))
    }
    @discardableResult
    func createCategory(_ body: CreateCategoryBody) async throws -> TicketCategory {
        try await client.send(.post("support/categories", body: body))
    }
    @discardableResult
    func updateCategory(_ id: String, _ body: UpdateCategoryBody) async throws -> TicketCategory {
        try await client.send(.patch("support/categories/\(id)", body: body))
    }
    func deleteCategory(_ id: String) async throws {
        try await client.sendVoid(.delete("support/categories/\(id)"))
    }

    // MARK: Settings hub — vanity / referrals / express-backups / backup-storage  (settings.manage)

    func vanitySettings() async throws -> VanitySettings {
        try await client.send(.get("admin/settings/vanity"))
    }
    func setVanitySettings(_ body: SetVanitySettingsBody) async throws {
        try await client.sendVoid(.patch("admin/settings/vanity", body: body))
    }

    func referralSettings() async throws -> ReferralSettings {
        try await client.send(.get("admin/settings/referrals"))
    }
    func setReferralSettings(_ body: SetReferralSettingsBody) async throws {
        try await client.sendVoid(.patch("admin/settings/referrals", body: body))
    }

    func expressBackupSettings() async throws -> ExpressBackupSettings {
        try await client.send(.get("admin/settings/express-backups"))
    }
    func setExpressBackupSettings(_ body: SetExpressBackupSettingsBody) async throws {
        try await client.sendVoid(.patch("admin/settings/express-backups", body: body))
    }

    func backupStorageConfig() async throws -> BackupStorageConfigMasked {
        try await client.send(.get("admin/settings/backup-storage"))
    }
    /// PATCH returns `{ config, push }`; we ignore the body and reload.
    func setBackupStorageConfig(_ body: SetBackupStorageBody) async throws {
        try await client.sendVoid(.patch("admin/settings/backup-storage", body: body))
    }

    // MARK: Server transfers  (servers.manage / servers.read)

    @discardableResult
    func transferServer(_ id: String, toNodeId: String) async throws -> ServerTransfer {
        try await client.send(.post("admin/servers/\(id)/transfer", body: TransferBody(toNodeId: toNodeId)))
    }

    func serverTransfers(_ id: String) async throws -> [ServerTransfer] {
        try await client.send(.get("admin/servers/\(id)/transfers"))
    }

    private struct TransferBody: Encodable { let toNodeId: String }
}
