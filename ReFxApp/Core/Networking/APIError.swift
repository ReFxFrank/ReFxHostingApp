import Foundation

/// A single, exhaustive error type for the API layer. Views map these to
/// human-readable copy and decide recovery (re-auth vs retry vs field errors).
enum APIError: Error, Equatable {
    /// 401 after a refresh attempt already failed — caller should sign out.
    case unauthorized
    /// 403 — authenticated but not permitted. "You don't have access."
    case forbidden(String?)
    /// 404.
    case notFound(String?)
    /// 400/409/422 — validation/conflict. Carries field-level messages.
    case validation([String])
    /// Any other non-2xx, with the server's message if present.
    case server(status: Int, message: String?)
    /// Transport failure (offline, timeout, TLS). `isOffline` drives UI copy.
    case network(isOffline: Bool, underlying: String)
    /// Response body didn't match the expected shape.
    case decoding(String)

    /// Friendly, user-facing description. Never leaks tokens or stack traces.
    var userMessage: String {
        switch self {
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .forbidden(let m):
            return m ?? "You don't have access to do that."
        case .notFound(let m):
            return m ?? "Not found."
        case .validation(let messages):
            return messages.first ?? "Please check your input and try again."
        case .server(_, let m):
            return m ?? "Something went wrong on the server. Try again shortly."
        case .network(let isOffline, _):
            return isOffline
                ? "You appear to be offline. Check your connection."
                : "Couldn't reach the server. Try again."
        case .decoding:
            return "We received an unexpected response. Try again."
        }
    }

    /// All field/validation messages, for surfacing under form fields.
    var validationMessages: [String] {
        if case .validation(let m) = self { return m }
        return []
    }
}
