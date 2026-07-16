import SwiftUI
import UIKit

@MainActor
final class NodeAdminViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[NodeAdmin]> = .idle
    @Published var actionMessage: String?
    @Published var pingResults: [String: String] = [:]
    @Published var busyNodeId: String?
    @Published var isUpdatingFleet = false
    /// Latest published agent release tag, for the "update available" badge.
    @Published var latestAgent: String?
    /// Capacity sheet + one-time bootstrap token alert.
    @Published var capacityNode: NodeAdmin?
    @Published var capacity: NodeCapacity?
    @Published var revealedToken: String?

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

    func updateAllAgents() async {
        guard let service, !isUpdatingFleet else { return }
        isUpdatingFleet = true
        defer { isUpdatingFleet = false }
        actionMessage = nil
        do { try await service.updateAllAgents(); actionMessage = "Fleet agent update started on all nodes." }
        catch let error as APIError { actionMessage = error.userMessage }
        catch { actionMessage = "Couldn't start the fleet update." }
    }

    func setMaintenance(_ node: NodeAdmin, on: Bool) async {
        await act(node, success: on ? "\(node.name) in maintenance." : "\(node.name) back online.") {
            try await $0.setMaintenance(node.id, on: on)
        }
        await load()
    }

    func showCapacity(_ node: NodeAdmin) async {
        guard let service else { return }
        busyNodeId = node.id
        defer { busyNodeId = nil }
        actionMessage = nil
        do {
            capacity = try await service.nodeCapacity(node.id)
            capacityNode = node
        } catch let error as APIError { actionMessage = error.userMessage }
        catch { actionMessage = "Couldn't load capacity." }
    }

    func rotateBootstrap(_ node: NodeAdmin) async {
        guard let service else { return }
        busyNodeId = node.id
        defer { busyNodeId = nil }
        actionMessage = nil
        do { revealedToken = try await service.rotateBootstrapToken(node.id).bootstrapToken }
        catch let error as APIError { actionMessage = error.userMessage }
        catch { actionMessage = "Couldn't rotate the token." }
    }

    func pinCert(_ node: NodeAdmin) async {
        await act(node, success: "Pinned agent cert on \(node.name).") { _ = try await $0.pinCert(node.id) }
    }

    func unpinCert(_ node: NodeAdmin) async {
        await act(node, success: "Cleared pinned cert on \(node.name).") { try await $0.unpinCert(node.id) }
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
    @State private var confirmFleetUpdate = false

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
                Menu {
                    Button { showAddNode = true } label: { Label("Add node", systemImage: "plus") }
                    Button {
                        confirmFleetUpdate = true
                    } label: { Label("Update all agents", systemImage: "arrow.down.circle.fill") }
                        .disabled(model.isUpdatingFleet)
                } label: {
                    if model.isUpdatingFleet { ProgressView() } else { Image(systemName: "ellipsis.circle") }
                }
                .accessibilityLabel("Node actions")
            }
        }
        .sheet(isPresented: $showAddNode) {
            AddNodeView { Task { await model.load() } }
        }
        .confirmationDialog("Update all node agents?", isPresented: $confirmFleetUpdate, titleVisibility: .visible) {
            Button("Update all agents") { Task { await model.updateAllAgents() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every node's agent self-updates to the latest release and briefly reconnects. Servers keep running.")
        }
        .sheet(isPresented: Binding(
            get: { model.capacityNode != nil },
            set: { if !$0 { model.capacityNode = nil; model.capacity = nil } })) {
            if let node = model.capacityNode, let capacity = model.capacity {
                NodeCapacitySheet(node: node, capacity: capacity)
            }
        }
        .alert("New bootstrap token", isPresented: Binding(
            get: { model.revealedToken != nil }, set: { if !$0 { model.revealedToken = nil } })) {
            Button("Copy") { if let t = model.revealedToken { Clipboard.copySecret(t) } }
            Button("Done", role: .cancel) {}
        } message: {
            if let token = model.revealedToken {
                Text("\(token)\n\nCopy it now — it's shown once and expires in about an hour.")
            }
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
                             onClearSteam: { Task { await model.clearSteamCache(node) } },
                             onMaintenance: { on in Task { await model.setMaintenance(node, on: on) } },
                             onCapacity: { Task { await model.showCapacity(node) } },
                             onRotateToken: { Task { await model.rotateBootstrap(node) } },
                             onPinCert: { Task { await model.pinCert(node) } },
                             onUnpinCert: { Task { await model.unpinCert(node) } })
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
    let latest: String?
    let busy: Bool
    let onPing: () -> Void
    let onRestart: () -> Void
    let onUpdate: () -> Void
    let onClearSteam: () -> Void
    let onMaintenance: (Bool) -> Void
    let onCapacity: () -> Void
    let onRotateToken: () -> Void
    let onPinCert: () -> Void
    let onUnpinCert: () -> Void

    @State private var confirmUpdate = false
    @State private var confirmMaintenance = false

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
                Menu {
                    if node.maintenance == true {
                        Button { onMaintenance(false) } label: { Label("End maintenance", systemImage: "wrench.and.screwdriver") }
                    } else {
                        Button { confirmMaintenance = true } label: { Label("Enter maintenance", systemImage: "wrench.and.screwdriver") }
                    }
                    Button { onCapacity() } label: { Label("View capacity", systemImage: "gauge.with.dots.needle.67percent") }
                    Divider()
                    Button { onRotateToken() } label: { Label("Rotate bootstrap token", systemImage: "key.horizontal") }
                    Button { onPinCert() } label: { Label("Pin agent cert", systemImage: "lock.shield") }
                    Button(role: .destructive) { onUnpinCert() } label: { Label("Unpin agent cert", systemImage: "lock.open") }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.appMuted)
                }
                .disabled(busy)
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
        .confirmationDialog("Put \(node.name) into maintenance?", isPresented: $confirmMaintenance, titleVisibility: .visible) {
            Button("Enter maintenance") { onMaintenance(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New servers won't be scheduled here while in maintenance. Running servers keep going.")
        }
    }
}

/// Node capacity: overcommit-adjusted totals vs. provisioned usage.
struct NodeCapacitySheet: View {
    let node: NodeAdmin
    let capacity: NodeCapacity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    row("CPU", capacity.cpu, unit: "cores", isMB: false)
                    row("Memory", capacity.memory, unit: "GB", isMB: true)
                    row("Disk", capacity.disk, unit: "GB", isMB: true)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(node.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ title: String, _ g: NodeCapacity.Group, unit: String, isMB: Bool) -> some View {
        let scale = isMB ? 1024.0 : 1.0
        let used = g.used / scale, total = g.total / scale, free = g.free / scale
        let fraction = total > 0 ? max(0, min(1, used / total)) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                Spacer()
                Text(String(format: "%.1f / %.1f %@", used, total, unit))
                    .font(.caption.monospacedDigit()).foregroundStyle(.appMuted)
            }
            ProgressView(value: fraction)
                .tint(fraction > 0.9 ? .appDestructive : (fraction > 0.7 ? .appWarning : .appPrimary))
            Text(String(format: "%.1f %@ free", free, unit))
                .font(.caption2).foregroundStyle(free < 0 ? .appDestructive : .appMuted)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
