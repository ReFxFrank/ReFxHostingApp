import Foundation

/// `GET /admin/growth?days=` — acquisition analytics. `*Minor` are integer cents.
struct GrowthReport: Decodable, Equatable {
    let days: Int
    let channels: [Channel]
    let landings: [Landing]
    let totals: Totals
    let referral: Referral

    struct Channel: Decodable, Identifiable, Equatable {
        let channel: String
        let signups: Int
        let payers: Int
        let revenueMinor: Int
        var id: String { channel }
    }

    struct Landing: Decodable, Identifiable, Equatable {
        let landing: String
        let signups: Int
        var id: String { landing }
    }

    struct Totals: Decodable, Equatable {
        let signups: Int
        let payers: Int
        let revenueMinor: Int
    }

    struct Referral: Decodable, Equatable {
        let signups: Int
        let converted: Int
        let creditIssuedMinor: Int
    }
}
