import Foundation
import SwiftUI

/// `GET /admin/network` — fleet network/allocation health overview.
struct NetworkOverview: Decodable, Equatable {
    let monitor: Bool
    let windowSamples: Int
    let cadenceSec: Int
    let rollup: Rollup
    let nodes: [Node]

    struct Rollup: Decodable, Equatable {
        let nodes: Int
        let healthy: Int
        let degraded: Int
        let down: Int
        let worstLossPct: Double
        let worstP95Ms: Double
        let totalRxMbps: Double
        let totalTxMbps: Double
    }

    struct Node: Decodable, Identifiable, Equatable {
        let nodeId: String
        let name: String
        let region: String
        let state: NodeState
        let health: String   // "healthy" | "degraded" | "down"
        let latencyMs: Double?
        let avgMs: Double?
        let p95Ms: Double?
        let jitterMs: Double
        let lossPct: Double
        let uptimePct: Double
        let rxMbps: Double
        let txMbps: Double
        let heartbeatAgeMs: Double?
        let samples: Int
        let latencyHistory: [Double?]

        var id: String { nodeId }

        var healthColor: Color {
            switch health {
            case "healthy": return .appSuccess
            case "degraded": return .appWarning
            default: return .appDestructive
            }
        }
    }
}
