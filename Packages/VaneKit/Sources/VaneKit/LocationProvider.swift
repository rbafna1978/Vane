import CoreLocation
import Foundation

/// Where the phone is.
///
/// `@MainActor` on purpose, and the one place in VaneKit that is: `CLLocationManager` is not
/// `Sendable` and delivers its callbacks on the thread its delegate was set up on. Pinning it
/// to the main actor is honest about that, rather than promising thread-safety with an
/// `@unchecked Sendable` the compiler cannot verify.
@MainActor
public final class LocationProvider: NSObject {
    public enum Status: Sendable, Equatable {
        case notDetermined, denied, unavailable
        case located(latitude: Double, longitude: Double, name: String?)
    }

    private let manager = CLLocationManager()
    private var pending: [CheckedContinuation<Status, Never>] = []

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
    public func request() async -> Status {
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
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
        }
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

    private func name(for location: CLLocation, coordinate: CLLocationCoordinate2D) async {
        // A place name is a nicety; failing to get one must never cost us the location itself.
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = [placemark?.locality, placemark?.administrativeArea]
            .compactMap { $0 }.joined(separator: ", ")
        resolve(.located(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: name.isEmpty ? nil : name
        ))
    }
}
