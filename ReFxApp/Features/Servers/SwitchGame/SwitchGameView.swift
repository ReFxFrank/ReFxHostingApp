import SwiftUI

@MainActor
final class SwitchGameViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[GameTemplate]> = .idle
    @Published var actionError: String?
    @Published var isSwitching = false
    @Published var didSwitch = false

    let serverId: String
    private var service: SwitchGameService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.switchGame } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.templates(serverId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func performSwitch(to template: GameTemplate, keepData: Bool) async {
        guard let service else { return }
        actionError = nil
        isSwitching = true
        defer { isSwitching = false }
        do {
            try await service.switchGame(serverId, templateId: template.id, keepData: keepData)
            didSwitch = true
        } catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't switch the game." }
    }
}

/// GPortal-style game switch: pick a target game, choose whether to keep the
/// data volume, and confirm (destructive — a clean switch wipes files).
struct SwitchGameView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: SwitchGameViewModel
    @State private var selected: GameTemplate?
    @State private var keepData = false

    init(serverId: String) { _model = StateObject(wrappedValue: SwitchGameViewModel(serverId: serverId)) }

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No other games available",
            emptyMessage: "This server's plan doesn't offer other games to switch to.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 10) { ForEach(0..<6, id: \.self) { _ in SkeletonBlock(height: 60) } }.padding(16) })
        .screenBackground()
        .navigationTitle("Switch Game")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            selected.map { "Switch to \($0.name)?" } ?? "",
            isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
            titleVisibility: .visible) {
            if let template = selected {
                Button("Keep my files & switch") {
                    Task { await model.performSwitch(to: template, keepData: true) }
                }
                Button("Wipe & switch (clean install)", role: .destructive) {
                    Task { await model.performSwitch(to: template, keepData: false) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Switching changes the game running on this server. A clean install wipes the current files; keeping them may leave incompatible data behind.")
        }
        .alert("Game switch started", isPresented: $model.didSwitch) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The server will reinstall with the new game. This can take a few minutes.")
        }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let error = model.actionError {
                    Text(error).font(.footnote).foregroundStyle(.appDestructive)
                }
                ForEach(model.state.value ?? []) { template in
                    Button { selected = template } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gamecontroller").foregroundStyle(.appPrimary).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name).foregroundStyle(.appForeground)
                                if let author = template.author {
                                    Text(author).font(.caption2).foregroundStyle(.appMuted)
                                }
                            }
                            Spacer()
                            if model.isSwitching { ProgressView() }
                        }
                        .padding(Theme.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSwitching)
                }
            }
            .padding(16)
        }
    }
}
