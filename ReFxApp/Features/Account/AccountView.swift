import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var config: AppConfig

    var body: some View {
        NavigationStack {
            List {
                if let user = session.currentUser {
                    Section { ProfileHeader(user: user) }
                        .listRowBackground(Color.appCard)
                }

                Section("Account") {
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        Label("Notifications", systemImage: "bell")
                            .badge(session.unreadCount)
                    }
                    NavigationLink {
                        SessionsView()
                    } label: {
                        Label("Active sessions", systemImage: "desktopcomputer")
                    }
                    NavigationLink {
                        ChangePasswordView()
                    } label: {
                        Label("Change password", systemImage: "key")
                    }
                }
                .listRowBackground(Color.appCard)

                Section("App") {
                    NavigationLink {
                        ConnectionSettingsView()
                    } label: {
                        Label("Connection settings", systemImage: "gearshape")
                    }
                    Button {
                        WebLink.open(config.webOrigin, path: "billing")
                    } label: {
                        Label("Billing & invoices (web)", systemImage: "creditcard")
                    }
                }
                .listRowBackground(Color.appCard)

                Section {
                    Button(role: .destructive) {
                        Task { await session.logout() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                .listRowBackground(Color.appCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Account")
        }
    }
}

struct ProfileHeader: View {
    let user: CurrentUser

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.appPrimary.opacity(0.18)).frame(width: 52, height: 52)
                Text(user.initials).font(.headline).foregroundStyle(.appPrimary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(user.displayName).font(.headline).foregroundStyle(.appForeground)
                Text(user.email).font(.caption).foregroundStyle(.appMuted)
                RoleBadge(role: user.globalRole)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct RoleBadge: View {
    let role: UserRole
    var body: some View {
        Text(role.rawValue.capitalized)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.appAccent)
            .foregroundStyle(.appForeground)
            .clipShape(Capsule())
    }
}
