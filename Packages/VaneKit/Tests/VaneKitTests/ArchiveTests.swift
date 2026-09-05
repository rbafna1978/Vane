import Foundation
import Testing

@testable import VaneKit

/// Compression is the archive's defining interaction and it runs under a finger. These tests are
/// about the aggregation being correct, because a wrong average is a lie about someone's own
/// history that they have no way to check.

private func store() throws -> ArchiveStore { try ArchiveStore() }

private func entry(_ day: String, tmax: Double, tmin: Double, precip: Double = 0,
                   normal: Double? = nil) -> ArchiveEntry {
    ArchiveEntry(day: day, cellId: "37.75,-122.25", tmaxC: tmax, tminC: tmin,
                 precipMm: precip, normalTmaxC: normal, code: 0)
}

@Test func `recording the same day twice keeps one row`() throws {
    let archive = try store()
    try archive.record(entry("2026-09-05", tmax: 20, tmin: 12))
    try archive.record(entry("2026-09-05", tmax: 22, tmin: 13))

    #expect(try archive.count() == 1)
    // The later write wins: opening again after the cell warmed should improve the row, not
    // duplicate it or leave the earlier, poorer version in place.
    #expect(try archive.entry(day: "2026-09-05")?.tmaxC == 22)
}

@Test func `daily scale returns one point per day, oldest first`() throws {
    let archive = try store()
    for day in 1...5 {
        try archive.record(entry(String(format: "2026-09-%02d", day), tmax: Double(20 + day), tmin: 10))
    }
    let points = try archive.points(scale: .day)
    #expect(points.count == 5)
    #expect(points.first?.day == "2026-09-01")
    #expect(points.last?.day == "2026-09-05")
    #expect(points.allSatisfy { $0.span == 1 })
}

@Test func `weekly scale averages the days inside each week`() throws {
    let archive = try store()
    // Two full ISO weeks with known means: 10 and 20.
    for day in 5...11 { try archive.record(entry(String(format: "2026-01-%02d", day), tmax: 10, tmin: 5)) }
    for day in 12...18 { try archive.record(entry(String(format: "2026-01-%02d", day), tmax: 20, tmin: 8)) }

    let points = try archive.points(scale: .week)
    #expect(points.count == 2)
    #expect(points[0].tmaxC == 10)
    #expect(points[1].tmaxC == 20)
    #expect(points.allSatisfy { $0.span == 7 })
}

@Test func `precipitation sums across a compressed span rather than averaging`() throws {
    let archive = try store()
    // Rainfall is a total, not a rate. Averaging it would report a wet week as a damp day.
    for day in 5...11 {
        try archive.record(entry(String(format: "2026-01-%02d", day), tmax: 10, tmin: 5, precip: 2))
    }
    let week = try #require(try archive.points(scale: .week).first)
    #expect(week.precipMm == 14)
}

@Test func `anomaly is nil when the day has no normal to compare against`() throws {
    let archive = try store()
    try archive.record(entry("2026-09-05", tmax: 30, tmin: 15))
    try archive.record(entry("2026-09-06", tmax: 30, tmin: 15, normal: 24))

    let points = try archive.points(scale: .day)
    #expect(points[0].anomaly == nil, "a cold cell has no comparison and must not invent one")
    #expect(points[1].anomaly == 6)
}

@Test(arguments: [(1, ArchiveStore.Scale.day), (44, .day), (45, .week),
                  (399, .week), (400, .month), (5_000, .month)])
func `scale compresses as more history has to fit`(days: Int, expected: ArchiveStore.Scale) {
    #expect(ArchiveStore.scale(forDays: days) == expected)
}

@Test func `an empty archive is an empty list, not a crash`() throws {
    let archive = try store()
    #expect(try archive.points(scale: .day).isEmpty)
    #expect(try archive.count() == 0)
}
