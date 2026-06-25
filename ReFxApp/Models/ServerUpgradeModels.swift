import Foundation

// Customer server plan/tier/slot change (`/servers/:id/upgrade*`). Money is
// integer minor units paired with `currency`. Branch on `perSlot`:
// true → slot stepper bounds; false → `tiers` + `currentTierId`.

struct UpgradeOptions: Codable, Equatable {
    let perSlot: Bool
    let currency: String
    let interval: String
    let prorationFactor: Double          // 0…1 fraction of the current period remaining
    let pendingChange: PendingChange?
    let slots: Int
    let minSlots: Int
    let maxSlots: Int
    let slotStep: Int
    let cpuPerSlot: Double
    let memoryMbPerSlot: Int
    let diskMbPerSlot: Int
    let perSlotAmountMinor: Int
    let cpuCores: Int                    // current resources
    let memoryMb: Int
    let diskMb: Int
    let currentTierId: String?
    let tiers: [Tier]

    struct PendingChange: Codable, Equatable {
        let kind: String                 // "upgrade" | "downgrade"
        let invoiceId: String?
        let effectiveAt: Date?

        var isUpgrade: Bool { kind == "upgrade" }
    }

    struct Tier: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let description: String?
        let cpuCores: Double
        let memoryMb: Int
        let diskMb: Int
        let recommendedPlayers: Int?
        let isRecommended: Bool
        let amountMinor: Int?            // recurring price at the sub's interval+currency

        func price(currency: String) -> Money? {
            amountMinor.map { Money(minorUnits: $0, currency: currency) }
        }
    }

    var perSlotAmount: Money { Money(minorUnits: perSlotAmountMinor, currency: currency) }
}

struct UpgradePreview: Codable, Equatable {
    let amountMinor: Int                  // NEW recurring amount (not due-today)
    let currency: String
    let interval: String
    let deltaMinor: Int                   // can be negative (downgrade)

    var newRecurring: Money { Money(minorUnits: amountMinor, currency: currency) }
    var delta: Money { Money(minorUnits: abs(deltaMinor), currency: currency) }
    var isIncrease: Bool { deltaMinor > 0 }
    var isDowngrade: Bool { deltaMinor < 0 }

    /// Prorated amount charged today for an increase (0 for same/downgrade).
    func dueToday(prorationFactor: Double) -> Money {
        let due = deltaMinor > 0 ? Int((Double(deltaMinor) * prorationFactor).rounded()) : 0
        return Money(minorUnits: due, currency: currency)
    }
}

struct UpgradeServerDTO: Encodable {
    var hardwareTierId: String? = nil    // UUID (tiered products)
    var slots: Int? = nil                // >=1 (per-slot products)
    var cpuCores: Double? = nil          // >=0.1
    var memoryMb: Int? = nil             // >=256
    var diskMb: Int? = nil               // >=1024
}

/// `POST /upgrade` — decode by `status`.
struct PlanChangeResult: Codable {
    let status: String                   // "applied" | "scheduled" | "invoiced"
    let effectiveAt: Date?               // scheduled only
    let invoiceId: String?               // invoiced only
    let amountMinor: Int?                // invoiced only — amount DUE NOW
    let currency: String?

    enum Status: String { case applied, scheduled, invoiced, unknown }
    var kind: Status { Status(rawValue: status) ?? .unknown }
    var amountDue: Money? {
        guard let amountMinor, let currency else { return nil }
        return Money(minorUnits: amountMinor, currency: currency)
    }
}

struct CancelPlanChangeResult: Codable { let canceled: Bool }
