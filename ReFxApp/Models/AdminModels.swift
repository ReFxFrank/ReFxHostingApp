import Foundation
import SwiftUI

// MARK: - Nodes

enum NodeState: String, Codable, Equatable {
    case provisioning = "PROVISIONING"
    case online = "ONLINE"
    case offline = "OFFLINE"
    case maintenance = "MAINTENANCE"
    case degraded = "DEGRADED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NodeState(rawValue: raw) ?? .unknown
    }

    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .online: return .appSuccess
        case .degraded, .maintenance, .provisioning: return .appWarning
        case .offline: return .appDestructive
        case .unknown: return .appMuted
        }
    }
}

struct RegionRef: Codable, Equatable {
    let name: String?
    let code: String?
}

/// `GET /admin/nodes` / `GET /admin/nodes/:id` (admin). Decoded permissively.
struct NodeAdmin: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let fqdn: String?
    let state: NodeState
    let agentVersion: String?
    let maintenance: Bool?
    let region: RegionRef?
    let memoryMb: Int?
    let diskMb: Int?
}

/// `GET /admin/nodes/:id/ping`.
struct NodePing: Decodable {
    let ms: Double?
    let reachable: Bool
    let heartbeatAgeMs: Double?
}

struct AgentLatest: Decodable { let latest: String? }

/// Body for `POST /admin/servers` (admin direct-provision). `name`, `ownerId`,
/// `nodeId`, `templateId` are required; resources default to the template's
/// recommended spec when omitted. Send `slots` for voice/slot-based templates
/// (resources auto-size server-side) instead of cpu/memory/disk.
struct AdminCreateServerBody: Encodable {
    let name: String
    let ownerId: String
    let nodeId: String
    let templateId: String
    var cpuCores: Double? = nil
    var memoryMb: Int? = nil
    var diskMb: Int? = nil
    var slots: Int? = nil
    var swapMb: Int? = nil
    var environment: [String: String]? = nil
}

/// Operating system a node runs (drives the runtime backend choice server-side).
enum NodeOS: String, CaseIterable, Identifiable {
    case linux = "LINUX"
    case windows = "WINDOWS"
    var id: String { rawValue }
    var label: String { self == .linux ? "Linux" : "Windows" }
}

/// Body for `POST /admin/nodes` (admin add-node). The agent installs against the
/// returned one-time bootstrap token. Port range + resources have panel defaults.
struct CreateNodeBody: Encodable {
    let name: String
    let fqdn: String
    let regionId: String
    let os: String
    let cpuCores: Int
    let memoryMb: Int
    let diskMb: Int
    let allocationPortStart: Int
    let allocationPortEnd: Int
}

/// Response of `POST /admin/nodes`: the created node plus a one-time bootstrap
/// token (shown to the operator once — it can't be retrieved again).
struct CreateNodeResult: Decodable {
    let id: String?
    let name: String?
    let bootstrapToken: String
}

// MARK: - Users (admin)

/// `GET /admin/users` (admin list row).
struct AdminUser: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let globalRole: UserRole?
    let state: String?

    var role: UserRole { globalRole ?? .unknown }
    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? email : name
    }
    var isSuspended: Bool { (state ?? "") == "SUSPENDED" || (state ?? "") == "BANNED" }
}

/// `GET /admin/users/:id` — full account view (secrets stripped server-side).
struct AdminUserDetail: Decodable, Identifiable, Equatable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    let globalRole: UserRole?
    let state: String?
    let createdAt: Date?
    let emailVerifiedAt: Date?
    let ownedServers: [AdminServerRef]
    let subscriptions: [AdminSubscription]
    let invoices: [AdminInvoice]
    let counts: Counts?

    enum CodingKeys: String, CodingKey {
        case id, email, firstName, lastName, globalRole, state, createdAt, emailVerifiedAt
        case ownedServers, subscriptions, invoices
        case counts = "_count"
    }

    struct Counts: Decodable, Equatable {
        let ownedServers: Int?
        let subscriptions: Int?
        let tickets: Int?
    }

    var role: UserRole { globalRole ?? .unknown }
    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? email : name
    }
    var isSuspended: Bool { (state ?? "") == "SUSPENDED" || (state ?? "") == "BANNED" }
    var isBanned: Bool { (state ?? "") == "BANNED" }
    var emailVerified: Bool { emailVerifiedAt != nil }
}

struct AdminServerRef: Decodable, Identifiable, Equatable {
    let id: String
    let shortId: String?
    let name: String
    let state: ServerState
    let node: NodeNameRef?
    struct NodeNameRef: Decodable, Equatable { let name: String? }
}

struct AdminSubscription: Decodable, Identifiable, Equatable {
    let id: String
    let state: String
    let interval: String?
    let gateway: String?
    let currentPeriodEnd: Date?
    let product: ProductRef?
    struct ProductRef: Decodable, Equatable {
        let id: String?
        let name: String?
        let type: String?
    }
}

struct AdminInvoice: Decodable, Identifiable, Equatable {
    let id: String
    let number: String?
    let state: String
    let currency: String
    let totalMinor: Int
    let amountPaidMinor: Int?
    let createdAt: Date?
    let paidAt: Date?

    var money: Money { Money(minorUnits: totalMinor, currency: currency) }
    var isPaid: Bool { state == "PAID" }
}

// MARK: - Platform overview (metrics)

/// `GET /admin/metrics` — platform KPIs for the staff overview.
struct AdminMetrics: Decodable, Equatable {
    let totals: Totals
    let serversByState: [String: Int]
    let nodes: [NodeMetric]

    struct Totals: Decodable, Equatable {
        let users: Int
        let servers: Int
        let nodesOnline: Int
        let openTickets: Int
        let activeSubscriptions: Int
        let mrrMinor: Int
        let mrrCurrency: String?

        var mrr: Money { Money(minorUnits: mrrMinor, currency: mrrCurrency ?? "USD") }
    }

    struct NodeMetric: Decodable, Identifiable, Equatable {
        let id: String
        let name: String
        let cpuPct: Double
        let memPct: Double
        let diskPct: Double
    }
}

// MARK: - Audit log

/// `GET /admin/audit-logs` (paginated).
struct AuditEntry: Decodable, Identifiable, Equatable {
    let id: String
    let actorId: String?
    let action: String
    let targetType: String?
    let targetId: String?
    let ip: String?
    let createdAt: Date

    /// Leading domain of the action, e.g. "server.power.start" → "server".
    var domain: String { action.split(separator: ".").first.map(String.init) ?? action }
    /// Human-ish remainder, e.g. "power start".
    var summary: String {
        action.split(separator: ".").dropFirst()
            .joined(separator: " ").replacingOccurrences(of: "-", with: " ")
    }
}

// MARK: - Platform alerts

enum AlertSeverity: String, Codable, Equatable {
    case info = "INFO"
    case warning = "WARNING"
    case critical = "CRITICAL"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AlertSeverity(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .unknown: return "Alert"
        }
    }
    var color: Color {
        switch self {
        case .info: return .appPrimary
        case .warning: return .appWarning
        case .critical: return .appDestructive
        case .unknown: return .appMuted
        }
    }
    var systemImage: String {
        switch self {
        case .critical: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        default: return "info.circle.fill"
        }
    }
}

/// `GET /admin/alerts` — platform-wide banner alerts (GlobalAlert).
struct AdminAlert: Decodable, Identifiable, Equatable {
    let id: String
    let severity: AlertSeverity?
    let title: String
    let body: String
    let isActive: Bool
    let startsAt: Date?
    let endsAt: Date?
    let createdAt: Date?
}
