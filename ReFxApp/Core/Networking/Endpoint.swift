import Foundation

enum HTTPMethod: String {
    case get = "GET", post = "POST", patch = "PATCH", put = "PUT", delete = "DELETE"
}

/// A typed description of one REST call. `path` is relative to `/api/v1`.
/// `authenticated` is true for everything except the `@Public()` auth routes.
struct Endpoint {
    var method: HTTPMethod = .get
    var path: String
    var query: [URLQueryItem] = []
    var body: Encodable?
    var authenticated: Bool = true

    func url(base: URL) -> URL? {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var comps = URLComponents(
            url: base.appendingPathComponent(trimmed),
            resolvingAgainstBaseURL: false) else { return nil }
        if !query.isEmpty { comps.queryItems = query }
        return comps.url
    }
}

extension Endpoint {
    static func get(_ path: String, query: [URLQueryItem] = [],
                    authenticated: Bool = true) -> Endpoint {
        Endpoint(method: .get, path: path, query: query, authenticated: authenticated)
    }

    static func post(_ path: String, body: Encodable? = nil,
                     authenticated: Bool = true) -> Endpoint {
        Endpoint(method: .post, path: path, body: body, authenticated: authenticated)
    }

    static func patch(_ path: String, body: Encodable? = nil) -> Endpoint {
        Endpoint(method: .patch, path: path, body: body)
    }

    static func put(_ path: String, body: Encodable? = nil) -> Endpoint {
        Endpoint(method: .put, path: path, body: body)
    }

    static func delete(_ path: String, body: Encodable? = nil) -> Endpoint {
        Endpoint(method: .delete, path: path, body: body)
    }
}
