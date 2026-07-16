import SwiftUI

@MainActor
final class GameHistoryViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[GameHistoryEntry]> = .idle

    let serverId: String
    private var service: SwitchGameService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.switchGame } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.history(serverId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
}

/// The record of past game switches for a server.
struct GameHistoryView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: GameHistoryViewModel

    init(serverId: String) { _model = StateObject(wrappedValue: GameHistoryViewModel(serverId: serverId)) }

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No game history",
            emptyMessage: "When you switch this server to a different game, the change is recorded here.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 60) } }.padding(16) })
        .screenBackground()
        .navigationTitle("Game history")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        List {
            ForEach(model.state.value ?? []) { entry in
                GameHistoryRow(entry: entry).listRowBackground(Color.appCard)
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).screenBackground()
        .refreshable { await model.load() }
    }
}

private struct GameHistoryRow: View {
    let entry: GameHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.appPrimary).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(transition).foregroundStyle(.appForeground).lineLimit(1)
                if let at = entry.at {
                    Text(at.formatted(.relative(presentation: .named)))
                        .font(.caption2).foregroundStyle(.appMuted)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var transition: String {
        switch (entry.fromGame, entry.toGame) {
        case let (from?, to?): return "\(from) → \(to)"
        case let (nil, to?): return "Switched to \(to)"
        case let (from?, nil): return "Switched from \(from)"
        default: return "Game switch"
        }
    }
}
