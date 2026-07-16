import Foundation
import SwiftUI

/// SSL provisioning state for a custom domain (`SslStatus`).
enum SslStatus: String, Decodable, Equatable {
    case pending = "PENDING"
    case active = "ACTIVE"
    case failed = "FAILED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SslStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .pending: return "SSL pending"
        case .active: return "SSL active"
        case .failed: return "SSL failed"
        case .unknown: return "SSL unknown"
        }
    }

    var color: Color {
        switch self {
        case .active: return .appSuccess
        case .failed: return .appDestructive
        case .pending: return .appWarning
        case .unknown: return .appMuted
        }
    }
}

/// `GET /servers/:id/domains` (WEB_APP servers only). Create/verify responses add
/// `dnsTarget` (and verify adds `verified`); both are optional so all three
/// shapes decode with one model.
struct ServerDomain: Decodable, Identifiable, Equatable {
    let id: String
    let serverId: String
    let hostname: String
    let isPrimary: Bool
    let sslStatus: SslStatus
    let verifiedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let dnsTarget: String?   // present on create/verify
    let verified: Bool?      // present on verify

    var isVerified: Bool { verifiedAt != nil }
}

/// `GET /servers/:id/vanity-address` status card.
struct VanityStatus: Decodable, Equatable {
    let enabled: Bool
    let gameDomain: String?
    let feeMinor: Int
    let currency: String
    let currentLabel: String?
    let currentAddress: String?
    let pending: Pending?

    struct Pending: Decodable, Equatable {
        let label: String
        let address: String
        let invoiceId: String
        let amountMinor: Int
        let currency: String
    }

    /// Human fee, e.g. "$5.00". Minor units → major with the currency symbol.
    var feeDescription: String { Money(minorUnits: feeMinor, currency: currency).formatted }
}

/// `POST /servers/:id/vanity-address` discriminated result.
struct VanityPurchaseResult: Decodable, Equatable {
    let status: String        // "applied" | "invoiced"
    let label: String
    let address: String
    let invoiceId: String?
    let amountMinor: Int?
    let currency: String?

    var isApplied: Bool { status == "applied" }
}
