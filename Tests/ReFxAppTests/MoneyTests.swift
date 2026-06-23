import XCTest
@testable import ReFxApp

/// Money is integer minor units + ISO currency. These lock in the cents→string
/// formatting and the per-currency minor-unit exponent handling.
final class MoneyTests: XCTestCase {

    func testUSDFormatsTwoDecimals() {
        let money = Money(minorUnits: 1299, currency: "USD")
        // Locale-independent: the numeric part must be 12.99.
        XCTAssertTrue(money.formatted.contains("12.99"), money.formatted)
    }

    func testZeroDecimalCurrencyHasNoFraction() {
        let money = Money(minorUnits: 1200, currency: "JPY")
        XCTAssertEqual(Money.minorUnitExponent(for: "JPY"), 0)
        XCTAssertTrue(money.formatted.contains("1,200") || money.formatted.contains("1200"),
                      money.formatted)
        XCTAssertFalse(money.formatted.contains("12.00"))
    }

    func testThreeDecimalCurrency() {
        XCTAssertEqual(Money.minorUnitExponent(for: "KWD"), 3)
        let money = Money(minorUnits: 1234, currency: "KWD")
        XCTAssertTrue(money.formatted.contains("1.234"), money.formatted)
    }

    func testZeroAmount() {
        let money = Money(minorUnits: 0, currency: "USD")
        XCTAssertTrue(money.formatted.contains("0.00"), money.formatted)
    }

    func testCurrencyCodeNormalizedToUppercase() {
        let money = Money(minorUnits: 500, currency: "eur")
        XCTAssertEqual(money.currency, "EUR")
    }

    func testNeverUsesFloatingPointInput() {
        // The integer-cents contract: 999999 cents == 9,999.99 in a 2-dp currency.
        let money = Money(minorUnits: 999_999, currency: "USD")
        XCTAssertTrue(money.formatted.contains("9,999.99") || money.formatted.contains("9999.99"),
                      money.formatted)
    }
}
