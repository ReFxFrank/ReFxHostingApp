import XCTest
@testable import ReFxApp

/// Networking robustness: one malformed row must not blank a whole paginated
/// screen, and the date strategy must tolerate the formats the backend can send.
final class TolerantDecodingTests: XCTestCase {

    /// Minimal element with a required field, to model a real list row.
    private struct Row: Decodable, Equatable {
        let id: String
        let createdAt: Date
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.makeDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Row-tolerant pagination

    func testPaginatedEnvelopeDropsMalformedRows() throws {
        // Row 2 is missing the required `id`; row 3 has a broken date. Both must
        // drop, leaving the two good rows and droppedCount == 2.
        let json = """
        {
          "success": true,
          "data": [
            { "id": "a", "createdAt": "2026-06-01T00:00:00Z" },
            { "createdAt": "2026-06-02T00:00:00Z" },
            { "id": "c", "createdAt": "not-a-date" },
            { "id": "d", "createdAt": "2026-06-04T00:00:00Z" }
          ],
          "meta": { "page": 1, "pageSize": 20, "total": 4, "totalPages": 1 }
        }
        """
        let env = try decode(PaginatedEnvelope<Row>.self, json)
        XCTAssertEqual(env.data.map(\.id), ["a", "d"])
        XCTAssertEqual(env.droppedCount, 2)
        XCTAssertEqual(env.meta.total, 4)
    }

    func testPaginatedEnvelopeAllGoodRowsKeepsAll() throws {
        let json = """
        {
          "data": [
            { "id": "a", "createdAt": "2026-06-01T00:00:00Z" },
            { "id": "b", "createdAt": "2026-06-02T00:00:00Z" }
          ],
          "meta": { "page": 1, "pageSize": 20, "total": 2, "totalPages": 1 }
        }
        """
        let env = try decode(PaginatedEnvelope<Row>.self, json)
        XCTAssertEqual(env.data.count, 2)
        XCTAssertEqual(env.droppedCount, 0)
    }

    func testFailableDecodableCapturesFailureAsNil() throws {
        let good = try decode(FailableDecodable<Row>.self,
            #"{ "id": "a", "createdAt": "2026-06-01T00:00:00Z" }"#)
        XCTAssertEqual(good.value?.id, "a")
        let bad = try decode(FailableDecodable<Row>.self, #"{ "createdAt": "2026-06-01T00:00:00Z" }"#)
        XCTAssertNil(bad.value)
    }

    // MARK: - Date strategy breadth

    private struct DateBox: Decodable { let at: Date }

    func testDateAcceptsFractionalAndPlainISO() throws {
        XCTAssertNoThrow(try decode(DateBox.self, #"{ "at": "2026-06-26T12:30:00.123Z" }"#))
        XCTAssertNoThrow(try decode(DateBox.self, #"{ "at": "2026-06-26T12:30:00Z" }"#))
    }

    func testDateAcceptsBareCalendarDate() throws {
        let box = try decode(DateBox.self, #"{ "at": "2026-06-26" }"#)
        // UTC midnight of that day.
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let parts = cal.dateComponents([.year, .month, .day], from: box.at)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 6)
        XCTAssertEqual(parts.day, 26)
    }

    func testDateAcceptsEpochSecondsAndMillis() throws {
        let secs = try decode(DateBox.self, #"{ "at": 1782519000 }"#)
        let millis = try decode(DateBox.self, #"{ "at": 1782519000000 }"#)
        XCTAssertEqual(secs.at.timeIntervalSince1970, 1782519000, accuracy: 1)
        XCTAssertEqual(millis.at.timeIntervalSince1970, 1782519000, accuracy: 1)
    }

    func testDateRejectsGarbageString() {
        XCTAssertThrowsError(try decode(DateBox.self, #"{ "at": "tuesday" }"#))
    }
}
