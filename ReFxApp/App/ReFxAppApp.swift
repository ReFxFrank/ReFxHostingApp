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
                .task {
                    await session.start()
                    // Ask once; awareness notifications are best-effort (see
                    // BackgroundRefreshScheduler). Declining is fine.
                    _ = await LocalNotifications.requestAuthorization()
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                BackgroundRefreshScheduler.shared.schedule()
            } else if phase == .active {
                Task { await session.refreshUnreadCount() }
            }
        }
    }

    private func configureAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Color.appBackground)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Color.appForeground)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.appForeground)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Color.appCard)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
