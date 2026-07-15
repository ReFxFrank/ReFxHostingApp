import Foundation

/// `GET /servers/:id/stats` → live snapshot from the node agent (`LiveStats`).
/// Note this includes `memTotalMb` (the socket `stats` frame does not).
struct LiveStats: Codable, Equatable {
    let state: String?
    let cpuPct: Double
    let memUsedMb: Double
    let memTotalMb: Double?
    let diskUsedMb: Double
    let netRxBytes: Double
    let netTxBytes: Double
    let players: Int?
    let uptimeMs: Double?
}

/// The Socket.IO `stats` frame (raw `StatSample` the agent posts). Shares most
/// fields with `LiveStats` but carries `serverId` and no `memTotalMb`.
struct StatsFrame: Decodable, Equatable {
    let serverId: String?
    let cpuPct: Double
    let memUsedMb: Double
    let diskUsedMb: Double
    let netRxBytes: Double
    let netTxBytes: Double
    let state: String?
    let players: Int?
}

/// Unified view-model value the gauges render, fed by either source.
struct ResourceSnapshot: Equatable {
    var cpuPct: Double
    /// The server's total vCPU allocation. `cpuPct` is a raw multi-core value
    /// (e.g. 172 = 1.72 cores), so the gauge normalizes it by this to a 0–100%
    /// figure, matching the web panel ("1.7 / 4 vCPU").
    var cpuCores: Double?
    var memUsedMb: Double
    var memTotalMb: Double?
    var diskUsedMb: Double
    var diskTotalMb: Double?
    var netRxBytes: Double
    var netTxBytes: Double
    var players: Int?
    var uptimeMs: Double?

    init(live: LiveStats, cpuCores: Double?, diskTotalMb: Double?) {
        cpuPct = live.cpuPct
        self.cpuCores = cpuCores
        memUsedMb = live.memUsedMb
        memTotalMb = live.memTotalMb
        diskUsedMb = live.diskUsedMb
        self.diskTotalMb = diskTotalMb
        netRxBytes = live.netRxBytes
        netTxBytes = live.netTxBytes
        players = live.players
        uptimeMs = live.uptimeMs
    }

    /// Build from a socket frame, preserving previously-known totals.
    init(frame: StatsFrame, previous: ResourceSnapshot?, cpuCores: Double?, memTotalMb: Double?, diskTotalMb: Double?) {
        cpuPct = frame.cpuPct
        self.cpuCores = cpuCores ?? previous?.cpuCores
        memUsedMb = frame.memUsedMb
        self.memTotalMb = memTotalMb ?? previous?.memTotalMb
        diskUsedMb = frame.diskUsedMb
        self.diskTotalMb = diskTotalMb ?? previous?.diskTotalMb
        netRxBytes = frame.netRxBytes
        netTxBytes = frame.netTxBytes
        players = frame.players ?? previous?.players
        uptimeMs = previous?.uptimeMs
    }
}
