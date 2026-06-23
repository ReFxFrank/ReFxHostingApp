import Foundation

/// Money is ALWAYS integer minor units (cents) + an ISO 4217 currency code.
/// Never a float. Formatting goes through `formatted` so the currency's real
/// minor-unit exponent is respected (JPY = 0 decimals, USD = 2, etc.).
struct Money: Equatable, Codable {
    let minorUnits: Int
    let currency: String

    init(minorUnits: Int, currency: String) {
        self.minorUnits = minorUnits
        self.currency = currency.uppercased()
    }

    /// Localized amount, e.g. "$12.00", "¥1200".
    var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let exponent = Money.minorUnitExponent(for: currency)
        let divisor = pow(10.0, Double(exponent))
        let value = Double(minorUnits) / divisor
        formatter.minimumFractionDigits = exponent
        formatter.maximumFractionDigits = exponent
        return formatter.string(from: NSNumber(value: value))
            ?? "\(currency) \(value)"
    }

    /// Minor-unit exponent for the currencies that aren't the 2-decimal default.
    /// Covers the zero-decimal set + the common 3-decimal ones.
    static func minorUnitExponent(for code: String) -> Int {
        let upper = code.uppercased()
        let zeroDecimal: Set<String> = [
            "JPY", "KRW", "VND", "CLP", "ISK", "HUF", "TWD", "UGX", "XAF", "XOF",
        ]
        let threeDecimal: Set<String> = ["BHD", "JOD", "KWD", "OMR", "TND"]
        if zeroDecimal.contains(upper) { return 0 }
        if threeDecimal.contains(upper) { return 3 }
        return 2
    }
}
