import Foundation
import SwiftUI
import Testing

@testable import VaneUI

private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents(); (c.year, c.month, c.day, c.hour, c.minute) = (y, mo, d, h, mi)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    return cal.date(from: c)!
}

@Test func `linear-light mixing does not darken the midpoint`() {
    // The bug this guards: mixing gamma-encoded sRGB directly puts a muddy grey band halfway
    // through every gradient. A true half-mix of black and white must be lighter than 0.5.
    let mid = RGB(0, 0, 0).mixed(with: RGB(1, 1, 1), amount: 0.5)
    #expect(mid.r > 0.70)
}

@Test func `mixing is exact at both ends`() {
    let a = RGB(hex: 0xDFE7DC), b = RGB(hex: 0x12171A)
    #expect(a.mixed(with: b, amount: 0).r == a.r)
    #expect(abs(a.mixed(with: b, amount: 1).r - b.r) < 0.001)
}

@Test func `mix amount is clamped rather than extrapolating off the ends`() {
    let a = RGB(0.2, 0.2, 0.2), b = RGB(0.8, 0.8, 0.8)
    #expect(a.mixed(with: b, amount: -5).r == a.r)
    #expect(abs(a.mixed(with: b, amount: 5).r - b.r) < 0.001)
}

@Test(arguments: [
    (-30.0, SkyPhase.night),
    (-15.0, .astronomicalTwilight),
    (-9.0, .nauticalTwilight),
    (-3.0, .civilTwilight),
    (3.0, .goldenHour),
    (45.0, .day),
])
func `sky phase uses the standard twilight definitions`(elevation: Double, expected: SkyPhase) {
    #expect(SkyPhase(elevation: elevation) == expected)
}

@Test func `paper is light by day and dark at night`() {
    let noon = SkyState.now(latitude: 37.8, longitude: -122.25, date: utc(2026, 9, 4, 20, 0))
    let midnight = SkyState.now(latitude: 37.8, longitude: -122.25, date: utc(2026, 9, 4, 9, 0))
    #expect(noon.palette.paper.r > 0.75)
    #expect(midnight.palette.paper.r < 0.20)
    #expect(noon.phase == .day)
    #expect(midnight.phase == .night)
}

@Test func `ink always stays readable against paper`() {
    // The whole palette moves through the day. If contrast ever collapses, the screen becomes
    // unreadable at exactly one time of day and nobody notices until a user is outside at dusk.
    for minute in stride(from: 0, to: 1_440, by: 15) {
        let state = SkyState.now(
            latitude: 37.8, longitude: -122.25,
            date: utc(2026, 9, 4, 0, 0).addingTimeInterval(Double(minute) * 60)
        )
        let contrast = contrastRatio(state.palette.paper, state.palette.ink)
        // WCAG AA for body text, guaranteed at every minute of the day. At the worst instant
        // — paper passing through mid-luminance at the horizon — even pure black only reaches
        // 4.8:1, so this is the strongest promise the design can actually keep.
        #expect(contrast >= 4.5, "contrast \(contrast) at minute \(minute), \(state.phase)")
    }
}

@Test func `the wash tints paper but never ink`() {
    let base = Palette.day
    let washed = base.washed(RGB(hex: 0xE8DFC9), amount: 0.6)
    #expect(washed.paper != base.paper)
    #expect(washed.ink == base.ink, "tinting ink drops contrast when the light is already lowest")
}

@Test func `contrast reaches AAA for the overwhelming majority of the day`() {
    // AA is the floor and holds at every minute. AAA measures 94.8% of the day on this date —
    // the shortfall is the two lightness transitions and the wash at golden and blue hour.
    // The guard sits below the measured value so it catches a real regression (the ramp
    // lingering in the unreadable band) rather than tripping on the honest number.
    var aaa = 0, total = 0
    for minute in stride(from: 0, to: 1_440, by: 5) {
        let state = SkyState.now(
            latitude: 37.8, longitude: -122.25,
            date: utc(2026, 9, 4, 7, 0).addingTimeInterval(Double(minute) * 60)
        )
        total += 1
        if contrastRatio(state.palette.paper, state.palette.ink) >= 7.0 { aaa += 1 }
    }
    #expect(Double(aaa) / Double(total) > 0.90)
}

@Test func `overcast flattens the wash`() {
    let clear = SkyState.now(
        latitude: 37.8, longitude: -122.25, date: utc(2026, 9, 5, 2, 15), cloudCover: 0)
    let overcast = SkyState.now(
        latitude: 37.8, longitude: -122.25, date: utc(2026, 9, 5, 2, 15), cloudCover: 1)
    // A grey day genuinely has less colour in it than a clear one.
    #expect(chroma(clear.palette.paper) > chroma(overcast.palette.paper))
}

@Test func `display type grows with Dynamic Type but is clamped`() {
    let largest = VaneType.reading(for: .accessibility5)
    #expect(largest <= VaneType.readingSize * 1.31, "148pt x AX5 would be ~380pt; nothing survives that")
    #expect(largest > VaneType.readingSize, "it must still grow, just not without bound")
}

@Test func `type scales monotonically across every Dynamic Type size`() {
    // Regression for the real bug: every font used `fixedSize:` or `Font.system(size:)`, both of
    // which opt out of Dynamic Type entirely, so the accessibility setting did nothing at all —
    // while these very curves sat tested and uncalled.
    var previousReading = 0.0
    var previousContext = 0.0
    for size in DynamicTypeSize.allCases {
        let reading = VaneType.reading(for: size)
        let context = VaneType.context(for: size)
        #expect(reading >= previousReading, "reading shrank at \(size)")
        #expect(context >= previousContext, "context shrank at \(size)")
        previousReading = reading
        previousContext = context
    }
    #expect(VaneType.reading(for: .accessibility5) > VaneType.reading(for: .large))
    #expect(VaneType.context(for: .accessibility5) > VaneType.context(for: .large))
}

private func luminance(_ c: RGB) -> Double {
    func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
}

private func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
    let (l1, l2) = (luminance(a), luminance(b))
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
}

private func chroma(_ c: RGB) -> Double { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }

@Test func `every sky phase has a readable label`() {
    // Uppercasing a camelCase rawValue silently produces "ASTRONOMICALTWILIGHT".
    for phase in SkyPhase.allCases {
        #expect(phase.label == phase.label.uppercased())
        #expect(!phase.label.contains("  "))
        if phase.rawValue.contains(where: \.isUppercase) {
            #expect(phase.label.contains(" "), "\(phase) needs a word break")
        }
    }
}

@Test func `the normal band clears WCAG non-text contrast at every hour`() {
    // The band is the comparison the whole chart is read against — essential graphic content
    // under WCAG 1.4.11, not ruling. It previously borrowed `grid`, which is held to a
    // decorative 1.6:1 and was invisible on dark paper.
    for minute in stride(from: 0, to: 1_440, by: 15) {
        let state = SkyState.now(
            latitude: 37.8, longitude: -122.25,
            date: utc(2026, 9, 4, 0, 0).addingTimeInterval(Double(minute) * 60)
        )
        let ratio = contrastRatio(state.palette.band, state.palette.paper)
        #expect(ratio >= 3.0, "band contrast \(ratio) at minute \(minute)")
    }
}

@Test func `ruling stays quieter than the band it sits behind`() {
    let palette = SkyState.now(latitude: 37.8, longitude: -122.25,
                               date: utc(2026, 9, 4, 20, 0)).palette
    #expect(contrastRatio(palette.grid, palette.paper)
            <= contrastRatio(palette.band, palette.paper))
}

@Test func `overcast flattens the paper toward neutral`() {
    // The brief asks for colour state driven by sun position AND conditions. `cloudCover` was
    // a parameter nothing ever passed, so every day rendered as though it were clear.
    let noon = utc(2026, 9, 4, 20, 0)
    let clear = SkyState.now(latitude: 37.8, longitude: -122.25, date: noon, cloudCover: 0)
    let overcast = SkyState.now(latitude: 37.8, longitude: -122.25, date: noon, cloudCover: 1)

    #expect(chroma(overcast.palette.paper) < chroma(clear.palette.paper))
    // Flatter, not darker — an overcast day loses colour, not light.
    #expect(abs(overcast.palette.paper.luminance - clear.palette.paper.luminance) < 0.12)
    // And the trace keeps its identity, because grey days are when it is hardest to find.
    #expect(overcast.palette.trace == clear.palette.trace)
}

@Test func `contrast survives every level of cloud cover`() {
    for cover in stride(from: 0.0, through: 1.0, by: 0.1) {
        for hour in [3, 7, 12, 18, 21] {
            let state = SkyState.now(
                latitude: 37.8, longitude: -122.25,
                date: utc(2026, 9, 4, hour, 0), cloudCover: cover
            )
            let ratio = contrastRatio(state.palette.paper, state.palette.ink)
            #expect(ratio >= 4.5, "contrast \(ratio) at cover \(cover), hour \(hour)")
        }
    }
}
