import Foundation

/// `GET /account/api-keys`.
struct ApiKey: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let prefix: String
    let scopes: [String]
    let lastUsedAt: Date?
    let expiresAt: Date?
    let createdAt: Date?

    var scopeSummary: String { scopes.map { $0.capitalized }.joined(separator: ", ") }
}

/// `POST /account/api-keys` → the full key, shown once.
struct CreatedApiKey: Decodable {
    let key: String
    let prefix: String
    let id: String
}

/// `POST /auth/mfa/totp/enroll`.
struct TotpEnrollment: Decodable {
    let otpauthUrl: String
    let secret: String
}

/// `POST /auth/mfa/totp/verify` → one-time recovery codes.
struct RecoveryCodes: Decodable {
    let recoveryCodes: [String]
}
