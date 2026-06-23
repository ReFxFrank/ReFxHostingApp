import Foundation

/// Result of a password login: either fully signed in, or a second factor is
/// still required (carry the challenge token to the MFA screen).
enum LoginOutcome: Equatable {
    case signedIn
    case mfaRequired(token: String, methods: [MFAMethod])
}

/// Owns the token lifecycle: Keychain persistence, in-memory cache, and the
/// **single-flight** refresh that serializes concurrent 401s into exactly one
/// `/auth/refresh` call (critical because refresh rotates — a second concurrent
/// refresh would reuse a token and revoke the whole session family).
///
/// An `actor`, so all token mutations are serialized without locks. The UI layer
/// (`AppSession`, `@MainActor`) observes results; this type holds no SwiftUI.
actor AuthStore {
    private let api: AuthAPI
    private let keychain: TokenStoring

    private var accessToken: String?
    private var refreshToken: String?

    /// The in-flight refresh, if any. Concurrent callers await the same task.
    private var refreshTask: Task<Bool, Never>?

    init(api: AuthAPI, keychain: TokenStoring = KeychainService()) {
        self.api = api
        self.keychain = keychain
        self.accessToken = keychain.get(.accessToken)
        self.refreshToken = keychain.get(.refreshToken)
    }

    // MARK: - State queries

    var hasSession: Bool { refreshToken != nil }

    func currentAccessToken() -> String? { accessToken }

    /// Best-effort role from the cached access token (server `/auth/me` is final).
    func cachedClaims() -> AccessTokenClaims? {
        accessToken.flatMap(AccessTokenClaims.init(jwt:))
    }

    // MARK: - Login

    func login(email: String, password: String, totp: String?, rememberMe: Bool) async throws -> LoginOutcome {
        let response = try await api.login(
            LoginRequest(email: email, password: password,
                         totp: totp?.nonEmpty, rememberMe: rememberMe))
        if response.requiresMFA {
            return .mfaRequired(token: response.mfaToken ?? "",
                                methods: response.methods ?? [.totp])
        }
        persist(response)
        return .signedIn
    }

    func verifyMFA(token: String, code: String, method: MFAMethod) async throws {
        let response = try await api.verifyMFA(
            MFAVerifyRequest(mfaToken: token, code: code,
                             method: method == .recovery ? "recovery" : "totp"))
        persist(response)
    }

    // MARK: - Refresh (single-flight)

    /// Perform at most one refresh at a time. Returns true if a fresh, rotated
    /// access token is now available. Safe to call from many concurrent 401s.
    func refreshIfPossible() async -> Bool {
        if let existing = refreshTask {
            return await existing.value
        }
        guard let token = refreshToken else { return false }

        let task = Task<Bool, Never> { [api] in
            do {
                let response = try await api.refresh(refreshToken: token)
                guard !response.accessToken.isEmpty else { return false }
                self.persist(response)
                return true
            } catch {
                // Refresh failed (revoked/expired/family-reuse) → drop session.
                self.clearTokens()
                return false
            }
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    // MARK: - Profile

    func fetchCurrentUser() async throws -> CurrentUser {
        try await api.me()
    }

    // MARK: - Logout

    func logout() async {
        if let token = refreshToken {
            // Best-effort server-side revoke; clear locally regardless.
            try? await api.logout(refreshToken: token)
        }
        clearTokens()
    }

    /// Clear tokens without a server round-trip (used when refresh fails).
    func invalidate() {
        clearTokens()
    }

    // MARK: - Persistence

    private func persist(_ response: TokenResponse) {
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        keychain.set(response.accessToken, for: .accessToken)
        keychain.set(response.refreshToken, for: .refreshToken)
    }

    private func clearTokens() {
        accessToken = nil
        refreshToken = nil
        keychain.clear()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
