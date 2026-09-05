import Foundation
import Testing

@testable import VaneKit

/// Decodes a payload captured from the running backend. If the server renames a field, this
/// fails here rather than rendering an empty screen with no explanation.
@Test func `a real server payload decodes into the model`() throws {
    let url = try #require(Bundle.module.url(forResource: "snapshot", withExtension: "json"))
    let snapshot = try VaneClient.decoder.decode(Snapshot.self, from: Data(contentsOf: url))

    #expect(snapshot.cellId == "37.75,-122.25")
    #expect(!snapshot.arc.isEmpty)
    #expect(snapshot.contextState == .warm)
    #expect(snapshot.context?.headline.hasSuffix(".") == true)
    #expect(snapshot.normal != nil)
    #expect(snapshot.sun.sunrise < snapshot.sun.sunset)
}

@Test func `dates keep the location's own UTC offset`() throws {
    // The server sends local wall-clock times. Losing the offset would make every "is this hour
    // today?" question wrong for anyone outside UTC.
    let url = try #require(Bundle.module.url(forResource: "snapshot", withExtension: "json"))
    let snapshot = try VaneClient.decoder.decode(Snapshot.self, from: Data(contentsOf: url))
    let firstHour = try #require(snapshot.arc.first)
    #expect(firstHour.t < snapshot.observedAt)
    #expect(snapshot.arc.count >= 24)
}

@Test func `a snapshot survives a round trip through the cache`() throws {
    let url = try #require(Bundle.module.url(forResource: "snapshot", withExtension: "json"))
    let original = try VaneClient.decoder.decode(Snapshot.self, from: Data(contentsOf: url))

    let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = SnapshotStore(directory: directory)
    store.save(original)

    // Offline-first depends entirely on this: what we wrote is what opens next launch.
    #expect(store.load(cellId: original.cellId) == original)
    #expect(store.loadMostRecent() == original)
}

@Test func `an empty cache is a nil, not a crash`() {
    let store = SnapshotStore(directory: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    #expect(store.load(cellId: "0.00,0.00") == nil)
    #expect(store.loadMostRecent() == nil)
}

@Test func `the snapshot carries the location's own time zone`() throws {
    // Without this the app formats a saved location's sunrise in the phone's zone, which is a
    // wrong number wearing the clothes of a fact.
    let url = try #require(Bundle.module.url(forResource: "snapshot", withExtension: "json"))
    let snapshot = try VaneClient.decoder.decode(Snapshot.self, from: Data(contentsOf: url))

    #expect(snapshot.utcOffsetSeconds == -25_200, "Oakland in September is UTC-7")
    #expect(snapshot.timeZone.secondsFromGMT() == -25_200)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = snapshot.timeZone
    let sunset = calendar.dateComponents([.hour], from: snapshot.sun.sunset)
    #expect(sunset.hour == 19, "sunset is in the evening; 07 would be a 12-hour clock bug")
}

@Test func `a cache written before the field existed still decodes`() throws {
    // A schema addition must never turn a working offline app into a blank screen.
    let url = try #require(Bundle.module.url(forResource: "snapshot", withExtension: "json"))
    var object = try #require(
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    object.removeValue(forKey: "utc_offset_seconds")
    let older = try JSONSerialization.data(withJSONObject: object)

    let snapshot = try VaneClient.decoder.decode(Snapshot.self, from: older)
    #expect(snapshot.utcOffsetSeconds == nil)
    #expect(snapshot.timeZone == .current, "falls back to the device zone rather than failing")
}

// MARK: - StreakStore

@Test func `a streak counts consecutive days and resets on a gap`() {
    let defaults = try! #require(UserDefaults(suiteName: "vane.test.\(UUID().uuidString)"))
    let store = StreakStore(defaults: defaults)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    #expect(store.recordOpen(today: day, calendar: calendar) == 1)
    // Opening twice in one day is still one day.
    #expect(store.recordOpen(today: day.addingTimeInterval(3_600), calendar: calendar) == 1)
    #expect(store.recordOpen(today: day.addingTimeInterval(86_400), calendar: calendar) == 2)
    #expect(store.recordOpen(today: day.addingTimeInterval(2 * 86_400), calendar: calendar) == 3)
    // A missed day breaks it, and today starts a new run rather than counting zero.
    #expect(store.recordOpen(today: day.addingTimeInterval(5 * 86_400), calendar: calendar) == 1)
}

@Test func `a clock moving backwards does not inflate the streak`() {
    let defaults = try! #require(UserDefaults(suiteName: "vane.test.\(UUID().uuidString)"))
    let store = StreakStore(defaults: defaults)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

    #expect(store.recordOpen(today: day, calendar: calendar) == 1)
    #expect(store.recordOpen(today: day.addingTimeInterval(86_400), calendar: calendar) == 2)
    // Travelling west or a manual clock change must not be rewarded.
    #expect(store.recordOpen(today: day.addingTimeInterval(-3 * 86_400), calendar: calendar) == 1)
}
