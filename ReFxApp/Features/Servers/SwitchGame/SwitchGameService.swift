import Foundation

/// `/servers/:id/switch-game` (servers.controller.ts). The GPortal-style game
/// switch: list switchable templates, then perform the switch. Permission
/// control.switch-game (templates need server.read).
struct SwitchGameService {
    let client: APIClient

    func templates(_ serverId: String) async throws -> [GameTemplate] {
        try await client.send(.get("servers/\(serverId)/switch-game/templates"))
    }

    func switchGame(_ serverId: String, templateId: String, keepData: Bool) async throws {
        try await client.sendVoid(.post("servers/\(serverId)/switch-game",
                                         body: SwitchBody(templateId: templateId, keepData: keepData)))
    }

    private struct SwitchBody: Encodable { let templateId: String; let keepData: Bool }
}
