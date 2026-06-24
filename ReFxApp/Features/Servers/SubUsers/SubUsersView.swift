import SwiftUI

@MainActor
final class SubUsersViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[SubUser]> = .idle
    @Published var actionError: String?

    let serverId: String
    private var service: SubUsersService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.subUsers } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.list(serverId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func add(email: String, permissions: Set<String>) async {
        await run { try await $0.add(self.serverId, email: email, permissions: Array(permissions)) }
    }

    func update(_ subUser: SubUser, permissions: Set<String>) async {
        await run { try await $0.update(self.serverId, subUserId: subUser.id, permissions: Array(permissions)) }
    }

    func remove(_ subUser: SubUser) async {
        await run { try await $0.remove(self.serverId, subUserId: subUser.id) }
    }

    private func run(_ work: (SubUsersService) async throws -> Void) async {
        guard let service else { return }
        actionError = nil
        do { try await work(service); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Action failed. Try again." }
    }
}

struct SubUsersView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: SubUsersViewModel
    @State private var showAdd = false
    @State private var editing: SubUser?

    init(serverId: String) { _model = StateObject(wrappedValue: SubUsersViewModel(serverId: serverId)) }

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No sub-users",
            emptyMessage: "Invite people to help manage this server with specific permissions.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 56) } }.padding(16) })
        .screenBackground()
        .navigationTitle("Sub-users")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "person.badge.plus") } }
        }
        .sheet(isPresented: $showAdd) {
            SubUserEditorSheet(title: "Add sub-user", email: "", permissions: []) { email, perms in
                Task { await model.add(email: email, permissions: perms) }
            }
        }
        .sheet(item: $editing) { sub in
            SubUserEditorSheet(title: sub.email, email: sub.email, lockEmail: true,
                               permissions: Set(sub.permissions)) { _, perms in
                Task { await model.update(sub, permissions: perms) }
            }
        }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        List {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).listRowBackground(Color.appCard)
            }
            ForEach(model.state.value ?? []) { sub in
                Button { editing = sub } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle").foregroundStyle(.appPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.email).foregroundStyle(.appForeground).lineLimit(1)
                            Text("\(sub.permissions.count) permission\(sub.permissions.count == 1 ? "" : "s")")
                                .font(.caption2).foregroundStyle(.appMuted)
                        }
                        Spacer()
                        if !sub.isActive {
                            Text("Pending").font(.caption2).foregroundStyle(.appWarning)
                        }
                    }
                }
                .listRowBackground(Color.appCard)
                .swipeActions {
                    Button(role: .destructive) { Task { await model.remove(sub) } } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Color.appBackground)
        .refreshable { await model.load() }
    }
}

struct SubUserEditorSheet: View {
    let title: String
    var lockEmail = false
    let onSave: (String, Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var permissions: Set<String>

    init(title: String, email: String, lockEmail: Bool = false,
         permissions: Set<String>, onSave: @escaping (String, Set<String>) -> Void) {
        self.title = title
        self.lockEmail = lockEmail
        self.onSave = onSave
        _email = State(initialValue: email)
        _permissions = State(initialValue: permissions)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !lockEmail {
                    Section("Email") {
                        TextField("person@example.com", text: $email)
                            .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .listRowBackground(Color.appCard)
                }
                PermissionEditor(selection: $permissions)
            }
            .scrollContentBackground(.hidden).background(Color.appBackground)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(email, permissions); dismiss() }
                        .disabled(email.isEmpty || permissions.isEmpty)
                }
            }
        }
    }
}
