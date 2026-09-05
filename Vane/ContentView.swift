import SwiftUI
import VaneKit
import VaneUI

struct ContentView: View {
    @State private var model = WeatherModel(client: VaneClient(baseURL: .vaneBackend))

    var body: some View {
        RollScreen(model: model)
    }
}

extension URL {
    /// Read from the bundle, not hardcoded.
    ///
    /// `VANE_BACKEND_URL` comes from the build settings, so a Release build cannot inherit the
    /// developer's `localhost`. A TestFlight build pointing at localhost is not a degraded app,
    /// it is a dead one, and a constant in source is nothing standing in the way of that.
    static var vaneBackend: URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "VaneBackendURL") as? String
        guard let configured, let url = URL(string: configured), url.host() != nil else {
            #if DEBUG
            return URL(string: "http://localhost:8000")!
            #else
            // A release build with no backend configured is a build mistake, not a runtime
            // condition to paper over — fail loudly at launch rather than silently offline.
            fatalError("VaneBackendURL is missing from Info.plist for a Release build")
            #endif
        }
        return url
    }
}

#Preview { ContentView() }
