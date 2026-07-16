import SwiftUI

// MARK: - Vanity addresses

@MainActor
final class VanitySettingsViewModel: ObservableObject {
    @Published var state: LoadState<VanitySettings> = .idle
    @Published var statusMessage: String?
    @Published var isSaving = false
    private var service: StaffService?
    func bind(_ s: AppSession) { if service == nil { service = s.staff } }
    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.vanitySettings()) }
        catch let e as APIError { state = .failed(e) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
    func save(_ body: SetVanitySettingsBody) async {
        guard let service else { return }
        isSaving = true; statusMessage = nil; defer { isSaving = false }
        do { try await service.setVanitySettings(body); statusMessage = "Saved."; await load() }
        catch let e as APIError { statusMessage = e.userMessage }
        catch { statusMessage = "Couldn't save." }
    }
}

struct VanitySettingsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = VanitySettingsViewModel()
    @State private var enabled = true
    @State private var feeMinor = "200"
    @State private var reserved = ""
    @State private var loadedOnce = false

    var body: some View {
        Form {
            statusRow(model.statusMessage)
            Section {
                Toggle("Enabled", isOn: $enabled).tint(.appPrimary)
                MinorField(title: "One-time fee", text: $feeMinor)
                TextField("Reserved words (comma/newline)", text: $reserved, axis: .vertical).lineLimit(1...4)
            } footer: { Text("Fee is in minor units (200 = $2.00). Reserved words are merged with the built-in list.") }
            .listRowBackground(Color.appCard)
            SaveSection(isSaving: model.isSaving, title: "Save vanity settings") {
                let words = reserved.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { String($0).trimmed }.filter { !$0.isEmpty }
                Task { await model.save(SetVanitySettingsBody(enabled: enabled, feeMinor: Int(feeMinor), reservedWords: words)) }
            }
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Vanity addresses").navigationBarTitleDisplayMode(.inline)
        .task { model.bind(session); if model.state.value == nil { await model.load() }; apply() }
        .onChange(of: model.state.value) { _ in apply() }
    }
    private func apply() {
        guard !loadedOnce, let c = model.state.value else { return }
        enabled = c.enabled; feeMinor = String(c.feeMinor); reserved = c.reservedWords.joined(separator: ", "); loadedOnce = true
    }
}

// MARK: - Referral program

@MainActor
final class ReferralSettingsViewModel: ObservableObject {
    @Published var state: LoadState<ReferralSettings> = .idle
    @Published var statusMessage: String?
    @Published var isSaving = false
    private var service: StaffService?
    func bind(_ s: AppSession) { if service == nil { service = s.staff } }
    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.referralSettings()) }
        catch let e as APIError { state = .failed(e) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
    func save(_ body: SetReferralSettingsBody) async {
        guard let service else { return }
        isSaving = true; statusMessage = nil; defer { isSaving = false }
        do { try await service.setReferralSettings(body); statusMessage = "Saved."; await load() }
        catch let e as APIError { statusMessage = e.userMessage }
        catch { statusMessage = "Couldn't save." }
    }
}

struct ReferralSettingsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = ReferralSettingsViewModel()
    @State private var enabled = false
    @State private var rewardMinor = "500"
    @State private var loadedOnce = false

    var body: some View {
        Form {
            statusRow(model.statusMessage)
            Section {
                Toggle("Enabled", isOn: $enabled).tint(.appPrimary)
                MinorField(title: "Reward (both sides)", text: $rewardMinor)
            } footer: { Text("Credit both sides receive when a referred customer first pays (500 = $5.00).") }
            .listRowBackground(Color.appCard)
            SaveSection(isSaving: model.isSaving, title: "Save referral settings") {
                Task { await model.save(SetReferralSettingsBody(enabled: enabled, rewardMinor: Int(rewardMinor))) }
            }
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Referral program").navigationBarTitleDisplayMode(.inline)
        .task { model.bind(session); if model.state.value == nil { await model.load() }; apply() }
        .onChange(of: model.state.value) { _ in apply() }
    }
    private func apply() {
        guard !loadedOnce, let c = model.state.value else { return }
        enabled = c.enabled; rewardMinor = String(c.rewardMinor); loadedOnce = true
    }
}

// MARK: - Express backups

@MainActor
final class ExpressBackupSettingsViewModel: ObservableObject {
    @Published var state: LoadState<ExpressBackupSettings> = .idle
    @Published var statusMessage: String?
    @Published var isSaving = false
    private var service: StaffService?
    func bind(_ s: AppSession) { if service == nil { service = s.staff } }
    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.expressBackupSettings()) }
        catch let e as APIError { state = .failed(e) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
    func save(_ body: SetExpressBackupSettingsBody) async {
        guard let service else { return }
        isSaving = true; statusMessage = nil; defer { isSaving = false }
        do { try await service.setExpressBackupSettings(body); statusMessage = "Saved."; await load() }
        catch let e as APIError { statusMessage = e.userMessage }
        catch { statusMessage = "Couldn't save." }
    }
}

struct ExpressBackupSettingsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = ExpressBackupSettingsViewModel()
    @State private var enabled = false
    @State private var monthlyMinor = "200"
    @State private var loadedOnce = false

    var body: some View {
        Form {
            statusRow(model.statusMessage)
            Section {
                Toggle("Enabled", isOn: $enabled).tint(.appPrimary)
                MinorField(title: "Monthly fee", text: $monthlyMinor)
            } footer: { Text("Monthly add-on fee (200 = $2.00/mo). Nodes also need S3 credentials configured.") }
            .listRowBackground(Color.appCard)
            SaveSection(isSaving: model.isSaving, title: "Save express backups") {
                Task { await model.save(SetExpressBackupSettingsBody(enabled: enabled, monthlyMinor: Int(monthlyMinor))) }
            }
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Express backups").navigationBarTitleDisplayMode(.inline)
        .task { model.bind(session); if model.state.value == nil { await model.load() }; apply() }
        .onChange(of: model.state.value) { _ in apply() }
    }
    private func apply() {
        guard !loadedOnce, let c = model.state.value else { return }
        enabled = c.enabled; monthlyMinor = String(c.monthlyMinor); loadedOnce = true
    }
}

// MARK: - Backup storage (S3/R2)

@MainActor
final class BackupStorageSettingsViewModel: ObservableObject {
    @Published var state: LoadState<BackupStorageConfigMasked> = .idle
    @Published var statusMessage: String?
    @Published var isSaving = false
    private var service: StaffService?
    func bind(_ s: AppSession) { if service == nil { service = s.staff } }
    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.backupStorageConfig()) }
        catch let e as APIError { state = .failed(e) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
    func save(_ body: SetBackupStorageBody) async {
        guard let service else { return }
        isSaving = true; statusMessage = nil; defer { isSaving = false }
        do { try await service.setBackupStorageConfig(body); statusMessage = "Saved & pushed to nodes."; await load() }
        catch let e as APIError { statusMessage = e.userMessage }
        catch { statusMessage = "Couldn't save." }
    }
}

struct BackupStorageSettingsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = BackupStorageSettingsViewModel()
    @State private var endpoint = ""
    @State private var region = "auto"
    @State private var bucket = ""
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var usePathStyle = false
    @State private var loadedOnce = false

    var body: some View {
        Form {
            statusRow(model.statusMessage)
            if let c = model.state.value {
                Section("Status") {
                    HStack { Text("Access key").foregroundStyle(.appForeground); Spacer()
                        StatusChip(text: c.accessKeySet ? "Set" : "Not set", color: c.accessKeySet ? .appSuccess : .appMuted) }
                    HStack { Text("Secret key").foregroundStyle(.appForeground); Spacer()
                        StatusChip(text: c.secretKeySet ? "Set" : "Not set", color: c.secretKeySet ? .appSuccess : .appMuted) }
                }.listRowBackground(Color.appCard)
            }
            Section {
                TextField("Endpoint (blank for AWS)", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Region (auto for R2)", text: $region).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Bucket", text: $bucket).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(accessKeySet ? "Access key (set — blank to keep)" : "Access key", text: $accessKey)
                SecureField(secretKeySet ? "Secret key (set — blank to keep)" : "Secret key", text: $secretKey)
                Toggle("Path-style URLs", isOn: $usePathStyle).tint(.appPrimary)
            } header: { Text("S3 / R2") } footer: {
                Text("Secrets are write-only — leave blank to keep. Clearing the bucket removes the whole config. Saving pushes to every node.")
            }
            .listRowBackground(Color.appCard)
            SaveSection(isSaving: model.isSaving, title: "Save & push to nodes") {
                var body = SetBackupStorageBody()
                body.endpoint = endpoint; body.region = region; body.bucket = bucket; body.usePathStyle = usePathStyle
                if !accessKey.isEmpty { body.accessKey = accessKey }
                if !secretKey.isEmpty { body.secretKey = secretKey }
                Task { await model.save(body); accessKey = ""; secretKey = "" }
            }
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Backup storage").navigationBarTitleDisplayMode(.inline)
        .task { model.bind(session); if model.state.value == nil { await model.load() }; apply() }
        .onChange(of: model.state.value) { _ in apply() }
    }
    private var accessKeySet: Bool { model.state.value?.accessKeySet ?? false }
    private var secretKeySet: Bool { model.state.value?.secretKeySet ?? false }
    private func apply() {
        guard !loadedOnce, let c = model.state.value else { return }
        endpoint = c.endpoint; region = c.region.isEmpty ? "auto" : c.region; bucket = c.bucket; usePathStyle = c.usePathStyle
        loadedOnce = true
    }
}

// MARK: - Shared helpers

/// A minor-units integer field with a live dollar preview.
private struct MinorField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack {
            TextField(title, text: $text).keyboardType(.numberPad)
            Spacer()
            Text(Money(minorUnits: Int(text) ?? 0, currency: "USD").formatted)
                .font(.caption.monospacedDigit()).foregroundStyle(.appMuted)
        }
    }
}

private struct SaveSection: View {
    let isSaving: Bool
    let title: String
    let action: () -> Void
    var body: some View {
        Section {
            Button(action: action) { HStack { if isSaving { ProgressView() }; Text(title) } }
                .buttonStyle(.refxPrimary).disabled(isSaving)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
    }
}

@ViewBuilder
private func statusRow(_ message: String?) -> some View {
    if let message {
        Text(message).font(.footnote).foregroundStyle(.appPrimary).listRowBackground(Color.appCard)
    }
}
