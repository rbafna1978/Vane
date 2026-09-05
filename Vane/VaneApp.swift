import SwiftUI
import VaneUI

@main
struct VaneApp: App {
    init() {
        // Fonts ship inside VaneUI's resource bundle, which iOS does not scan the way it scans
        // an app's Info.plist. Registering at launch is what makes Archivo Narrow and
        // JetBrains Mono resolvable by name anywhere in the app and its extensions.
        VaneFont.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
