import Foundation
import SwiftUI

enum TransferState: String, Decodable, Equatable {
    case pending = "PENDING", snapshotting = "SNAPSHOTTING", provisioning = "PROVISIONING"
    case restoring = "RESTORING", finalizing = "FINALIZING", succeeded = "SUCCEEDED", failed = "FAILED", unknown
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TransferState(rawValue: raw) ?? .unknown
    }
    var label: String { self == .unknown ? "—" : rawValue.capitalized }
    var color: Color {
        switch self {
        case .succeeded: return .appSuccess
        case .failed: return .appDestructive
        case .unknown: return .appMuted
        default: return .appWarning   // in-flight
        }
    }
    var isInFlight: Bool {
        switch self { case .succeeded, .failed, .unknown: return false; default: return true }
    }
}

/// `POST /admin/servers/:id/transfer` and `GET /admin/servers/:id/transfers`.
struct ServerTransfer: Decodable, Identifiable, Equatable {
    let id: String
    let serverId: String
    let fromNodeId: String
    let toNodeId: String
    let state: TransferState
    let error: String?
    let startedAt: Date?
    let finishedAt: Date?
    let createdAt: Date?
}
