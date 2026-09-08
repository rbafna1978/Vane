import Foundation
import Testing
@testable import VaneKit

@Suite("Marks as displayed")
struct TimelineMarkTests {
    private func mark(high: Double, normal: Double?) -> TimelineMark {
        TimelineMark(
            offset: 0, dayKey: "2026-09-08", highC: high, lowC: nil,
            normalHighC: normal, normalLowC: nil, precipMm: 0, code: 0,
            headline: nil, kind: .today
        )
    }

    /// The panel showed "23°" against "NORMAL 27°" and labelled the difference "-3°", because
    /// the true values were 23.4 and 26.6 and each was rounded on its own. Every figure on
    /// screen has to survive being checked with arithmetic.
    @Test func `the shown difference matches the shown readings`() {
        let m = mark(high: 23.4, normal: 26.6)
        #expect(Int(m.highC.rounded()) == 23)
        #expect(Int(m.normalHighC!.rounded()) == 27)
        #expect(m.displayAnomaly == -4)
        // The precise measure is untouched, for anything that measures rather than displays.
        #expect(abs(m.anomaly! - -3.2) < 0.0001)
    }

    @Test func `a day on the mark reads as zero`() {
        #expect(mark(high: 26.4, normal: 26.2).displayAnomaly == 0)
    }

    @Test func `a day with no normal has no difference`() {
        #expect(mark(high: 23, normal: nil).displayAnomaly == nil)
        #expect(mark(high: 23, normal: nil).anomaly == nil)
    }

    /// Marks are sparse — the record only holds days the app was open — so the strip runs
    /// -3, 0, 1, 2 and not -3, -2, -1, 0. Anything that treats position in the array as a day
    /// offset puts the header on a different day from the pen.
    @Test func `the record is sparse and offsets are not indices`() {
        let archive = [
            ArchivePoint(day: "2026-09-05", tmaxC: 23, tminC: 12,
                         normalTmaxC: 27, precipMm: 0, span: 1)
        ]
        let marks = Timeline.build(archive: archive, snapshot: nil, forecast: nil)
        #expect(marks.count == 1)
        // Three days back, at array index zero.
        let today = Calendar(identifier: .gregorian).startOfDay(for: .now)
        let expected = Calendar(identifier: .gregorian).dateComponents(
            [.day],
            from: today,
            to: Timeline.dayFormatter(in: .current).date(from: "2026-09-05")!
        ).day!
        #expect(marks[0].offset == Double(expected))
    }
}
