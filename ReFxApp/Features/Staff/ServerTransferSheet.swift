import SwiftUI
import UIKit

@MainActor
final class ServerTransferViewModel: ObservableObject {
    @Published var nodes: [NodeAdmin] = []
    @Published var transfers: [ServerTransfer] = []
    @Published var selectedNodeId: String?
    @Published var actionError: String?
    @Published var isTransferring = false

    let server: Server
    private var service: StaffService?

    init(server: Server) { self.server = server }

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        async let nodesTask = try? await service.nodes()
        async let transfersTask = try? await service.serverTransfers(server.id)
        nodes = (await nodesTask) ?? []
        transfers = (await transfersTask) ?? []
    }

    func transfer() async -> Bool {
        guard let service, let toNodeId = selectedNodeId, !isTransferring else { return false }
        isTransferring = true; actionError = nil
        defer { isTransferring = false }
        do {
            try await service.transferServer(server.id, toNodeId: toNodeId)
            await load()
            return true
        } catch let error as APIError { actionError = error.userMessage; return false }
        catch { actionError = "Couldn't start the transfer."; return false }
    }
}

/// Move a server to another node and see its transfer history.
struct ServerTransferSheet: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: ServerTransferViewModel
    @Environment(\.dismiss) private var dismiss

    init(server: Server) { _model = StateObject(wrappedValue: ServerTransferViewModel(server: server)) }

    /// Nodes other than the one currently hosting the server.
    private var targetNodes: [NodeAdmin] {
        model.nodes.filter { $0.name != model.server.node?.name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = model.actionError {
                        Text(error).font(.footnote).foregroundStyle(.appDestructive)
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Destination node", systemImage: "arrow.left.arrow.right")
                            if let current = model.server.node?.name {
                                Text("Currently on \(current)").font(.caption).foregroundStyle(.appMuted)
                            }
                            if targetNodes.isEmpty {
                                Text("No other nodes available.").font(.caption).foregroundStyle(.appMuted)
                            } else {
                                Picker("Node", selection: Binding(
                                    get: { model.selectedNodeId ?? "" },
                                    set: { model.selectedNodeId = $0.isEmpty ? nil : $0 })) {
                                    Text("Select…").tag("")
                                    ForEach(targetNodes) { node in
                                        Text("\(node.name)\(node.state == .online ? "" : " (\(node.state.label))")").tag(node.id)
                                    }
                                }
                            }
                            Button { Task { if await model.transfer() { UINotificationFeedbackGenerator().notificationOccurred(.success) } } } label: {
                                HStack { if model.isTransferring { ProgressView() }; Text("Start transfer") }
                            }
                            .buttonStyle(.refxPrimary)
                            .disabled(model.selectedNodeId == nil || model.isTransferring)
                        }
                    }

                    if !model.transfers.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader("History", systemImage: "clock")
                                ForEach(model.transfers) { t in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            StatusChip(text: t.state.label, color: t.state.color)
                                            if t.state.isInFlight { ProgressView().controlSize(.mini) }
                                            Spacer()
                                            if let at = t.createdAt {
                                                Text(at.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.appMuted)
                                            }
                                        }
                                        if let error = t.error {
                                            Text(error).font(.caption2).foregroundStyle(.appDestructive).lineLimit(2)
                                        }
                                    }
                                    Divider()
                                }
                            }
                        }
                    }

                    Text("Transferring snapshots the server, provisions it on the destination node, and restores it. The server is briefly offline.")
                        .font(.caption2).foregroundStyle(.appMuted)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Transfer \(model.server.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { model.bind(session); await model.load() }
        }
    }
}
