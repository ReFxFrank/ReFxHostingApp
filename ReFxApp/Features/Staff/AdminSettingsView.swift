import SwiftUI

/// Settings hub: links to the three config forms. Secrets are write-only —
/// reads only ever show masks / presence flags, and inputs are SecureFields
/// left blank to keep the existing value.
struct AdminSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                NavigationLink { EmailSettingsView() } label: {
                    ManageRow(icon: "envelope", title: "Email (SMTP)",
                              subtitle: "Outgoing mail server & test send")
                }.buttonStyle(.plain)

                NavigationLink { SteamSettingsView() } label: {
                    ManageRow(icon: "shippingbox", title: "Steam",
                              subtitle: "API key & downloader login")
                }.buttonStyle(.plain)

                NavigationLink { GatewaySettingsView() } label: {
                    ManageRow(icon: "creditcard", title: "Payment gateways",
                              subtitle: "Stripe & PayPal credentials")
                }.buttonStyle(.plain)

                NavigationLink { BackupStorageSettingsView() } label: {
                    ManageRow(icon: "externaldrive.badge.icloud", title: "Backup storage",
                              subtitle: "S3/R2 offsite backup credentials")
                }.buttonStyle(.plain)

                NavigationLink { VanitySettingsView() } label: {
                    ManageRow(icon: "sparkles", title: "Vanity addresses",
                              subtitle: "Enable & price custom addresses")
                }.buttonStyle(.plain)

                NavigationLink { ReferralSettingsView() } label: {
                    ManageRow(icon: "gift", title: "Referral program",
                              subtitle: "Enable & set the reward")
                }.buttonStyle(.plain)

                NavigationLink { ExpressBackupSettingsView() } label: {
                    ManageRow(icon: "arrow.up.bin", title: "Express backups",
                              subtitle: "Offsite-backup add-on pricing")
                }.buttonStyle(.plain)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Email

@MainActor
final class EmailSettingsViewModel: ObservableObject {
    @Published var state: LoadState<EmailConfigMasked> = .idle
    @Published var statusMessage: String?
    @Published var isSaving = false
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.emailConfig()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func save(_ body: SetEmailConfigBody) async {
        guard let service else { return }
        isSaving = true; statusMessage = nil
        defer { isSaving = false }
        do { try await service.setEmailConfig(body); statusMessage = "Saved."; await load() }
        catch let error as APIError { statusMessage = error.userMessage }
        catch { statusMessage = "Couldn't save email settings." }
    }

    func sendTest(to: String) async {
        guard let service else { return }
        statusMessage = nil
        do {
            let result = try await service.testEmail(to: to)
            statusMessage = result.delivered ? "Test email sent." : "Send failed."
        }
        catch let error as APIError { statusMessage = error.userMessage }
        catch { statusMessage = "Couldn't send the test email." }
    }
}

struct EmailSettingsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = EmailSettingsViewModel()

    @State private var host = ""
    @State private var port = "587"
    @State private var user = ""
    @State private var from = ""
    @State private var secure = true
    @State private var theme: EmailTheme = .dark
    @State private var password = ""
    @State private var testTo = ""
    @State private var loadedOnce = false

    var body: some View {
        Form {
            if let status = model.statusMessage {
                Text(status).font(.footnote).foregroundStyle(.appPrimary).listRowBackground(Color.appCard)
            }
            Section {
                TextField("Host", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Port", text: $port).keyboardType(.numberPad)
                TextField("Username", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(passwordPlaceholder, text: $password)
                TextField("From address", text: $from).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Use TLS/SSL", isOn: $secure).tint(.appPrimary)
                Picker("Email theme", selection: $theme) {
                    Text("Dark").tag(EmailTheme.dark); Text("Light").tag(EmailTheme.light)
                }
            } header: { Text("SMTP") } footer: {
                Text("Leave password blank to keep the current one. An empty field clears that setting.")
            }
            .listRowBackground(Color.appCard)

            Section {
                Button { save() } label: {
                    HStack { if model.isSaving { ProgressView() }; Text("Save email settings") }
                }
                .buttonStyle(.refxPrimary).disabled(model.isSaving)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }

            Section {
                TextField("Send test to…", text: $testTo).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Send test email") { Task { await model.sendTest(to: testTo) } }
                    .disabled(testTo.isEmpty)
                    .foregroundStyle(.appPrimary)
            } header: { Text("Test") }
            .listRowBackground(Color.appCard)
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Email").navigationBarTitleDisplayMode(.inline)
        .task {
            model.bind(session)
            if model.state.value == nil { await model.load() }
            applyLoaded()
        }
        .onChange(of: model.state.value) { _ in applyLoaded() }
    }

    private var passwordPlaceholder: String {
        (model.state.value?.passwordSet ?? false) ? "Password (set — leave blank to keep)" : "Password"
    }

    private func applyLoaded() {
        guard !loadedOnce, let config = model.state.value else { return }
        host = config.host; port = String(config.port); user = config.user
        from = config.from; secure = config.secure; theme = config.theme
        loadedOnce = true
    }

    private func save() {
        var body = SetEmailConfigBody()
        body.host = host; body.port = Int(port); body.user = user
        body.from = from; body.secure = secure; body.theme = theme
        if !password.isEmpty { body.password = password }
        Task { await model.save(body); password = "" }
    }
}

// MARK: - Steam

@MainActor
final class SteamSettingsViewModel: ObservableObject {
    @Published var state: LoadState<SteamConfigMasked> = .idle
    @Published var statusMessage: String?
    @Published var isSaving = false
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.steamConfig()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func save(_ body: SetSteamConfigBody) async {
        guard let service else { return }
        isSaving = true; statusMessage = nil
        defer { isSaving = false }
        do { try await service.setSteamConfig(body); statusMessage = "Saved."; await load() }
        catch let error as APIError { statusMessage = error.userMessage }
        catch { statusMessage = "Couldn't save Steam settings." }
    }
}

struct SteamSettingsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = SteamSettingsViewModel()

    @State private var username = ""
    @State private var apiKey = ""
    @State private var password = ""
    @State private var guardCode = ""
    @State private var loadedOnce = false

    var body: some View {
        Form {
            if let status = model.statusMessage {
                Text(status).font(.footnote).foregroundStyle(.appPrimary).listRowBackground(Color.appCard)
            }
            if let config = model.state.value {
                Section {
                    statusRow("API key", isSet: config.apiKeySet)
                    statusRow("Downloader login", isSet: config.loginConfigured)
                    if config.guardCodePending {
                        Label("Steam Guard code pending", systemImage: "exclamationmark.shield")
                            .font(.caption).foregroundStyle(.appWarning)
                    }
                } header: { Text("Status") }
                .listRowBackground(Color.appCard)
            }
            Section {
                SecureField(apiKeySet ? "API key (set — blank to keep)" : "API key", text: $apiKey)
                TextField("Downloader username", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(passwordSet ? "Password (set — blank to keep)" : "Password", text: $password)
                SecureField("Steam Guard code (one-time)", text: $guardCode)
            } header: { Text("Credentials") } footer: {
                Text("Secrets are write-only. Leave a field blank to keep its current value.")
            }
            .listRowBackground(Color.appCard)

            Section {
                Button { save() } label: {
                    HStack { if model.isSaving { ProgressView() }; Text("Save Steam settings") }
                }
                .buttonStyle(.refxPrimary).disabled(model.isSaving)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Steam").navigationBarTitleDisplayMode(.inline)
        .task {
            model.bind(session)
            if model.state.value == nil { await model.load() }
            applyLoaded()
        }
        .onChange(of: model.state.value) { _ in applyLoaded() }
    }

    private var apiKeySet: Bool { model.state.value?.apiKeySet ?? false }
    private var passwordSet: Bool { model.state.value?.passwordSet ?? false }

    private func statusRow(_ title: String, isSet: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(.appForeground)
            Spacer()
            StatusChip(text: isSet ? "Configured" : "Not set", color: isSet ? .appSuccess : .appMuted)
        }
    }

    private func applyLoaded() {
        guard !loadedOnce, let config = model.state.value else { return }
        username = config.username
        loadedOnce = true
    }

    private func save() {
        var body = SetSteamConfigBody()
        body.username = username
        if !apiKey.isEmpty { body.apiKey = apiKey }
        if !password.isEmpty { body.password = password }
        if !guardCode.isEmpty { body.guardCode = guardCode }
        Task { await model.save(body); apiKey = ""; password = ""; guardCode = "" }
    }
}

// MARK: - Gateways

@MainActor
final class GatewaySettingsViewModel: ObservableObject {
    @Published var state: LoadState<GatewayConfigMasked> = .idle
    @Published var statusMessage: String?
    @Published var isSaving = false
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.gatewayConfig()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func save(_ body: SetGatewayConfigBody) async {
        guard let service else { return }
        isSaving = true; statusMessage = nil
        defer { isSaving = false }
        do { try await service.setGatewayConfig(body); statusMessage = "Saved."; await load() }
        catch let error as APIError { statusMessage = error.userMessage }
        catch { statusMessage = "Couldn't save gateway settings." }
    }
}

struct GatewaySettingsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = GatewaySettingsViewModel()

    @State private var stripePublishable = ""
    @State private var stripeDescriptor = ""
    @State private var stripeSecret = ""
    @State private var stripeWebhook = ""
    @State private var paypalClientId = ""
    @State private var paypalMode: PayPalMode = .sandbox
    @State private var paypalSecret = ""
    @State private var paypalWebhookId = ""
    @State private var loadedOnce = false

    var body: some View {
        Form {
            if let status = model.statusMessage {
                Text(status).font(.footnote).foregroundStyle(.appPrimary).listRowBackground(Color.appCard)
            }
            Section {
                TextField("Publishable key", text: $stripePublishable)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(stripeSecretPlaceholder, text: $stripeSecret)
                SecureField(stripeWebhookSet ? "Webhook secret (set — blank to keep)" : "Webhook secret", text: $stripeWebhook)
                TextField("Statement descriptor", text: $stripeDescriptor)
            } header: { Text("Stripe") } footer: {
                if let masked = model.state.value?.stripe.secretKeyMasked, !masked.isEmpty {
                    Text("Current secret: \(masked)")
                }
            }
            .listRowBackground(Color.appCard)

            Section {
                TextField("Client ID", text: $paypalClientId)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(paypalSecretSet ? "Client secret (set — blank to keep)" : "Client secret", text: $paypalSecret)
                Picker("Mode", selection: $paypalMode) {
                    Text("Sandbox").tag(PayPalMode.sandbox); Text("Live").tag(PayPalMode.live)
                }
                TextField("Webhook ID", text: $paypalWebhookId)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("PayPal") }
            .listRowBackground(Color.appCard)

            Section {
                Button { save() } label: {
                    HStack { if model.isSaving { ProgressView() }; Text("Save gateways") }
                }
                .buttonStyle(.refxPrimary).disabled(model.isSaving)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            } footer: {
                Text("Secrets are write-only. Leave a field blank to keep its current value.")
            }
        }
        .scrollContentBackground(.hidden).screenBackground()
        .navigationTitle("Gateways").navigationBarTitleDisplayMode(.inline)
        .task {
            model.bind(session)
            if model.state.value == nil { await model.load() }
            applyLoaded()
        }
        .onChange(of: model.state.value) { _ in applyLoaded() }
    }

    private var stripeWebhookSet: Bool { model.state.value?.stripe.webhookSecretSet ?? false }
    private var paypalSecretSet: Bool { model.state.value?.paypal.clientSecretSet ?? false }
    private var stripeSecretPlaceholder: String {
        (model.state.value?.stripe.configured ?? false) ? "Secret key (set — blank to keep)" : "Secret key"
    }

    private func applyLoaded() {
        guard !loadedOnce, let config = model.state.value else { return }
        stripePublishable = config.stripe.publishableKey
        stripeDescriptor = config.stripe.statementDescriptor
        paypalClientId = config.paypal.clientId
        paypalWebhookId = config.paypal.webhookId
        paypalMode = config.paypal.mode == "live" ? .live : .sandbox
        loadedOnce = true
    }

    private func save() {
        var body = SetGatewayConfigBody()
        body.stripePublishableKey = stripePublishable
        body.stripeStatementDescriptor = stripeDescriptor
        body.paypalClientId = paypalClientId
        body.paypalWebhookId = paypalWebhookId
        body.paypalMode = paypalMode
        if !stripeSecret.isEmpty { body.stripeSecretKey = stripeSecret }
        if !stripeWebhook.isEmpty { body.stripeWebhookSecret = stripeWebhook }
        if !paypalSecret.isEmpty { body.paypalClientSecret = paypalSecret }
        Task { await model.save(body); stripeSecret = ""; stripeWebhook = ""; paypalSecret = "" }
    }
}
