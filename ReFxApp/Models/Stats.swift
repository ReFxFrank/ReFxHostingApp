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

/// `GET /servers/:id/players` — Minecraft Server List Ping. Non-MC templates
/// return `supported:false`; `players`/`version`/`latencyMs` are present only
/// when `online:true`.
struct PlayersResult: Decodable, Equatable {
    let supported: Bool
    let online: Bool
    let players: PlayerCount?
    let version: String?
    let latencyMs: Int?

    struct PlayerCount: Decodable, Equatable {
        let online: Int
        let max: Int
        let names: [String]
    }
}

/// One historical sample from `GET /servers/:id/stats/history` (Prisma
/// `ServerStat`). BigInt net counters arrive as JSON numbers.
struct ServerStat: Decodable, Identifiable, Equatable {
    let id: String
    let cpuPct: Double
    let memUsedMb: Int
    let diskUsedMb: Int
    let netRxBytes: Double
    let netTxBytes: Double
    let players: Int?
    let recordedAt: Date
}

/// Time windows accepted by `GET /servers/:id/stats/history?range=`.
enum StatsRange: String, CaseIterable, Identifiable {
    case h1 = "1h", h6 = "6h", h24 = "24h", d7 = "7d", d30 = "30d"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .h1: return "1H"
        case .h6: return "6H"
        case .h24: return "24H"
        case .d7: return "7D"
        case .d30: return "30D"
        }
    }
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

    init(live: LiveStats, cpuCores: Double?, memTotalMb: Double?, diskTotalMb: Double?) {
        cpuPct = live.cpuPct
        self.cpuCores = cpuCores
        memUsedMb = live.memUsedMb
        // The live snapshot's memory ceiling field name has varied server-side
        // (`memLimitMb` vs `memTotalMb`), so fall back to the server's allocated
        // RAM — same source Disk uses (Server.diskMb) — so the gauge always has a
        // denominator instead of rendering an empty ring.
        self.memTotalMb = live.memTotalMb ?? memTotalMb
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
