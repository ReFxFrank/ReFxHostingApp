import SwiftUI

@MainActor
final class SessionsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[UserSession]> = .idle
    private var service: AccountService?

    func bind(_ session: AppSession) {
        if service == nil { service = session.account }
    }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.sessions()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func revoke(_ session: UserSession) async {
        guard let service else { return }
        try? await service.revokeSession(session.id)
        await load()
    }
}

struct SessionsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = SessionsViewModel()

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No active sessions",
            retry: { Task { await model.load() } },
            content: { items in list(items) },
            skeleton: {
                VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 60) } }
                    .padding(16)
            })
        .screenBackground()
        .navigationTitle("Active sessions")
        .task { model.bind(session); await model.load() }
    }

    private func list(_ items: [UserSession]) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.userAgent ?? "Unknown device")
                                .font(.subheadline).foregroundStyle(.appForeground).lineLimit(2)
                            if let ip = item.ip {
                                Text(ip).font(.caption.monospaced()).foregroundStyle(.appMuted)
                            }
                            if let created = item.createdAt {
                                Text("Signed in \(created.formatted(.relative(presentation: .named)))")
                                    .font(.caption2).foregroundStyle(.appMuted)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await model.revoke(item) }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.appDestructive)
                        }
                        .accessibilityLabel("Revoke session")
                    }
                    .padding(Theme.cardPadding)
                    .cardSurface()
                }
            }
            .padding(16)
        }
        .refreshable { await model.load() }
    }
}
