import Foundation
import SwiftUI

enum IncidentStatus: String, Codable, CaseIterable, Identifiable, Equatable {
    case investigating = "INVESTIGATING", identified = "IDENTIFIED"
    case monitoring = "MONITORING", resolved = "RESOLVED", unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IncidentStatus(rawValue: raw) ?? .unknown
    }
    var id: String { rawValue }
    var label: String { self == .unknown ? "—" : rawValue.capitalized }
    var color: Color {
        switch self {
        case .resolved: return .appSuccess
        case .monitoring: return .appPrimary
        case .identified: return .appWarning
        case .investigating: return .appDestructive
        case .unknown: return .appMuted
        }
    }
}

enum IncidentImpact: String, Codable, CaseIterable, Identifiable, Equatable {
    case maintenance = "MAINTENANCE", degraded = "DEGRADED", outage = "OUTAGE", unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IncidentImpact(rawValue: raw) ?? .unknown
    }
    var id: String { rawValue }
    var label: String { self == .unknown ? "—" : rawValue.capitalized }
    var color: Color {
        switch self {
        case .outage: return .appDestructive
        case .degraded: return .appWarning
        case .maintenance: return .appPrimary
        case .unknown: return .appMuted
        }
    }
}

/// Status-page components an incident can affect.
enum IncidentComponent: String, CaseIterable, Identifiable {
    case panelApi = "panel-api", web = "web", nodes = "nodes", iosApp = "ios-app"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .panelApi: return "Panel API"
        case .web: return "Web"
        case .nodes: return "Nodes"
        case .iosApp: return "iOS app"
        }
    }
}

struct StatusIncidentUpdate: Decodable, Identifiable, Equatable {
    let id: String
    let status: IncidentStatus
    let body: String
    let createdAt: Date
}

/// `GET /admin/status/incidents`. `updates` present on list/create/patch,
/// absent on the add-update response.
struct StatusIncident: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let status: IncidentStatus
    let impact: IncidentImpact
    let components: [String]
    let startedAt: Date?
    let resolvedAt: Date?
    let createdAt: Date?
    let updates: [StatusIncidentUpdate]?
}

struct CreateIncidentBody: Encodable {
    let title: String
    let impact: String
    let components: [String]
    let body: String
    var status: String?
    var notify: Bool?
}

struct AddIncidentUpdateBody: Encodable { let status: String; let body: String }
struct UpdateIncidentBody: Encodable {
    var title: String?
    var impact: String?
    var status: String?
    var components: [String]?
}

// MARK: - Status webhooks

/// `GET /admin/status/webhooks` (secret never returned). Create adds a one-time
/// `secret`.
struct StatusWebhook: Decodable, Identifiable, Equatable {
    let id: String
    let url: String
    let events: [String]
    let isActive: Bool
    let description: String?
    let lastDeliveryAt: Date?
    let lastStatus: Int?
    let createdAt: Date?
    let secret: String?   // present only on create
}

/// Webhook event types.
enum StatusWebhookEvent: String, CaseIterable, Identifiable {
    case created = "incident.created", updated = "incident.updated"
    case resolved = "incident.resolved", componentChanged = "component.status_changed"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .created: return "Created"
        case .updated: return "Updated"
        case .resolved: return "Resolved"
        case .componentChanged: return "Component change"
        }
    }
}

struct CreateWebhookBody: Encodable {
    let url: String
    var events: [String]?
    var description: String?
}

struct UpdateWebhookBody: Encodable {
    var url: String?
    var events: [String]?
    var isActive: Bool?
    var description: String?
}
