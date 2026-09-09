import SwiftUI
import VaneKit
import VaneUI

struct ContentView: View {
    @State private var model = WeatherModel(client: VaneClient(baseURL: .vaneBackend))

    var body: some View {
        VaneScreen(model: model)
    }
}

extension URL {
    /// Read from the bundle, not hardcoded.
    ///
    /// `VaneBackendURL` lives in `VaneInfo.plist` rather than in a build setting: the
    /// `INFOPLIST_KEY_` mechanism only honours Apple's own allowlist and silently drops custom
    /// keys, so for four phases this key never reached the bundle and every Release build would
    /// have hit the `fatalError` below at launch.
    static var vaneBackend: URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "VaneBackendURL") as? String
        guard let configured, let url = URL(string: configured), url.host() != nil else {
            #if DEBUG
            return URL(string: "http://localhost:8000")!
            #else
            fatalError("VaneBackendURL is missing from Info.plist for a Release build")
            #endif
        }
        return url
    }
}

#Preview { ContentView() }
