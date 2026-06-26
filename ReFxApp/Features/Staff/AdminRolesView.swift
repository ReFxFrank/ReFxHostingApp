import SwiftUI

@MainActor
final class AdminRolesViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[Role]> = .idle
    @Published var catalog: [String] = []
    @Published var actionError: String?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do {
            async let roles = service.roles()
            async let perms = service.permissionCatalog()
            let (loadedRoles, loadedCatalog) = try await (roles, perms)
            state = .loaded(loadedRoles)
            catalog = loadedCatalog.permissions
        }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func create(key: String, name: String, description: String, permissions: [String]) async -> Bool {
        await mutate { try await $0.createRole(.init(key: key, name: name,
            description: description.isEmpty ? nil : description, permissions: permissions)) }
    }
    func update(_ role: Role, name: String, description: String, permissions: [String]) async -> Bool {
        await mutate { try await $0.updateRole(role.id, .init(name: name,
            description: description.isEmpty ? nil : description, permissions: permissions)) }
    }
    func delete(_ role: Role) async {
        _ = await mutate { try await $0.deleteRole(role.id) }
    }

    @discardableResult
    private func mutate(_ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { try await work(service); await load(); return true }
        catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Action failed. Try again."; return false }
    }
}

struct AdminRolesView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = AdminRolesViewModel()
    @State private var editing: Role?
    @State private var showCreate = false

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No roles",
                emptyMessage: "Define an RBAC role to grant a custom set of permissions.",
                retry: { Task { await model.load() } },
                content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 84) } } })
            .padding(16)
            .readableWidth()
        }
        .screenBackground()
        .navigationTitle("Roles & permissions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add role")
            }
        }
        .sheet(isPresented: $showCreate) {
            RoleEditSheet(title: "New role", catalog: model.catalog) { key, name, desc, perms in
                await model.create(key: key, name: name, description: desc, permissions: perms)
            }
        }
        .sheet(item: $editing) { role in
            RoleEditSheet(title: "Edit role", catalog: model.catalog, role: role) { _, name, desc, perms in
                await model.update(role, name: name, description: desc, permissions: perms)
            }
        }
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func list(_ roles: [Role]) -> some View {
        VStack(spacing: 12) {
            if let actionError = model.actionError {
                Text(actionError).font(.footnote).foregroundStyle(.appDestructive)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(roles) { role in
                RoleCard(role: role,
                         onEdit: { editing = role },
                         onDelete: { Task { await model.delete(role) } })
            }
        }
    }
}

private struct RoleCard: View {
    let role: Role
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var confirmDelete = false

    private var permsLabel: String {
        if role.isWildcard { return "All permissions" }
        return role.permissions.isEmpty ? "No permissions" : "\(role.permissions.count) permissions"
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(role.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                    if role.isSystem { StatusChip(text: "System", color: .appMuted) }
                    Spacer()
                    Text(role.usersLabel).font(.caption2).foregroundStyle(.appMuted)
                }
                Text(role.key).font(.caption.monospaced()).foregroundStyle(.appMuted)
                if let description = role.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.appMuted).lineLimit(2)
                }
                StatusChip(text: permsLabel, color: role.isWildcard ? .appWarning : .appPrimary)
            }
        }
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            if !role.isSystem {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .confirmationDialog("Delete \(role.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Roles in use by users can't be deleted.")
        }
    }
}

private struct RoleEditSheet: View {
    let title: String
    let catalog: [String]
    var role: Role?
    let onSave: (String, String, String, [String]) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var name = ""
    @State private var description = ""
    @State private var selected: Set<String> = []
    @State private var isSaving = false

    private var isEditing: Bool { role != nil }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (isEditing || !key.trimmingCharacters(in: .whitespaces).isEmpty) && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !isEditing {
                        TextField("Key (e.g. billing-agent)", text: $key)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $description)
                } header: { Text("Role") }
                .listRowBackground(Color.appCard)

                Section {
                    ForEach(catalog, id: \.self) { perm in
                        Button {
                            if selected.contains(perm) { selected.remove(perm) } else { selected.insert(perm) }
                        } label: {
                            HStack {
                                Text(perm).font(.callout.monospaced()).foregroundStyle(.appForeground)
                                Spacer()
                                if selected.contains(perm) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.appPrimary)
                                } else {
                                    Image(systemName: "circle").foregroundStyle(.appMuted)
                                }
                            }
                        }
                    }
                } header: { Text("Permissions") } footer: {
                    Text("Selected: \(selected.count) of \(catalog.count)")
                }
                .listRowBackground(Color.appCard)

                Section {
                    Button {
                        isSaving = true
                        Task {
                            let ok = await onSave(key.trimmingCharacters(in: .whitespaces),
                                                  name.trimmingCharacters(in: .whitespaces),
                                                  description.trimmingCharacters(in: .whitespaces),
                                                  Array(selected))
                            isSaving = false
                            if ok { dismiss() }
                        }
                    } label: {
                        HStack { if isSaving { ProgressView() }; Text("Save") }
                    }
                    .buttonStyle(.refxPrimary).disabled(!canSave)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden).screenBackground()
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if let role {
                    key = role.key; name = role.name; description = role.description ?? ""
                    selected = Set(role.permissions)
                }
            }
        }
    }
}
