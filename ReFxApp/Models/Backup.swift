import Foundation
import SwiftUI

enum BackupState: String, Codable, Equatable {
    case pending = "PENDING"
    case inProgress = "IN_PROGRESS"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BackupState(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .pending: return "Queued"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .unknown: return "Unknown"
        }
    }

    var isFinished: Bool { self == .completed || self == .failed }
    var isWorking: Bool { self == .pending || self == .inProgress }

    var color: Color {
        switch self {
        case .completed: return .appSuccess
        case .failed: return .appDestructive
        case .pending, .inProgress: return .appWarning
        case .unknown: return .appMuted
        }
    }
}

/// `GET /servers/:id/backups` (paginated). `sizeBytes` arrives as a JSON number
/// (the API patches BigInt.toJSON → number).
struct Backup: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let state: BackupState
    let sizeBytes: Int
    let checksum: String?
    let isLocked: Bool?
    let error: String?
    let completedAt: Date?
    let createdAt: Date

    var sizeDescription: String { Format.bytes(Double(sizeBytes)) }
    var locked: Bool { isLocked ?? false }
}
