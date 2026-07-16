import SwiftUI

@MainActor
final class DatabaseHostsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[DatabaseHost]> = .idle
    @Published var actionMessage: String?
    @Published var isError = false
    @Published var testingId: String?

    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.databaseHosts()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func create(_ body: CreateDatabaseHostBody) async -> Bool {
        await mutate { try await $0.createDatabaseHost(body) }
    }

    func update(_ id: String, _ body: UpdateDatabaseHostBody) async -> Bool {
        await mutate { try await $0.updateDatabaseHost(id, body) }
    }

    func delete(_ host: DatabaseHost) async {
        _ = await mutate { try await $0.deleteDatabaseHost(host.id) }
    }

    func test(_ host: DatabaseHost) async {
        guard let service else { return }
        testingId = host.id; actionMessage = nil
        defer { testingId = nil }
        do {
            try await service.testDatabaseHost(host.id)
            flash("\(host.name): connection OK.", error: false)
        } catch let error as APIError { flash("\(host.name): \(error.userMessage)", error: true) }
        catch { flash("\(host.name): connection failed.", error: true) }
    }

    @discardableResult
    private func mutate(_ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionMessage = nil
        do { try await work(service); await load(); return true }
        catch let error as APIError { flash(error.userMessage, error: true); return false }
        catch { flash("Action failed. Try again.", error: true); return false }
    }

    private func flash(_ text: String, error: Bool) { actionMessage = text; isError = error }
}

struct DatabaseHostsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = DatabaseHostsViewModel()
    @State private var showCreate = false
    @State private var editing: DatabaseHost?

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No database hosts",
                emptyMessage: "Register a MySQL/MariaDB host to provision customer databases on.",
                retry: { Task { await model.load() } },
                content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 92) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Database hosts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add database host")
            }
        }
        .sheet(isPresented: $showCreate) {
            DatabaseHostEditSheet(title: "New host") { create in
                await model.create(create)
            }
        }
        .sheet(item: $editing) { host in
            DatabaseHostEditSheet(title: "Edit host", host: host) { create in
                // Reuse the create fields for a partial update (engine is fixed).
                await model.update(host.id, UpdateDatabaseHostBody(
                    name: create.name, host: create.host, port: create.port,
                    username: create.username,
                    password: create.password.isEmpty ? nil : create.password,
                    publicHost: create.publicHost, maxDatabases: create.maxDatabases,
                    isActive: create.isActive))
            }
        }
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func list(_ hosts: [DatabaseHost]) -> some View {
        VStack(spacing: 12) {
            if let msg = model.actionMessage {
                Text(msg).font(.footnote)
                    .foregroundStyle(model.isError ? .appDestructive : .appSuccess)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(hosts) { host in
                DatabaseHostCard(host: host, testing: model.testingId == host.id,
                                 onTest: { Task { await model.test(host) } },
                                 onEdit: { editing = host },
                                 onDelete: { Task { await model.delete(host) } })
            }
        }
    }
}

private struct DatabaseHostCard: View {
    let host: DatabaseHost
    let testing: Bool
    let onTest: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                        Text("\(host.publicHost):\(host.port)").font(.caption.monospaced()).foregroundStyle(.appMuted)
                    }
                    Spacer()
                    StatusChip(text: host.engine.label, color: .appPrimary)
                    if !host.isActive { StatusChip(text: "Inactive", color: .appMuted) }
                }
                HStack(spacing: 12) {
                    if let count = host.databaseCount {
                        Label("\(count) / \(host.maxDatabases) DBs", systemImage: "cylinder.split.1x2")
                            .font(.caption2).foregroundStyle(.appMuted)
                    }
                    Label(host.username, systemImage: "person").font(.caption2).foregroundStyle(.appMuted)
                    Spacer()
                    Button(action: onTest) {
                        HStack(spacing: 4) { if testing { ProgressView().controlSize(.mini) }; Text("Test") }
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.appPrimary).disabled(testing)
                }
            }
        }
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button { onTest() } label: { Label("Test connection", systemImage: "bolt.horizontal") }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
        }
        .confirmationDialog("Delete \(host.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Hosts with databases attached can't be deleted.")
        }
    }
}

private struct DatabaseHostEditSheet: View {
    let title: String
    var host: DatabaseHost?
    let onSave: (CreateDatabaseHostBody) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var engine: DbEngine = .mariadb
    @State private var hostAddr = ""
    @State private var port = "3306"
    @State private var username = ""
    @State private var password = ""
    @State private var publicHost = ""
    @State private var maxDatabases = "500"
    @State private var isActive = true
    @State private var isSaving = false

    private var isEditing: Bool { host != nil }
    private var canSave: Bool {
        !name.trimmed.isEmpty && !hostAddr.trimmed.isEmpty && !username.trimmed.isEmpty
            && !publicHost.trimmed.isEmpty && (Int(port) ?? 0) > 0
            && (isEditing || !password.isEmpty) && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    TextField("Name", text: $name)
                    if !isEditing {
                        Picker("Engine", selection: $engine) {
                            ForEach(DbEngine.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) }
                        }
                    }
                    TextField("Admin host (panel → DB)", text: $hostAddr)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Port", text: $port).keyboardType(.numberPad)
                    TextField("Public host (customers connect)", text: $publicHost)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .listRowBackground(Color.appCard)

                Section("Credentials") {
                    TextField("Admin username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(isEditing ? "New password (blank = keep)" : "Admin password", text: $password)
                }
                .listRowBackground(Color.appCard)

                Section {
                    TextField("Max databases", text: $maxDatabases).keyboardType(.numberPad)
                    Toggle("Active", isOn: $isActive).tint(.appPrimary)
                }
                .listRowBackground(Color.appCard)

                Section {
                    Button {
                        isSaving = true
                        Task {
                            let ok = await onSave(CreateDatabaseHostBody(
                                name: name.trimmed, engine: engine.rawValue, host: hostAddr.trimmed,
                                port: Int(port) ?? 3306, username: username.trimmed, password: password,
                                publicHost: publicHost.trimmed, maxDatabases: Int(maxDatabases) ?? 500,
                                isActive: isActive))
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: { HStack { if isSaving { ProgressView() }; Text("Save") } }
                    .buttonStyle(.refxPrimary).disabled(!canSave)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if let host {
                    name = host.name; engine = host.engine; hostAddr = host.host
                    port = String(host.port); username = host.username
                    publicHost = host.publicHost; maxDatabases = String(host.maxDatabases)
                    isActive = host.isActive
                }
            }
        }
    }
}
