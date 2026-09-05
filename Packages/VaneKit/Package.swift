// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VaneKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "VaneKit", targets: ["VaneKit"])],
    targets: [
        // Deliberately NOT main-actor-by-default. VaneKit is a library: it ships nonisolated
        // APIs and lets the caller decide where work runs. The app and VaneUI opt into
        // MainActor isolation; forcing it down here would drag the widget extension and the
        // sun engine onto the main actor for no reason.
        .target(name: "VaneKit"),
        .testTarget(
            name: "VaneKitTests",
            dependencies: ["VaneKit"],
            // A payload captured from the running backend. Decoding it in a test is what
            // catches contract drift — a renamed field shows up here, not on a blank screen.
            resources: [.process("snapshot.json")]
        ),
    ]
)
