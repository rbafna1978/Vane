import Foundation
import Testing

@testable import VaneKit

/// Validated against physical invariants and against Open-Meteo's own published sunrise and
/// sunset times — an independent source, so agreement is evidence rather than self-consistency.
private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents()
    (c.year, c.month, c.day, c.hour, c.minute) = (y, mo, d, h, mi)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    return cal.date(from: c)!
}

@Test func `sun sits on the horizon at published sunrise and sunset`() {
    // Oakland, 2026-09-04. Open-Meteo: sunrise 06:42, sunset 19:33 local (UTC-7).
    let lat = 37.8044, lon = -122.2712
    let sunrise = SunPosition.at(latitude: lat, longitude: lon, date: utc(2026, 9, 4, 13, 42))
    let sunset = SunPosition.at(latitude: lat, longitude: lon, date: utc(2026, 9, 5, 2, 33))
    #expect(abs(sunrise.elevation) < 1.0)
    #expect(abs(sunset.elevation) < 1.0)
}

@Test func `sun is nearly overhead at the equator on the equinox`() {
    // Solar noon at 0N/0E on the March equinox: the subsolar point is on the equator.
    let noon = SunPosition.at(latitude: 0, longitude: 0, date: utc(2026, 3, 20, 12, 7))
    #expect(noon.elevation > 89.0)
}

@Test func `sun reaches the zenith over the Tropic of Cancer at the solstice`() {
    let noon = SunPosition.at(latitude: 23.4368, longitude: 0, date: utc(2026, 6, 21, 12, 2))
    #expect(noon.elevation > 89.0)
}

@Test func `sun is due south at local solar noon in the northern hemisphere`() {
    let noon = SunPosition.at(latitude: 51.5, longitude: 0, date: utc(2026, 6, 21, 12, 2))
    #expect(abs(noon.azimuth - 180) < 2.0)
}

@Test func `sun is due north at local solar noon in the southern hemisphere`() {
    let noon = SunPosition.at(latitude: -33.87, longitude: 151.21, date: utc(2026, 6, 21, 1, 56))
    let fromNorth = min(noon.azimuth, 360 - noon.azimuth)
    #expect(fromNorth < 3.0)
}

@Test func `polar night keeps the sun below the horizon all day`() {
    // Svalbard in December. If any hour reads positive, the declination sign is wrong.
    for hour in 0..<24 {
        let p = SunPosition.at(latitude: 78.22, longitude: 15.65, date: utc(2026, 12, 21, hour, 0))
        #expect(p.elevation < 0, "hour \(hour) should be dark")
    }
}

@Test func `midnight sun keeps the sun above the horizon all day`() {
    for hour in 0..<24 {
        let p = SunPosition.at(latitude: 78.22, longitude: 15.65, date: utc(2026, 6, 21, hour, 0))
        #expect(p.elevation > 0, "hour \(hour) should be lit")
    }
}

@Test func `elevation peaks once a day and never returns a NaN`() {
    // Windowed on the LOCAL day (00:00 PDT = 07:00 UTC). A UTC-day window over a Pacific
    // location spans two local afternoons and genuinely contains two descents.
    var previous = -90.0
    var rising = true
    var peaks = 0
    for minute in stride(from: 0, to: 1_440, by: 10) {
        let p = SunPosition.at(
            latitude: 37.8, longitude: -122.25,
            date: utc(2026, 9, 4, 7, 0).addingTimeInterval(Double(minute) * 60)
        )
        #expect(!p.elevation.isNaN && !p.azimuth.isNaN)
        #expect((0...360).contains(p.azimuth))
        if p.elevation > 0 {
            if p.elevation < previous, rising { peaks += 1; rising = false }
            if p.elevation > previous { rising = true }
        }
        previous = p.elevation
    }
    #expect(peaks == 1)
}

@Test func `azimuth advances westward through the day and never runs backwards`() {
    // Regression. An unnormalised hour angle sends the azimuth from 242 degrees back to 105
    // in the late afternoon — the sun running east while it sets. The wash colour is driven
    // by azimuth, so this lit the interface from the wrong side of the sky.
    var previous = -1.0
    var readings: [Double] = []
    for minute in stride(from: 0, to: 1_440, by: 10) {
        let p = SunPosition.at(
            latitude: 37.8, longitude: -122.25,
            date: utc(2026, 9, 4, 7, 0).addingTimeInterval(Double(minute) * 60)
        )
        readings.append(p.azimuth)
    }
    // Azimuth increases monotonically through a local day, wrapping through 360 at most once.
    var wraps = 0
    for value in readings {
        if previous >= 0, value < previous { wraps += 1 }
        previous = value
    }
    #expect(wraps <= 1, "azimuth reversed \(wraps) times; it should wrap at most once")
}
