import Foundation

/// The panel-api wraps every successful REST response in `{ success: true, data }`.
/// Paginated reads spread `meta` alongside `data`: `{ success, data:[...], meta }`.
struct APIEnvelope<T: Decodable>: Decodable {
    let data: T
}

/// Decodes `Wrapped` if the element is well-formed, otherwise captures the
/// failure as `nil`. Lets an array of these survive a single malformed element
/// instead of throwing for the whole collection.
struct FailableDecodable<Wrapped: Decodable>: Decodable {
    let value: Wrapped?
    init(from decoder: Decoder) throws { value = try? Wrapped(from: decoder) }
}

/// `{ success, data:[...], meta:{ page, pageSize, total, totalPages } }`.
///
/// Decoding is **row-tolerant**: one malformed element (a missing required
/// field, a bad date) drops just that row rather than failing the entire
/// paginated screen. `droppedCount` records how many rows were skipped so the
/// caller can log it. `meta` is still required — it drives pagination.
struct PaginatedEnvelope<Element: Decodable>: Decodable {
    let data: [Element]
    let meta: PageMeta
    let droppedCount: Int

    private enum CodingKeys: String, CodingKey { case data, meta }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try c.decode([FailableDecodable<Element>].self, forKey: .data)
        data = rows.compactMap(\.value)
        droppedCount = rows.count - data.count
        meta = try c.decode(PageMeta.self, forKey: .meta)
    }
}

struct PageMeta: Decodable, Equatable {
    let page: Int
    let pageSize: Int
    let total: Int
    let totalPages: Int
}

/// A loaded page plus the metadata needed to drive infinite scroll.
struct Page<Element> {
    let items: [Element]
    let meta: PageMeta
    var hasMore: Bool { meta.page < meta.totalPages }
}

/// Error body shape from `AllExceptionsFilter`:
/// `{ statusCode, error, message, path, timestamp }` where `message` is a
/// string OR an array of validation strings.
struct APIErrorBody: Decodable {
    let statusCode: Int
    let error: String?
    let messages: [String]

    private enum CodingKeys: String, CodingKey { case statusCode, error, message }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusCode = (try? c.decode(Int.self, forKey: .statusCode)) ?? 0
        error = try? c.decode(String.self, forKey: .error)
        if let single = try? c.decode(String.self, forKey: .message) {
            messages = [single]
        } else if let many = try? c.decode([String].self, forKey: .message) {
            messages = many
        } else {
            messages = []
        }
    }
}
