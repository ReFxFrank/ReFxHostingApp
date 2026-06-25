import Foundation

// Customer-facing billing models (the signed-in user's OWN billing — distinct
// from the staff `admin/*` surface). Shapes mirror panel-api's `billing` /
// `orders` controllers. Shared enums (InvoiceState, PaymentState,
// SubscriptionState, BillingInterval, BillingModel, ProductType, CreditReason)
// are reused from AdminConfigModels — not redefined here.
//
// Money: every `…Minor` is integer cents, paired with a sibling `currency`.

// MARK: - Invoices

struct Invoice: Codable, Identifiable, Equatable {
    let id: String
    let number: String
    let userId: String
    let subscriptionId: String?
    let state: InvoiceState
    let currency: String
    let subtotalMinor: Int
    let discountMinor: Int
    let couponCode: String?
    let taxMinor: Int
    let totalMinor: Int
    let amountPaidMinor: Int
    let taxType: String?
    let taxRatePct: Double?
    let dueAt: Date?
    let paidAt: Date?
    let createdAt: Date
    let lineItems: [InvoiceLineItem]?       // list + detail
    let payments: [InvoicePayment]?         // detail only

    var total: Money { Money(minorUnits: totalMinor, currency: currency) }
    var subtotal: Money { Money(minorUnits: subtotalMinor, currency: currency) }
    var discount: Money { Money(minorUnits: discountMinor, currency: currency) }
    var tax: Money { Money(minorUnits: taxMinor, currency: currency) }
    var amountPaid: Money { Money(minorUnits: amountPaidMinor, currency: currency) }
    /// Remaining balance due (never negative).
    var outstanding: Money { Money(minorUnits: max(0, totalMinor - amountPaidMinor), currency: currency) }
    var isOpen: Bool { state == .open }
    var isPaid: Bool { state == .paid }
}

struct InvoiceLineItem: Codable, Identifiable, Equatable {
    let id: String
    let invoiceId: String
    let description: String
    let quantity: Int
    let unitMinor: Int
    let amountMinor: Int

    var amount: Money { Money(minorUnits: amountMinor, currency: "USD") }
    func amount(in currency: String) -> Money { Money(minorUnits: amountMinor, currency: currency) }
}

/// `Payment` is taken by the admin models; the customer invoice-payment row.
struct InvoicePayment: Codable, Identifiable, Equatable {
    let id: String
    let invoiceId: String
    let gateway: String
    let gatewayRef: String?
    let amountMinor: Int
    let currency: String
    let state: PaymentState
    let failureReason: String?
    let createdAt: Date

    var amount: Money { Money(minorUnits: amountMinor, currency: currency) }
}

/// `POST /billing/invoices/:id/pay` (and the server-scoped variant).
struct PayInvoiceResult: Codable {
    let paid: Bool
    let checkoutUrl: String?    // hosted Stripe Checkout / PayPal approval URL
    let reason: String?         // decline reason when paid == false and no URL
}

struct PayPalCaptureResult: Codable { let paid: Bool }

// MARK: - Subscriptions

/// `GET /billing/subscriptions` — enriched list item (the full shape; no detail route).
struct SubscriptionListItem: Codable, Identifiable, Equatable {
    let id: String
    let productId: String
    let priceId: String
    let interval: BillingInterval
    let slots: Int
    let state: SubscriptionState
    let currentPeriodStart: Date
    let currentPeriodEnd: Date
    let cancelAtPeriodEnd: Bool
    let autoRenew: Bool
    let gateway: String
    let createdAt: Date
    let product: ProductRef
    let hardwareTier: TierRef?
    let servers: [ServerRef]
    let renewalAmountMinor: Int
    let currency: String

    var renewalAmount: Money { Money(minorUnits: renewalAmountMinor, currency: currency) }
    /// e.g. "$12.00/mo".
    var renewalLabel: String { renewalAmount.formatted + interval.shortSuffix }

    struct ProductRef: Codable, Equatable {
        let id: String
        let name: String
        let type: ProductType
        let billingModel: BillingModel
        let perSlot: Bool
    }
    struct TierRef: Codable, Equatable {
        let id: String
        let name: String
        let cpuCores: Double
        let memoryMb: Int
        let diskMb: Int
    }
    struct ServerRef: Codable, Equatable, Identifiable {
        let id: String
        let shortId: String
        let name: String
        let state: String
    }
}

/// Raw row returned by cancel / resume.
struct Subscription: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let productId: String
    let priceId: String
    let hardwareTierId: String?
    let interval: BillingInterval
    let slots: Int
    let state: SubscriptionState
    let currentPeriodStart: Date
    let currentPeriodEnd: Date
    let cancelAtPeriodEnd: Bool
    let autoRenew: Bool
    let gateway: String
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Store credit

struct CreditBalance: Codable, Equatable {
    let balanceMinor: Int
    let transactions: [CreditTransaction]

    /// Currency isn't returned on the balance; the platform bills in USD.
    var balance: Money { Money(minorUnits: balanceMinor, currency: "USD") }
}

struct CreditTransaction: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let amountMinor: Int            // signed: + added, - spent
    let reason: CreditReason
    let note: String?
    let invoiceId: String?
    let actorId: String?
    let createdAt: Date

    var amount: Money { Money(minorUnits: amountMinor, currency: "USD") }
    var isCredit: Bool { amountMinor >= 0 }
    var signedLabel: String { (isCredit ? "+" : "−") + Money(minorUnits: abs(amountMinor), currency: "USD").formatted }
}

// MARK: - Payment methods

struct PaymentMethod: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let gateway: String             // "stripe" | "paypal"
    let gatewayRef: String
    let brand: String?
    let last4: String?
    let expMonth: Int?
    let expYear: Int?
    let isDefault: Bool
    let createdAt: Date

    /// "Visa •••• 4242" / "PayPal".
    var displayLabel: String {
        if gateway == "paypal" { return "PayPal" }
        let name = (brand ?? "Card").capitalized
        if let last4 { return "\(name) •••• \(last4)" }
        return name
    }
    var expiryLabel: String? {
        guard let m = expMonth, let y = expYear else { return nil }
        return String(format: "%02d/%02d", m, y % 100)
    }
}

// MARK: - Config

struct BillingConfig: Codable, Equatable {
    struct Stripe: Codable, Equatable { let configured: Bool; let publishableKey: String? }
    struct PayPal: Codable, Equatable { let configured: Bool }
    let stripe: Stripe
    let paypal: PayPal
}
