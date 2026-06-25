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
    private(set) lazy var files = FilesService(client: client)
    private(set) lazy var dashboard = DashboardService(client: client)
    private(set) lazy var backups = BackupsService(client: client)
    private(set) lazy var serverSettings = ServerSettingsService(client: client)
    private(set) lazy var schedules = SchedulesService(client: client)
    private(set) lazy var databases = DatabasesService(client: client)
    private(set) lazy var subUsers = SubUsersService(client: client)
    private(set) lazy var switchGame = SwitchGameService(client: client)
    private(set) lazy var support = SupportService(client: client)
    private(set) lazy var workshop = WorkshopService(client: client)
    private(set) lazy var minecraft = MinecraftService(client: client)
    private(set) lazy var mods = ModsService(client: client)
    private(set) lazy var modpacks = ModpacksService(client: client)
    private(set) lazy var voice = VoiceService(client: client)
    private(set) lazy var staff = StaffService(client: client)
    private(set) lazy var catalog = CatalogService(client: client)
    private(set) lazy var billing = BillingService(client: client)

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

    /// Passkey second factor: fetch options → run the system passkey sheet →
    /// verify the assertion → finish sign-in.
    func completePasskey(token: String) async throws {
        let options = try await authStore.webauthnOptions(token: token)
        guard let challenge = options.challengeData else {
            throw APIError.decoding("Bad passkey challenge")
        }
        let authenticator = PasskeyAuthenticator()
        let assertion = try await authenticator.assert(
            rpId: options.rpId,
            challenge: challenge,
            allowedCredentialIDs: options.allowedCredentialIDs)
        let response = WebAuthnAssertionResponse(
            credentialID: assertion.credentialID,
            clientDataJSON: assertion.clientDataJSON,
            authenticatorData: assertion.authenticatorData,
            signature: assertion.signature,
            userID: assertion.userID)
        try await authStore.verifyWebauthn(token: token, response: response)
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

    /// Re-engage the app-lock when leaving the foreground, so returning to the
    /// app requires biometric re-auth instead of resuming straight into the
    /// signed-in session. No-op if the lock is disabled or we aren't signed in.
    func lockForBackground() {
        guard appLock.isEnabled, case .signedIn = phase else { return }
        phase = .locked
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

    /// Re-fetch `/auth/me` (e.g. after enabling/disabling TOTP) and update state.
    func reloadUser() async {
        guard currentUser != nil else { return }
        if let user = try? await authStore.fetchCurrentUser() {
            phase = .signedIn(user)
        }
    }

    func refreshUnreadCount() async {
        guard currentUser != nil else { return }
        if let count = try? await account.unreadCount() {
            unreadCount = count.unread
        }
    }
}
