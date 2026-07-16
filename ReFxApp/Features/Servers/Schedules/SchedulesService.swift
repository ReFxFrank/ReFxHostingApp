import Foundation

/// `/servers/:id/schedules` (servers.controller.ts). Permissions:
/// server.read (list), schedule.create/update/delete, schedule.update (run).
struct SchedulesService {
    let client: APIClient

    func list(_ serverId: String) async throws -> [Schedule] {
        try await client.send(.get("servers/\(serverId)/schedules"))
    }

    func setActive(_ serverId: String, scheduleId: String, isActive: Bool) async throws {
        try await client.sendVoid(
            .patch("servers/\(serverId)/schedules/\(scheduleId)", body: ActiveBody(isActive: isActive)))
    }

    func run(_ serverId: String, scheduleId: String) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/schedules/\(scheduleId)/run"))
    }

    func delete(_ serverId: String, scheduleId: String) async throws {
        try await client.sendVoid(.delete("servers/\(serverId)/schedules/\(scheduleId)"))
    }

    func create(_ serverId: String, name: String, cron: String,
                onlyWhenOnline: Bool, tasks: [ScheduleTaskInput]) async throws {
        let body = CreateBody(
            name: name, cron: cron, onlyWhenOnline: onlyWhenOnline, isActive: true,
            tasks: tasks.map { TaskBody(action: $0.action.rawValue, payload: $0.payload) })
        try await client.sendVoid(.post("servers/\(serverId)/schedules", body: body))
    }

    private struct ActiveBody: Encodable { let isActive: Bool }
    private struct TaskBody: Encodable { let action: String; let payload: String }
    private struct CreateBody: Encodable {
        let name: String; let cron: String; let onlyWhenOnline: Bool
        let isActive: Bool; let tasks: [TaskBody]
    }
}
