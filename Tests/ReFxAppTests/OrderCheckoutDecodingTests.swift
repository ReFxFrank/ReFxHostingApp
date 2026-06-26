import XCTest
@testable import ReFxApp

/// Decode + logic contracts for the new-server checkout models (catalog, order,
/// account preconditions).
final class OrderCheckoutDecodingTests: XCTestCase {

    func testCatalogProductTieredDecodes() throws {
        let json = """
        {
          "id": "p_1", "type": "GAME_SERVER", "billingModel": "HARDWARE_TIER",
          "name": "Minecraft", "slug": "minecraft", "description": "Java & Bedrock",
          "isActive": true, "cpuCores": null, "memoryMb": null, "diskMb": null, "slots": null,
          "allowedTemplateIds": [], "perSlot": false, "gameTemplateId": null,
          "minSlots": 1, "maxSlots": 1, "slotStep": 1,
          "cpuPerSlot": 0, "memoryMbPerSlot": 0, "diskMbPerSlot": 0,
          "paypalProductId": null,
          "createdAt": "2026-06-01T00:00:00Z", "updatedAt": "2026-06-01T00:00:00Z",
          "prices": [],
          "hardwareTiers": [
            {
              "id": "t_1", "productId": "p_1", "name": "Standard", "description": null,
              "cpuCores": 2.0, "memoryMb": 4096, "diskMb": 20480,
              "recommendedPlayers": 20, "isRecommended": true, "isActive": true, "sortOrder": 0,
              "createdAt": "2026-06-01T00:00:00Z", "updatedAt": "2026-06-01T00:00:00Z",
              "prices": [
                { "id": "pr_1", "productId": "p_1", "hardwareTierId": "t_1", "interval": "MONTHLY", "currency": "USD", "amountMinor": 1200, "stripePriceId": null, "paypalPlanId": null, "isActive": true }
              ]
            }
          ]
        }
        """
        let product = try TestJSON.decode(CatalogProduct.self, json)
        XCTAssertEqual(product.type, .gameServer)
        XCTAssertFalse(product.isPerSlot)
        XCTAssertTrue(product.allowedTemplateIds.isEmpty)        // empty = all templates allowed
        XCTAssertEqual(product.hardwareTiers.count, 1)
        let tier = try XCTUnwrap(product.hardwareTiers.first)
        XCTAssertTrue(tier.isRecommended)
        XCTAssertEqual(tier.activePrices.first?.amountMinor, 1200)
        XCTAssertTrue(tier.resourceLabel.contains("4GB RAM"))
    }

    func testCatalogProductPerSlotProductPrices() throws {
        let json = """
        {
          "id": "p_2", "type": "GAME_SERVER", "billingModel": "PER_SLOT",
          "name": "Slots Game", "slug": "slots", "description": null, "isActive": true,
          "allowedTemplateIds": ["tmpl_1"], "perSlot": true, "gameTemplateId": "tmpl_1",
          "minSlots": 4, "maxSlots": 64, "slotStep": 4,
          "createdAt": "2026-06-01T00:00:00Z", "updatedAt": "2026-06-01T00:00:00Z",
          "prices": [
            { "id": "pr_slot", "productId": "p_2", "hardwareTierId": null, "interval": "MONTHLY", "currency": "USD", "amountMinor": 200, "isActive": true }
          ],
          "hardwareTiers": []
        }
        """
        let product = try TestJSON.decode(CatalogProduct.self, json)
        XCTAssertTrue(product.isPerSlot)
        XCTAssertEqual(product.productPrices.count, 1)
        XCTAssertNil(product.productPrices.first?.hardwareTierId)
        XCTAssertEqual(product.gameTemplateId, "tmpl_1")
    }

    func testCatalogTemplateWithVariables() throws {
        let json = """
        {
          "id": "tmpl_1", "name": "Vanilla", "slug": "vanilla", "description": null, "author": "ReFx",
          "category": { "id": "c1", "name": "Minecraft", "slug": "mc", "iconUrl": null },
          "dockerImages": { "Java 21": "ghcr.io/refx/mc:21" },
          "recCpuCores": 1.0, "recMemoryMb": 1024, "recDiskMb": 5120,
          "supportsLinux": true, "supportsWindows": false,
          "variables": [
            { "id": "v1", "envName": "SERVER_JARFILE", "displayName": "Jar file", "description": "the jar",
              "type": "STRING", "defaultValue": "server.jar", "rules": {}, "userEditable": true, "userViewable": true, "sortOrder": 0 },
            { "id": "v2", "envName": "EULA", "displayName": "Accept EULA", "description": null,
              "type": "BOOLEAN", "defaultValue": "true", "rules": {}, "userEditable": false, "userViewable": true, "sortOrder": 1 }
          ]
        }
        """
        let template = try TestJSON.decode(CatalogTemplate.self, json)
        XCTAssertEqual(template.category?.name, "Minecraft")
        XCTAssertEqual(template.variables.count, 2)
        XCTAssertEqual(template.variables[0].type, .string)
        XCTAssertEqual(template.variables[1].type, .boolean)
        XCTAssertTrue(template.variables[0].userEditable)
    }

    func testOrderProfilePreconditions() throws {
        // Verified + complete non-US address → ready.
        let ready = try TestJSON.decode(OrderProfile.self, profileJSON(
            emailVerifiedAt: "\"2026-01-01T00:00:00Z\"", country: "GB", region: "null"))
        XCTAssertTrue(ready.emailVerified)
        XCTAssertTrue(ready.hasAddress)
        XCTAssertFalse(ready.needsState)
        XCTAssertTrue(ready.orderReady)

        // US without a state → needsState, not ready.
        let usNoState = try TestJSON.decode(OrderProfile.self, profileJSON(
            emailVerifiedAt: "\"2026-01-01T00:00:00Z\"", country: "US", region: "null"))
        XCTAssertTrue(usNoState.needsState)
        XCTAssertFalse(usNoState.orderReady)

        // Unverified email → not ready even with full address.
        let unverified = try TestJSON.decode(OrderProfile.self, profileJSON(
            emailVerifiedAt: "null", country: "GB", region: "null"))
        XCTAssertFalse(unverified.emailVerified)
        XCTAssertFalse(unverified.orderReady)
    }

    func testOrderResultAndCouponDecode() throws {
        let order = try TestJSON.decode(OrderResult.self,
            #"{ "serverId": "s1", "subscriptionId": "sub1", "invoiceId": "inv1", "checkoutUrl": null, "paid": true }"#)
        XCTAssertTrue(order.paid)
        XCTAssertEqual(order.serverId, "s1")

        let coupon = try TestJSON.decode(CouponValidateResult.self,
            #"{ "valid": true, "code": "SAVE10", "kind": "PERCENT", "value": 10, "discountMinor": 120 }"#)
        XCTAssertTrue(coupon.valid)
        XCTAssertEqual(coupon.kind, .percent)
        XCTAssertEqual(coupon.discountMinor, 120)
    }

    // MARK: helpers

    private func profileJSON(emailVerifiedAt: String, country: String, region: String) -> String {
        """
        {
          "id": "u_1", "email": "a@b.com", "emailVerifiedAt": \(emailVerifiedAt),
          "firstName": "A", "lastName": "B", "phone": null,
          "addressLine1": "1 Main St", "addressLine2": null, "city": "Town",
          "region": \(region), "postalCode": "12345", "country": "\(country)",
          "creditBalanceMinor": 0
        }
        """
    }
}
