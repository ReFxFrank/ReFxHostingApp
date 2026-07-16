import SwiftUI
import UIKit

@MainActor
final class AllocationsViewModel: ObservableObject {
    @Published private(set) var state: LoadState<[Allocation]> = .idle
    @Published var actionError: String?
    @Published private(set) var isAdding = false

    let serverId: String
    private var service: ServerSettingsService?

    init(serverId: String) { self.serverId = serverId }

    func bind(_ session: AppSession) { if service == nil { service = session.serverSettings } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.allocations(serverId)) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func add() async {
        guard let service, !isAdding else { return }
        isAdding = true; actionError = nil
        defer { isAdding = false }
        do { try await service.addAllocation(serverId); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't add a port. Try again." }
    }

    func delete(_ allocation: Allocation) async {
        guard let service else { return }
        actionError = nil
        do { try await service.deleteAllocation(serverId, allocationId: allocation.id); await load() }
        catch let error as APIError { actionError = error.userMessage }
        catch { actionError = "Couldn't remove the port. Try again." }
    }
}

/// Extra port allocations for a server. The primary allocation is the connect
/// address and can't be removed; additional ports are assigned from the node.
struct AllocationsView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: AllocationsViewModel

    init(serverId: String) { _model = StateObject(wrappedValue: AllocationsViewModel(serverId: serverId)) }

    var body: some View {
        AsyncStateView(
            state: model.state,
            isEmpty: { $0.isEmpty },
            emptyTitle: "No ports",
            emptyMessage: "This server has no port allocations yet.",
            retry: { Task { await model.load() } },
            content: { _ in list },
            skeleton: { VStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 60) } }.padding(16) })
        .screenBackground()
        .navigationTitle("Ports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.add() } } label: {
                    if model.isAdding { ProgressView() } else { Image(systemName: "plus") }
                }
                .disabled(model.isAdding)
                .accessibilityLabel("Add port")
            }
        }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private var list: some View {
        List {
            if let error = model.actionError {
                Text(error).font(.footnote).foregroundStyle(.appDestructive).listRowBackground(Color.appCard)
            }
            ForEach(model.state.value ?? []) { allocation in
                AllocationRow(allocation: allocation)
                    .listRowBackground(Color.appCard)
                    .swipeActions(edge: .trailing) {
                        if !allocation.isPrimary {
                            Button(role: .destructive) { Task { await model.delete(allocation) } } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
            }
            Section {
                Text("The primary port is your connect address and can't be removed. Additional ports are assigned automatically from the node.")
                    .font(.caption).foregroundStyle(.appMuted)
            }.listRowBackground(Color.clear)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).screenBackground()
        .refreshable { await model.load() }
    }
}

private struct AllocationRow: View {
    let allocation: Allocation

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(allocation.connectionString).font(.callout.monospaced()).foregroundStyle(.appForeground)
                    if allocation.isPrimary {
                        Text("PRIMARY").font(.caption2.weight(.bold)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.appPrimary.opacity(0.15))
                            .foregroundStyle(.appAccentText).clipShape(Capsule())
                    }
                }
                if let alias = allocation.alias, alias != allocation.ip {
                    Text(alias).font(.caption2).foregroundStyle(.appMuted)
                }
            }
            Spacer()
            Button {
                UIPasteboard.general.string = allocation.connectionString
            } label: { Image(systemName: "doc.on.doc").foregroundStyle(.appMuted) }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
