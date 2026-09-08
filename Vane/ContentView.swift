import SwiftUI
import VaneKit
import VaneUI

struct ContentView: View {
    @State private var model = WeatherModel(client: VaneClient(baseURL: .vaneBackend))

    var body: some View {
        #if DEBUG
        // `xcrun simctl launch <device> <bundle> -VaneCatalog YES` opens the design system
        // instead of the app. The `-Key Value` form is read straight out of `UserDefaults`,
        // which is what launch arguments are for; a bare `--catalog` never arrives, because
        // simctl treats a leading double dash as its own option.
        //
        // Debug only. It exists so rendering paths that need weather we cannot summon — rain, a
        // gale, an overcast midnight — can be looked at rather than assumed.
        if UserDefaults.standard.bool(forKey: "VaneCatalog") {
            Catalog()
        } else {
            VaneScreen(model: model)
        }
        #else
        VaneScreen(model: model)
        #endif
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
