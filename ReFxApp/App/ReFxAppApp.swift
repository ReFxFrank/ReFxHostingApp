import SwiftUI
import UIKit

@main
struct ReFxAppApp: App {
    @StateObject private var session = AppSession()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Force the dark, control-panel aesthetic everywhere.
        configureAppearance()
        // Must register BG task handlers before launch completes.
        BackgroundRefreshScheduler.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(AppConfig.shared)
                .tint(.appPrimary)
                .preferredColorScheme(.dark)
                // Obscure the app-switcher snapshot: when the scene is not active
                // (inactive/background) cover the UI with an opaque branded
                // curtain so console output, server IPs and revealed secrets are
                // not captured in the task-switcher thumbnail. (MASTG snapshot leak.)
                .overlay {
                    if scenePhase != .active { PrivacyCurtain() }
                }
                .task {
                    // Clear any Live Activity orphaned by a previous run (e.g. the
                    // app was closed mid-operation, freezing the op pill).
                    LiveActivityManager.endAll()
                    await session.start()
                    // Ask once; awareness notifications are best-effort (see
                    // BackgroundRefreshScheduler). Declining is fine.
                    _ = await LocalNotifications.requestAuthorization()
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                BackgroundRefreshScheduler.shared.schedule()
                // No push backend, so a backgrounded Live Activity can't update —
                // end it instead of leaving a frozen pill on screen.
                LiveActivityManager.endAll()
            } else if phase == .active {
                Task { await session.refreshUnreadCount() }
            }
        }
    }

    private func configureAppearance() {
        // Glassy chrome: dark translucent blur tinted with the ReFx navy so the
        // bars read as intentional ReFx glass, never Apple's stock frosted look.
        let foreground = UIColor(Color.appForeground)
        let label = UIColor(Color.appLabel)
        let hairline = UIColor(Color.appBorder)

        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        nav.backgroundColor = UIColor(Color.appBackground).withAlphaComponent(0.62)
        nav.shadowColor = hairline
        nav.titleTextAttributes = [.foregroundColor: foreground]
        nav.largeTitleTextAttributes = [.foregroundColor: foreground]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        tab.backgroundColor = UIColor(Color.appBackgroundDeep).withAlphaComponent(0.62)
        tab.shadowColor = hairline
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.selected.iconColor = UIColor(Color.appPrimary)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(Color.appPrimary)]
            item.normal.iconColor = label
            item.normal.titleTextAttributes = [.foregroundColor: label]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

/// Opaque branded cover shown while the app is inactive/backgrounded so sensitive
/// content (console, server IPs, revealed secrets) is not captured in the
/// app-switcher snapshot.
private struct PrivacyCurtain: View {
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.appPrimary)
        }
    }
}
