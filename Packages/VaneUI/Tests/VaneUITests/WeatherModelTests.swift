import Foundation
import Testing
import VaneKit

@testable import VaneUI

/// The orchestration layer: cache-first launch, the decision to stay quiet when a refresh fails,
/// and the four screen states. This is the most breakable code in the app and had no tests —
/// every bug found by eye in phase 4 lived within one file of it.

@MainActor
final class FakeLocation: LocationProviding {
    var placeName: String?
    var next: LocationProvider.Status
    private(set) var requests = 0

    init(_ next: LocationProvider.Status) { self.next = next }

    func request(timeout: Duration) async -> LocationProvider.Status {
        requests += 1
        return next
    }
}

/// A URLProtocol that answers from memory, so no test touches the network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body: Data?
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var failure: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body = Self.body { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
private func makeModel(
    location: FakeLocation,
    directory: URL,
    payload: Data? = nil,
    failure: Error? = nil
) -> WeatherModel {
    StubProtocol.body = payload
    StubProtocol.failure = failure
    StubProtocol.status = 200

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    let client = VaneClient(
        baseURL: URL(string: "http://test.local")!, session: URLSession(configuration: configuration)
    )
    return WeatherModel(
        client: client,
        store: SnapshotStore(directory: directory),
        location: location,
        streaks: StreakStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    )
}

private func samplePayload() throws -> Data {
    // The same payload the contract tests decode — captured from the running backend.
    let url = try #require(Bundle.module.url(forResource: "snapshot", withExtension: "json"))
    return try Data(contentsOf: url)
}

@Suite(.serialized)
@MainActor
struct WeatherModelBehaviour {
    private func scratch() -> URL {
        URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func `a denied location with nothing cached asks for permission, not for a retry`() async {
        let model = makeModel(location: FakeLocation(.denied), directory: scratch())
        await model.refresh()
        #expect(model.screen == .locationDenied)
        #expect(model.snapshot == nil)
    }

    @Test func `a failed refresh with content on screen stays silent`() async throws {
        let directory = scratch()
        // Seed a cache the way a previous successful launch would have.
        let seeded = try VaneClient.decoder.decode(Snapshot.self, from: try samplePayload())
        SnapshotStore(directory: directory).save(seeded)

        let model = makeModel(
            location: FakeLocation(.located(latitude: 37.8, longitude: -122.25, name: "Oakland")),
            directory: directory,
            failure: URLError(.notConnectedToInternet)
        )
        // Cache-first: content exists before any request is made.
        #expect(model.snapshot != nil)

        await model.refresh()
        // The user is looking at the last known reading, which is what they wanted. An error
        // screen here would replace real information with an apology.
        #expect(model.screen == .content)
        #expect(model.snapshot != nil)
    }

    @Test func `an unreachable server with no cache surfaces the empty state`() async {
        let model = makeModel(
            location: FakeLocation(.located(latitude: 37.8, longitude: -122.25, name: nil)),
            directory: scratch(),
            failure: URLError(.cannotConnectToHost)
        )
        await model.refresh()
        #expect(model.screen == .unreachable)
        #expect(model.snapshot == nil)
    }

    @Test func `a successful refresh writes the cache for the next launch`() async throws {
        let directory = scratch()
        let model = makeModel(
            location: FakeLocation(.located(latitude: 37.8, longitude: -122.25, name: "Oakland")),
            directory: directory,
            payload: try samplePayload()
        )
        #expect(model.snapshot == nil, "nothing cached yet")

        await model.refresh()
        #expect(model.snapshot != nil)
        #expect(model.screen == .content)
        // Offline-first is only real if the next cold launch finds this.
        #expect(SnapshotStore(directory: directory).loadMostRecent() != nil)
    }

    @Test func `opening records a streak from the very first launch`() {
        let model = makeModel(location: FakeLocation(.notDetermined), directory: scratch())
        #expect(model.streak == 1)
    }
}
