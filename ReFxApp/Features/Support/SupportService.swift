import Foundation

/// Customer support surface (`support.controller.ts`). Tickets are authed to the
/// caller; staff get wider access via the same routes.
struct SupportService {
    let client: APIClient

    func tickets(page: Int = 1, mine: Bool = false) async throws -> Page<Ticket> {
        var query = [URLQueryItem(name: "page", value: String(page)),
                     URLQueryItem(name: "pageSize", value: "25")]
        if mine { query.append(URLQueryItem(name: "mine", value: "true")) }
        return try await client.sendPaginated(.get("support/tickets", query: query))
    }

    func ticket(_ id: String) async throws -> TicketDetail {
        try await client.send(.get("support/tickets/\(id)"))
    }

    func create(subject: String, body: String, priority: TicketPriority?) async throws -> Ticket {
        try await client.send(.post("support/tickets",
                                     body: CreateBody(subject: subject, body: body,
                                                      priority: priority?.rawValue)))
    }

    func reply(_ id: String, body: String) async throws {
        try await client.sendVoid(.post("support/tickets/\(id)/messages", body: ReplyBody(body: body)))
    }

    private struct CreateBody: Encodable { let subject: String; let body: String; let priority: String? }
    private struct ReplyBody: Encodable { let body: String }
}
