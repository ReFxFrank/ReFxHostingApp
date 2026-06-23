import Foundation
import SwiftUI

/// App-level coordinator the root view observes. Owns the object graph
/// (config → client → auth → feature services) and exposes the high-level
/// `phase` that decides what the user sees. `@MainActor` so published changes
/// are always delivered on the main thread.
@MainActor
final class AppSession: ObservableObject {
    enum Phase: Equatable {
        case loading
        case signedOut
        case locked            // authenticated but app-lock (Face ID) engaged
        case signedIn(CurrentUser)
    }

    @Published private(set) var phase: Phase = .loading
    @Published var unreadCount: Int = 0

    let config: AppConfig
    let client: APIClient
    let authStore: AuthStore
    let appLock: AppLock

    // Feature services (constructed once the graph is up).
    private(set) lazy var servers = ServersService(client: client)
    private(set) lazy var account = AccountService(client: client)

    private var didWireClient = false

    init(config: AppConfig = .shared,
         client: APIClient? = nil,
         appLock: AppLock = AppLock()) {
        let resolvedClient = client ?? APIClient(config: config)
        self.config = config
        self.client = resolvedClient
        self.authStore = AuthStore(api: AuthService(client: resolvedClient))
        self.appLock = appLock
    }

    var currentUser: CurrentUser? {
        if case .signedIn(let user) = phase { return user }
        return nil
    }

    // MARK: - Bootstrap

    func start() async {
        await wireClientIfNeeded()
        if await authStore.hasSession {
            await loadSignedInUser(applyLock: appLock.isEnabled)
        } else {
            phase = .signedOut
        }
    }

    private func wireClientIfNeeded() async {
        guard !didWireClient else { return }
        didWireClient = true
        await client.configure(
            tokenProvider: { [authStore] in await authStore.currentAccessToken() },
            refreshHandler: { [weak self] in
                guard let self else { return false }
                let ok = await self.authStore.refreshIfPossible()
                if !ok { await self.handleSessionExpired() }
                return ok
            })
    }

    // MARK: - Auth flows

    func login(email: String, password: String, totp: String?,
               rememberMe: Bool) async throws -> LoginOutcome {
        await wireClientIfNeeded()
        let outcome = try await authStore.login(
            email: email, password: password, totp: totp, rememberMe: rememberMe)
        if outcome == .signedIn { await loadSignedInUser(applyLock: false) }
        return outcome
    }

    func completeMFA(token: String, code: String, method: MFAMethod) async throws {
        try await authStore.verifyMFA(token: token, code: code, method: method)
        await loadSignedInUser(applyLock: false)
    }

    func logout() async {
        await authStore.logout()
        unreadCount = 0
        phase = .signedOut
    }

    func unlock() async {
        let ok = await appLock.authenticate()
        if ok { await loadSignedInUser(applyLock: false) }
    }

    // MARK: - Internal

    private func loadSignedInUser(applyLock: Bool) async {
        if applyLock {
            phase = .locked
            return
        }
        do {
            let user = try await authStore.fetchCurrentUser()
            phase = .signedIn(user)
            await refreshUnreadCount()
        } catch APIError.unauthorized {
            await handleSessionExpired()
        } catch {
            // Network hiccup on bootstrap: keep the session but show signed-out
            // so the user can retry rather than being stuck on a spinner. The
            // tokens remain in Keychain for the next attempt.
            if await authStore.hasSession {
                // Surface a retryable signed-out state.
                phase = .signedOut
            } else {
                phase = .signedOut
            }
        }
    }

    private func handleSessionExpired() async {
        await authStore.invalidate()
        unreadCount = 0
        phase = .signedOut
    }

    func refreshUnreadCount() async {
        guard currentUser != nil else { return }
        if let count = try? await account.unreadCount() {
            unreadCount = count.unread
        }
    }
}
