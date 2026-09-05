import Foundation

/// The API contract, mirrored. Field names match the server's JSON exactly so no
/// `CodingKeys` boilerplate is needed and drift shows up as a decode failure in tests
/// rather than as a silently missing value on screen.
///
/// Every type here is a `Sendable` value type. Public types never get sendability inferred,
/// so the conformance is written out — and it is what lets a decoded snapshot cross from a
/// background download into the main actor without ceremony.

public struct Current: Codable, Sendable, Hashable {
    public let tempC: Double
    public let feelsC: Double
    /// Percent. Optional so a cache written before the field existed still decodes.
    public let cloudCover: Int?
    public let windKt: Double
    public let windDeg: Int
    public let humidity: Int
    public let pressureHpa: Double
    public let code: Int

    enum CodingKeys: String, CodingKey {
        case tempC = "temp_c", feelsC = "feels_c", windKt = "wind_kt", windDeg = "wind_deg"
        case humidity, pressureHpa = "pressure_hpa", code, cloudCover = "cloud_cover"
    }
}

public struct ArcPoint: Codable, Sendable, Hashable {
    public let t: Date
    public let tempC: Double
    public let precipMm: Double
    public let code: Int

    enum CodingKeys: String, CodingKey { case t, tempC = "temp_c", precipMm = "precip_mm", code }
}

/// The dashed reference behind the trace: the average high and low for this calendar date.
public struct NormalBand: Codable, Sendable, Hashable {
    public let tmaxC: Double
    public let tminC: Double
    public let years: Int

    enum CodingKeys: String, CodingKey { case tmaxC = "tmax_c", tminC = "tmin_c", years }
}

public struct WeatherContext: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case percentile, streak, since, threshold, seasonalEdge = "seasonal_edge"
    }

    public enum Confidence: String, Codable, Sendable { case high, low }

    public let headline: String
    public let kind: Kind
    public let confidence: Confidence

    /// Swift synthesises an *internal* memberwise initialiser, so without this VaneUI and the
    /// tests cannot build a sample. Public API has to be written out on purpose.
    public init(headline: String, kind: Kind, confidence: Confidence) {
        self.headline = headline
        self.kind = kind
        self.confidence = confidence
    }
}

public struct SunTimes: Codable, Sendable, Hashable {
    public let sunrise: Date
    public let sunset: Date
}

public enum ContextState: String, Codable, Sendable {
    /// No history yet and nothing queued.
    case cold
    /// Backfill is running. The screen renders without a context line and gains one later.
    case warming
    /// History present; `context` may still be nil when nothing true is interesting.
    case warm
}

public struct Snapshot: Codable, Sendable, Hashable {
    public let cellId: String
    public let observedAt: Date
    /// The location's own UTC offset, from the server.
    ///
    /// Optional so a cache written by an older build still decodes — a schema addition must
    /// never turn a working offline app into a blank screen. When absent we fall back to the
    /// device's zone, which is right for the common case of looking at where you are standing.
    public let utcOffsetSeconds: Int?
    public let current: Current
    public let arc: [ArcPoint]
    public let normal: NormalBand?
    public let context: WeatherContext?
    public let contextState: ContextState
    public let sun: SunTimes

    enum CodingKeys: String, CodingKey {
        case cellId = "cell_id", observedAt = "observed_at", current, arc, normal, context
        case contextState = "context_state", sun
        case utcOffsetSeconds = "utc_offset_seconds"
    }

    /// The time zone of the place being looked at, not of the phone doing the looking.
    ///
    /// Sunrise at a saved location three time zones away has to read in *its* local time, or
    /// the number is a lie dressed as a fact.
    public var timeZone: TimeZone {
        utcOffsetSeconds.flatMap { TimeZone(secondsFromGMT: $0) } ?? .current
    }
}

public struct ForecastHour: Codable, Sendable, Hashable {
    public let t: Date
    public let tempC: Double
    public let precipMm: Double
    public let precipProbability: Int?
    public let code: Int

    enum CodingKeys: String, CodingKey {
        case t, tempC = "temp_c", precipMm = "precip_mm"
        case precipProbability = "precip_probability", code
    }
}

public struct ForecastDay: Codable, Sendable, Hashable, Identifiable {
    /// Decoded from a bare `YYYY-MM-DD`, which the datetime strategy would reject. Anchored at
    /// noon UTC rather than midnight so a day never lands on the wrong side of a zone boundary
    /// when it is formatted for display.
    public let d: Date
    public let tmaxC: Double
    public let tminC: Double
    public let precipMm: Double
    public let precipProbability: Int?
    public let code: Int
    public let sunrise: Date
    public let sunset: Date
    /// This calendar date's own 30-year normal. Nil while the cell is still warming.
    public let normal: NormalBand?

    public var id: Date { d }
    public var condition: WeatherCode { WeatherCode(code) }

    /// How far this day's high sits from the usual high for the date. The whole reason this
    /// screen is not a list of numbers.
    public var highAnomaly: Double? {
        normal.map { tmaxC - $0.tmaxC }
    }

    enum CodingKeys: String, CodingKey {
        case d, tmaxC = "tmax_c", tminC = "tmin_c", precipMm = "precip_mm"
        case precipProbability = "precip_probability", code, sunrise, sunset, normal
    }
}

public struct Forecast: Codable, Sendable, Hashable {
    public let cellId: String
    public let hourly: [ForecastHour]
    public let daily: [ForecastDay]

    enum CodingKeys: String, CodingKey { case cellId = "cell_id", hourly, daily }
}
