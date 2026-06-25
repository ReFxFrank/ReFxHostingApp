import Foundation

/// Customer billing REST surface (`billing` controller). Everything is scoped to
/// the signed-in user server-side. Viewing & management are fully native; paying
/// without a saved card returns a hosted `checkoutUrl` to hand off to the gateway.
struct BillingService {
    let client: APIClient

    // MARK: Credit

    func credit() async throws -> CreditBalance {
        try await client.send(.get("billing/credit"))
    }

    // MARK: Invoices

    func invoices(page: Int = 1) async throws -> Page<Invoice> {
        try await client.sendPaginated(.get("billing/invoices", query: [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: "25"),
        ]))
    }

    func invoice(_ id: String) async throws -> Invoice {
        try await client.send(.get("billing/invoices/\(id)"))
    }

    /// Pay an open invoice. `paid == true` settled silently (saved card / credit);
    /// otherwise `checkoutUrl` must be opened, or `reason` shown on decline.
    func payInvoice(_ id: String, gateway: String? = nil) async throws -> PayInvoiceResult {
        try await client.send(Endpoint(method: .post, path: "billing/invoices/\(id)/pay",
                                       query: gatewayQuery(gateway)))
    }

    /// Pay the open invoice attached to a specific server.
    func payServerInvoice(serverId: String, gateway: String? = nil) async throws -> PayInvoiceResult {
        try await client.send(Endpoint(method: .post, path: "billing/servers/\(serverId)/pay",
                                       query: gatewayQuery(gateway)))
    }

    func capturePayPal(token: String) async throws -> PayPalCaptureResult {
        try await client.send(Endpoint(method: .post, path: "billing/paypal/capture",
                                       query: [URLQueryItem(name: "token", value: token)]))
    }

    // MARK: Subscriptions

    func subscriptions() async throws -> [SubscriptionListItem] {
        try await client.send(.get("billing/subscriptions"))
    }

    /// Cancel: defaults to cancel-at-period-end; pass `atPeriodEnd: false` for immediate.
    @discardableResult
    func cancelSubscription(_ id: String, atPeriodEnd: Bool = true) async throws -> Subscription {
        let query = atPeriodEnd ? [] : [URLQueryItem(name: "atPeriodEnd", value: "false")]
        return try await client.send(Endpoint(method: .post,
            path: "billing/subscriptions/\(id)/cancel", query: query))
    }

    /// Un-cancel (only undoes cancel-at-period-end; a hard-canceled sub can't resume).
    @discardableResult
    func resumeSubscription(_ id: String) async throws -> Subscription {
        try await client.send(Endpoint(method: .post, path: "billing/subscriptions/\(id)/resume"))
    }

    // MARK: Payment methods

    func paymentMethods() async throws -> [PaymentMethod] {
        try await client.send(.get("billing/payment-methods"))
    }

    @discardableResult
    func setDefaultPaymentMethod(_ id: String) async throws -> PaymentMethod {
        try await client.send(Endpoint(method: .post, path: "billing/payment-methods/\(id)/default"))
    }

    func deletePaymentMethod(_ id: String) async throws {
        try await client.sendVoid(.delete("billing/payment-methods/\(id)"))
    }

    // MARK: Config

    func config() async throws -> BillingConfig {
        try await client.send(.get("billing/config"))
    }

    // MARK: Helpers

    private func gatewayQuery(_ gateway: String?) -> [URLQueryItem] {
        guard let gateway else { return [] }
        return [URLQueryItem(name: "gateway", value: gateway)]
    }
}
