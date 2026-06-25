import Foundation

// Codable models + DTOs for the seven admin config areas (Products, Templates,
// Coupons, Billing, Roles, Locations, Settings). Shapes mirror apps/panel-api.
//
// Conventions (handled by APIClient, so models stay plain):
//   • Responses are unwrapped from `{ success, data }` / `{ success, data, meta }`.
//   • `…Minor` fields are integer minor units; pair with a sibling `currency`.
//     Computed `Money` accessors format them.
//   • Dates decode/encode ISO-8601. Enums fall back to `.unknown` where the
//     backend might add cases, so an unexpected value never crashes a decode.
//
// Reused from elsewhere: `Money`, `NodeState`, `NodePing`, `AgentLatest`, `UserRole`.

// MARK: - Shared enums

enum ProductType: String, Codable, CaseIterable {
    case gameServer = "GAME_SERVER"
    case voiceServer = "VOICE_SERVER"
    case vps = "VPS"
    case dedicated = "DEDICATED"
    case addon = "ADDON"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProductType(rawValue: raw) ?? .unknown
    }
    var label: String {
        switch self {
        case .gameServer: return "Game server"
        case .voiceServer: return "Voice server"
        case .vps: return "VPS"
        case .dedicated: return "Dedicated"
        case .addon: return "Add-on"
        case .unknown: return "Product"
        }
    }
}

enum BillingModel: String, Codable, CaseIterable {
    case hardwareTier = "HARDWARE_TIER"
    case perSlot = "PER_SLOT"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BillingModel(rawValue: raw) ?? .unknown
    }
    var label: String {
        switch self {
        case .hardwareTier: return "Hardware tier"
        case .perSlot: return "Per slot"
        case .unknown: return "—"
        }
    }
}

enum BillingInterval: String, Codable, CaseIterable {
    case weekly = "WEEKLY"
    case biweekly = "BIWEEKLY"
    case monthly = "MONTHLY"
    case quarterly = "QUARTERLY"
    case semiannual = "SEMIANNUAL"
    case annual = "ANNUAL"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BillingInterval(rawValue: raw) ?? .unknown
    }
    /// Short suffix for price labels, e.g. "/mo".
    var shortSuffix: String {
        switch self {
        case .weekly: return "/wk"
        case .biweekly: return "/2wk"
        case .monthly: return "/mo"
        case .quarterly: return "/qtr"
        case .semiannual: return "/6mo"
        case .annual: return "/yr"
        case .unknown: return ""
        }
    }
    var label: String { rawValue.capitalized }
}

enum DeployMethod: String, Codable, CaseIterable {
    case docker = "DOCKER"
    case nativeProcess = "NATIVE_PROCESS"
    case windowsContainer = "WINDOWS_CONTAINER"
    case sandbox = "SANDBOX"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DeployMethod(rawValue: raw) ?? .unknown
    }
    var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

enum VariableType: String, Codable, CaseIterable {
    case string = "STRING"
    case number = "NUMBER"
    case boolean = "BOOLEAN"
    case `enum` = "ENUM"
    case secret = "SECRET"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VariableType(rawValue: raw) ?? .unknown
    }
    var label: String { rawValue.capitalized }
}

enum CouponKind: String, Codable, CaseIterable {
    case percent = "PERCENT"
    case fixed = "FIXED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CouponKind(rawValue: raw) ?? .unknown
    }
    var label: String {
        switch self {
        case .percent: return "Percent"
        case .fixed: return "Fixed"
        case .unknown: return "—"
        }
    }
}

enum InvoiceState: String, Codable, CaseIterable {
    case draft = "DRAFT"
    case open = "OPEN"
    case paid = "PAID"
    case void = "VOID"
    case uncollectible = "UNCOLLECTIBLE"
    case refunded = "REFUNDED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InvoiceState(rawValue: raw) ?? .unknown
    }
    var label: String { rawValue.capitalized }
}

enum PaymentState: String, Codable, CaseIterable {
    case pending = "PENDING"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case refunded = "REFUNDED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PaymentState(rawValue: raw) ?? .unknown
    }
    var label: String { rawValue.capitalized }
}

enum SubscriptionState: String, Codable, CaseIterable {
    case trialing = "TRIALING"
    case active = "ACTIVE"
    case pastDue = "PAST_DUE"
    case canceled = "CANCELED"
    case suspended = "SUSPENDED"
    case expired = "EXPIRED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SubscriptionState(rawValue: raw) ?? .unknown
    }
    var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

enum CreditReason: String, Codable, CaseIterable {
    case adminGrant = "ADMIN_GRANT"
    case refund = "REFUND"
    case giftCard = "GIFT_CARD"
    case invoicePayment = "INVOICE_PAYMENT"
    case adjustment = "ADJUSTMENT"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CreditReason(rawValue: raw) ?? .unknown
    }
    var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

enum EmailTheme: String, Codable, CaseIterable {
    case dark
    case light
}

enum PayPalMode: String, Codable, CaseIterable {
    case sandbox
    case live
}

// MARK: - Shared payloads

/// Embedded customer (userSelect) used across billing payloads.
struct EmbeddedUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? email : name
    }
}

/// Body for the orders/invoices bulk-delete endpoints.
struct BulkIdsBody: Encodable { let ids: [String] }

/// Result shape returned by bulk-delete endpoints.
struct BulkDeleteResult: Decodable {
    struct Skip: Decodable { let id: String; let reason: String }
    let deleted: [String]
    let skipped: [Skip]
}

// MARK: - Arbitrary JSON (dockerImages, installScript, configFiles, rules)

/// A loss-tolerant JSON value for free-form template fields. Mainly displayed
/// and round-tripped; the app doesn't deeply edit these.
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
            debugDescription: "Unsupported JSON value"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    /// Compact single-line preview for display.
    var preview: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let a): return "[\(a.count)]"
        case .object(let o): return "{\(o.count)}"
        }
    }
}

// MARK: - Area 1 · Products & pricing

struct AdminPrice: Codable, Identifiable, Equatable {
    let id: String
    let productId: String
    let hardwareTierId: String?      // nil = product-level price
    let interval: BillingInterval
    let currency: String
    let amountMinor: Int
    let stripePriceId: String?
    let paypalPlanId: String?
    let isActive: Bool

    var money: Money { Money(minorUnits: amountMinor, currency: currency) }
    /// e.g. "$12.00/mo".
    var label: String { money.formatted + interval.shortSuffix }
}

struct HardwareTier: Codable, Identifiable, Equatable {
    let id: String
    let productId: String
    let name: String
    let description: String?
    let cpuCores: Double
    let memoryMb: Int
    let diskMb: Int
    let recommendedPlayers: Int?
    let isRecommended: Bool
    let isActive: Bool
    let sortOrder: Int
    let prices: [AdminPrice]?
}

struct AdminProduct: Codable, Identifiable, Equatable {
    let id: String
    let type: ProductType
    let billingModel: BillingModel
    let name: String
    let slug: String
    let description: String?
    let isActive: Bool
    let cpuCores: Double?
    let memoryMb: Int?
    let diskMb: Int?
    let slots: Int?
    let allowedTemplateIds: [String]?
    let perSlot: Bool?
    let gameTemplateId: String?
    let minSlots: Int?
    let maxSlots: Int?
    let prices: [AdminPrice]?
    let hardwareTiers: [HardwareTier]?
}

struct CreateProductBody: Encodable {
    var type: ProductType
    var billingModel: BillingModel? = nil
    var name: String
    var slug: String
    var description: String? = nil
    var isActive: Bool? = nil
}

struct UpdateProductBody: Encodable {
    var name: String? = nil
    var slug: String? = nil
    var description: String? = nil
    var isActive: Bool? = nil
    var billingModel: BillingModel? = nil
}

struct CreateTierBody: Encodable {
    var name: String
    var description: String? = nil
    var cpuCores: Double
    var memoryMb: Int
    var diskMb: Int
    var recommendedPlayers: Int? = nil
    var isRecommended: Bool? = nil
    var isActive: Bool? = nil
    var sortOrder: Int? = nil
}

struct CreatePriceBody: Encodable {
    var interval: BillingInterval? = nil
    var currency: String? = nil
    var amountMinor: Int
    var isActive: Bool? = nil
}

// MARK: - Area 2 · Game templates / eggs

struct GameCategory: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let slug: String
    let iconUrl: String?
}

struct TemplateVariable: Codable, Identifiable, Equatable {
    let id: String
    let templateId: String
    let envName: String
    let displayName: String
    let description: String?
    let type: VariableType
    let defaultValue: String?
    let userEditable: Bool
    let userViewable: Bool
    let sortOrder: Int
}

struct GameTemplate: Codable, Identifiable, Equatable {
    let id: String
    let categoryId: String?
    let category: GameCategory?
    let name: String
    let slug: String
    let author: String
    let description: String?
    let version: Int
    let deployMethods: [DeployMethod]
    let supportsLinux: Bool
    let supportsWindows: Bool
    let dockerImages: JSONValue?
    let steamAppId: Int?
    let startupCommand: String
    let recCpuCores: Double
    let recMemoryMb: Int
    let recDiskMb: Int
    let isPublished: Bool
    let featured: Bool
    let sortOrder: Int
    let tags: [String]?
    let variables: [TemplateVariable]?

    var platformsLabel: String {
        [supportsLinux ? "Linux" : nil, supportsWindows ? "Windows" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// Subset of UpdateTemplateDTO covering the fields the app edits inline.
struct UpdateTemplateBody: Encodable {
    var name: String? = nil
    var author: String? = nil
    var description: String? = nil
    var isPublished: Bool? = nil
    var featured: Bool? = nil
    var sortOrder: Int? = nil
    var tags: [String]? = nil
}

// MARK: - Area 3 · Coupons & gift cards

struct Coupon: Codable, Identifiable, Equatable {
    struct Count: Codable, Equatable { let redemptions: Int }
    let id: String
    let code: String
    let description: String?
    let kind: CouponKind
    let value: Int                 // PERCENT: 1–100 ; FIXED: minor units
    let currency: String
    let minSubtotalMinor: Int?
    let maxRedemptions: Int?
    let timesRedeemed: Int
    let maxPerUser: Int?
    let startsAt: Date?
    let expiresAt: Date?
    let isActive: Bool
    let _count: Count?

    /// "20% off" or "$5.00 off".
    var valueLabel: String {
        switch kind {
        case .percent: return "\(value)% off"
        case .fixed: return Money(minorUnits: value, currency: currency).formatted + " off"
        case .unknown: return "\(value)"
        }
    }
    var redemptionsLabel: String {
        let used = _count?.redemptions ?? timesRedeemed
        if let max = maxRedemptions { return "\(used)/\(max) used" }
        return "\(used) used"
    }
}

struct CreateCouponBody: Encodable {
    var code: String
    var description: String? = nil
    var kind: CouponKind
    var value: Int
    var currency: String? = nil
    var minSubtotalMinor: Int? = nil
    var maxRedemptions: Int? = nil
    var maxPerUser: Int? = nil
    var expiresAt: Date? = nil
    var isActive: Bool? = nil
}

struct UpdateCouponBody: Encodable {
    var description: String? = nil
    var maxRedemptions: Int? = nil
    var maxPerUser: Int? = nil
    var expiresAt: Date? = nil
    var isActive: Bool? = nil
}

struct GiftCard: Codable, Identifiable, Equatable {
    let id: String
    let code: String
    let initialBalanceMinor: Int
    let balanceMinor: Int
    let currency: String
    let isActive: Bool
    let expiresAt: Date?
    let note: String?

    var balance: Money { Money(minorUnits: balanceMinor, currency: currency) }
    var initialBalance: Money { Money(minorUnits: initialBalanceMinor, currency: currency) }
}

struct CreateGiftCardBody: Encodable {
    var code: String? = nil
    var initialBalanceMinor: Int
    var currency: String? = nil
    var note: String? = nil
    var expiresAt: Date? = nil
    var isActive: Bool? = nil
}

struct UpdateGiftCardBody: Encodable {
    var isActive: Bool? = nil
    var note: String? = nil
    var expiresAt: Date? = nil
}

// MARK: - Area 4 · Billing (summary / orders / invoices / payments / credit)

struct BillingSummary: Codable, Equatable {
    let currency: String
    let revenueMinor: Int
    let outstandingMinor: Int
    let activeSubscriptions: Int
    let openInvoices: Int
    let paidInvoices: Int

    var revenue: Money { Money(minorUnits: revenueMinor, currency: currency) }
    var outstanding: Money { Money(minorUnits: outstandingMinor, currency: currency) }
}

/// An "order" is a Subscription row.
struct AdminOrder: Codable, Identifiable, Equatable {
    struct ProductRef: Codable, Equatable { let id: String; let name: String; let type: ProductType }
    let id: String
    let interval: BillingInterval
    let slots: Int
    let state: SubscriptionState
    let currentPeriodEnd: Date?
    let gateway: String?
    let user: EmbeddedUser?
    let product: ProductRef?
}

struct AdminBillingInvoice: Codable, Identifiable, Equatable {
    let id: String
    let number: String
    let userId: String
    let state: InvoiceState
    let currency: String
    let totalMinor: Int
    let amountPaidMinor: Int
    let pdfUrl: String?
    let dueAt: Date?
    let paidAt: Date?
    let createdAt: Date
    let user: EmbeddedUser?

    var total: Money { Money(minorUnits: totalMinor, currency: currency) }
}

struct Payment: Codable, Identifiable, Equatable {
    struct InvoiceRef: Codable, Equatable {
        let id: String
        let number: String
        let user: EmbeddedUser
    }
    let id: String
    let gateway: String
    let amountMinor: Int
    let currency: String
    let state: PaymentState
    let failureReason: String?
    let createdAt: Date
    let invoice: InvoiceRef

    var amount: Money { Money(minorUnits: amountMinor, currency: currency) }
}

// MARK: - Area 5 · Roles & permissions (RBAC)

struct Role: Codable, Identifiable, Equatable {
    struct Count: Codable, Equatable { let users: Int }
    let id: String
    let key: String
    let name: String
    let description: String?
    let isSystem: Bool
    let permissions: [String]
    let _count: Count?

    var isWildcard: Bool { permissions.contains("*") }
    var usersLabel: String {
        let n = _count?.users ?? 0
        return n == 1 ? "1 user" : "\(n) users"
    }
}

struct PermissionCatalog: Codable, Equatable {
    let wildcard: String
    let permissions: [String]
}

struct CreateRoleBody: Encodable {
    var key: String
    var name: String
    var description: String? = nil
    var permissions: [String]? = nil
}

struct UpdateRoleBody: Encodable {
    var name: String? = nil
    var description: String? = nil
    var permissions: [String]? = nil
}

// MARK: - Area 6 · Locations / regions

struct Region: Codable, Identifiable, Equatable {
    let id: String
    let code: String
    let name: String
    let country: String
}

struct CreateLocationBody: Encodable {
    var code: String
    var name: String
    var country: String
}

struct UpdateLocationBody: Encodable {
    var code: String? = nil
    var name: String? = nil
    var country: String? = nil
}

// MARK: - Area 7 · Settings (email / steam / gateways)

struct EmailConfigMasked: Codable, Equatable {
    let configured: Bool
    let host: String
    let port: Int
    let user: String
    let from: String
    let secure: Bool
    let theme: EmailTheme
    let passwordSet: Bool
}

struct SetEmailConfigBody: Encodable {
    var host: String? = nil
    var port: Int? = nil
    var user: String? = nil
    var password: String? = nil
    var from: String? = nil
    var secure: Bool? = nil
    var theme: EmailTheme? = nil
}

struct TestEmailResult: Codable { let delivered: Bool }

struct SteamConfigMasked: Codable, Equatable {
    let username: String
    let apiKeySet: Bool
    let passwordSet: Bool
    let loginConfigured: Bool
    let guardCodePending: Bool
}

struct SetSteamConfigBody: Encodable {
    var apiKey: String? = nil
    var username: String? = nil
    var password: String? = nil
    var guardCode: String? = nil
}

struct GatewayConfigMasked: Codable, Equatable {
    struct Stripe: Codable, Equatable {
        let configured: Bool
        let secretKeyMasked: String
        let webhookSecretSet: Bool
        let publishableKey: String
        let statementDescriptor: String
    }
    struct PayPal: Codable, Equatable {
        let configured: Bool
        let clientId: String
        let clientSecretSet: Bool
        let mode: String
        let webhookId: String
    }
    let stripe: Stripe
    let paypal: PayPal
}

struct SetGatewayConfigBody: Encodable {
    var stripeSecretKey: String? = nil
    var stripeWebhookSecret: String? = nil
    var stripePublishableKey: String? = nil
    var stripeStatementDescriptor: String? = nil
    var paypalClientId: String? = nil
    var paypalClientSecret: String? = nil
    var paypalMode: PayPalMode? = nil
    var paypalWebhookId: String? = nil
}
