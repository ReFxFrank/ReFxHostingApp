import XCTest
@testable import ReFxApp

/// The push deep-link router (recent cold-launch fix): a tapped notification's
/// `type` + id must select the right tab and stash the entity id for the tab
/// root to deep-push. `type` is matched by lowercased substring.
@MainActor
final class PushRouterTests: XCTestCase {
    private var router: PushRouter { PushRouter.shared }

    override func setUp() {
        super.setUp()
        // Shared singleton — clear any state from a previous test.
        router.tab = nil; router.serverId = nil; router.invoiceId = nil; router.ticketId = nil
    }

    func testServerStateRoutesToServersTabWithId() {
        router.route(type: "server.state", serverId: "srv_1", invoiceId: nil, ticketId: nil)
        XCTAssertEqual(router.tab, .servers)
        XCTAssertEqual(router.serverId, "srv_1")
        XCTAssertNil(router.invoiceId)
    }

    func testBillingInvoiceRoutesToBillingTabWithId() {
        router.route(type: "billing.invoice", serverId: nil, invoiceId: "inv_9", ticketId: nil)
        XCTAssertEqual(router.tab, .billing)
        XCTAssertEqual(router.invoiceId, "inv_9")
    }

    func testPaymentTypeAlsoRoutesToBillingEvenWithoutInvoiceId() {
        router.route(type: "payment.failed", serverId: nil, invoiceId: nil, ticketId: nil)
        XCTAssertEqual(router.tab, .billing)
        XCTAssertNil(router.invoiceId)   // just the tab, no entity
    }

    func testSupportReplyRoutesToSupportTabWithTicket() {
        router.route(type: "support.reply", serverId: nil, invoiceId: nil, ticketId: "tkt_3")
        XCTAssertEqual(router.tab, .support)
        XCTAssertEqual(router.ticketId, "tkt_3")
    }

    func testUnknownTypeWithServerIdFallsBackToServers() {
        router.route(type: "something.weird", serverId: "srv_2", invoiceId: nil, ticketId: nil)
        XCTAssertEqual(router.tab, .servers)
        XCTAssertEqual(router.serverId, "srv_2")
    }

    func testUnknownTypeWithNoIdsDoesNothing() {
        router.route(type: nil, serverId: nil, invoiceId: nil, ticketId: nil)
        XCTAssertNil(router.tab)
        XCTAssertNil(router.serverId)
    }
}
