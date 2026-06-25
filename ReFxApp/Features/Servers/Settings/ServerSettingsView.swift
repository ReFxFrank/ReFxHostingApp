import SwiftUI
import UIKit

@MainActor
final class ServerSettingsViewModel: ObservableObject {
    @Published var startupCommand = ""
    @Published private(set) var savedStartup = ""
    @Published private(set) var variables: [ServerVariable] = []
    @Published private(set) var isLoading = true
    @Published var message: String?
    @Published var isError = false
    @Published private(set) var isSavingStartup = false

    let serverId: String
    private var service: ServerSettingsService?

    init(serverId: String) { self.serverId = serverId }

    var startupDirty: Bool { startupCommand != savedStartup }

    func bind(_ session: AppSession) {
        if service == nil { service = session.serverSettings }
    }

    func load() async {
        guard let service else { return }
        isLoading = true
        defer { isLoading = false }
        // Each is permission-gated independently; tolerate a 403 on either.
        if let startup = try? await service.startup(serverId) {
            startupCommand = startup.startupCommand ?? ""
            savedStartup = startupCommand
        }
        if let vars = try? await service.variables(serverId) {
            variables = vars.sorted { $0.envName < $1.envName }
        }
    }

    func saveStartup() async {
        guard let service, startupDirty else { return }
        await runStartup { try await service.setStartup(self.serverId, command: self.startupCommand) }
    }

    func upsertVariable(envName: String, value: String) async {
        guard let service else { return }
        let name = envName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await run { try await service.setVariable(self.serverId, envName: name, value: value) }
    }

    func deleteVariable(_ variable: ServerVariable) async {
        guard let service else { return }
        await run { try await service.deleteVariable(self.serverId, envName: variable.envName) }
    }

    func reinstall() async {
        guard let service else { return }
        await run(successMessage: "Reinstall started.") {
            try await service.reinstall(self.serverId)
        }
    }

    private func runStartup(_ work: () async throws -> Void) async {
        message = nil
        isSavingStartup = true
        defer { isSavingStartup = false }
        do {
            try await work()
            savedStartup = startupCommand
            flash("Startup command saved.", error: false)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch let error as APIError { flash(error.userMessage, error: true) }
        catch { flash("Couldn't save.", error: true) }
    }

    private func run(successMessage: String? = nil, _ work: () async throws -> Void) async {
        message = nil
        do {
            try await work()
            await load()
            if let successMessage { flash(successMessage, error: false) }
        } catch let error as APIError { flash(error.userMessage, error: true) }
        catch { flash("Action failed. Try again.", error: true) }
    }

    private func flash(_ text: String, error: Bool) {
        message = text
        isError = error
    }
}

struct ServerSettingsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: ServerSettingsViewModel

    @State private var editingVar: ServerVariable?
    @State private var editValue = ""
    @State private var showAddVar = false
    @State private var newVarName = ""
    @State private var newVarValue = ""
    @State private var confirmReinstall = false

    init(serverId: String) {
        _model = StateObject(wrappedValue: ServerSettingsViewModel(serverId: serverId))
    }

    var body: some View {
        Form {
            if let message = model.message {
                Text(message).font(.footnote)
                    .foregroundStyle(model.isError ? .appDestructive : .appSuccess)
                    .listRowBackground(Color.appCard)
            }

            startupSection
            variablesSection
            accessSection
            dangerSection
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Edit variable", isPresented: Binding(
            get: { editingVar != nil }, set: { if !$0 { editingVar = nil } })) {
            TextField("Value", text: $editValue)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Save") {
                if let v = editingVar { Task { await model.upsertVariable(envName: v.envName, value: editValue) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(editingVar?.envName ?? "")
        }
        .alert("Add variable", isPresented: $showAddVar) {
            TextField("NAME", text: $newVarName)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Value", text: $newVarValue)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Add") {
                Task { await model.upsertVariable(envName: newVarName, value: newVarValue) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Reinstall server?", isPresented: $confirmReinstall,
                            titleVisibility: .visible) {
            Button("Reinstall", role: .destructive) { Task { await model.reinstall() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This re-runs the install script. Server files may be reset depending on the game. The server will be unavailable during reinstall.")
        }
        .task {
            model.bind(session)
            await model.load()
        }
    }

    private var startupSection: some View {
        Section {
            TextField("Startup command", text: $model.startupCommand, axis: .vertical)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(2...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                Task { await model.saveStartup() }
            } label: {
                HStack {
                    if model.isSavingStartup { ProgressView() }
                    Text("Save startup command")
                }
            }
            .disabled(!model.startupDirty || model.isSavingStartup)
        } header: {
            Text("Startup command")
        } footer: {
            Text("The command used to launch the server process.")
        }
        .listRowBackground(Color.appCard)
    }

    private var variablesSection: some View {
        Section {
            if model.variables.isEmpty {
                Text("No editable variables.").font(.footnote).foregroundStyle(.appMuted)
            }
            ForEach(model.variables) { variable in
                Button {
                    editingVar = variable
                    editValue = variable.value
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(variable.envName).font(.caption.monospaced()).foregroundStyle(.appMuted)
                        Text(variable.value.isEmpty ? "—" : variable.value)
                            .foregroundStyle(.appForeground).lineLimit(1)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await model.deleteVariable(variable) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            Button {
                newVarName = ""; newVarValue = ""; showAddVar = true
            } label: {
                Label("Add variable", systemImage: "plus")
            }
        } header: {
            Text("Environment variables")
        }
        .listRowBackground(Color.appCard)
    }

    private var accessSection: some View {
        Section {
            NavigationLink {
                SubUsersView(serverId: model.serverId)
            } label: {
                Label("Sub-users", systemImage: "person.2")
            }
        } header: {
            Text("Access")
        }
        .listRowBackground(Color.appCard)
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                confirmReinstall = true
            } label: {
                Label("Reinstall server", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("Danger zone")
        }
        .listRowBackground(Color.appCard)
    }
}
