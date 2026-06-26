import SwiftUI

/// Live resource gauges + key stats, fed by the socket `stats` stream (seeded by
/// a REST snapshot on load).
struct MonitorView: View {
    @ObservedObject var model: ServerDetailViewModel
    @ObservedObject var socket: ConsoleSocket

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let snapshot = model.snapshot {
                    GaugeRow(snapshot: snapshot)
                    statGrid(snapshot)
                } else {
                    waiting
                }
            }
            .padding(16)
            .readableWidth()
        }
    }

    private func statGrid(_ s: ResourceSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let players = s.players {
                StatCard(title: "Players", value: "\(players)", systemImage: "person.2.fill")
            }
            if let uptime = s.uptimeMs {
                StatCard(title: "Uptime", value: Format.duration(ms: uptime),
                         systemImage: "clock")
            }
            StatCard(title: "Network ↓", value: Format.bytes(s.netRxBytes),
                     systemImage: "arrow.down")
            StatCard(title: "Network ↑", value: Format.bytes(s.netTxBytes),
                     systemImage: "arrow.up")
        }
    }

    private var waiting: some View {
        VStack(spacing: 10) {
            ProgressView().tint(.appPrimary)
            Text("Waiting for live stats…").font(.subheadline).foregroundStyle(.appMuted)
        }
        .frame(maxWidth: .infinity).padding(.top, 40)
    }
}

struct GaugeRow: View {
    let snapshot: ResourceSnapshot

    var body: some View {
        HStack(spacing: 12) {
            ResourceGauge(
                title: "CPU",
                fraction: snapshot.cpuPct / 100,
                caption: "\(Int(snapshot.cpuPct))%",
                systemImage: "cpu")
            ResourceGauge(
                title: "RAM",
                fraction: fraction(snapshot.memUsedMb, snapshot.memTotalMb),
                caption: usage(snapshot.memUsedMb, snapshot.memTotalMb),
                systemImage: "memorychip")
            ResourceGauge(
                title: "Disk",
                fraction: fraction(snapshot.diskUsedMb, snapshot.diskTotalMb),
                caption: usage(snapshot.diskUsedMb, snapshot.diskTotalMb),
                systemImage: "internaldrive")
        }
        .padding(Theme.cardPadding)
        .cardSurface()
    }

    private func fraction(_ used: Double, _ total: Double?) -> Double {
        guard let total, total > 0 else { return 0 }
        return used / total
    }
    private func usage(_ used: Double, _ total: Double?) -> String {
        guard let total, total > 0 else { return "\(Int(used)) MB" }
        return "\(Int(used)) / \(Int(total)) MB"
    }
}

/// Lightweight formatters for byte counts and durations.
enum Format {
    static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = value, i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        return String(format: i == 0 ? "%.0f %@" : "%.1f %@", v, units[i])
    }

    static func duration(ms: Double) -> String {
        let total = Int(ms / 1000)
        let d = total / 86400, h = (total % 86400) / 3600, m = (total % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
