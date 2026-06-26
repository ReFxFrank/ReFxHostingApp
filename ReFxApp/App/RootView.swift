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
            case .offline:
                OfflineView()
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

/// Shown when we hold a valid session but couldn't reach the server at launch
/// (offline / server unreachable). Preserves the session and offers a retry,
/// plus a sign-out escape — never silently dumps the user back to login.
struct OfflineView: View {
    @EnvironmentObject private var session: AppSession
    @State private var retrying = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 48)).foregroundStyle(.appWarning)
                Text("Can’t reach ReFx").font(.headline).foregroundStyle(.appForeground)
                Text("You’re still signed in — we just couldn’t connect. Check your connection and try again.")
                    .font(.subheadline).foregroundStyle(.appMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                Button {
                    retrying = true
                    Task { await session.start(); retrying = false }
                } label: {
                    HStack { if retrying { ProgressView() }; Text(retrying ? "Connecting…" : "Try again") }
                }
                .buttonStyle(.refxPrimary(fullWidth: false)).disabled(retrying)
                Button("Sign out") { Task { await session.logout() } }
                    .font(.footnote).tint(.appMuted)
            }
            .padding(24)
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
                // Always-available escape so a user can never be locked out (e.g.
                // if biometrics/passcode become unavailable on the device).
                Button("Sign out") { Task { await session.logout() } }
                    .font(.footnote).tint(.appMuted)
            }
        }
        .task { await session.unlock() }
    }
}

struct MainTabView: View {
    let user: CurrentUser
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var pushRouter: PushRouter
    @State private var tab: Tab = .home

    enum Tab: Hashable { case home, servers, support, staff, account }

    var body: some View {
        TabView(selection: $tab) {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

            ServersListView()
                .tabItem { Label("Servers", systemImage: "server.rack") }
                .tag(Tab.servers)

            SupportListView()
                .tabItem { Label("Support", systemImage: "lifepreserver") }
                .tag(Tab.support)

            if user.globalRole.isStaff {
                StaffHomeView(role: user.globalRole)
                    .tabItem { Label("Staff", systemImage: "shield.lefthalf.filled") }
                    .tag(Tab.staff)
            }

            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .badge(session.unreadCount)
                .tag(Tab.account)
        }
        // A tapped push selects the relevant tab; each tab root then deep-pushes
        // to the exact server/invoice/ticket via the router's id targets.
        .onChange(of: pushRouter.tab) { intent in
            guard let intent else { return }
            apply(intent)
        }
        // Cold launch: a notification tap routes through PushRouter before this
        // view exists, so `tab` is already set by the time it appears and
        // onChange never fires. Apply any pending route on appear. Deferred to
        // the next runloop so the TabView honours the selection change.
        .onAppear {
            guard let intent = pushRouter.tab else { return }
            DispatchQueue.main.async { apply(intent) }
        }
    }

    /// Switch to the tab a push intent targets, then clear it so it isn't
    /// re-applied. The id targets (serverId/invoiceId/ticketId) persist until
    /// the destination is dismissed, so the tab root still deep-pushes.
    private func apply(_ intent: PushTab) {
        switch intent {
        case .servers: tab = .servers
        case .billing: tab = .account
        case .support: tab = .support
        }
        pushRouter.tab = nil
    }
}
