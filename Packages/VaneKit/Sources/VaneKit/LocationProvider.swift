import CoreLocation
import Foundation
import Observation

/// Where the phone is.
///
/// `@MainActor` on purpose, and the one place in VaneKit that is: `CLLocationManager` is not
/// `Sendable` and delivers its callbacks on the thread its delegate was set up on. Pinning it
/// to the main actor is honest about that, rather than promising thread-safety with an
/// `@unchecked Sendable` the compiler cannot verify.
/// The seam the model is tested through. Only the hardware-touching part is behind a protocol;
/// the client and the cache already take injectable collaborators.
@MainActor
public protocol LocationProviding: AnyObject {
    var placeName: String? { get }
    func request(timeout: Duration) async -> LocationProvider.Status
}

public extension LocationProviding {
    func request() async -> LocationProvider.Status { await request(timeout: .seconds(12)) }
}

/// `@Observable` so the place name can arrive *after* the coordinate and still reach the screen.
/// Resolving the fix immediately is what stops a slow geocoder holding up the weather, but it
/// means the name lands later — and without observation it would land nowhere.
@Observable
@MainActor
public final class LocationProvider: NSObject, LocationProviding {
    public enum Status: Sendable, Equatable {
        case notDetermined, denied, unavailable
        case located(latitude: Double, longitude: Double, name: String?)
    }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var pending: [CheckedContinuation<Status, Never>] = []
    /// Kept across fixes so a momentary geocoder failure does not blank a name we already had.
    @ObservationIgnored private var lastName: String?

    /// The place name, once it is known. Nil until reverse geocoding returns, which is after
    /// the coordinate and sometimes never.
    public var placeName: String? {
        if case let .located(_, _, name) = status { return name }
        return nil
    }

    public private(set) var status: Status = .notDetermined

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Ask once, and resolve when the answer arrives.
    ///
    /// Accuracy is deliberately coarse: everything downstream snaps to a 0.25 degree cell
    /// (~25km), so requesting anything finer would collect precision we discard and would make
    /// the privacy label worse for nothing.
    public func request(timeout: Duration = .seconds(12)) async -> Status {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            status = .denied
            return .denied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }

        manager.requestLocation()

        // A permission dialog nobody answers produces no delegate callback at all, and the
        // continuation would never resume — hanging `refresh()`, and with it the caller's
        // `.task`, for the lifetime of the process. This timer is the only thing standing
        // between an ignored alert and a permanently pending task. It resolves the waiting
        // continuation rather than racing it, so there is exactly one resume on every path.
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.resolveIfPending(.notDetermined)
        }
        defer { timer.cancel() }

        return await withCheckedContinuation { continuation in
            pending.append(continuation)
        }
    }

    private func resolveIfPending(_ status: Status) {
        guard !pending.isEmpty else { return }
        resolve(status)
    }

    private func resolve(_ status: Status) {
        self.status = status
        // Every continuation must resume exactly once. Draining the array before resuming
        // means a delegate callback arriving twice cannot resume the same one again, which
        // would be a hard crash rather than a bug.
        let waiting = pending
        pending.removeAll()
        for continuation in waiting { continuation.resume(returning: status) }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated public func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        MainActor.assumeIsolated {
            _ = Task { await self.name(for: location, coordinate: coordinate) }
        }
    }

    nonisolated public func locationManager(
        _ manager: CLLocationManager, didFailWithError error: Error
    ) {
        MainActor.assumeIsolated { self.resolve(.unavailable) }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read the value here, then hop with the value only. Sending the manager itself across
        // the isolation boundary is a real race — it is a non-Sendable reference arriving from
        // an isolation domain we do not control.
        let authorization = manager.authorizationStatus
        MainActor.assumeIsolated {
            switch authorization {
            case .denied, .restricted: self.resolve(.denied)
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            default: break
            }
        }
    }

    /// The coordinate resolves immediately; the place name catches up.
    ///
    /// The previous version awaited reverse geocoding *before* resolving, which meant a slow or
    /// hanging `CLGeocoder` held up the weather fetch — the whole screen waiting on a label.
    /// The comment claimed a failed name must never cost us the location; the code did exactly
    /// that. Now the fix lands first and `placeName` is filled in after, if it arrives at all.
    private func name(for location: CLLocation, coordinate: CLLocationCoordinate2D) async {
        resolve(.located(
            latitude: coordinate.latitude, longitude: coordinate.longitude, name: lastName
        ))

        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = [placemark?.locality, placemark?.administrativeArea]
            .compactMap { $0 }.joined(separator: ", ")
        if !name.isEmpty {
            lastName = name
            if case let .located(latitude, longitude, _) = status {
                status = .located(latitude: latitude, longitude: longitude, name: name)
            }
        }
    }
}
