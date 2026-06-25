import Foundation

/// Admin config endpoints (Products, Templates, Coupons, Billing, Roles,
/// Locations, Settings). Every route is permission-gated server-side; the UI
/// only surfaces what the role allows.
extension StaffService {

    // MARK: Products & pricing  (catalog.manage)

    func products() async throws -> [AdminProduct] {
        try await client.send(.get("admin/products"))
    }
    func product(_ id: String) async throws -> AdminProduct {
        try await client.send(.get("admin/products/\(id)"))
    }
    func createProduct(_ body: CreateProductBody) async throws -> AdminProduct {
        try await client.send(.post("admin/products", body: body))
    }
    func updateProduct(_ id: String, _ body: UpdateProductBody) async throws {
        try await client.sendVoid(.patch("admin/products/\(id)", body: body))
    }
    func deleteProduct(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/products/\(id)"))
    }
    func createTier(productId: String, _ body: CreateTierBody) async throws {
        try await client.sendVoid(.post("admin/products/\(productId)/tiers", body: body))
    }
    func deleteTier(_ tierId: String) async throws {
        try await client.sendVoid(.delete("admin/tiers/\(tierId)"))
    }
    func createPrice(productId: String, _ body: CreatePriceBody) async throws {
        try await client.sendVoid(.post("admin/products/\(productId)/prices", body: body))
    }
    func createTierPrice(productId: String, tierId: String, _ body: CreatePriceBody) async throws {
        try await client.sendVoid(.post("admin/products/\(productId)/tiers/\(tierId)/prices", body: body))
    }
    func deletePrice(_ priceId: String) async throws {
        try await client.sendVoid(.delete("admin/prices/\(priceId)"))
    }

    // MARK: Game templates  (catalog.manage)

    func templates() async throws -> [GameTemplate] {
        try await client.send(.get("admin/templates"))
    }
    func template(_ id: String) async throws -> GameTemplate {
        try await client.send(.get("admin/templates/\(id)"))
    }
    func updateTemplate(_ id: String, _ body: UpdateTemplateBody) async throws {
        try await client.sendVoid(.patch("admin/templates/\(id)", body: body))
    }
    func deleteTemplate(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/templates/\(id)"))
    }

    // MARK: Coupons & gift cards  (billing.manage)

    func coupons() async throws -> [Coupon] {
        try await client.send(.get("admin/coupons"))
    }
    func createCoupon(_ body: CreateCouponBody) async throws {
        try await client.sendVoid(.post("admin/coupons", body: body))
    }
    func updateCoupon(_ id: String, _ body: UpdateCouponBody) async throws {
        try await client.sendVoid(.patch("admin/coupons/\(id)", body: body))
    }
    func deleteCoupon(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/coupons/\(id)"))
    }
    func giftCards() async throws -> [GiftCard] {
        try await client.send(.get("admin/gift-cards"))
    }
    func createGiftCard(_ body: CreateGiftCardBody) async throws {
        try await client.sendVoid(.post("admin/gift-cards", body: body))
    }
    func updateGiftCard(_ id: String, _ body: UpdateGiftCardBody) async throws {
        try await client.sendVoid(.patch("admin/gift-cards/\(id)", body: body))
    }

    // MARK: Billing  (billing.read / billing.manage / payments.manage)

    func billingSummary() async throws -> BillingSummary {
        try await client.send(.get("admin/billing/summary"))
    }
    func orders(page: Int = 1, query: String? = nil) async throws -> Page<AdminOrder> {
        var items = [URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "pageSize", value: "25")]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await client.sendPaginated(.get("admin/orders", query: items))
    }
    func deleteOrder(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/orders/\(id)"))
    }
    func invoices(page: Int = 1, state: InvoiceState? = nil) async throws -> Page<AdminBillingInvoice> {
        var items = [URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "pageSize", value: "25")]
        if let state, state != .unknown { items.append(URLQueryItem(name: "state", value: state.rawValue)) }
        return try await client.sendPaginated(.get("admin/invoices", query: items))
    }
    func voidInvoice(_ id: String) async throws {
        try await client.sendVoid(.post("admin/invoices/\(id)/void"))
    }
    func markInvoicePaid(_ id: String) async throws {
        try await client.sendVoid(.post("admin/invoices/\(id)/mark-paid"))
    }
    func deleteInvoice(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/invoices/\(id)"))
    }
    func payments(page: Int = 1, query: String? = nil) async throws -> Page<Payment> {
        var items = [URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "pageSize", value: "25")]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await client.sendPaginated(.get("admin/payments", query: items))
    }
    func grantCredit(userId: String, amountMinor: Int, reason: CreditReason?, note: String?) async throws {
        try await client.sendVoid(.post("admin/users/\(userId)/credit",
            body: GrantCreditBody(amountMinor: amountMinor, reason: reason, note: note)))
    }

    // MARK: Roles & permissions  (roles.manage)

    func roles() async throws -> [Role] {
        try await client.send(.get("admin/roles"))
    }
    func permissionCatalog() async throws -> PermissionCatalog {
        try await client.send(.get("admin/roles/permissions"))
    }
    func createRole(_ body: CreateRoleBody) async throws {
        try await client.sendVoid(.post("admin/roles", body: body))
    }
    func updateRole(_ id: String, _ body: UpdateRoleBody) async throws {
        try await client.sendVoid(.patch("admin/roles/\(id)", body: body))
    }
    func deleteRole(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/roles/\(id)"))
    }

    // MARK: Locations / regions  (locations.manage)

    func locations() async throws -> [Region] {
        try await client.send(.get("admin/locations"))
    }
    func createLocation(_ body: CreateLocationBody) async throws {
        try await client.sendVoid(.post("admin/locations", body: body))
    }
    func updateLocation(_ id: String, _ body: UpdateLocationBody) async throws {
        try await client.sendVoid(.patch("admin/locations/\(id)", body: body))
    }
    func deleteLocation(_ id: String) async throws {
        try await client.sendVoid(.delete("admin/locations/\(id)"))
    }

    // MARK: Settings — email / steam / gateways  (settings.manage / payments.manage)

    func emailConfig() async throws -> EmailConfigMasked {
        try await client.send(.get("admin/settings/email"))
    }
    func setEmailConfig(_ body: SetEmailConfigBody) async throws {
        try await client.sendVoid(.patch("admin/settings/email", body: body))
    }
    func testEmail(to: String) async throws -> TestEmailResult {
        try await client.send(.post("admin/settings/email/test", body: TestEmailBody(to: to)))
    }
    func steamConfig() async throws -> SteamConfigMasked {
        try await client.send(.get("admin/settings/steam"))
    }
    func setSteamConfig(_ body: SetSteamConfigBody) async throws {
        try await client.sendVoid(.patch("admin/settings/steam", body: body))
    }
    func gatewayConfig() async throws -> GatewayConfigMasked {
        try await client.send(.get("admin/payments/gateways/config"))
    }
    func setGatewayConfig(_ body: SetGatewayConfigBody) async throws {
        try await client.sendVoid(.patch("admin/payments/gateways/config", body: body))
    }

    // MARK: Bodies (inline)

    private struct GrantCreditBody: Encodable {
        let amountMinor: Int; let reason: CreditReason?; let note: String?
    }
    private struct TestEmailBody: Encodable { let to: String }
}
