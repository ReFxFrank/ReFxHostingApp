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

    // MARK: Push tokens (APNs)

    /// Register this device's APNs token so the backend can target it. Backend
    /// endpoint TBD — see the push-notifications contract.
    func registerPushToken(_ token: String) async throws {
        try await client.sendVoid(.post("account/push-tokens", body: PushTokenBody(token: token, platform: "ios")))
    }

    func unregisterPushToken(_ token: String) async throws {
        try await client.sendVoid(.delete("account/push-tokens/\(token)"))
    }

    private struct PushTokenBody: Encodable { let token: String; let platform: String }

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

    // MARK: Passkeys (WebAuthn registration — authenticated)

    func passkeys() async throws -> [PasskeyCredential] {
        try await client.send(.get("auth/mfa/webauthn/credentials"))
    }

    func passkeyRegisterOptions() async throws -> PasskeyRegistrationOptions {
        try await client.send(.post("auth/mfa/webauthn/register/options"))
    }

    /// Verify a freshly-created passkey. `label` names it in the account UI.
    func passkeyRegisterVerify(response: WebAuthnRegistrationResponse, label: String?) async throws {
        try await client.sendVoid(
            .post("auth/mfa/webauthn/register/verify",
                  body: PasskeyVerifyBody(response: response, label: label)))
    }

    func deletePasskey(_ id: String) async throws {
        try await client.sendVoid(.delete("auth/mfa/webauthn/credentials/\(id)"))
    }

    private struct PasskeyVerifyBody: Encodable {
        let response: WebAuthnRegistrationResponse
        let label: String?
    }

    // MARK: Profile

    /// `PATCH /account` — update the signed-in user's profile fields.
    func updateProfile(firstName: String, lastName: String) async throws -> CurrentUser {
        try await client.send(
            .patch("account", body: UpdateProfileBody(firstName: firstName, lastName: lastName)))
    }

    private struct UpdateProfileBody: Encodable {
        let firstName: String
        let lastName: String
    }

    // MARK: Account lifecycle (GDPR)

    /// `GET /account/export` — everything the platform holds for this account,
    /// returned as JSON for the user to save/share.
    func exportData() async throws -> JSONValue {
        try await client.send(.get("account/export"))
    }

    /// `DELETE /account` — permanently delete the signed-in account. Required for
    /// App Store compliance (Guideline 5.1.1(v)) since the app supports sign-up.
    func deleteAccount() async throws {
        try await client.sendVoid(.delete("account"))
    }
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
