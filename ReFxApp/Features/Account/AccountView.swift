import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var pushRouter: PushRouter

    var body: some View {
        NavigationStack {
            List {
                if let user = session.currentUser {
                    Section { ProfileHeader(user: user) }
                        .listRowBackground(Color.appCard)
                }

                Section(header: Eyebrow("Account").padding(.bottom, 2)) {
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        Label("Notifications", systemImage: "bell")
                            .badge(session.unreadCount)
                    }
                    NavigationLink {
                        SecurityView()
                    } label: {
                        Label("Security (2FA, API keys)", systemImage: "lock.shield")
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

                Section(header: Eyebrow("App").padding(.bottom, 2)) {
                    NavigationLink {
                        BillingView()
                    } label: {
                        Label("Billing & invoices", systemImage: "creditcard")
                    }
                    NavigationLink {
                        PushSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell")
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
            .screenBackground()
            .navigationTitle("Account")
            .navigationDestination(isPresented: Binding(
                get: { pushRouter.invoiceId != nil },
                set: { if !$0 { pushRouter.invoiceId = nil } })) {
                if let id = pushRouter.invoiceId { InvoiceDetailView(invoiceId: id) }
            }
        }
    }
}

struct ProfileHeader: View {
    let user: CurrentUser

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.appPrimary.opacity(0.18))
                Circle().strokeBorder(Color.appPrimary.opacity(0.45), lineWidth: 1)
                Text(user.initials).font(.headline).foregroundStyle(.appPrimary)
            }
            .frame(width: 54, height: 54)
            .shadow(color: .appPrimary.opacity(0.35), radius: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName).font(.headline).foregroundStyle(.appForegroundStrong)
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
        Text(role.rawValue.uppercased())
            .font(.caption2.weight(.bold)).tracking(0.8)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Color.appPrimary.opacity(0.14))
            .overlay(Capsule().strokeBorder(Color.appPrimary.opacity(0.35), lineWidth: 1))
            .foregroundStyle(.appAccentText)
            .clipShape(Capsule())
    }
}
