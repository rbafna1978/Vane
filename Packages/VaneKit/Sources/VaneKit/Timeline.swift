import Foundation

/// One roll of paper, from the first day recorded to the last day forecast.
///
/// The app is not three screens. It is a single strip where the horizontal axis is time — past
/// to the left, future to the right — and the pen sits at today. Everything the interface shows
/// is a function of where you are on this strip, which is why the strip is a model rather than
/// something each view assembles for itself.
public struct TimelineMark: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable { case recorded, today, forecast }

    /// Days from today. Negative is the past. Fractional within today's own hours.
    public let offset: Double
    public let dayKey: String
    public let highC: Double
    public let lowC: Double?
    public let normalHighC: Double?
    public let normalLowC: Double?
    public let precipMm: Double
    public let code: Int
    public let headline: String?
    public let kind: Kind

    public var id: String { "\(kind)-\(dayKey)-\(offset)" }

    public var anomaly: Double? { normalHighC.map { highC - $0 } }
}

public enum Timeline {
    /// Merge the record, today, and the forecast into one ordered strip.
    ///
    /// Today is deliberately a *single* mark here rather than its 24 hourly points: the strip is
    /// a day scale, and mixing resolutions on one axis would make today twenty-four times wider
    /// than yesterday for no reason the eye could explain. The hourly detail belongs to today's
    /// own chart, which is a different instrument.
    public static func build(
        archive: [ArchivePoint],
        snapshot: Snapshot?,
        forecast: Forecast?
    ) -> [TimelineMark] {
        var marks: [TimelineMark] = []

        // One zone throughout: the location's own. Archive keys are written in it, so parsing
        // them in UTC would put every day one boundary out for anyone west of Greenwich — the
        // same mismatch that has bitten every date in this app at least once.
        let zone = snapshot?.timeZone ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = calendar.startOfDay(for: snapshot?.observedAt ?? .now)

        let dayFormatter = Timeline.dayFormatter(in: zone)

        func offset(ofDayKey key: String) -> Double? {
            guard let date = dayFormatter.date(from: key) else { return nil }
            let day = calendar.startOfDay(for: date)
            return Double(calendar.dateComponents([.day], from: today, to: day).day ?? 0)
        }

        let todayKey = dayFormatter.string(from: today)

        for point in archive where point.day != todayKey {
            guard let offset = offset(ofDayKey: point.day), offset < 0 else { continue }
            marks.append(TimelineMark(
                offset: offset, dayKey: point.day, highC: point.tmaxC, lowC: point.tminC,
                normalHighC: point.normalTmaxC, normalLowC: nil,
                precipMm: point.precipMm, code: 0, headline: nil, kind: .recorded
            ))
        }

        if let snapshot {
            marks.append(TimelineMark(
                offset: 0, dayKey: todayKey,
                highC: snapshot.arc.map(\.tempC).max() ?? snapshot.current.tempC,
                lowC: snapshot.arc.map(\.tempC).min(),
                normalHighC: snapshot.normal?.tmaxC, normalLowC: snapshot.normal?.tminC,
                precipMm: snapshot.arc.reduce(0) { $0 + $1.precipMm },
                code: snapshot.current.code, headline: snapshot.context?.headline, kind: .today
            ))
        }

        for day in forecast?.daily ?? [] {
            let key = dayFormatter.string(from: day.d)
            guard key != todayKey, let offset = offset(ofDayKey: key), offset > 0 else { continue }
            marks.append(TimelineMark(
                offset: offset, dayKey: key, highC: day.tmaxC, lowC: day.tminC,
                normalHighC: day.normal?.tmaxC, normalLowC: day.normal?.tminC,
                precipMm: day.precipMm, code: day.code, headline: nil, kind: .forecast
            ))
        }

        return marks.sorted { $0.offset < $1.offset }
    }

    /// Built per call rather than shared: `DateFormatter` is a mutable class, and a shared one
    /// whose time zone is reassigned is a data race waiting for a second location.
    public static func dayFormatter(in zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        return formatter
    }
}
