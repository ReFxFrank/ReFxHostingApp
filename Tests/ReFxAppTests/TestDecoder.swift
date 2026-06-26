import Foundation
@testable import ReFxApp

/// Mirrors `APIClient`'s private JSON decoder (custom ISO-8601 date strategy,
/// with and without fractional seconds) so model decode tests exercise the same
/// behavior the app uses at runtime. Models are decoded from the inner `data`
/// payload — the envelope is unwrapped by `APIClient` in production.
enum TestJSON {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let frac = ISO8601DateFormatter(); frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { dec in
            let raw = try dec.singleValueContainer().decode(String.self)
            if let date = frac.date(from: raw) ?? plain.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath,
                debugDescription: "Unrecognized date: \(raw)"))
        }
        return decoder
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try makeDecoder().decode(T.self, from: Data(json.utf8))
    }
}
