// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GrimoireCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "GrimoireCore", targets: ["GrimoireCore"]),
        .executable(name: "grimoire", targets: ["grimoire"]),
    ],
    targets: [
        .target(
            name: "GrimoireCore",
            resources: [.copy("Resources/Definitions"), .copy("Resources/Book")]
        ),
        .executableTarget(name: "grimoire", dependencies: ["GrimoireCore"]),
        .testTarget(
            name: "GrimoireCoreTests",
            dependencies: ["GrimoireCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
