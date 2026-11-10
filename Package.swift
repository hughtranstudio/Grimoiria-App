// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GrimoireCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "GrimoireCore", targets: ["GrimoireCore"]),
        .executable(name: "grimoire", targets: ["GrimoireCLI"]),
    ],
    targets: [
        .target(
            name: "GrimoireCore",
            resources: [.copy("Resources/Definitions"), .copy("Resources/Book")]
        ),
        // The command-line tool keeps its name ("swift run grimoire", .build/release/grimoire), but the
        // target is GrimoireCLI: a target named "grimoire" shares its build folder with the Mac app's
        // "Grimoire" on a case-insensitive disk, and the app then fails to link.
        .executableTarget(name: "GrimoireCLI", dependencies: ["GrimoireCore"], path: "Sources/grimoire"),
        .testTarget(
            name: "GrimoireCoreTests",
            dependencies: ["GrimoireCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
