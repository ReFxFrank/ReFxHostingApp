import XCTest
@testable import ReFxApp

/// Decode + computed-property contracts for the customer billing models
/// (`/billing/*`). JSON shapes are authored from the panel-api reference so the
/// tests double as a recorded spec and catch field/shape drift.
final class CustomerBillingDecodingTests: XCTestCase {

    func testInvoiceDecodesWithLineItemsAndComputedTotals() throws {
        let json = """
        {
          "id": "inv_1", "number": "RFX-1001", "userId": "u_1",
          "subscriptionId": "sub_1", "state": "OPEN", "currency": "USD",
          "subtotalMinor": 1500, "discountMinor": 500, "couponCode": "SAVE5",
          "taxMinor": 100, "totalMinor": 1100, "amountPaidMinor": 400,
          "taxType": "US_SALES_TAX", "taxRatePct": 7.0,
          "dueAt": "2026-07-01T00:00:00.000Z", "paidAt": null,
          "createdAt": "2026-06-25T12:00:00Z",
          "lineItems": [
            { "id": "li_1", "invoiceId": "inv_1", "description": "Standard tier", "quantity": 1, "unitMinor": 1500, "amountMinor": 1500 }
          ],
          "payments": null
        }
        """
        let invoice = try TestJSON.decode(Invoice.self, json)
        XCTAssertEqual(invoice.number, "RFX-1001")
        XCTAssertEqual(invoice.state, .open)
        XCTAssertTrue(invoice.isOpen)
        XCTAssertFalse(invoice.isPaid)
        XCTAssertEqual(invoice.lineItems?.count, 1)
        // outstanding = total - amountPaid = 1100 - 400 = 700
        XCTAssertEqual(invoice.outstanding.minorUnits, 700)
        XCTAssertTrue(invoice.total.formatted.contains("11.00"))
    }

    func testInvoiceUnknownStateFallsBack() throws {
        let json = """
        { "id": "i", "number": "N", "userId": "u", "subscriptionId": null,
          "state": "SOMETHING_NEW", "currency": "USD",
          "subtotalMinor": 0, "discountMinor": 0, "couponCode": null,
          "taxMinor": 0, "totalMinor": 0, "amountPaidMinor": 0,
          "taxType": null, "taxRatePct": null, "dueAt": null, "paidAt": null,
          "createdAt": "2026-06-25T12:00:00Z", "lineItems": null, "payments": null }
        """
        let invoice = try TestJSON.decode(Invoice.self, json)
        XCTAssertEqual(invoice.state, .unknown)
        // A defensive default keeps outstanding non-negative.
        XCTAssertEqual(invoice.outstanding.minorUnits, 0)
    }

    func testSubscriptionListItemRenewalLabel() throws {
        let json = """
        {
          "id": "sub_1", "productId": "p_1", "priceId": "pr_1",
          "interval": "MONTHLY", "slots": 3, "state": "ACTIVE",
          "currentPeriodStart": "2026-06-01T00:00:00Z",
          "currentPeriodEnd": "2026-07-01T00:00:00Z",
          "cancelAtPeriodEnd": false, "autoRenew": true, "gateway": "stripe",
          "createdAt": "2026-06-01T00:00:00Z",
          "product": { "id": "p_1", "name": "Game Server", "type": "GAME_SERVER", "billingModel": "PER_SLOT", "perSlot": true },
          "hardwareTier": null,
          "servers": [ { "id": "s_1", "shortId": "abcd", "name": "My Server", "state": "RUNNING" } ],
          "renewalAmountMinor": 1800, "currency": "USD"
        }
        """
        let sub = try TestJSON.decode(SubscriptionListItem.self, json)
        XCTAssertEqual(sub.state, .active)
        XCTAssertEqual(sub.product.type, .gameServer)
        XCTAssertEqual(sub.servers.first?.name, "My Server")
        XCTAssertTrue(sub.renewalLabel.contains("18.00"))
        XCTAssertTrue(sub.renewalLabel.hasSuffix("/mo"))
    }

    func testCreditBalanceAndSignedLabels() throws {
        let json = """
        {
          "balanceMinor": 2500,
          "transactions": [
            { "id": "t1", "userId": "u", "amountMinor": 5000, "reason": "ADMIN_GRANT", "note": "welcome", "invoiceId": null, "actorId": "a", "createdAt": "2026-06-20T00:00:00Z" },
            { "id": "t2", "userId": "u", "amountMinor": -2500, "reason": "INVOICE_PAYMENT", "note": null, "invoiceId": "inv_9", "actorId": null, "createdAt": "2026-06-22T00:00:00Z" }
          ]
        }
        """
        let credit = try TestJSON.decode(CreditBalance.self, json)
        XCTAssertEqual(credit.balance.minorUnits, 2500)
        XCTAssertTrue(credit.transactions[0].isCredit)
        XCTAssertFalse(credit.transactions[1].isCredit)
        XCTAssertTrue(credit.transactions[0].signedLabel.hasPrefix("+"))
        XCTAssertFalse(credit.transactions[1].signedLabel.hasPrefix("+"))
        XCTAssertTrue(credit.transactions[1].signedLabel.contains("25.00"))
    }

    func testPaymentMethodDisplay() throws {
        let card = """
        { "id": "pm_1", "userId": "u", "gateway": "stripe", "gatewayRef": "pm_x",
          "brand": "visa", "last4": "4242", "expMonth": 4, "expYear": 2030,
          "isDefault": true, "createdAt": "2026-06-01T00:00:00Z" }
        """
        let pm = try TestJSON.decode(PaymentMethod.self, card)
        XCTAssertTrue(pm.displayLabel.hasPrefix("Visa"))
        XCTAssertTrue(pm.displayLabel.hasSuffix("4242"))
        XCTAssertEqual(pm.expiryLabel, "04/30")
        XCTAssertTrue(pm.isDefault)

        let paypal = """
        { "id": "pm_2", "userId": "u", "gateway": "paypal", "gatewayRef": "ba_x",
          "brand": null, "last4": null, "expMonth": null, "expYear": null,
          "isDefault": false, "createdAt": "2026-06-01T00:00:00Z" }
        """
        let pp = try TestJSON.decode(PaymentMethod.self, paypal)
        XCTAssertEqual(pp.displayLabel, "PayPal")
        XCTAssertNil(pp.expiryLabel)
    }

    func testPayInvoiceResultVariants() throws {
        let paid = try TestJSON.decode(PayInvoiceResult.self, #"{ "paid": true, "checkoutUrl": null, "reason": null }"#)
        XCTAssertTrue(paid.paid)
        XCTAssertNil(paid.checkoutUrl)

        let hosted = try TestJSON.decode(PayInvoiceResult.self, #"{ "paid": false, "checkoutUrl": "https://checkout.stripe.com/x", "reason": null }"#)
        XCTAssertFalse(hosted.paid)
        XCTAssertEqual(hosted.checkoutUrl, "https://checkout.stripe.com/x")
    }

    func testBillingConfig() throws {
        let json = """
        { "stripe": { "configured": true, "publishableKey": "pk_test_123" },
          "paypal": { "configured": false } }
        """
        let config = try TestJSON.decode(BillingConfig.self, json)
        XCTAssertTrue(config.stripe.configured)
        XCTAssertEqual(config.stripe.publishableKey, "pk_test_123")
        XCTAssertFalse(config.paypal.configured)
    }
}
