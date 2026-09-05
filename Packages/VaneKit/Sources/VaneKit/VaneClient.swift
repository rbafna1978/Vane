import Foundation

/// The API client. `Sendable` and `nonisolated`, so a view can call it from wherever it happens
/// to be and the widget extension can use the same code without touching the main actor.
public struct VaneClient: Sendable {
    public enum Failure: Error, Sendable, Equatable {
        case offline
        case server(code: String)
        case malformed
    }

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        // URLSession's default 60s timeout is far longer than anyone waits before deciding the
        // app is broken. There is always cached content behind this, so failing fast costs
        // nothing and hanging costs the whole impression of the app.
        self.session = session ?? {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 10
            configuration.waitsForConnectivity = false
            return URLSession(configuration: configuration)
        }()
    }

    public func snapshot(latitude: Double, longitude: Double) async throws -> Snapshot {
        try await get(
            "v1/snapshot",
            query: [
                .init(name: "lat", value: String(latitude)),
                .init(name: "lon", value: String(longitude)),
            ]
        )
    }

    /// One request path, one error mapping. Two copies would drift the moment either changed.
    func get<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false
        )
        components?.queryItems = query
        guard let url = components?.url else { throw Failure.malformed }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            // Anything that stopped us reaching the server is "offline" to the caller. The
            // distinction between DNS failure and a dropped socket is not one the interface
            // can act on differently.
            throw Failure.offline
        }

        guard let http = response as? HTTPURLResponse else { throw Failure.malformed }
        guard (200..<300).contains(http.statusCode) else {
            // The server's own error envelope carries a stable code. Its `message` is for logs;
            // the client maps `code` to copy, so an upstream string never reaches a person who
            // just wants to know if it will rain.
            let code = (try? Self.decoder.decode(ErrorEnvelope.self, from: data))?.error.code
            throw Failure.server(code: code ?? "http_\(http.statusCode)")
        }

        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw Failure.malformed
        }
    }

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    /// The server sends local wall-clock times with a UTC offset (`2026-09-04T12:15:00-07:00`).
    ///
    /// `Date.ISO8601FormatStyle` rather than `ISO8601DateFormatter`: the old formatter is a
    /// class and is not `Sendable`, so capturing one in a decoding closure is a data race the
    /// compiler correctly refuses to ignore. The format style is a value and crosses freely.
    ///
    /// Both variants are tried because a fractional-seconds field appearing on the server later
    /// would otherwise turn every date in the payload into a decode failure at once.
    static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    static let isoFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    /// Forecast days arrive as a bare `2026-09-05`, which the datetime styles reject outright.
    /// Anchored at noon UTC rather than midnight so formatting a day for display cannot push it
    /// across a zone boundary onto the wrong date.
    static let isoDay = Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: .gmt)
        .year().month().day()

    /// Public because it is the canonical decoder for this API's payloads, and the widget
    /// extension reads the same cached JSON without going through the client.
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: iso) { return date }
            if let date = try? Date(text, strategy: isoFractional) { return date }
            if let day = try? Date(text, strategy: isoDay) {
                return day.addingTimeInterval(12 * 3_600)
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not an ISO-8601 date: \(text)"
            )
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(iso))
        }
        return encoder
    }()
}

public extension VaneClient {
    /// The extended forecast. Each day carries its own 30-year normal, which is what stops the
    /// detail screen being a list like any other app's.
    func forecast(latitude: Double, longitude: Double, days: Int = 10) async throws -> Forecast {
        try await get(
            "v1/forecast",
            query: [
                .init(name: "lat", value: String(latitude)),
                .init(name: "lon", value: String(longitude)),
                .init(name: "days", value: String(days)),
            ]
        )
    }
}
