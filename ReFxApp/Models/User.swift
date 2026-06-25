import Foundation

/// JWT `role` claim / `User.globalRole`. Unknown values decode to `.unknown`
/// so a future backend role never crashes the client.
enum UserRole: String, Codable, CaseIterable {
    case pendingCustomer = "PENDING_CUSTOMER"
    case customer = "CUSTOMER"
    case support = "SUPPORT"
    case admin = "ADMIN"
    case owner = "OWNER"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UserRole(rawValue: raw) ?? .unknown
    }

    /// SUPPORT, ADMIN and OWNER see the Staff section.
    var isStaff: Bool { self == .support || self == .admin || self == .owner }
    /// Full platform admin (server/node/user admin). SUPPORT is support-only.
    var isAdmin: Bool { self == .admin || self == .owner }
}

/// The authoritative current user from `GET /auth/me` (profile + effective
/// admin permission strings the server attaches).
struct CurrentUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let globalRole: UserRole
    let avatarUrl: String?
    let creditBalanceMinor: Int?
    let permissions: [String]?
    let totpEnabledAt: Date?

    var isTotpEnabled: Bool { totpEnabledAt != nil }

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? email : name
    }

    var initials: String {
        let parts = [firstName, lastName].compactMap { $0?.first }.map(String.init)
        if parts.isEmpty { return String(email.prefix(1)).uppercased() }
        return parts.joined().uppercased()
    }
}
