import SwiftUI
import UIKit

@MainActor
final class AdminUserDetailViewModel: ObservableObject {
    @Published private(set) var state: LoadState<AdminUserDetail> = .idle
    @Published var actionError: String?

    let userId: String
    private var service: StaffService?

    init(userId: String) { self.userId = userId }

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.userDetail(userId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func refresh() async { await load() }

    func suspend() async { await run { try await $0.suspendUser(self.userId) } }
    func reactivate() async { await run { try await $0.reactivateUser(self.userId) } }
    func ban() async { await run { try await $0.banUser(self.userId) } }
    func verifyEmail() async { await run { try await $0.verifyEmail(self.userId) } }
    func setRole(_ role: UserRole) async { await run { try await $0.setRole(self.userId, role: role.rawValue) } }

    /// Returns true on success so the sheet can dismiss.
    func grantCredit(amountMinor: Int, reason: CreditReason, note: String?) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do {
            try await service.grantCredit(userId: userId, amountMinor: amountMinor, reason: reason, note: note)
            await load(); return true
        }
        catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Couldn't update store credit."; return false }
    }

    private func run(_ work: (StaffService) async throws -> Void) async {
        guard let service else { return }
        actionError = nil
        do { try await work(service); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Action failed. Try again." }
    }
}

/// Full admin account view: profile, staff actions, owned servers, billing.
struct AdminUserDetailView: View {
    @StateObject private var model: AdminUserDetailViewModel
    @EnvironmentObject private var session: AppSession
    @State private var showGrantCredit = false
    private let previewName: String?

    init(userId: String, preview: AdminUser? = nil) {
        _model = StateObject(wrappedValue: AdminUserDetailViewModel(userId: userId))
        self.previewName = preview?.displayName
    }

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { _ in false },
                retry: { Task { await model.load() } },
                content: { content($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 90) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(model.state.value?.displayName ?? previewName ?? "User")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func content(_ user: AdminUserDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(user)
            if let actionError = model.actionError {
                Label(actionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.appDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            actions(user)
            servers(user)
            billing(user)
        }
    }

    // MARK: Header

    private func header(_ user: AdminUserDetail) -> some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.appPrimary.opacity(0.18))
                    Circle().strokeBorder(Color.appPrimary.opacity(0.45), lineWidth: 1)
                    Text(initials(user)).font(.headline).foregroundStyle(.appPrimary)
                }
                .frame(width: 54, height: 54)
                .shadow(color: .appPrimary.opacity(0.35), radius: 8)

                VStack(alignment: .leading, spacing: 5) {
                    Text(user.displayName).font(.headline).foregroundStyle(.appForegroundStrong).lineLimit(1)
                    Text(user.email).font(.caption).foregroundStyle(.appMuted).lineLimit(1)
                    HStack(spacing: 6) {
                        RoleBadge(role: user.role)
                        StatusChip(text: (user.state ?? "Active").capitalized, color: stateColor(user.state))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .overlay(alignment: .topTrailing) {
            if user.emailVerified {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.appSuccess)
                    .padding(10).accessibilityLabel("Email verified")
            }
        }
    }

    // MARK: Actions

    private func actions(_ user: AdminUserDetail) -> some View {
        GlassCard {
            VStack(spacing: 10) {
                if user.isSuspended {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await model.reactivate() }
                    } label: { Label("Reactivate account", systemImage: "checkmark.circle") }
                    .buttonStyle(.refxSecondary)
                } else {
                    ConfirmingButton(title: "Suspend account", systemImage: "pause.circle",
                                     role: .destructive, message: "The user keeps their data but can't use the service.") {
                        await model.suspend()
                    }
                }
                if !user.isBanned {
                    ConfirmingButton(title: "Ban account", systemImage: "nosign",
                                     role: .destructive, message: "Bans the account from the platform.") {
                        await model.ban()
                    }
                }
                if !user.emailVerified {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task { await model.verifyEmail() }
                    } label: { Label("Mark email verified", systemImage: "envelope.badge") }
                    .buttonStyle(.refxSecondary)
                }
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showGrantCredit = true
                } label: { Label("Adjust store credit", systemImage: "creditcard.and.123") }
                .buttonStyle(.refxSecondary)
                RoleMenuButton { role in Task { await model.setRole(role) } }
            }
        }
        .sheet(isPresented: $showGrantCredit) {
            GrantCreditSheet { amountMinor, reason, note in
                await model.grantCredit(amountMinor: amountMinor, reason: reason, note: note)
            }
        }
    }

    // MARK: Servers

    @ViewBuilder private func servers(_ user: AdminUserDetail) -> some View {
        if !user.ownedServers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Servers", systemImage: "server.rack") {
                    Text("\(user.counts?.ownedServers ?? user.ownedServers.count)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.appMuted)
                }.padding(.leading, 4)
                ForEach(user.ownedServers) { server in
                    NavigationLink {
                        ServerDetailView(serverId: server.id, preview: nil)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name).foregroundStyle(.appForeground).lineLimit(1)
                                if let node = server.node?.name {
                                    Text(node).font(.caption2).foregroundStyle(.appMuted)
                                }
                            }
                            Spacer()
                            StatePill(state: server.state)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.appMuted)
                        }
                        .padding(Theme.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Billing

    @ViewBuilder private func billing(_ user: AdminUserDetail) -> some View {
        if !user.subscriptions.isEmpty || !user.invoices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Billing", systemImage: "creditcard").padding(.leading, 4)
                ForEach(user.subscriptions) { sub in
                    HStack {
                        Text(sub.product?.name ?? "Subscription").foregroundStyle(.appForeground).lineLimit(1)
                        Spacer()
                        StatusChip(text: sub.state.capitalized, color: sub.state == "ACTIVE" ? .appSuccess : .appMuted)
                    }
                    .padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                }
                ForEach(user.invoices) { invoice in
                    HStack(spacing: 10) {
                        Text(invoice.number ?? "#\(invoice.id.prefix(6))")
                            .font(.caption.monospaced()).foregroundStyle(.appMuted)
                        Text(invoice.money.formatted).foregroundStyle(.appForeground)
                        Spacer()
                        StatusChip(text: invoice.state.capitalized,
                                   color: invoice.isPaid ? .appSuccess : .appWarning)
                    }
                    .padding(Theme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
                }
            }
        }
    }

    // MARK: Helpers

    private func initials(_ user: AdminUserDetail) -> String {
        let parts = [user.firstName, user.lastName].compactMap { $0?.first }.map(String.init)
        if !parts.isEmpty { return parts.joined().uppercased() }
        return String(user.email.prefix(1)).uppercased()
    }

    private func stateColor(_ state: String?) -> Color {
        switch (state ?? "ACTIVE").uppercased() {
        case "ACTIVE": return .appSuccess
        case "SUSPENDED": return .appWarning
        case "BANNED": return .appDestructive
        default: return .appMuted
        }
    }
}

/// A destructive ReFx button that confirms before running an async action.
private struct ConfirmingButton: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let message: String
    let action: () async -> Void
    @State private var confirm = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            confirm = true
        } label: { Label(title, systemImage: systemImage) }
        .buttonStyle(.refxDestructive)
        .confirmationDialog(title, isPresented: $confirm, titleVisibility: .visible) {
            Button(title, role: .destructive) { Task { await action() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(message) }
    }
}

/// Sheet to add (or deduct) store credit on an account. Amount is entered in
/// dollars and converted to minor units; toggling "Deduct" negates it.
private struct GrantCreditSheet: View {
    /// Returns true on success so the sheet can dismiss itself.
    let onSubmit: (_ amountMinor: Int, _ reason: CreditReason, _ note: String?) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var deduct = false
    @State private var reason: CreditReason = .adminGrant
    @State private var note = ""
    @State private var submitting = false

    private let reasons: [CreditReason] = [.adminGrant, .refund, .adjustment, .giftCard]

    private var amountMinor: Int? {
        guard let dollars = Double(amountText.trimmingCharacters(in: .whitespaces)), dollars > 0 else { return nil }
        let minor = Int((dollars * 100).rounded())
        return deduct ? -minor : minor
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$").foregroundStyle(.appMuted)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title3.monospacedDigit())
                    }
                    Toggle("Deduct from balance", isOn: $deduct)
                } header: { Text("Amount") } footer: {
                    Text(deduct ? "Removes credit from the account." : "Adds credit to the account.")
                }
                .listRowBackground(Color.appCard)

                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        ForEach(reasons, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(Color.appCard)

                Section("Note (optional)") {
                    TextField("Visible in the audit log", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
                .listRowBackground(Color.appCard)

                Section {
                    Button {
                        guard let amountMinor else { return }
                        submitting = true
                        Task {
                            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                            let ok = await onSubmit(amountMinor, reason, trimmed.isEmpty ? nil : trimmed)
                            submitting = false
                            if ok { dismiss() }
                        }
                    } label: {
                        if submitting { ProgressView() } else { Text(deduct ? "Deduct credit" : "Add credit") }
                    }
                    .buttonStyle(.refxPrimary)
                    .disabled(amountMinor == nil || submitting)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Store credit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// "Change role" button → confirmation dialog of the assignable roles.
private struct RoleMenuButton: View {
    let onPick: (UserRole) -> Void
    @State private var show = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            show = true
        } label: { Label("Change role", systemImage: "person.badge.shield.checkmark") }
        .buttonStyle(.refxSecondary)
        .confirmationDialog("Set role", isPresented: $show, titleVisibility: .visible) {
            ForEach([UserRole.customer, .support, .admin, .owner], id: \.self) { role in
                Button(role.rawValue.capitalized) { onPick(role) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
