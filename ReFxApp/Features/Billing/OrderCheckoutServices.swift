import Foundation

// Public catalog reads that drive the new-server wizard. These routes are public
// on the backend; the bearer token (always present in-app) is simply ignored.
extension CatalogService {
    func products() async throws -> [CatalogProduct] {
        try await client.send(.get("catalog/products"))
    }

    func templates() async throws -> [CatalogTemplate] {
        try await client.send(.get("catalog/templates"))
    }

    /// Regions that have a node able to fit the chosen plan's resources.
    func regions(cpuCores: Double, memoryMb: Int, diskMb: Int) async throws -> [Region] {
        try await client.send(.get("catalog/locations", query: resourceQuery(cpuCores, memoryMb, diskMb)))
    }

    /// Nodes in a region with capacity (optional manual placement).
    func nodes(regionId: String, cpuCores: Double, memoryMb: Int, diskMb: Int) async throws -> [PlacementNode] {
        var q = resourceQuery(cpuCores, memoryMb, diskMb)
        q.insert(URLQueryItem(name: "regionId", value: regionId), at: 0)
        return try await client.send(.get("catalog/nodes", query: q))
    }

    private func resourceQuery(_ cpu: Double, _ mem: Int, _ disk: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "cpuCores", value: String(cpu)),
         URLQueryItem(name: "memoryMb", value: String(mem)),
         URLQueryItem(name: "diskMb", value: String(disk))]
    }
}

// Order placement + checkout-preview helpers.
extension BillingService {
    /// `POST /orders` — places the order. `paid == true` settled & provisioning;
    /// otherwise open `checkoutUrl` to finish payment.
    func createOrder(_ body: CreateOrderBody) async throws -> OrderResult {
        try await client.send(.post("orders", body: body))
    }

    func validateCoupon(code: String, subtotalMinor: Int) async throws -> CouponValidateResult {
        try await client.send(.post("billing/coupons/validate",
            body: ValidateCouponBody(code: code, subtotalMinor: subtotalMinor)))
    }

    func lookupGiftCard(code: String) async throws -> GiftCardLookupResult {
        try await client.send(.post("billing/gift-cards/lookup", body: GiftCardCodeBody(code: code)))
    }

    private struct ValidateCouponBody: Encodable { let code: String; let subtotalMinor: Int }
    private struct GiftCardCodeBody: Encodable { let code: String }
}

// Order preconditions (email-verified + billing address) live on the User row.
extension AccountService {
    func orderProfile() async throws -> OrderProfile {
        try await client.send(.get("account"))
    }

    func updateProfile(_ body: UpdateProfileBody) async throws {
        try await client.sendVoid(.patch("account", body: body))
    }
}
