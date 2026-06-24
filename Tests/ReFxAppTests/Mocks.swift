import Foundation
@testable import ReFxApp

/// In-memory token store so `AuthStore` tests don't touch the real Keychain.
final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    init(access: String? = nil, refresh: String? = nil) {
        if let access { storage[TokenKey.accessToken.rawValue] = access }
        if let refresh { storage[TokenKey.refreshToken.rawValue] = refresh }
    }

    func set(_ value: String, for key: TokenKey) {
        lock.lock(); defer { lock.unlock() }
        storage[key.rawValue] = value
    }
    func get(_ key: TokenKey) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key.rawValue]
    }
    func delete(_ key: TokenKey) {
        lock.lock(); defer { lock.unlock() }
        storage[key.rawValue] = nil
    }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
}

/// Configurable `AuthAPI` mock. Counts refresh calls (to prove single-flight)
/// and rotates tokens on each refresh (to mirror the real backend).
actor MockAuthAPI: AuthAPI {
    private(set) var refreshCallCount = 0
    private(set) var loginCallCount = 0
    var refreshShouldFail = false
    var refreshDelayNanos: UInt64 = 50_000_000 // 50ms to expose concurrency
    private var rotation = 0

    func configure(refreshShouldFail: Bool) { self.refreshShouldFail = refreshShouldFail }

    func login(_ request: LoginRequest) async throws -> TokenResponse {
        loginCallCount += 1
        if request.totp == nil, request.password == "needs-mfa" {
            return TokenResponse(accessToken: "", refreshToken: "", expiresIn: 0,
                                 mfaRequired: true, mfaToken: "challenge-123",
                                 methods: [.totp])
        }
        return token(prefix: "login")
    }

    func verifyMFA(_ request: MFAVerifyRequest) async throws -> TokenResponse {
        token(prefix: "mfa")
    }

    func refresh(refreshToken: String) async throws -> TokenResponse {
        refreshCallCount += 1
        if refreshDelayNanos > 0 { try? await Task.sleep(nanoseconds: refreshDelayNanos) }
        if refreshShouldFail { throw APIError.unauthorized }
        return token(prefix: "refreshed")
    }

    func logout(refreshToken: String) async throws {}

    func me() async throws -> CurrentUser {
        CurrentUser(id: "u1", email: "user@example.com", firstName: "Test",
                    lastName: "User", globalRole: .customer, avatarUrl: nil,
                    creditBalanceMinor: 0, permissions: [], totpEnabledAt: nil)
    }

    private func token(prefix: String) -> TokenResponse {
        rotation += 1
        return TokenResponse(accessToken: "\(prefix)-access-\(rotation)",
                             refreshToken: "\(prefix)-refresh-\(rotation)",
                             expiresIn: 900, mfaRequired: nil, mfaToken: nil, methods: nil)
    }
}
