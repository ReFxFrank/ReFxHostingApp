import SwiftUI
import UIKit

@MainActor
final class NodeAdminViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[NodeAdmin]> = .idle
    @Published var actionMessage: String?
    @Published var pingResults: [String: String] = [:]
    @Published var busyNodeId: String?
    /// Latest published agent release tag, for the "update available" badge.
    @Published var latestAgent: String?

    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.nodes()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
        // Best-effort; the badge is informational only.
        if let latest = try? await service.agentLatest() { latestAgent = latest }
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
        await act(node, success: "Agent restart requested for \(node.name).") { try await $0.restartAgent(node.id) }
    }

    func updateAgent(_ node: NodeAdmin) async {
        await act(node, success: "Agent update started for \(node.name).") { try await $0.updateAgent(node.id) }
    }

    func clearSteamCache(_ node: NodeAdmin) async {
        await act(node, success: "Cleared Steam cache on \(node.name).") { try await $0.clearSteamCache(node.id) }
    }

    private func act(_ node: NodeAdmin,
                     success: String,
                     _ work: (StaffService) async throws -> Void) async {
        guard let service else { return }
        busyNodeId = node.id
        defer { busyNodeId = nil }
        actionMessage = nil
        do { try await work(service); actionMessage = success }
        catch let error as APIError { actionMessage = error.userMessage }
        catch { actionMessage = "Action failed. Try again." }
    }
}

struct NodeAdminView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = NodeAdminViewModel()
    @State private var showAddNode = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddNode = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add node")
            }
        }
        .sheet(isPresented: $showAddNode) {
            AddNodeView { Task { await model.load() } }
        }
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
                             latest: model.latestAgent,
                             busy: model.busyNodeId == node.id,
                             onPing: { Task { await model.ping(node) } },
                             onRestart: { Task { await model.restartAgent(node) } },
                             onUpdate: { Task { await model.updateAgent(node) } },
                             onClearSteam: { Task { await model.clearSteamCache(node) } })
                }
            }
            .padding(16)
            .readableWidth()
        }
        .refreshable { await model.load() }
    }
}

struct NodeCard: View {
    let node: NodeAdmin
    let ping: String?
    let latest: String?
    let busy: Bool
    let onPing: () -> Void
    let onRestart: () -> Void
    let onUpdate: () -> Void
    let onClearSteam: () -> Void

    @State private var confirmUpdate = false

    private var updateAvailable: Bool {
        guard let version = node.agentVersion, let latest else { return false }
        return version != latest
    }

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
                if updateAvailable { StatusChip(text: "Update", color: .appWarning) }
                Spacer()
                if let ping { Text(ping).font(.caption2).foregroundStyle(.appPrimary) }
            }

            // Two rows of two so the four actions wrap cleanly on a phone.
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: onPing) { Label("Ping", systemImage: "wave.3.right") }
                        .buttonStyle(.refxSecondary)
                    Button(action: onRestart) { Label("Restart", systemImage: "arrow.clockwise") }
                        .buttonStyle(.refxSecondary)
                }
                HStack(spacing: 8) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        confirmUpdate = true
                    } label: { Label("Update", systemImage: "arrow.down.circle") }
                        .buttonStyle(.refxSecondary)
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onClearSteam()
                    } label: { Label("Steam cache", systemImage: "trash") }
                        .buttonStyle(.refxSecondary)
                }
            }
            .disabled(busy)
            .opacity(busy ? 0.6 : 1)

            if busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Working…").font(.caption2).foregroundStyle(.appMuted)
                }
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .confirmationDialog("Update the agent on \(node.name)?",
                            isPresented: $confirmUpdate, titleVisibility: .visible) {
            Button("Update agent") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onUpdate()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The agent self-updates to the latest release and briefly reconnects.")
        }
    }
}
