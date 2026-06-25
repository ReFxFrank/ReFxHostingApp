import SwiftUI

@MainActor
final class UserAdminViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[AdminUser]> = .idle
    @Published var searchText = ""
    @Published var actionError: String?
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.users(query: searchText.isEmpty ? nil : searchText).items) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func toggleSuspend(_ user: AdminUser) async {
        await run {
            if user.isSuspended { try await $0.reactivateUser(user.id) }
            else { try await $0.suspendUser(user.id) }
        }
    }

    func setRole(_ user: AdminUser, role: UserRole) async {
        await run { try await $0.setRole(user.id, role: role.rawValue) }
    }

    private func run(_ work: (StaffService) async throws -> Void) async {
        guard let service else { return }
        actionError = nil
        do { try await work(service); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Action failed. Try again." }
    }
}

struct UserAdminView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = UserAdminViewModel()
    @State private var roleTarget: AdminUser?

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No users",
            emptyMessage: "Search by name or email.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 10) { ForEach(0..<6, id: \.self) { _ in SkeletonBlock(height: 60) } }.padding(16) })
        .screenBackground()
        .navigationTitle("User admin")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.searchText, prompt: "Search users")
        .onSubmit(of: .search) { Task { await model.load() } }
        .confirmationDialog("Change role", isPresented: Binding(
            get: { roleTarget != nil }, set: { if !$0 { roleTarget = nil } }),
            titleVisibility: .visible) {
            if let user = roleTarget {
                ForEach([UserRole.customer, .support, .admin, .owner], id: \.self) { role in
                    Button(role.rawValue.capitalized) { Task { await model.setRole(user, role: role) } }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        List {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).listRowBackground(Color.appCard)
            }
            ForEach(model.state.value ?? []) { user in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(user.displayName).foregroundStyle(.appForeground).lineLimit(1)
                        Spacer()
                        RoleBadge(role: user.role)
                    }
                    Text(user.email).font(.caption).foregroundStyle(.appMuted).lineLimit(1)
                    if user.isSuspended {
                        Text("Suspended").font(.caption2).foregroundStyle(.appDestructive)
                    }
                }
                .listRowBackground(Color.appCard)
                .swipeActions {
                    Button(role: user.isSuspended ? nil : .destructive) {
                        Task { await model.toggleSuspend(user) }
                    } label: {
                        Label(user.isSuspended ? "Reactivate" : "Suspend",
                              systemImage: user.isSuspended ? "person.fill.checkmark" : "person.fill.xmark")
                    }
                    .tint(user.isSuspended ? .appSuccess : .appDestructive)
                    Button { roleTarget = user } label: { Label("Role", systemImage: "person.badge.key") }
                        .tint(.appPrimary)
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).screenBackground()
        .refreshable { await model.load() }
    }
}
