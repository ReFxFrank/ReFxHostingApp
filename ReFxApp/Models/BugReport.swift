import Foundation
import SwiftUI

enum BugSeverity: String, Codable, CaseIterable, Identifiable, Equatable {
    case low = "LOW", medium = "MEDIUM", high = "HIGH", critical = "CRITICAL", unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BugSeverity(rawValue: raw) ?? .unknown
    }
    var id: String { rawValue }
    var label: String { self == .unknown ? "—" : rawValue.capitalized }
    var color: Color {
        switch self {
        case .critical: return .appDestructive
        case .high: return .appWarning
        case .medium: return .appPrimary
        default: return .appMuted
        }
    }
}

enum BugStatus: String, Codable, CaseIterable, Identifiable, Equatable {
    case new = "NEW", triaged = "TRIAGED", inProgress = "IN_PROGRESS"
    case resolved = "RESOLVED", closed = "CLOSED", unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BugStatus(rawValue: raw) ?? .unknown
    }
    var id: String { rawValue }
    var label: String {
        switch self {
        case .new: return "New"
        case .triaged: return "Triaged"
        case .inProgress: return "In progress"
        case .resolved: return "Resolved"
        case .closed: return "Closed"
        case .unknown: return "—"
        }
    }
    var color: Color {
        switch self {
        case .new: return .appWarning
        case .triaged, .inProgress: return .appPrimary
        case .resolved, .closed: return .appSuccess
        case .unknown: return .appMuted
        }
    }
}

/// A staff/user reference embedded on a bug report.
struct BugUserRef: Decodable, Equatable {
    let id: String
    let email: String
    let firstName: String?
    let lastName: String?
    var displayName: String {
        let n = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
        return n.isEmpty ? email : n
    }
}

/// `GET /bugs` (paginated list, staff view) and `GET /bugs/:id` (detail adds
/// `comments`/`attachments`).
struct BugReport: Decodable, Identifiable, Equatable {
    let id: String
    let number: Int
    let title: String
    let description: String
    let stepsToReproduce: String?
    let severity: BugSeverity
    let status: BugStatus
    let area: String?
    let assigneeId: String?
    let pageUrl: String?
    let appVersion: String?
    let resolutionNote: String?
    let createdAt: Date
    let updatedAt: Date
    let reporter: BugUserRef?
    let assignee: BugUserRef?
    let server: ServerRef?
    let comments: [BugComment]?
    let attachments: [BugAttachment]?

    struct ServerRef: Decodable, Equatable {
        let id: String
        let shortId: String
        let name: String
    }

    var ref: String { "BUG-\(number)" }
}

struct BugComment: Decodable, Identifiable, Equatable {
    let id: String
    let body: String
    let isInternal: Bool
    let createdAt: Date
    let author: BugUserRef?
}

struct BugAttachment: Decodable, Identifiable, Equatable {
    let id: String
    let fileName: String
    let contentType: String
    let sizeBytes: Int
    let createdAt: Date?
}

/// `PATCH /bugs/:id` — staff triage. Only non-nil fields are written; empty
/// string clears `area`/`resolutionNote`. `assigneeId` = nil is omitted here;
/// to clear an assignee send an explicit JSON null (handled via a wrapper).
struct UpdateBugBody: Encodable {
    var status: String?
    var severity: String?
    var area: String?
    var assigneeId: String?
    var resolutionNote: String?
}
