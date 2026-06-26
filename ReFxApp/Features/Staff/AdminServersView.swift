import SwiftUI

@MainActor
final class AdminServersViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[Server]> = .idle
    @Published var searchText = ""
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.servers(query: searchText.isEmpty ? nil : searchText).items) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func refresh() async { await load() }
}

/// Platform-wide server list for staff. Opens the standard server screen, so
/// power controls / restart / full management apply to any customer's server.
struct AdminServersView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = AdminServersViewModel()
    @State private var showCreate = false

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No servers",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 12) { ForEach(0..<6, id: \.self) { _ in SkeletonBlock(height: 80) } }.padding(16) })
        .screenBackground()
        .navigationTitle("Server admin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Create server")
            }
        }
        .searchable(text: $model.searchText, prompt: "Search all servers")
        .onSubmit(of: .search) { Task { await model.load() } }
        .sheet(isPresented: $showCreate) {
            AdminCreateServerView { Task { await model.refresh() } }
        }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(model.state.value ?? []) { server in
                    NavigationLink {
                        ServerDetailView(serverId: server.id, preview: server)
                    } label: { ServerRow(server: server) }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .readableWidth()
        }
        .refreshable { await model.refresh() }
    }
}
