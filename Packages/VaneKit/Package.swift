// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VaneKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "VaneKit", targets: ["VaneKit"])],
    dependencies: [
        // ADR-0002. The archive's defining interaction is scroll compression, which is a
        // GROUP BY run during a gesture; SwiftData has no way to express that and would force
        // the reduction into Swift on the main actor at 120fps.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // Deliberately NOT main-actor-by-default. VaneKit is a library: it ships nonisolated
        // APIs and lets the caller decide where work runs. The app and VaneUI opt into
        // MainActor isolation; forcing it down here would drag the widget extension and the
        // sun engine onto the main actor for no reason.
        .target(name: "VaneKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(
            name: "VaneKitTests",
            dependencies: ["VaneKit"],
            // A payload captured from the running backend. Decoding it in a test is what
            // catches contract drift — a renamed field shows up here, not on a blank screen.
            resources: [.process("snapshot.json")]
        ),
    ]
)
