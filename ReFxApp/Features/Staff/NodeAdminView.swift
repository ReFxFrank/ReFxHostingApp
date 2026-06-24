import SwiftUI

@MainActor
final class NodeAdminViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[NodeAdmin]> = .idle
    @Published var actionMessage: String?
    @Published var pingResults: [String: String] = [:]
    @Published var busyNodeId: String?

    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.nodes()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func ping(_ node: NodeAdmin) async {
        guard let service else { return }
        busyNodeId = node.id
        defer { busyNodeId = nil }
        do {
            let result = try await service.pingNode(node.id)
            if result.reachable {
                let ms = result.ms.map { " · \(Int($0))ms" } ?? ""
                pingResults[node.id] = "Reachable\(ms)"
            } else {
                pingResults[node.id] = "Unreachable"
            }
        } catch { pingResults[node.id] = "Ping failed" }
    }

    func restartAgent(_ node: NodeAdmin) async {
        guard let service else { return }
        busyNodeId = node.id
        defer { busyNodeId = nil }
        actionMessage = nil
        do { try await service.restartAgent(node.id); actionMessage = "Agent restart requested for \(node.name)." }
        catch let error as APIError { actionMessage = error.userMessage }
        catch { actionMessage = "Couldn't restart the agent." }
    }
}

struct NodeAdminView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = NodeAdminViewModel()

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No nodes",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 80) } }.padding(16) })
        .screenBackground()
        .navigationTitle("Node health")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let message = model.actionMessage {
                    Text(message).font(.footnote).foregroundStyle(.appPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(model.state.value ?? []) { node in
                    NodeCard(node: node,
                             ping: model.pingResults[node.id],
                             busy: model.busyNodeId == node.id,
                             onPing: { Task { await model.ping(node) } },
                             onRestart: { Task { await model.restartAgent(node) } })
                }
            }
            .padding(16)
        }
        .refreshable { await model.load() }
    }
}

struct NodeCard: View {
    let node: NodeAdmin
    let ping: String?
    let busy: Bool
    let onPing: () -> Void
    let onRestart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name).font(.headline).foregroundStyle(.appForeground)
                    if let fqdn = node.fqdn {
                        Text(fqdn).font(.caption.monospaced()).foregroundStyle(.appMuted).lineLimit(1)
                    }
                }
                Spacer()
                StatusChip(text: node.state.label, color: node.state.color)
            }
            HStack(spacing: 12) {
                if let region = node.region?.name {
                    Label(region, systemImage: "globe").font(.caption2).foregroundStyle(.appMuted)
                }
                if let version = node.agentVersion {
                    Label("agent \(version)", systemImage: "cpu").font(.caption2).foregroundStyle(.appMuted)
                }
                Spacer()
                if let ping { Text(ping).font(.caption2).foregroundStyle(.appPrimary) }
            }
            HStack(spacing: 10) {
                Button(action: onPing) { Label("Ping", systemImage: "wave.3.right") }
                    .buttonStyle(.bordered).controlSize(.small).tint(.appPrimary)
                Button(action: onRestart) { Label("Restart agent", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).controlSize(.small).tint(.appWarning)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
