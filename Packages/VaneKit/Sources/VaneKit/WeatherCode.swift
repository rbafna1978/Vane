import Foundation

/// WMO 4677 present-weather codes, which is what Open-Meteo reports in `weather_code`.
///
/// Rendered in plain words rather than the METAR abbreviations the rest of the interface borrows
/// from. "OVC" and "-RA" are the right vocabulary for the chart's furniture, but this is the
/// answer to "what is it doing out?" — and someone deciding on a jacket should not have to learn
/// a code to read it.
public enum WeatherCode: Sendable, Hashable {
    case clear, mainlyClear, partlyCloudy, overcast
    case fog
    case drizzle(Intensity)
    case rain(Intensity)
    case showers(Intensity)
    case freezing
    case snow(Intensity)
    case thunderstorm
    case hail
    case unknown

    public enum Intensity: Sendable, Hashable { case light, moderate, heavy }

    public init(_ code: Int) {
        switch code {
        case 0: self = .clear
        case 1: self = .mainlyClear
        case 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51: self = .drizzle(.light)
        case 53: self = .drizzle(.moderate)
        case 55: self = .drizzle(.heavy)
        case 56, 57, 66, 67: self = .freezing
        case 61: self = .rain(.light)
        case 63: self = .rain(.moderate)
        case 65: self = .rain(.heavy)
        case 71, 77: self = .snow(.light)
        case 73: self = .snow(.moderate)
        case 75, 85, 86: self = .snow(.heavy)
        case 80: self = .showers(.light)
        case 81: self = .showers(.moderate)
        case 82: self = .showers(.heavy)
        case 95: self = .thunderstorm
        case 96, 99: self = .hail
        default: self = .unknown
        }
    }

    /// Sentence case, because it reads as a description rather than a label.
    public var label: String {
        switch self {
        case .clear: "Clear"
        case .mainlyClear: "Mainly clear"
        case .partlyCloudy: "Partly cloudy"
        case .overcast: "Overcast"
        case .fog: "Fog"
        case .drizzle(.light): "Light drizzle"
        case .drizzle: "Drizzle"
        case .rain(.light): "Light rain"
        case .rain(.moderate): "Rain"
        case .rain(.heavy): "Heavy rain"
        case .showers(.light): "Light showers"
        case .showers(.moderate): "Showers"
        case .showers(.heavy): "Heavy showers"
        case .freezing: "Freezing rain"
        case .snow(.light): "Light snow"
        case .snow(.moderate): "Snow"
        case .snow(.heavy): "Heavy snow"
        case .thunderstorm: "Thunderstorm"
        case .hail: "Hail"
        case .unknown: ""
        }
    }

    /// Whether this code means water is falling. Drives whether the chart bothers drawing its
    /// precipitation row at all.
    public var isPrecipitating: Bool {
        switch self {
        case .drizzle, .rain, .showers, .freezing, .snow, .thunderstorm, .hail: true
        default: false
        }
    }
}

public extension Current {
    var condition: WeatherCode { WeatherCode(code) }
}
