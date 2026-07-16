import Foundation
import SwiftUI

// MARK: - Staff members ("meet the team")

/// `GET /admin/staff` — a team member. `title` is the role; there's a single
/// `link`, not a socials object.
struct StaffMember: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let title: String
    let bio: String?
    let avatarUrl: String?
    let link: String?
    let isActive: Bool
    let sortOrder: Int
    let createdAt: Date?
    let updatedAt: Date?
}

/// `POST`/`PATCH /admin/staff` body.
struct StaffMemberBody: Encodable {
    var name: String?
    var title: String?
    var bio: String?
    var avatarUrl: String?
    var link: String?
    var isActive: Bool?
    var sortOrder: Int?
}

// MARK: - Homepage alerts (storefront notices)

enum HomepageAlertType: String, Codable, CaseIterable, Identifiable {
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARNING"
    case danger = "DANGER"
    case promo = "PROMO"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HomepageAlertType(rawValue: raw) ?? .unknown
    }

    var id: String { rawValue }
    var label: String { self == .unknown ? "Alert" : rawValue.capitalized }
    var color: Color {
        switch self {
        case .success: return .appSuccess
        case .warning, .promo: return .appWarning
        case .danger: return .appDestructive
        default: return .appPrimary
        }
    }
}

/// `GET /admin/homepage-alerts` — public storefront banner. Distinct from
/// `GlobalAlert` (dashboard): uses `type` (5 values), has CTA + priority.
struct HomepageAlert: Decodable, Identifiable, Equatable {
    let id: String
    let type: HomepageAlertType
    let title: String
    let body: String
    let isActive: Bool
    let startsAt: Date?
    let endsAt: Date?
    let ctaLabel: String?
    let ctaUrl: String?
    let dismissible: Bool
    let priority: Int
    let createdAt: Date?
    let updatedAt: Date?
}

/// `POST`/`PATCH /admin/homepage-alerts` body.
struct HomepageAlertBody: Encodable {
    var type: String?
    var title: String?
    var body: String?
    var isActive: Bool?
    var ctaLabel: String?
    var ctaUrl: String?
    var dismissible: Bool?
    var priority: Int?
}
