import SwiftUI
import UIKit

@MainActor
final class DatabasesViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[ServerDatabase]> = .idle
    @Published var actionError: String?
    /// Shown once after create/rotate.
    @Published var revealedPassword: (db: String, password: String)?

    let serverId: String
    private var service: DatabasesService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.databases } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.list(serverId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func create(engine: DbEngine, name: String, remoteAccess: String?) async {
        guard let service else { return }
        actionError = nil
        do {
            let db = try await service.create(serverId, engine: engine, name: name, remoteAccess: remoteAccess)
            if let pw = db.password { revealedPassword = (db.name, pw) }
            await load()
        } catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't create the database." }
    }

    func rotate(_ db: ServerDatabase) async {
        guard let service else { return }
        actionError = nil
        do {
            let pw = try await service.rotate(serverId, dbId: db.id)
            revealedPassword = (db.name, pw)
        } catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't rotate the password." }
    }

    func delete(_ db: ServerDatabase) async {
        guard let service else { return }
        actionError = nil
        do { try await service.delete(serverId, dbId: db.id); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't delete the database." }
    }
}

struct DatabasesView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: DatabasesViewModel
    @State private var showCreate = false

    init(serverId: String) { _model = StateObject(wrappedValue: DatabasesViewModel(serverId: serverId)) }

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No databases",
            emptyMessage: "Create a MySQL database for your server.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 76) } }.padding(16) })
        .screenBackground()
        .navigationTitle("Databases")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Image(systemName: "plus") } }
        }
        .sheet(isPresented: $showCreate) {
            CreateDatabaseSheet { engine, name, remote in
                Task { await model.create(engine: engine, name: name, remoteAccess: remote) }
            }
        }
        .alert("Database password", isPresented: Binding(
            get: { model.revealedPassword != nil }, set: { if !$0 { model.revealedPassword = nil } })) {
            Button("Copy") {
                if let pw = model.revealedPassword?.password { UIPasteboard.general.string = pw }
            }
            Button("Done", role: .cancel) {}
        } message: {
            if let reveal = model.revealedPassword {
                Text("Password for \(reveal.db):\n\(reveal.password)\n\nThis is shown only once — copy it now.")
            }
        }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        List {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).listRowBackground(Color.appCard)
            }
            ForEach(model.state.value ?? []) { db in
                DatabaseRow(db: db)
                    .listRowBackground(Color.appCard)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await model.delete(db) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { Task { await model.rotate(db) } } label: {
                            Label("New password", systemImage: "key")
                        }.tint(.appWarning)
                    }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).screenBackground()
        .refreshable { await model.load() }
    }
}

struct DatabaseRow: View {
    let db: ServerDatabase
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(db.name).foregroundStyle(.appForeground)
                Text(db.engine.label).font(.caption2).foregroundStyle(.appMuted)
            }
            Text("User: \(db.username)").font(.caption).foregroundStyle(.appMuted)
            CopyChip(label: "Host", value: db.connection)
        }
        .padding(.vertical, 4)
    }
}

struct CreateDatabaseSheet: View {
    let onCreate: (DbEngine, String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var engine: DbEngine = .mysql
    @State private var name = ""
    @State private var remoteAccess = "%"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Engine", selection: $engine) {
                        Text("MySQL").tag(DbEngine.mysql)
                        Text("MariaDB").tag(DbEngine.mariadb)
                    }
                    TextField("Name (a-z, 0-9, _)", text: $name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Remote access pattern", text: $remoteAccess)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("Database")
                } footer: {
                    Text("Use \"%\" to allow any host, or a CIDR like 10.0.0.0/8.")
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle("New database").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(engine, name, remoteAccess.isEmpty ? nil : remoteAccess); dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}
