import Foundation

/// Consecutive days opened.
///
/// Local, because the server has no `/v1/archive/open` yet — that lands with the push loop.
/// Lives in VaneKit rather than VaneUI: it is persistence and calendar arithmetic with no view
/// in it, and the widget will want the same count.
///
/// Kept deliberately quiet in the UI: a streak that nags is a streak people delete the app to
/// escape.
/// Not `Sendable`: `UserDefaults` is documented as thread-safe but is not marked `Sendable`,
/// and claiming the conformance would need `@unchecked`, which is a promise the compiler cannot
/// check. Nothing needs to send this across an isolation boundary, so it does not claim it.
public struct StreakStore {
    private let defaults: UserDefaults
    private let lastKey = "vane.streak.lastOpen"
    private let countKey = "vane.streak.count"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    @discardableResult
    public func recordOpen(today: Date = .now, calendar: Calendar = .current) -> Int {
        let day = calendar.startOfDay(for: today)
        let previous = defaults.object(forKey: lastKey) as? Date
        var count = defaults.integer(forKey: countKey)

        if let previous {
            let last = calendar.startOfDay(for: previous)
            let gap = calendar.dateComponents([.day], from: last, to: day).day ?? 0
            switch gap {
            case 0: return max(count, 1)      // already counted today
            case 1: count += 1                 // consecutive
            default: count = 1                 // streak broken; today starts a new one
            }
        } else {
            count = 1
        }

        defaults.set(day, forKey: lastKey)
        defaults.set(count, forKey: countKey)
        return count
    }
}
