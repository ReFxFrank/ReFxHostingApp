import SwiftUI

@MainActor
final class StaffMembersViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[StaffMember]> = .idle
    @Published var actionError: String?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.staffMembers()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func create(_ body: StaffMemberBody) async -> Bool { await mutate { try await $0.createStaffMember(body) } }
    func update(_ id: String, _ body: StaffMemberBody) async -> Bool { await mutate { try await $0.updateStaffMember(id, body) } }
    func delete(_ m: StaffMember) async { _ = await mutate { try await $0.deleteStaffMember(m.id) } }

    @discardableResult
    private func mutate(_ work: (StaffService) async throws -> Void) async -> Bool {
        guard let service else { return false }
        actionError = nil
        do { try await work(service); await load(); return true }
        catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Action failed. Try again."; return false }
    }
}

struct StaffMembersView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = StaffMembersViewModel()
    @State private var showCreate = false
    @State private var editing: StaffMember?

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.isEmpty },
                emptyTitle: "No team members",
                emptyMessage: "Add the people shown on your public “meet the team” page.",
                retry: { Task { await model.load() } },
                content: { list($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 72) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Staff members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add member")
            }
        }
        .sheet(isPresented: $showCreate) {
            StaffMemberEditSheet(title: "New member") { await model.create($0) }
        }
        .sheet(item: $editing) { m in
            StaffMemberEditSheet(title: "Edit member", member: m) { await model.update(m.id, $0) }
        }
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func list(_ members: [StaffMember]) -> some View {
        VStack(spacing: 12) {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(members) { m in
                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle").foregroundStyle(.appSecondary).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                            Text(m.title).font(.caption).foregroundStyle(.appMuted)
                        }
                        Spacer()
                        if !m.isActive { StatusChip(text: "Hidden", color: .appMuted) }
                    }
                }
                .contextMenu {
                    Button { editing = m } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { Task { await model.delete(m) } } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }
}

private struct StaffMemberEditSheet: View {
    let title: String
    var member: StaffMember?
    let onSave: (StaffMemberBody) async -> Bool
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var role = ""
    @State private var bio = ""
    @State private var link = ""
    @State private var sortOrder = "0"
    @State private var isActive = true
    @State private var isSaving = false

    private var canSave: Bool { !name.trimmed.isEmpty && !role.trimmed.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Title (e.g. Founder)", text: $role)
                    TextField("Bio", text: $bio, axis: .vertical).lineLimit(2...5)
                    TextField("Public link", text: $link)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }.listRowBackground(Color.appCard)
                Section {
                    TextField("Sort order", text: $sortOrder).keyboardType(.numberPad)
                    Toggle("Visible", isOn: $isActive).tint(.appPrimary)
                }.listRowBackground(Color.appCard)
                Section {
                    Button {
                        isSaving = true
                        Task {
                            let ok = await onSave(StaffMemberBody(
                                name: name.trimmed, title: role.trimmed,
                                bio: bio.trimmed.isEmpty ? nil : bio.trimmed,
                                link: link.trimmed.isEmpty ? nil : link.trimmed,
                                isActive: isActive, sortOrder: Int(sortOrder) ?? 0))
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
                if let member {
                    name = member.name; role = member.title; bio = member.bio ?? ""
                    link = member.link ?? ""; sortOrder = String(member.sortOrder); isActive = member.isActive
                }
            }
        }
    }
}
