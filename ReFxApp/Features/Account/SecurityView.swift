import SwiftUI
import UIKit

@MainActor
final class SecurityViewModel: ObservableObject {
    @Published private(set) var apiKeys: [ApiKey] = []
    @Published var message: String?
    @Published var isError = false
    @Published var revealedKey: String?

    private weak var session: AppSession?
    private var service: AccountService?

    func bind(_ session: AppSession) {
        self.session = session
        if service == nil { service = session.account }
    }

    var totpEnabled: Bool { session?.currentUser?.isTotpEnabled ?? false }

    func loadKeys() async {
        guard let service else { return }
        if let keys = try? await service.apiKeys() { apiKeys = keys }
    }

    func disableTotp() async {
        guard let service else { return }
        do {
            try await service.totpDisable()
            await session?.reloadUser()
            flash("Two-factor disabled.", error: false)
        } catch { flash("Couldn't disable two-factor.", error: true) }
    }

    func createKey(name: String, scopes: [String]) async {
        guard let service, !name.isEmpty, !scopes.isEmpty else { return }
        do {
            let created = try await service.createApiKey(name: name, scopes: scopes)
            revealedKey = created.key
            await loadKeys()
        } catch let error as APIError { flash(error.userMessage, error: true) }
        catch { flash("Couldn't create the key.", error: true) }
    }

    func revoke(_ key: ApiKey) async {
        guard let service else { return }
        do { try await service.revokeApiKey(key.id); await loadKeys() }
        catch { flash("Couldn't revoke the key.", error: true) }
    }

    func onTotpEnabled() async {
        await session?.reloadUser()
    }

    private func flash(_ text: String, error: Bool) { message = text; isError = error }
}

struct SecurityView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = SecurityViewModel()
    @State private var showEnroll = false
    @State private var showCreateKey = false
    @State private var confirmDisable = false

    var body: some View {
        Form {
            if let message = model.message {
                Text(message).font(.footnote)
                    .foregroundStyle(model.isError ? .appDestructive : .appSuccess)
                    .listRowBackground(Color.appCard)
            }

            Section {
                if model.totpEnabled {
                    Label("Enabled", systemImage: "checkmark.shield.fill").foregroundStyle(.appSuccess)
                    Button("Disable two-factor", role: .destructive) { confirmDisable = true }
                } else {
                    Button { showEnroll = true } label: {
                        Label("Set up authenticator app", systemImage: "lock.shield")
                    }
                }
            } header: {
                Text("Two-factor authentication")
            } footer: {
                Text("Protect your account with a time-based code from an authenticator app.")
            }
            .listRowBackground(Color.appCard)

            Section {
                if model.apiKeys.isEmpty {
                    Text("No API keys.").font(.footnote).foregroundStyle(.appMuted)
                }
                ForEach(model.apiKeys) { key in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.name).foregroundStyle(.appForeground)
                        Text("\(key.prefix)… · \(key.scopeSummary)")
                            .font(.caption2.monospaced()).foregroundStyle(.appMuted)
                    }
                    .swipeActions {
                        Button(role: .destructive) { Task { await model.revoke(key) } } label: {
                            Label("Revoke", systemImage: "trash")
                        }
                    }
                }
                Button { showCreateKey = true } label: { Label("Create API key", systemImage: "plus") }
            } header: {
                Text("API keys")
            }
            .listRowBackground(Color.appCard)
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEnroll) {
            TotpEnrollView { await model.onTotpEnabled() }
        }
        .sheet(isPresented: $showCreateKey) {
            CreateApiKeyView { name, scopes in await model.createKey(name: name, scopes: scopes) }
        }
        .alert("API key created", isPresented: Binding(
            get: { model.revealedKey != nil }, set: { if !$0 { model.revealedKey = nil } })) {
            Button("Copy") { if let k = model.revealedKey { UIPasteboard.general.string = k } }
            Button("Done", role: .cancel) {}
        } message: {
            if let key = model.revealedKey {
                Text("\(key)\n\nCopy it now — it won't be shown again.")
            }
        }
        .confirmationDialog("Disable two-factor?", isPresented: $confirmDisable, titleVisibility: .visible) {
            Button("Disable", role: .destructive) { Task { await model.disableTotp() } }
            Button("Cancel", role: .cancel) {}
        }
        .task { model.bind(session); await model.loadKeys() }
    }
}

/// Enroll a TOTP authenticator: show the secret, verify a code, reveal recovery codes.
struct TotpEnrollView: View {
    let onEnabled: () async -> Void
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var enrollment: TotpEnrollment?
    @State private var code = ""
    @State private var recoveryCodes: [String]?
    @State private var errorText: String?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            Form {
                if let codes = recoveryCodes {
                    Section {
                        ForEach(codes, id: \.self) { Text($0).font(.callout.monospaced()) }
                    } header: {
                        Text("Recovery codes")
                    } footer: {
                        Text("Save these somewhere safe. Each can be used once if you lose your authenticator.")
                    }
                    .listRowBackground(Color.appCard)
                } else if let enrollment {
                    Section {
                        Text(enrollment.secret).font(.callout.monospaced()).textSelection(.enabled)
                        Button("Copy setup key") { UIPasteboard.general.string = enrollment.secret }
                    } header: {
                        Text("1. Add this key to your authenticator")
                    }
                    .listRowBackground(Color.appCard)
                    Section {
                        TextField("123456", text: $code).keyboardType(.numberPad)
                            .textContentType(.oneTimeCode).font(.title3.monospaced())
                    } header: {
                        Text("2. Enter the 6-digit code")
                    }
                    .listRowBackground(Color.appCard)
                    if let errorText { Text(errorText).foregroundStyle(.appDestructive).font(.footnote) }
                } else {
                    ProgressView().tint(.appPrimary)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("Two-factor").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(recoveryCodes == nil ? "Cancel" : "Done") { dismiss() }
                }
                if recoveryCodes == nil && enrollment != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Verify") { Task { await verify() } }.disabled(code.count < 6 || isBusy)
                    }
                }
            }
            .task { await enroll() }
        }
    }

    private func enroll() async {
        guard enrollment == nil else { return }
        enrollment = try? await session.account.totpEnroll()
    }

    private func verify() async {
        errorText = nil; isBusy = true
        defer { isBusy = false }
        do {
            let result = try await session.account.totpVerify(code: code)
            recoveryCodes = result.recoveryCodes
            await onEnabled()
        } catch let e as APIError { errorText = e.userMessage }
        catch { errorText = "Invalid code. Try again." }
    }
}

struct CreateApiKeyView: View {
    let onCreate: (String, [String]) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scopes: Set<String> = ["READ"]

    private let allScopes = ["READ", "WRITE", "ADMIN"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("e.g. CI deploy", text: $name) }
                Section("Scopes") {
                    ForEach(allScopes, id: \.self) { scope in
                        Toggle(scope.capitalized, isOn: Binding(
                            get: { scopes.contains(scope) },
                            set: { on in if on { scopes.insert(scope) } else { scopes.remove(scope) } }))
                        .tint(.appPrimary)
                    }
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("New API key").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await onCreate(name, Array(scopes)) }
                        dismiss()
                    }.disabled(name.isEmpty || scopes.isEmpty)
                }
            }
        }
    }
}
