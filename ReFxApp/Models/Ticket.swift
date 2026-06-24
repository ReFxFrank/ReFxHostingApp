import Foundation
import SwiftUI

enum TicketState: String, Codable, Equatable {
    case open = "OPEN"
    case pendingCustomer = "PENDING_CUSTOMER"
    case pendingAgent = "PENDING_AGENT"
    case resolved = "RESOLVED"
    case closed = "CLOSED"
    case archived = "ARCHIVED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TicketState(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .open: return "Open"
        case .pendingCustomer: return "Your reply needed"
        case .pendingAgent: return "Awaiting support"
        case .resolved: return "Resolved"
        case .closed: return "Closed"
        case .archived: return "Archived"
        case .unknown: return "—"
        }
    }

    var color: Color {
        switch self {
        case .open, .pendingAgent: return .appPrimary
        case .pendingCustomer: return .appWarning
        case .resolved: return .appSuccess
        case .closed, .archived, .unknown: return .appMuted
        }
    }

    var isOpen: Bool { self != .closed && self != .archived && self != .resolved }
}

enum TicketPriority: String, Codable, Equatable {
    case low = "LOW", normal = "NORMAL", high = "HIGH", urgent = "URGENT", unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TicketPriority(rawValue: raw) ?? .unknown
    }

    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .urgent: return .appDestructive
        case .high: return .appWarning
        default: return .appMuted
        }
    }
}

/// `GET /support/tickets` row.
struct Ticket: Codable, Identifiable, Equatable {
    let id: String
    let number: Int
    let subject: String
    let state: TicketState
    let priority: TicketPriority
    let createdAt: Date
    let updatedAt: Date?
}

struct TicketAuthor: Codable, Equatable {
    let id: String
    let email: String?
    let firstName: String?
    let lastName: String?
    let globalRole: UserRole?

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? (email ?? "User") : name
    }
    var isStaff: Bool { globalRole?.isStaff ?? false }
}

struct TicketMessage: Codable, Identifiable, Equatable {
    let id: String
    let body: String
    let isInternal: Bool?
    let createdAt: Date
    let author: TicketAuthor?
}

/// `GET /support/tickets/:id` — ticket plus its message thread.
struct TicketDetail: Codable, Identifiable, Equatable {
    let id: String
    let number: Int
    let subject: String
    let state: TicketState
    let priority: TicketPriority
    let createdAt: Date
    let messages: [TicketMessage]
}
