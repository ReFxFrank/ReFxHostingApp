import Foundation
@testable import ReFxApp

/// Mirrors `APIClient`'s private JSON decoder (custom ISO-8601 date strategy,
/// with and without fractional seconds) so model decode tests exercise the same
/// behavior the app uses at runtime. Models are decoded from the inner `data`
/// payload — the envelope is unwrapped by `APIClient` in production.
enum TestJSON {
    /// Delegates to the real production decoder so tests can never drift from
    /// the app's actual date/decoding behavior.
    static func makeDecoder() -> JSONDecoder { APIClient.makeDecoder() }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try makeDecoder().decode(T.self, from: Data(json.utf8))
    }
}
