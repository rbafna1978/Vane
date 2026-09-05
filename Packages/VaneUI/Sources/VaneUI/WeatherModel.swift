import Foundation
import Observation
import SwiftUI
import VaneKit

/// The seam between the screen and everything asynchronous.
///
/// The view stays synchronous and dumb; this owns the order things happen in. That order is the
/// whole offline-first promise: **cache first, synchronously, in `init`** — so the first frame
/// the screen ever draws already has content in it. Nothing here can produce a launch spinner,
/// because there is no state that means "waiting" when a cache exists.
@Observable
@MainActor
public final class WeatherModel {
    public enum Screen: Equatable {
        case content
        case needsLocation
        case locationDenied
        case unreachable
    }

    public private(set) var snapshot: Snapshot?
    public private(set) var placeName: String?
    public private(set) var screen: Screen = .content
    public private(set) var streak: Int

    /// Set once the context sentence has been on screen. The entry moment plays when a sentence
    /// *arrives*; re-rendering the same cached sentence several times a day is not a moment.
    public private(set) var hasPresentedContext = false

    private let client: VaneClient
    private let store: SnapshotStore
    private let location: LocationProvider
    private let streaks: StreakStore

    public init(
        client: VaneClient,
        store: SnapshotStore = SnapshotStore(),
        location: LocationProvider = LocationProvider(),
        streaks: StreakStore = StreakStore()
    ) {
        self.client = client
        self.store = store
        self.location = location
        self.streaks = streaks

        // Synchronous, before the first frame. This is the line that makes the app open
        // instantly instead of showing a spinner and then content.
        self.snapshot = store.loadMostRecent()
        self.streak = streaks.recordOpen()
        self.hasPresentedContext = self.snapshot?.context != nil
    }

    public func refresh() async {
        let status = await location.request()
        switch status {
        case .notDetermined:
            screen = snapshot == nil ? .needsLocation : .content
        case .denied:
            screen = snapshot == nil ? .locationDenied : .content
        case .unavailable:
            screen = snapshot == nil ? .unreachable : .content
        case let .located(latitude, longitude, name):
            placeName = name ?? placeName
            await load(latitude: latitude, longitude: longitude)
        }
    }

    private func load(latitude: Double, longitude: Double) async {
        do {
            let fresh = try await client.snapshot(latitude: latitude, longitude: longitude)
            store.save(fresh)
            snapshot = fresh
            screen = .content
        } catch {
            // A failed refresh with content on screen is not an error the user needs told
            // about — they are looking at the last known reading, which is what they wanted.
            // It is only a failure when there is nothing to show.
            screen = snapshot == nil ? .unreachable : .content
        }
    }

    public func markContextPresented() { hasPresentedContext = true }

    /// The sky for this snapshot's own location and moment, not the device's.
    public var sky: SkyState {
        guard let snapshot else {
            return SkyState.now(latitude: 0, longitude: 0)
        }
        let parts = snapshot.cellId.split(separator: ",").compactMap { Double($0) }
        return SkyState.now(
            latitude: parts.first ?? 0, longitude: parts.last ?? 0, date: .now
        )
    }
}

/// Consecutive days opened. Local, because the server has no `/v1/archive/open` yet — that
/// lands with the push loop. Kept deliberately quiet in the UI: a streak that nags is a streak
/// people delete the app to escape.
public struct StreakStore: Sendable {
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
