import Foundation

/// REST surface for the Account tab: profile, sessions, notifications,
/// change-password. Confirmed against `account.controller.ts`.
struct AccountService {
    let client: APIClient

    func profile() async throws -> CurrentUser {
        try await client.send(.get("account"))
    }

    // MARK: Notifications

    /// `GET /account/notifications` returns a plain array (under `{ data }`).
    func notifications() async throws -> [AppNotification] {
        try await client.send(.get("account/notifications"))
    }

    func unreadCount() async throws -> UnreadCount {
        try await client.send(.get("account/notifications/unread-count"))
    }

    func markRead(_ id: String) async throws {
        try await client.sendVoid(.post("account/notifications/\(id)/read"))
    }

    func markAllRead() async throws {
        try await client.sendVoid(.post("account/notifications/read-all"))
    }

    // MARK: Sessions

    func sessions() async throws -> [UserSession] {
        try await client.send(.get("account/sessions"))
    }

    func revokeSession(_ id: String) async throws {
        try await client.sendVoid(.delete("account/sessions/\(id)"))
    }

    // MARK: Security

    func changePassword(current: String, new: String) async throws {
        try await client.sendVoid(
            .post("account/password",
                  body: ChangePasswordBody(currentPassword: current, newPassword: new)))
    }

    private struct ChangePasswordBody: Encodable {
        let currentPassword: String
        let newPassword: String
    }

    // MARK: Two-factor (TOTP)

    func totpEnroll() async throws -> TotpEnrollment {
        try await client.send(.post("auth/mfa/totp/enroll"))
    }

    func totpVerify(code: String) async throws -> RecoveryCodes {
        try await client.send(.post("auth/mfa/totp/verify", body: TotpCodeBody(code: code)))
    }

    func totpDisable() async throws {
        try await client.sendVoid(.delete("auth/mfa/totp"))
    }

    // MARK: API keys

    func apiKeys() async throws -> [ApiKey] {
        try await client.send(.get("account/api-keys"))
    }

    func createApiKey(name: String, scopes: [String]) async throws -> CreatedApiKey {
        try await client.send(.post("account/api-keys",
                                     body: CreateApiKeyBody(name: name, scopes: scopes)))
    }

    func revokeApiKey(_ id: String) async throws {
        try await client.sendVoid(.delete("account/api-keys/\(id)"))
    }

    private struct TotpCodeBody: Encodable { let code: String }
    private struct CreateApiKeyBody: Encodable { let name: String; let scopes: [String] }
}

/// `GET /account/sessions` → `{ id, ip, userAgent, createdAt, expiresAt }`
/// (only active, non-revoked sessions are returned).
struct UserSession: Codable, Identifiable, Equatable {
    let id: String
    let ip: String?
    let userAgent: String?
    let createdAt: Date?
    let expiresAt: Date?
}
