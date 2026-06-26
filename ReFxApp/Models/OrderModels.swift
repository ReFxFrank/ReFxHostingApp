import Foundation

// New-server checkout (`POST /orders`) + the catalog/account reads that drive it.
// Catalog types are `Catalog`-prefixed to avoid clashing with the staff admin
// models. Shared enums (ProductType, BillingModel, BillingInterval, VariableType,
// CouponKind) and `Region` are reused. Money = integer minor units + currency.

// MARK: - Catalog

struct CatalogProduct: Codable, Identifiable, Equatable {
    let id: String
    let type: ProductType
    let billingModel: BillingModel
    let name: String
    let slug: String
    let description: String?
    let isActive: Bool
    let allowedTemplateIds: [String]      // empty = all templates allowed
    let perSlot: Bool
    let gameTemplateId: String?           // PER_SLOT products are bound to one template
    let minSlots: Int
    let maxSlots: Int
    let slotStep: Int
    let prices: [CatalogPrice]            // product-level (hardwareTierId == nil)
    let hardwareTiers: [CatalogTier]

    var isPerSlot: Bool { perSlot || billingModel == .perSlot }
    /// Active product-level prices (used for per-slot products).
    var productPrices: [CatalogPrice] { prices.filter { $0.isActive && $0.hardwareTierId == nil } }

    /// Server bounds can arrive malformed (min > max). Normalize so a SwiftUI
    /// Stepper range built from these never traps (`a...b` precondition: a <= b).
    var slotRange: ClosedRange<Int> {
        let lo = min(minSlots, maxSlots), hi = max(minSlots, maxSlots)
        return lo...hi
    }
    /// Stepper step must be >= 1; a 0/negative step from the server would trap.
    var safeSlotStep: Int { max(1, slotStep) }
}

struct CatalogPrice: Codable, Identifiable, Equatable {
    let id: String
    let productId: String
    let hardwareTierId: String?
    let interval: BillingInterval
    let currency: String
    let amountMinor: Int
    let isActive: Bool

    var money: Money { Money(minorUnits: amountMinor, currency: currency) }
    var label: String { money.formatted + interval.shortSuffix }
}

struct CatalogTier: Codable, Identifiable, Equatable {
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
    let prices: [CatalogPrice]

    var activePrices: [CatalogPrice] { prices.filter { $0.isActive } }
    var resourceLabel: String {
        String(format: "%.1f vCPU · %dGB RAM · %dGB disk", cpuCores, memoryMb / 1024, diskMb / 1024)
    }
}

struct CatalogTemplate: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let slug: String
    let description: String?
    let author: String
    let category: Category?
    let recCpuCores: Double
    let recMemoryMb: Int
    let recDiskMb: Int
    let supportsLinux: Bool
    let supportsWindows: Bool
    let variables: [CatalogTemplateVariable]

    struct Category: Codable, Equatable { let id: String; let name: String; let slug: String; let iconUrl: String? }
}

struct CatalogTemplateVariable: Codable, Identifiable, Equatable {
    let id: String
    let envName: String
    let displayName: String
    let description: String?
    let type: VariableType
    let defaultValue: String?
    let userEditable: Bool
    let userViewable: Bool
    let sortOrder: Int
}

struct PlacementNode: Codable, Identifiable, Equatable { let id: String; let name: String }

// MARK: - Account profile (order preconditions live on the User row)

struct OrderProfile: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let emailVerifiedAt: Date?
    let firstName: String?
    let lastName: String?
    let phone: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let region: String?               // state / province (free text)
    let postalCode: String?
    let country: String?
    let creditBalanceMinor: Int?

    var emailVerified: Bool { emailVerifiedAt != nil }
    var creditBalance: Money { Money(minorUnits: creditBalanceMinor ?? 0, currency: "USD") }
    var hasAddress: Bool {
        !(addressLine1 ?? "").isEmpty && !(city ?? "").isEmpty &&
        !(postalCode ?? "").isEmpty && !(country ?? "").isEmpty
    }
    /// US billing addresses must include a state.
    var needsState: Bool { (country ?? "").uppercased() == "US" && (region ?? "").isEmpty }
    var orderReady: Bool { emailVerified && hasAddress && !needsState }
}

struct UpdateProfileBody: Encodable {
    var firstName: String? = nil
    var lastName: String? = nil
    var phone: String? = nil
    var addressLine1: String? = nil
    var addressLine2: String? = nil
    var city: String? = nil
    var region: String? = nil
    var postalCode: String? = nil
    var country: String? = nil
}

// MARK: - Order

struct CreateOrderBody: Encodable {
    var productId: String
    var priceId: String
    var templateId: String
    var name: String
    var hardwareTierId: String? = nil
    var regionId: String? = nil
    var nodeId: String? = nil
    var slots: Int? = nil
    var couponCode: String? = nil
    var giftCardCode: String? = nil
    var useCredit: Bool? = nil
    var paymentMethodId: String? = nil
    var gateway: String? = nil
    var environment: [String: String]? = nil
}

struct OrderResult: Codable {
    let serverId: String
    let subscriptionId: String
    let invoiceId: String
    let checkoutUrl: String?
    let paid: Bool
}

// MARK: - Coupon / gift-card preview

struct CouponValidateResult: Codable {
    let valid: Bool
    let code: String
    let kind: CouponKind
    let value: Int
    let discountMinor: Int
}

struct GiftCardLookupResult: Codable {
    let code: String
    let balanceMinor: Int
    let currency: String

    var balance: Money { Money(minorUnits: balanceMinor, currency: currency) }
}
