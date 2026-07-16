import SwiftUI

@MainActor
final class NetworkOverviewViewModel: ObservableObject {
    @Published private(set) var state: LoadState<NetworkOverview> = .idle
    private var service: StaffService?

    func bind(_ session: AppSession) { if service == nil { service = session.staff } }

    func load() async {
        guard let service else { return }
        if state.value == nil { state = .loading }
        do { state = .loaded(try await service.network()) }
        catch let error as APIError { state = .failed(error) }
        catch { state = .failed(.network(isOffline: false, underlying: "\(error)")) }
    }
}

struct NetworkOverviewView: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = NetworkOverviewViewModel()

    var body: some View {
        ScrollView {
            AsyncStateView(
                state: model.state,
                isEmpty: { $0.nodes.isEmpty },
                emptyTitle: "No nodes",
                emptyMessage: "No nodes are reporting network telemetry.",
                retry: { Task { await model.load() } },
                content: { content($0) },
                skeleton: { VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 80) } } })
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Network")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { model.bind(session); if model.state.value == nil { await model.load() } }
    }

    private func content(_ net: NetworkOverview) -> some View {
        VStack(spacing: 12) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Fleet", systemImage: "chart.bar.xaxis")
                    HStack(spacing: 10) {
                        rollupChip("\(net.rollup.healthy)", "Healthy", .appSuccess)
                        rollupChip("\(net.rollup.degraded)", "Degraded", .appWarning)
                        rollupChip("\(net.rollup.down)", "Down", .appDestructive)
                    }
                    HStack(spacing: 16) {
                        stat("↓ \(fmt(net.rollup.totalRxMbps)) Mbps", "Total in")
                        stat("↑ \(fmt(net.rollup.totalTxMbps)) Mbps", "Total out")
                    }
                    HStack(spacing: 16) {
                        stat("\(Int(net.rollup.worstP95Ms))ms", "Worst p95")
                        stat("\(Int(net.rollup.worstLossPct))%", "Worst loss")
                    }
                    if !net.monitor {
                        Text("Network monitor is disabled.").font(.caption2).foregroundStyle(.appMuted)
                    }
                }
            }
            ForEach(net.nodes) { node in NetworkNodeCard(node: node) }
        }
    }

    private func rollupChip(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.appMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(.appForeground)
            Text(label).font(.caption2).foregroundStyle(.appMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
}

private struct NetworkNodeCard: View {
    let node: NetworkOverview.Node

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name).font(.subheadline.weight(.semibold)).foregroundStyle(.appForeground)
                        Text(node.region).font(.caption2).foregroundStyle(.appMuted)
                    }
                    Spacer()
                    StatusChip(text: node.health.capitalized, color: node.healthColor)
                }
                HStack(spacing: 14) {
                    metric(node.latencyMs.map { "\(Int($0))ms" } ?? "—", "latency")
                    metric("\(Int(node.p95Ms ?? 0))ms", "p95")
                    metric("\(Int(node.lossPct))%", "loss")
                    metric("\(Int(node.uptimePct))%", "uptime")
                }
                HStack(spacing: 14) {
                    metric("↓ \(String(format: "%.1f", node.rxMbps))", "Mbps in")
                    metric("↑ \(String(format: "%.1f", node.txMbps))", "Mbps out")
                    metric("\(Int(node.jitterMs))ms", "jitter")
                }
            }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.appForeground)
            Text(label).font(.caption2).foregroundStyle(.appMuted)
        }
    }
}
