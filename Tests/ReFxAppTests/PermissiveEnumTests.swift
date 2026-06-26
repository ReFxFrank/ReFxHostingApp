import XCTest
@testable import ReFxApp

/// Every server-driven enum decodes permissively: an unrecognised raw value maps
/// to `.unknown` instead of throwing, so a backend addition can never break a
/// whole response decode. This locks that contract across the model layer.
final class PermissiveEnumTests: XCTestCase {
    /// Decode an enum from a single JSON string value (wrapped so we never rely
    /// on top-level JSON fragments).
    private struct Box<T: Decodable>: Decodable { let v: T }
    private func decode<T: Decodable>(_ type: T.Type, _ raw: String) throws -> T {
        try TestJSON.decode(Box<T>.self, "{\"v\":\"\(raw)\"}").v
    }

    func testUnknownRawValueFallsBackEverywhere() throws {
        XCTAssertEqual(try decode(ServerState.self, "WARP_SPEED"), .unknown)
        XCTAssertEqual(try decode(UserRole.self, "WIZARD"), .unknown)
        XCTAssertEqual(try decode(TicketState.self, "ON_FIRE"), .unknown)
        XCTAssertEqual(try decode(TicketPriority.self, "OMEGA"), .unknown)
        XCTAssertEqual(try decode(InvoiceState.self, "SETTLED?"), .unknown)
        XCTAssertEqual(try decode(PaymentState.self, "MAYBE"), .unknown)
        XCTAssertEqual(try decode(SubscriptionState.self, "PAUSED"), .unknown)
        XCTAssertEqual(try decode(NodeState.self, "MELTED"), .unknown)
        XCTAssertEqual(try decode(AlertSeverity.self, "MEH"), .unknown)
        XCTAssertEqual(try decode(BackupState.self, "SCHRODINGER"), .unknown)
        XCTAssertEqual(try decode(DeployMethod.self, "TELEPORT"), .unknown)
        XCTAssertEqual(try decode(BillingInterval.self, "FORTNIGHTLY"), .unknown)
        XCTAssertEqual(try decode(BillingModel.self, "VIBES"), .unknown)
        XCTAssertEqual(try decode(ProductType.self, "MAINFRAME"), .unknown)
        XCTAssertEqual(try decode(CouponKind.self, "BOGO"), .unknown)
        XCTAssertEqual(try decode(VariableType.self, "QUANTUM"), .unknown)
        XCTAssertEqual(try decode(CreditReason.self, "LOYALTY"), .unknown)
        XCTAssertEqual(try decode(DbEngine.self, "POSTGRES"), .unknown)
        XCTAssertEqual(try decode(ScheduleAction.self, "DANCE"), .unknown)
    }

    func testKnownUppercaseRawValuesDecode() throws {
        XCTAssertEqual(try decode(ServerState.self, "RUNNING"), .running)
        XCTAssertEqual(try decode(UserRole.self, "ADMIN"), .admin)
        XCTAssertEqual(try decode(InvoiceState.self, "PAID"), .paid)
        XCTAssertEqual(try decode(NodeState.self, "ONLINE"), .online)
        XCTAssertEqual(try decode(SubscriptionState.self, "PAST_DUE"), .pastDue)
        XCTAssertEqual(try decode(BillingInterval.self, "MONTHLY"), .monthly)
        XCTAssertEqual(try decode(ProductType.self, "GAME_SERVER"), .gameServer)
        XCTAssertEqual(try decode(CreditReason.self, "ADMIN_GRANT"), .adminGrant)
    }
}
