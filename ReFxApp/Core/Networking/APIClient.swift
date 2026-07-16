import Foundation

/// The single typed entry point for all REST traffic. An `actor` so token reads
/// and the request pipeline are serialized without locks.
///
/// Auth is injected as two closures (set once by `AuthStore`) to avoid a hard
/// dependency cycle: the client knows how to *get* the current access token and
/// how to *ask for* a refresh, but the token state machine lives in `AuthStore`.
///   - `tokenProvider`  → current access token (nil when signed out)
///   - `refreshHandler` → perform a single-flight refresh; returns true on success
actor APIClient {
    private let config: AppConfig
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var tokenProvider: () async -> String? = { nil }
    private var refreshHandler: () async -> Bool = { false }

    init(config: AppConfig = .shared, session: URLSession? = nil) {
        self.config = config
        self.session = session ?? APIClient.makeSession()
        self.decoder = APIClient.makeDecoder()
        self.encoder = APIClient.makeEncoder()
    }

    /// Token-bearing JSON must never be written to an on-disk cache. An ephemeral
    /// session keeps URL cache, cookies and credentials in memory only, so
    /// authenticated responses are not persisted to the app container.
    private static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Per-request timeout is set on each URLRequest (30s). Also cap the
        // *overall* time a request (incl. retries/redirects) may run so a
        // stalled connection can't hang a screen indefinitely.
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }

    func configure(tokenProvider: @escaping () async -> String?,
                   refreshHandler: @escaping () async -> Bool) {
        self.tokenProvider = tokenProvider
        self.refreshHandler = refreshHandler
    }

    // MARK: - Public request surface

    /// Decode `{ success, data: T }` and return `T`.
    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        let data = try await perform(endpoint)
        do {
            return try decoder.decode(APIEnvelope<T>.self, from: data).data
        } catch {
            // Some routes (raw-response) return the payload unwrapped; fall back.
            if let direct = try? decoder.decode(T.self, from: data) { return direct }
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Decode `{ success, data: [E], meta }` into a `Page<E>`.
    func sendPaginated<E: Decodable>(_ endpoint: Endpoint,
                                     of element: E.Type = E.self) async throws -> Page<E> {
        let data = try await perform(endpoint)
        do {
            let env = try decoder.decode(PaginatedEnvelope<E>.self, from: data)
            if env.droppedCount > 0 {
                // One or more rows were malformed; we kept the good ones rather
                // than blanking the whole screen. Surface it for diagnostics.
                print("⚠️ sendPaginated(\(E.self)): dropped \(env.droppedCount) malformed row(s)")
            }
            return Page(items: env.data, meta: env.meta)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// For 204 / empty-body mutations.
    func sendVoid(_ endpoint: Endpoint) async throws {
        _ = try await perform(endpoint)
    }

    // MARK: - Pipeline

    /// Build, send, handle 401→refresh→retry-once, and surface non-2xx as APIError.
    private func perform(_ endpoint: Endpoint, isRetry: Bool = false) async throws -> Data {
        let request = try await buildRequest(endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            // A timeout almost always means degraded/absent connectivity, so
            // present it like an offline error ("check your connection") rather
            // than a generic failure.
            let offline = [.notConnectedToInternet, .networkConnectionLost,
                           .dataNotAllowed, .timedOut].contains(urlError.code)
            throw APIError.network(isOffline: offline, underlying: urlError.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("Non-HTTP response")
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 401 where endpoint.authenticated && !isRetry:
            // Single attempt: ask AuthStore to refresh (serialized there), retry once.
            if await refreshHandler() {
                return try await perform(endpoint, isRetry: true)
            }
            throw APIError.unauthorized
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden(decodeMessage(data))
        case 404:
            throw APIError.notFound(decodeMessage(data))
        case 400, 409, 422:
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            throw APIError.validation(body?.messages ?? [decodeMessage(data) ?? "Invalid request"])
        default:
            throw APIError.server(status: http.statusCode, message: decodeMessage(data))
        }
    }

    private func buildRequest(_ endpoint: Endpoint) async throws -> URLRequest {
        guard let url = endpoint.url(base: config.apiBaseURL) else {
            throw APIError.decoding("Bad URL for \(endpoint.path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        if let raw = endpoint.rawBody {
            request.setValue(endpoint.rawContentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = raw
        } else if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }
        if endpoint.authenticated, let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func decodeMessage(_ data: Data) -> String? {
        (try? decoder.decode(APIErrorBody.self, from: data))?.messages.first
    }

    // MARK: - Coding

    /// The single source of truth for REST JSON decoding (custom date strategy).
    /// Non-private so tests decode models exactly as the app does at runtime.
    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // String dates: ISO-8601 (with/without fractional seconds) or a
            // bare calendar date (`yyyy-MM-dd`, common for invoice due dates).
            if let raw = try? container.decode(String.self) {
                if let date = ISO8601DateFormatter.withFractional.date(from: raw)
                    ?? ISO8601DateFormatter.plain.date(from: raw)
                    ?? DateFormatter.yearMonthDay.date(from: raw) {
                    return date
                }
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unrecognized date string: \(raw)"))
            }
            // Numeric epoch: seconds, or milliseconds when the value is large.
            if let epoch = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: epoch > 1_000_000_000_000 ? epoch / 1000 : epoch)
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognized date value"))
        }
        return d
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain = ISO8601DateFormatter()
}

private extension DateFormatter {
    /// Bare calendar date (`2026-06-26`). Parsed at UTC midnight with a fixed
    /// POSIX locale so the day is stable regardless of device locale/time zone.
    static let yearMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Type-erasing box so `Endpoint.body: Encodable?` can be encoded directly
/// (Swift 5.9 can encode an `any Encodable`, but the box keeps call sites clean).
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
