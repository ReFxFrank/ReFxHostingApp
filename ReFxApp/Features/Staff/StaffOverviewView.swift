import SwiftUI

@MainActor
final class StaffOverviewViewModel: ObservableObject {
    @Published private(set) var state: LoadState<AdminMetrics> = .idle
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.metrics()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }

    func refresh() async { await load() }
}

/// Staff landing: live platform KPIs, server-state breakdown and per-node health.
struct StaffOverviewView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = StaffOverviewViewModel()

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { _ in false },
                retry: { Task { await model.load() } },
                content: { content($0) },
                skeleton: { skeleton })
            .padding(16)
            .readableWidth()
        }
        .screenBackground()
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func content(_ m: AdminMetrics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: "Users", value: "\(m.totals.users)", systemImage: "person.2")
                StatCard(title: "Servers", value: "\(m.totals.servers)", systemImage: "server.rack")
                StatCard(title: "Nodes online", value: "\(m.totals.nodesOnline)",
                         systemImage: "externaldrive.connected.to.line.below")
                StatCard(title: "Open tickets", value: "\(m.totals.openTickets)", systemImage: "ticket")
                StatCard(title: "Active subs", value: "\(m.totals.activeSubscriptions)", systemImage: "creditcard")
                StatCard(title: "MRR", value: m.totals.mrr.formatted, systemImage: "dollarsign.circle")
            }

            let states = m.serversByState.filter { $0.value > 0 }.sorted { $0.value > $1.value }
            if !states.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("Servers by state", systemImage: "circle.grid.2x2").padding(.leading, 4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(states, id: \.key) { entry in
                                StatusChip(text: "\(entry.key) \(entry.value)",
                                           color: Self.color(forState: entry.key))
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }

            if !m.nodes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Node health", systemImage: "gauge.with.dots.needle.bottom.50percent")
                        .padding(.leading, 4)
                    ForEach(m.nodes) { NodeHealthCard(node: $0) }
                }
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 72) } }
    }

    private static func color(forState raw: String) -> Color {
        switch raw.uppercased() {
        case "RUNNING": return .appSuccess
        case "OFFLINE": return .appMuted
        case "SUSPENDED", "CRASHED", "PENDING_PAYMENT": return .appDestructive
        default: return .appWarning
        }
    }
}

private struct NodeHealthCard: View {
    let node: AdminMetrics.NodeMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(node.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
            HStack(spacing: 12) {
                ResourceGauge(title: "CPU", fraction: node.cpuPct / 100,
                              caption: "\(Int(node.cpuPct))%", systemImage: "cpu")
                ResourceGauge(title: "RAM", fraction: node.memPct / 100,
                              caption: "\(Int(node.memPct))%", systemImage: "memorychip")
                ResourceGauge(title: "Disk", fraction: node.diskPct / 100,
                              caption: "\(Int(node.diskPct))%", systemImage: "internaldrive")
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
