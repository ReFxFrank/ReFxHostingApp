import Foundation

/// `GET /dashboard` — the client-area home summary. We decode the fields the
/// app surfaces (servers, billing flags, active alerts); other keys are ignored.
struct DashboardSummary: Decodable, Equatable {
    let servers: [Server]
    let billing: DashboardBilling
    let alerts: [PlatformAlert]
}

struct DashboardBilling: Decodable, Equatable {
    let openInvoices: Int
    let nextInvoiceMinor: Int
    let currency: String

    var nextInvoice: Money { Money(minorUnits: nextInvoiceMinor, currency: currency) }
}

/// Platform-wide alert/banner (`/platform/alerts`), surfaced on the dashboard.
struct PlatformAlert: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let isActive: Bool
}
