import XCTest
@testable import ReFxApp

/// Decode + proration/branch logic for the server plan-change models.
final class ServerUpgradeDecodingTests: XCTestCase {

    func testUpgradeOptionsTieredDecodes() throws {
        let json = """
        {
          "perSlot": false, "currency": "USD", "interval": "MONTHLY",
          "prorationFactor": 0.5, "pendingChange": null,
          "slots": 1, "minSlots": 1, "maxSlots": 1, "slotStep": 1,
          "cpuPerSlot": 0, "memoryMbPerSlot": 0, "diskMbPerSlot": 0,
          "perSlotAmountMinor": 0,
          "cpuCores": 2, "memoryMb": 4096, "diskMb": 20480,
          "currentTierId": "t_1",
          "tiers": [
            { "id": "t_1", "name": "Standard", "description": null, "cpuCores": 2.0, "memoryMb": 4096, "diskMb": 20480, "recommendedPlayers": 20, "isRecommended": false, "amountMinor": 1200 },
            { "id": "t_2", "name": "Pro", "description": "more power", "cpuCores": 4.0, "memoryMb": 8192, "diskMb": 40960, "recommendedPlayers": 50, "isRecommended": true, "amountMinor": 2400 }
          ]
        }
        """
        let opts = try TestJSON.decode(UpgradeOptions.self, json)
        XCTAssertFalse(opts.perSlot)
        XCTAssertNil(opts.pendingChange)
        XCTAssertEqual(opts.currentTierId, "t_1")
        XCTAssertEqual(opts.tiers.count, 2)
        XCTAssertEqual(opts.tiers[1].price(currency: "USD")?.minorUnits, 2400)
    }

    func testUpgradeOptionsPendingDowngrade() throws {
        let json = """
        {
          "perSlot": true, "currency": "USD", "interval": "MONTHLY", "prorationFactor": 1.0,
          "pendingChange": { "kind": "downgrade", "invoiceId": null, "effectiveAt": "2026-07-01T00:00:00Z" },
          "slots": 8, "minSlots": 4, "maxSlots": 64, "slotStep": 4,
          "cpuPerSlot": 0.5, "memoryMbPerSlot": 256, "diskMbPerSlot": 512,
          "perSlotAmountMinor": 200,
          "cpuCores": 4, "memoryMb": 2048, "diskMb": 4096,
          "currentTierId": null, "tiers": []
        }
        """
        let opts = try TestJSON.decode(UpgradeOptions.self, json)
        let pending = try XCTUnwrap(opts.pendingChange)
        XCTAssertFalse(pending.isUpgrade)
        XCTAssertNotNil(pending.effectiveAt)
        XCTAssertEqual(opts.perSlotAmount.minorUnits, 200)
    }

    func testUpgradePreviewProration() throws {
        let increase = try TestJSON.decode(UpgradePreview.self,
            #"{ "amountMinor": 2400, "currency": "USD", "interval": "MONTHLY", "deltaMinor": 1200 }"#)
        XCTAssertTrue(increase.isIncrease)
        XCTAssertFalse(increase.isDowngrade)
        // due today = delta * proration = 1200 * 0.5 = 600
        XCTAssertEqual(increase.dueToday(prorationFactor: 0.5).minorUnits, 600)

        let downgrade = try TestJSON.decode(UpgradePreview.self,
            #"{ "amountMinor": 600, "currency": "USD", "interval": "MONTHLY", "deltaMinor": -600 }"#)
        XCTAssertTrue(downgrade.isDowngrade)
        // downgrades never charge today
        XCTAssertEqual(downgrade.dueToday(prorationFactor: 0.5).minorUnits, 0)
    }

    func testPlanChangeResultBranches() throws {
        let applied = try TestJSON.decode(PlanChangeResult.self,
            #"{ "status": "applied", "effectiveAt": null, "invoiceId": null, "amountMinor": null, "currency": null }"#)
        XCTAssertEqual(applied.kind, .applied)
        XCTAssertNil(applied.amountDue)

        let invoiced = try TestJSON.decode(PlanChangeResult.self,
            #"{ "status": "invoiced", "effectiveAt": null, "invoiceId": "inv_9", "amountMinor": 700, "currency": "USD" }"#)
        XCTAssertEqual(invoiced.kind, .invoiced)
        XCTAssertEqual(invoiced.invoiceId, "inv_9")
        XCTAssertEqual(invoiced.amountDue?.minorUnits, 700)

        let scheduled = try TestJSON.decode(PlanChangeResult.self,
            #"{ "status": "scheduled", "effectiveAt": "2026-07-01T00:00:00Z", "invoiceId": null, "amountMinor": null, "currency": null }"#)
        XCTAssertEqual(scheduled.kind, .scheduled)
        XCTAssertNotNil(scheduled.effectiveAt)

        let weird = try TestJSON.decode(PlanChangeResult.self,
            #"{ "status": "??", "effectiveAt": null, "invoiceId": null, "amountMinor": null, "currency": null }"#)
        XCTAssertEqual(weird.kind, .unknown)
    }

    // MARK: - Slot-range normalization (Stepper crash guard)

    /// A malformed backend payload (min > max, step <= 0) must NOT produce a
    /// reversed ClosedRange — `a...b` traps when a > b, which would crash the
    /// new-server and upgrade Stepper screens.
    func testUpgradeOptionsSlotRangeNeverTraps() throws {
        let json = """
        {
          "perSlot": true, "currency": "USD", "interval": "MONTHLY", "prorationFactor": 1.0,
          "pendingChange": null,
          "slots": 8, "minSlots": 64, "maxSlots": 4, "slotStep": 0,
          "cpuPerSlot": 0.5, "memoryMbPerSlot": 256, "diskMbPerSlot": 512,
          "perSlotAmountMinor": 200,
          "cpuCores": 4, "memoryMb": 2048, "diskMb": 4096,
          "currentTierId": null, "tiers": []
        }
        """
        let opts = try TestJSON.decode(UpgradeOptions.self, json)
        XCTAssertEqual(opts.slotRange, 4...64)         // bounds normalized low→high
        XCTAssertEqual(opts.safeSlotStep, 1)           // step clamped to >= 1
        XCTAssertLessThanOrEqual(opts.slotRange.lowerBound, opts.slotRange.upperBound)
    }

    func testCatalogProductSlotRangeNeverTraps() throws {
        let json = """
        {
          "id": "p_1", "type": "GAME_SERVER", "billingModel": "PER_SLOT",
          "name": "Per-slot", "slug": "per-slot", "description": null, "isActive": true,
          "allowedTemplateIds": [], "perSlot": true, "gameTemplateId": "tpl_1",
          "minSlots": 32, "maxSlots": 8, "slotStep": -2,
          "prices": [], "hardwareTiers": []
        }
        """
        let product = try TestJSON.decode(CatalogProduct.self, json)
        XCTAssertEqual(product.slotRange, 8...32)
        XCTAssertEqual(product.safeSlotStep, 1)
    }
}
