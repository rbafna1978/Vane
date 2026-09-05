import Foundation

/// Where the sun actually is, from latitude, longitude and an instant.
///
/// This exists because the brief refuses a light/dark toggle: the interface's colour state is
/// computed from real sun position. It is pure arithmetic with no I/O, which is why it lives in
/// VaneKit as `nonisolated` static functions — the widget, the app, and the tests all call it
/// from wherever they happen to be running, and it keeps advancing the palette while offline.
///
/// Implements the NOAA solar position equations (the same ones behind NOAA's public solar
/// calculator). Accurate to well under a degree for any date this app will ever show, which is
/// far tighter than the eye can distinguish in a colour ramp.
public enum SunPosition {

    public struct Result: Sendable, Hashable {
        /// Degrees above the horizon. Negative after sunset.
        public let elevation: Double
        /// Degrees clockwise from true north.
        public let azimuth: Double
    }

    public static func at(latitude: Double, longitude: Double, date: Date) -> Result {
        // Julian Day, then Julian Century since J2000.0 — the time base every term below uses.
        // 2440587.5 is the Julian Day of the Unix epoch.
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545.0) / 36_525.0

        // Mean longitude and mean anomaly: where the sun would be if Earth's orbit were a
        // circle traversed at constant speed. Everything after this corrects that fiction.
        let meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.0003032))
            .truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)

        // Equation of the centre: the correction for the orbit being an ellipse, so the sun
        // runs ahead of the mean position near perihelion and behind it near aphelion.
        let m = meanAnomaly.radians
        let centre = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m) * (0.019993 - 0.000101 * t)
            + sin(3 * m) * 0.000289

        let trueLongitude = meanLongitude + centre
        // Nutation: the Moon's pull wobbles Earth's axis. Small, but it is the difference
        // between civil twilight starting on the right minute and the wrong one.
        let omega = (125.04 - 1_934.136 * t).radians
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(omega)

        // Obliquity: the tilt of Earth's axis. This single number is why there are seasons.
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = (meanObliquity + 0.00256 * cos(omega)).radians

        let declination = asin(sin(obliquity) * sin(apparentLongitude.radians))

        // Equation of time: apparent solar time minus mean clock time, in minutes. Runs about
        // ±16 minutes across the year, and omitting it visibly shifts the colour ramp.
        let y = pow(tan(obliquity / 2), 2)
        let l0 = meanLongitude.radians
        let equationOfTime = 4 * (
            y * sin(2 * l0)
            - 2 * eccentricity * sin(m)
            + 4 * eccentricity * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0)
            - 1.25 * eccentricity * eccentricity * sin(2 * m)
        ).degrees

        // Work in UTC and fold the longitude in directly: 4 minutes of solar time per degree.
        // This sidesteps time zones entirely, which is what makes the result correct for a
        // coordinate rather than for whatever zone the phone happens to be set to.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = utc.dateComponents([.hour, .minute, .second], from: date)
        let minutesUTC = Double(parts.hour ?? 0) * 60 + Double(parts.minute ?? 0)
            + Double(parts.second ?? 0) / 60

        var trueSolarMinutes = (minutesUTC + equationOfTime + 4 * longitude)
            .truncatingRemainder(dividingBy: 1_440)
        // truncatingRemainder keeps the sign of the dividend, so a western longitude leaves
        // this negative and the hour angle lands outside [-180, 180]. Elevation survives that
        // (cosine is periodic) but the azimuth branch below tests the *sign* of the hour angle
        // to decide morning from afternoon — so an unnormalised value runs the sun backwards
        // across the sky after noon. Normalise first.
        if trueSolarMinutes < 0 { trueSolarMinutes += 1_440 }

        // Hour angle: 0 at local solar noon, negative in the morning, +15 degrees per hour.
        // Now guaranteed to be in [-180, 180).
        let hourAngleDegrees = trueSolarMinutes / 4 - 180
        let hourAngle = hourAngleDegrees.radians

        let lat = latitude.radians
        let cosZenith = sin(lat) * sin(declination)
            + cos(lat) * cos(declination) * cos(hourAngle)
        let zenith = acos(min(1, max(-1, cosZenith)))
        let elevation = (.pi / 2 - zenith).degrees

        // Azimuth is undefined straight overhead; clamp rather than hand back a NaN that would
        // propagate into a colour and paint the screen black.
        let denominator = cos(lat) * sin(zenith)
        var azimuth: Double
        if abs(denominator) < 1e-9 {
            azimuth = 180
        } else {
            let cosAzimuth = (sin(lat) * cos(zenith) - sin(declination)) / denominator
            azimuth = acos(min(1, max(-1, cosAzimuth))).degrees
            azimuth = hourAngleDegrees > 0
                ? (azimuth + 180).truncatingRemainder(dividingBy: 360)
                : (540 - azimuth).truncatingRemainder(dividingBy: 360)
        }

        return Result(elevation: elevation + refraction(apparent: elevation), azimuth: azimuth)
    }

    /// Atmospheric refraction lifts the sun's apparent position near the horizon by roughly
    /// half a degree — which is most of why sunset is later than geometry alone predicts, and
    /// it matters here because the twilight thresholds sit exactly in that range.
    private static func refraction(apparent elevation: Double) -> Double {
        guard elevation < 85 else { return 0 }
        let e = elevation.radians
        let arcseconds: Double
        switch elevation {
        case 5...:
            arcseconds = 58.1 / tan(e) - 0.07 / pow(tan(e), 3) + 0.000086 / pow(tan(e), 5)
        case -0.575..<5:
            arcseconds = 1_735 + elevation
                * (-518.2 + elevation * (103.4 + elevation * (-12.79 + elevation * 0.711)))
        default:
            arcseconds = -20.772 / tan(e)
        }
        return arcseconds / 3_600
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
