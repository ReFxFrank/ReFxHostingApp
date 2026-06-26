import XCTest
@testable import ReFxApp

/// Decode + computed-helper coverage for admin models that drive staff screens:
/// Coupon value/redemption labels, and AdminUserDetail's `_count` remap plus its
/// account-state flags.
final class AdminModelDecodingTests: XCTestCase {

    func testPercentCouponLabels() throws {
        let json = """
        {
          "id": "c1", "code": "SAVE20", "description": null, "kind": "PERCENT",
          "value": 20, "currency": "USD", "minSubtotalMinor": null,
          "maxRedemptions": 100, "timesRedeemed": 5, "maxPerUser": null,
          "startsAt": null, "expiresAt": null, "isActive": true,
          "_count": { "redemptions": 7 }
        }
        """
        let coupon = try TestJSON.decode(Coupon.self, json)
        XCTAssertEqual(coupon.valueLabel, "20% off")
        // used = _count.redemptions (7), preferred over timesRedeemed (5)
        XCTAssertEqual(coupon.redemptionsLabel, "7/100 used")
        XCTAssertTrue(coupon.isActive)
    }

    func testFixedCouponLabelUsesMoney() throws {
        let json = """
        {
          "id": "c2", "code": "FIVE", "description": null, "kind": "FIXED",
          "value": 500, "currency": "USD", "minSubtotalMinor": null,
          "maxRedemptions": null, "timesRedeemed": 2, "maxPerUser": null,
          "startsAt": null, "expiresAt": null, "isActive": false, "_count": null
        }
        """
        let coupon = try TestJSON.decode(Coupon.self, json)
        XCTAssertTrue(coupon.valueLabel.contains("5.00"))
        XCTAssertTrue(coupon.valueLabel.contains("off"))
        // No max and no _count → falls back to timesRedeemed.
        XCTAssertEqual(coupon.redemptionsLabel, "2 used")
    }

    func testAdminUserDetailSuspendedWithCountRemap() throws {
        let json = """
        {
          "id": "u1", "email": "ada@example.com", "firstName": "Ada", "lastName": "Lovelace",
          "globalRole": "ADMIN", "state": "SUSPENDED",
          "createdAt": "2026-01-01T00:00:00Z", "emailVerifiedAt": "2026-01-02T00:00:00Z",
          "ownedServers": [], "subscriptions": [], "invoices": [],
          "_count": { "ownedServers": 3, "subscriptions": 1, "tickets": 2 }
        }
        """
        let user = try TestJSON.decode(AdminUserDetail.self, json)
        XCTAssertEqual(user.displayName, "Ada Lovelace")
        XCTAssertEqual(user.role, .admin)
        XCTAssertTrue(user.isSuspended)
        XCTAssertFalse(user.isBanned)
        XCTAssertTrue(user.emailVerified)
        XCTAssertEqual(user.counts?.ownedServers, 3)   // JSON `_count` → `counts`
        XCTAssertEqual(user.counts?.tickets, 2)
    }

    func testAdminUserDetailBannedAndUnverifiedFallbacks() throws {
        let json = """
        {
          "id": "u2", "email": "nobody@example.com", "firstName": null, "lastName": null,
          "globalRole": null, "state": "BANNED",
          "createdAt": null, "emailVerifiedAt": null,
          "ownedServers": [], "subscriptions": [], "invoices": [], "_count": null
        }
        """
        let user = try TestJSON.decode(AdminUserDetail.self, json)
        XCTAssertEqual(user.displayName, "nobody@example.com")   // no name → email
        XCTAssertEqual(user.role, .unknown)                      // null globalRole
        XCTAssertTrue(user.isBanned)
        XCTAssertTrue(user.isSuspended)                          // banned counts as suspended-or-worse
        XCTAssertFalse(user.emailVerified)
        XCTAssertNil(user.counts)
    }
}
