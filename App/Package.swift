// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Grimoire",
    platforms: [.macOS(.v26)],
    dependencies: [
        // The domain core lives one folder up, in this same repository.
        .package(name: "GrimoireCore", path: ".."),
    ],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(
            name: "GrimoireAppKit",
            dependencies: [.product(name: "GrimoireCore", package: "GrimoireCore")]
        ),
        .executableTarget(
            name: "Grimoire",
            dependencies: ["GrimoireAppKit", .product(name: "GrimoireCore", package: "GrimoireCore")],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "GrimoireAppKitTests", dependencies: ["GrimoireAppKit"]),
    ]
)
