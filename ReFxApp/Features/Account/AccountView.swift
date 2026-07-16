import SwiftUI
import UIKit

struct AccountView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var pushRouter: PushRouter
    @State private var exporting = false
    @State private var exportItem: ExportFile?
    @State private var exportError: String?
    @State private var showDelete = false

    /// "1.2 (34)" from the bundle, for the About row.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                if let user = session.currentUser {
                    Section { ProfileHeader(user: user) }
                        .listRowBackground(Color.appCard)
                }

                Section(header: Eyebrow("Account").padding(.bottom, 2)) {
                    NavigationLink {
                        EditProfileView()
                    } label: {
                        Label("Edit profile", systemImage: "person.crop.circle")
                    }
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

                Section(header: Eyebrow("About & legal").padding(.bottom, 2)) {
                    LegalLinkRow(title: "Privacy Policy", systemImage: "hand.raised", path: "privacy")
                    LegalLinkRow(title: "Terms of Service", systemImage: "doc.text", path: "terms")
                    LegalLinkRow(title: "Help & Support", systemImage: "questionmark.circle", path: "support")
                    HStack {
                        Label("Version", systemImage: "info.circle").foregroundStyle(.appForeground)
                        Spacer()
                        Text(Self.appVersion).font(.caption.monospacedDigit()).foregroundStyle(.appMuted)
                    }
                }
                .listRowBackground(Color.appCard)

                Section(header: Eyebrow("Privacy & data").padding(.bottom, 2)) {
                    if let exportError {
                        Text(exportError).font(.footnote).foregroundStyle(.appDestructive)
                    }
                    Button { exportData() } label: {
                        HStack {
                            Label("Export my data", systemImage: "square.and.arrow.up").foregroundStyle(.appForeground)
                            Spacer()
                            if exporting { ProgressView() }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(exporting)
                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Delete account", systemImage: "trash")
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
            .sheet(item: $exportItem) { ShareSheet(url: $0.url) }
            .sheet(isPresented: $showDelete) { DeleteAccountSheet() }
        }
    }

    /// Fetch the account export, write it to a temp JSON file, and present a
    /// share sheet so the user can save it (Files, AirDrop, etc.).
    private func exportData() {
        exporting = true; exportError = nil
        Task {
            defer { exporting = false }
            do {
                let json = try await session.account.exportData()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(json)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("refx-account-data.json")
                try data.write(to: url, options: .atomic)
                exportItem = ExportFile(url: url)
            } catch let error as APIError { exportError = error.userMessage }
            catch { exportError = "Couldn't export your data. Try again." }
        }
    }
}

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// System share sheet for the exported data file.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Permanent account deletion behind a typed "DELETE" confirmation. On success
/// the session signs out, which returns the app to the login screen.
private struct DeleteAccountSheet: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var confirmText = ""
    @State private var deleting = false
    @State private var errorText: String?

    private var canDelete: Bool {
        confirmText.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE" && !deleting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("This permanently deletes your account", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.appWarning)
                    Text("Your servers, billing history, and personal data are removed and can’t be recovered. Active services are cancelled.")
                        .font(.caption).foregroundStyle(.appMuted)
                }
                .listRowBackground(Color.appCard)

                Section {
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.appDestructive)
                    }
                    TextField("Type DELETE to confirm", text: $confirmText)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                } header: { Text("Confirm") }
                .listRowBackground(Color.appCard)

                Section {
                    Button(role: .destructive) {
                        deleting = true; errorText = nil
                        Task {
                            do {
                                try await session.account.deleteAccount()
                                await session.logout()
                            } catch let error as APIError { deleting = false; errorText = error.userMessage }
                            catch { deleting = false; errorText = "Couldn’t delete the account. Try again." }
                        }
                    } label: {
                        HStack { if deleting { ProgressView() }; Text("Delete my account") }
                    }
                    .buttonStyle(.refxDestructive).disabled(!canDelete)
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("Delete account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// A tappable row that opens a web page (privacy / terms / support) relative to
/// the configured web origin, with an external-link affordance.
private struct LegalLinkRow: View {
    let title: String
    let systemImage: String
    let path: String

    var body: some View {
        Button {
            WebLink.open(AppConfig.shared.webOrigin, path: path)
        } label: {
            HStack {
                Label(title, systemImage: systemImage).foregroundStyle(.appForeground)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.appMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
