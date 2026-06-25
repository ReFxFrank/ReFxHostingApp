import Foundation

enum ScheduleAction: String, Codable, Equatable {
    case command = "COMMAND"
    case power = "POWER"
    case backup = "BACKUP"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ScheduleAction(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .command: return "Command"
        case .power: return "Power"
        case .backup: return "Backup"
        case .unknown: return "Task"
        }
    }
}

struct ScheduleTask: Codable, Identifiable, Equatable {
    let id: String
    let action: ScheduleAction
    let payload: String
}

/// `GET /servers/:id/schedules`.
struct Schedule: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let cron: String
    let isActive: Bool
    let onlyWhenOnline: Bool?
    let lastRunAt: Date?
    let nextRunAt: Date?
    let tasks: [ScheduleTask]?

    var taskSummary: String {
        guard let tasks, !tasks.isEmpty else { return "No tasks" }
        return tasks.map { "\($0.action.label): \($0.payload)" }.joined(separator: ", ")
    }
}
