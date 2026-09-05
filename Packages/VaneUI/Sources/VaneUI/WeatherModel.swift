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
    public private(set) var forecast: Forecast?
    public private(set) var screen: Screen = .content
    public private(set) var streak: Int

    /// Set once the context sentence has been on screen. The entry moment plays when a sentence
    /// *arrives*; re-rendering the same cached sentence several times a day is not a moment.
    public private(set) var hasPresentedContext = false

    /// Read through to the provider rather than snapshotting the name at fetch time: geocoding
    /// finishes after the coordinate does, so a copied value would stay "Here" forever.
    public var placeName: String? { location.placeName }

    private let client: VaneClient
    private let store: SnapshotStore
    private let location: any LocationProviding
    private let streaks: StreakStore

    public init(
        client: VaneClient,
        store: SnapshotStore = SnapshotStore(),
        location: any LocationProviding = LocationProvider(),
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
        case let .located(latitude, longitude, _):
            await load(latitude: latitude, longitude: longitude)
        }
    }

    private func load(latitude: Double, longitude: Double) async {
        do {
            // Two independent requests, so they run concurrently. The forecast is not on the
            // first-paint path, but making the screen wait for it in series would add a whole
            // round trip to a refresh nobody asked for.
            async let snapshotTask = client.snapshot(latitude: latitude, longitude: longitude)
            async let forecastTask = client.forecast(latitude: latitude, longitude: longitude)

            let fresh = try await snapshotTask
            store.save(fresh)
            snapshot = fresh
            screen = .content
            // The forecast failing must not cost us the snapshot we already have.
            forecast = try? await forecastTask
        } catch {
            // A failed refresh with content on screen is not an error the user needs told
            // about — they are looking at the last known reading, which is what they wanted.
            // It is only a failure when there is nothing to show.
            screen = snapshot == nil ? .unreachable : .content
        }
    }

    public func markContextPresented() { hasPresentedContext = true }

    /// The sky for this snapshot's own location, moment, and conditions.
    ///
    /// The brief is explicit that colour state comes from sun position *and current
    /// conditions*. `cloudCover` was a parameter from phase 3 that nothing ever passed, so
    /// until now every day rendered as though it were clear.
    public var sky: SkyState {
        guard let snapshot else {
            return SkyState.now(latitude: 0, longitude: 0)
        }
        let parts = snapshot.cellId.split(separator: ",").compactMap { Double($0) }
        return SkyState.now(
            latitude: parts.first ?? 0,
            longitude: parts.last ?? 0,
            date: .now,
            cloudCover: Double(snapshot.current.cloudCover ?? 0) / 100
        )
    }
}
