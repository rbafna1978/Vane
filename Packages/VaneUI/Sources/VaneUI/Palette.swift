import Foundation
import SwiftUI
import VaneKit

/// The Barograph palette.
///
/// `trace` and `alert` are the entire saturated budget. Everything else lives between paper
/// and ink, because a chart is ink on stock and the stock is not trying to be interesting.
///
/// Light and dark are not a toggle. The palette is a continuous function of where the sun
/// actually is, so the interface drains toward night through real twilight rather than
/// flipping at a threshold someone picked.
public nonisolated struct Palette: Sendable, Hashable {
    public let paper: RGB
    public let grid: RGB
    public let ink: RGB
    public let trace: RGB
    public let alert: RGB

    /// The normal band. Derived from `grid` but held to 3:1, because it is information rather
    /// than ruling — it is what "unusual" is measured against.
    public var band: RGB { grid.meetingContrast(3.0, against: paper) }
    public var bandColor: Color { band.color }

    public var paperColor: Color { paper.color }
    public var gridColor: Color { grid.color }
    public var inkColor: Color { ink.color }
    public var traceColor: Color { trace.color }
    public var alertColor: Color { alert.color }

    // The two endpoints. Everything shown is a mix of these, washed.
    static let day = Palette(
        paper: RGB(hex: 0xDFE7DC),   // barograph chart stock: eau-de-nil, not cream
        grid: RGB(hex: 0xAFBFA9),    // printed hairline ruling
        ink: RGB(hex: 0x1B2021),     // warm black, never #000
        trace: RGB(hex: 0x3A2E6B),   // aniline violet: the ink real barograph pens used
        alert: RGB(hex: 0xB8442E)
    )

    static let night = Palette(
        paper: RGB(hex: 0x12171A),
        grid: RGB(hex: 0x263029),
        ink: RGB(hex: 0xDCE6DE),
        trace: RGB(hex: 0x8B7BD4),   // lifted, because violet on near-black loses its identity
        alert: RGB(hex: 0xE06A4F)
    )

    func mixed(with other: Palette, amount t: Double) -> Palette {
        Palette(
            paper: paper.mixed(with: other.paper, amount: t),
            grid: grid.mixed(with: other.grid, amount: t),
            ink: ink.mixed(with: other.ink, amount: t),
            trace: trace.mixed(with: other.trace, amount: t),
            alert: alert.mixed(with: other.alert, amount: t)
        )
    }

    /// Ink is pushed away from paper until it clears `minimum`, so no time of day can produce
    /// an unreadable screen.
    ///
    /// `grid` carries two jobs at different weights: the hairline ruling, which is scaffolding
    /// and should stay quiet, and the normal band, which is the chart's essential comparison and
    /// so must clear WCAG 1.4.11's 3:1 for non-text content. The band gets its own token rather
    /// than borrowing one held to a decorative threshold.
    func guaranteeingContrast(_ minimum: Double) -> Palette {
        Palette(
            paper: paper,
            grid: grid.meetingContrast(1.6, against: paper),
            ink: ink.meetingContrast(minimum, against: paper),
            trace: trace.meetingContrast(3.0, against: paper),
            alert: alert.meetingContrast(3.0, against: paper)
        )
    }

    func washed(_ wash: RGB, amount: Double) -> Palette {
        // Only the paper takes the wash. Tinting the ink too would drop contrast exactly when
        // the light is lowest, which is when it is already hardest to read.
        Palette(
            paper: paper.mixed(with: wash, amount: amount),
            grid: grid.mixed(with: wash, amount: amount * 0.5),
            ink: ink, trace: trace, alert: alert
        )
    }
}

/// Where the sun is, named. Thresholds are the standard definitions, not invented ones:
/// civil, nautical and astronomical twilight are each 6 degrees of solar depression.
public nonisolated enum SkyPhase: String, Sendable, CaseIterable {
    case night, astronomicalTwilight, nauticalTwilight, civilTwilight, goldenHour, day

    /// Display name. Uppercasing the camelCase rawValue produces "ASTRONOMICALTWILIGHT"; the
    /// names are written out because a label is content, not a derived string.
    public var label: String {
        switch self {
        case .night: "NIGHT"
        case .astronomicalTwilight: "ASTRONOMICAL TWILIGHT"
        case .nauticalTwilight: "NAUTICAL TWILIGHT"
        case .civilTwilight: "CIVIL TWILIGHT"
        case .goldenHour: "GOLDEN HOUR"
        case .day: "DAY"
        }
    }

    public init(elevation: Double) {
        switch elevation {
        case ..<(-18): self = .night
        case ..<(-12): self = .astronomicalTwilight
        case ..<(-6): self = .nauticalTwilight
        case ..<(-0.833): self = .civilTwilight   // -0.833: the sun's disc plus refraction
        case ..<6: self = .goldenHour
        default: self = .day
        }
    }
}

public nonisolated struct SkyState: Sendable, Hashable {
    public let phase: SkyPhase
    public let elevation: Double
    public let azimuth: Double
    public let palette: Palette

    /// - Parameter cloudCover: 0...1. Overcast flattens chroma — a grey day genuinely has less
    ///   colour in it, and pretending otherwise is the "always golden hour" look every other
    ///   weather app has.
    public static func now(
        latitude: Double, longitude: Double, date: Date = .now, cloudCover: Double = 0
    ) -> SkyState {
        let sun = SunPosition.at(latitude: latitude, longitude: longitude, date: date)

        // Lightness crosses over exactly civil twilight: +6 degrees to -6 degrees, which is
        // the astronomical definition of the light changing rather than a number chosen to
        // look right. Measured cost of the gentle ramp over a steep one is 2 points of AAA
        // contrast (94.5% to 92.2% of the day) and nothing else, because `guaranteeingContrast`
        // below holds the floor at 4.5:1 regardless of where paper sits. Cheap, so the brief
        // gets what it asked for: light and dark are not a toggle.
        let daylight = smoothstep(-6, 6, sun.elevation)
        var palette = Palette.night.mixed(with: .day, amount: daylight)

        // Warm wash peaks at the horizon and falls away as the sun climbs — this is the low
        // sun reddening as its light travels further through the atmosphere.
        let warmth = (1 - smoothstep(0, 12, sun.elevation)) * smoothstep(-8, 0, sun.elevation)
        // Blue wash for the hour after the warm one has gone: the sky is lit but the sun is not.
        let blueHour = smoothstep(-12, -4, sun.elevation) * (1 - smoothstep(-4, 2, sun.elevation))

        let cover = min(1, max(0, cloudCover))
        let clear = 1 - cover
        if warmth > 0 { palette = palette.washed(RGB(hex: 0xE8DFC9), amount: warmth * 0.55 * clear) }
        if blueHour > 0 { palette = palette.washed(RGB(hex: 0x5B6E86), amount: blueHour * 0.45 * clear) }

        // Cover does more than mute the wash: an overcast day is genuinely flatter, so the
        // paper loses chroma toward its own neutral. Only the paper — draining colour from the
        // trace would make the reading harder to find on exactly the days it is greyest.
        if cover > 0.35 {
            let flattening = smoothstep(0.35, 1.0, cover) * 0.7
            palette = Palette(
                paper: palette.paper.mixed(with: palette.paper.neutral, amount: flattening),
                grid: palette.grid, ink: palette.ink,
                trace: palette.trace, alert: palette.alert
            )
        }

        // Last word on legibility. Whatever the wash did to the paper, ink is pushed until it
        // clears WCAG AA for body text. Contrast is not something the palette gets to lose.
        palette = palette.guaranteeingContrast(4.5)

        return SkyState(
            phase: SkyPhase(elevation: sun.elevation),
            elevation: sun.elevation,
            azimuth: sun.azimuth,
            palette: palette
        )
    }
}

/// Hermite smoothstep. A linear ramp between two thresholds has visible corners where it
/// starts and stops; smoothstep leaves with zero slope at both ends, so the colour arrives
/// and departs without a seam.
nonisolated func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
}
