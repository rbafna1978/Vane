import SwiftUI
import VaneKit
import VaneUI

struct ContentView: View {
    @State private var model = WeatherModel(client: VaneClient(baseURL: .vaneBackend))

    var body: some View {
        MainScreen(model: model)
    }
}

extension URL {
    /// Local Docker Compose. Phase 7 swaps this for the deployed host; deployment is
    /// deliberately deferred until the push loop needs it.
    static let vaneBackend = URL(string: "http://localhost:8000")!
}

#Preview { ContentView() }
