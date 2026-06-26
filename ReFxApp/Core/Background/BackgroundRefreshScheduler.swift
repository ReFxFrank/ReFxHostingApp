import Foundation
import BackgroundTasks

/// Registers and schedules a `BGAppRefreshTask` that periodically wakes the app
/// to check server health + unread notifications and fires local notifications
/// on regressions (server → offline/suspended/crashed, unread count rose).
///
/// Important honesty: iOS fully controls scheduling. This task may run rarely,
/// late, or not at all (depends on usage patterns, battery, Low Power Mode). It
/// is awareness-on-a-best-effort basis, NOT a real-time alerting system — that
/// requires APNs (backend TODO). Built so the diff/notify step can later be fed
/// by an APNs payload instead of a poll.
final class BackgroundRefreshScheduler {
    static let shared = BackgroundRefreshScheduler()

    static let taskIdentifier = "com.refx.app.refresh"
    private let lastStatesKey = "refx.bg.lastServerStates"
    private let lastUnreadKey = "refx.bg.lastUnread"

    private var didRegister = false

    /// Call once during app launch (before launch finishes).
    func register() {
        guard !didRegister else { return }
        didRegister = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier, using: nil) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else { return }
            self?.handle(task)
        }
    }

    /// Ask iOS to wake us no earlier than ~15 minutes from now (a floor, not a
    /// guarantee). Call when entering the background.
    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Execution

    private func handle(_ task: BGAppRefreshTask) {
        schedule() // chain the next wake-up

        let work = Task {
            await performCheck()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Build a minimal, self-contained network stack (tokens come from Keychain),
    /// fetch state, diff, and notify. No SwiftUI / AppSession needed here.
    private func performCheck() async {
        let config = AppConfig()
        let client = APIClient(config: config)
        let auth = AuthStore(api: AuthService(client: client))
        guard await auth.hasSession else { return }
        await client.configure(
            tokenProvider: { await auth.currentAccessToken() },
            // Deliberately do NOT refresh here. Refresh rotates the token, and this
            // throwaway AuthStore can't keep the foreground session's in-memory
            // token in sync — a later foreground refresh with the now-stale token
            // would trip family-reuse detection and revoke the whole session. Run
            // best-effort on the current access token; if it's expired this cycle
            // simply does nothing and the next foreground use refreshes normally.
            refreshHandler: { false })

        let servers = ServersService(client: client)
        let account = AccountService(client: client)

        // Server health regressions.
        if let page = try? await servers.list(pageSize: 100) {
            diffAndNotifyServers(page.items)
        }
        // Ticket replies / new notifications (proxied by unread count rising).
        if let unread = try? await account.unreadCount() {
            diffAndNotifyUnread(unread.unread)
            LocalNotifications.setBadge(unread.unread)
        }
    }

    private func diffAndNotifyServers(_ servers: [Server]) {
        let defaults = UserDefaults.standard
        let previous = defaults.dictionary(forKey: lastStatesKey) as? [String: String] ?? [:]
        var current: [String: String] = [:]
        for server in servers {
            current[server.id] = server.state.rawValue
            let was = previous[server.id].flatMap(ServerState.init(rawValue:))
            // Only notify on a *transition* into an attention state (not on every
            // poll while it stays down).
            if server.state.needsAttention, was != server.state {
                LocalNotifications.notify(
                    title: server.name,
                    body: "Server is now \(server.state.label.lowercased()).",
                    identifier: "state-\(server.id)-\(server.state.rawValue)",
                    serverId: server.id)
            }
        }
        defaults.set(current, forKey: lastStatesKey)
    }

    private func diffAndNotifyUnread(_ unread: Int) {
        let defaults = UserDefaults.standard
        let previous = defaults.integer(forKey: lastUnreadKey)
        if unread > previous {
            let delta = unread - previous
            LocalNotifications.notify(
                title: "New activity",
                body: "You have \(delta) new notification\(delta == 1 ? "" : "s").",
                identifier: "unread-\(unread)")
        }
        defaults.set(unread, forKey: lastUnreadKey)
    }
}
