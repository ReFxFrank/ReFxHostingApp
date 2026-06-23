import Foundation
import SwiftUI

/// Mirrors Prisma `ServerState`. Unknown future states decode to `.unknown`.
enum ServerState: String, Codable, Equatable {
    case installing = "INSTALLING"
    case offline = "OFFLINE"
    case starting = "STARTING"
    case running = "RUNNING"
    case stopping = "STOPPING"
    case crashed = "CRASHED"
    case suspended = "SUSPENDED"
    case reinstalling = "REINSTALLING"
    case switchingGame = "SWITCHING_GAME"
    case transferring = "TRANSFERRING"
    case pendingPayment = "PENDING_PAYMENT"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ServerState(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .installing: return "Installing"
        case .offline: return "Offline"
        case .starting: return "Starting"
        case .running: return "Running"
        case .stopping: return "Stopping"
        case .crashed: return "Crashed"
        case .suspended: return "Suspended"
        case .reinstalling: return "Reinstalling"
        case .switchingGame: return "Switching game"
        case .transferring: return "Transferring"
        case .pendingPayment: return "Awaiting payment"
        case .unknown: return "Unknown"
        }
    }

    /// Loud states the home screen surfaces prominently.
    var needsAttention: Bool {
        self == .offline || self == .suspended || self == .crashed || self == .pendingPayment
    }

    /// A mid-transition state where power actions should be disabled/debounced.
    var isTransitional: Bool {
        [.installing, .starting, .stopping, .reinstalling,
         .switchingGame, .transferring].contains(self)
    }

    var isRunning: Bool { self == .running }
}

struct Allocation: Codable, Identifiable, Equatable {
    let id: String
    let ip: String
    let port: Int
    let alias: String?
    let isPrimary: Bool

    /// Connection string the customer pastes into a game client.
    var connectionString: String { "\(alias ?? ip):\(port)" }
}

struct GameTemplateRef: Codable, Equatable {
    let id: String
    let name: String?
    let slug: String?
}

struct NodeRef: Codable, Equatable {
    let name: String?
    let fqdn: String?
}

/// `GET /servers` (list) and `GET /servers/:id` (detail). The service adds
/// `primaryAllocation`; detail additionally includes `variables`.
struct Server: Codable, Identifiable, Equatable {
    let id: String
    let shortId: String
    let name: String
    let description: String?
    let state: ServerState
    let cpuCores: Double?
    let memoryMb: Int?
    let diskMb: Int?
    let slots: Int?
    let suspendedAt: Date?
    let template: GameTemplateRef?
    let node: NodeRef?
    let primaryAllocation: Allocation?

    var gameName: String { template?.name ?? "No game" }
    var connectionString: String? { primaryAllocation?.connectionString }
}
