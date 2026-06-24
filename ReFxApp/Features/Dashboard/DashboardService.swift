import Foundation

struct DashboardService {
    let client: APIClient

    func summary() async throws -> DashboardSummary {
        try await client.send(.get("dashboard"))
    }
}
