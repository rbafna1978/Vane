// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VaneUI",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "VaneUI", targets: ["VaneUI"])],
    dependencies: [.package(path: "../VaneKit")],
    targets: [
        .target(
            name: "VaneUI",
            dependencies: ["VaneKit"],
            resources: [.process("Resources")],
            // UI-facing, so main-actor-by-default is right here — unlike VaneKit, which stays
            // nonisolated so the widget and the sun engine are not dragged onto the main actor.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "VaneUITests", dependencies: ["VaneUI"], resources: [.process("snapshot.json")]),
    ]
)
