import SwiftUI

/// Auth gate → role-aware tab tree. The single app adapts to the signed-in
/// user's role: customers get Servers / Support / Account; staff additionally
/// get a Staff section.
struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                LaunchView()
            case .signedOut:
                LoginView()
            case .locked:
                AppLockView()
            case .signedIn(let user):
                MainTabView(user: user)
            }
        }
        .animation(.default, value: session.phase)
    }
}

struct LaunchView: View {
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ProgressView().tint(.appPrimary)
        }
    }
}

struct AppLockView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield").font(.system(size: 48)).foregroundStyle(.appPrimary)
                Text("ReFx is locked").font(.headline).foregroundStyle(.appForeground)
                Button("Unlock") { Task { await session.unlock() } }
                    .buttonStyle(.borderedProminent).tint(.appPrimary)
            }
        }
        .task { await session.unlock() }
    }
}

struct MainTabView: View {
    let user: CurrentUser
    @EnvironmentObject private var session: AppSession

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house") }

            ServersListView()
                .tabItem { Label("Servers", systemImage: "server.rack") }

            SupportListView()
                .tabItem { Label("Support", systemImage: "lifepreserver") }

            if user.globalRole.isStaff {
                StaffHomeView(role: user.globalRole)
                    .tabItem { Label("Staff", systemImage: "shield.lefthalf.filled") }
            }

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .badge(session.unreadCount)
        }
    }
}
