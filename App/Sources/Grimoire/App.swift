import AppKit
import SwiftData
import SwiftUI

// Grimoire
//   Grimoire                      the app
//   APP_STORE=<file> Grimoire     use another database (tests, experiments); definitions and settings go beside it
//   APP_SNAPSHOT=<dir> Grimoire   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 Grimoire           fill an empty /tmp store with sample records (tools/snap.sh)
//   Grimoire --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Grimoire      run with another accent from Theme.all (UI/Theme.swift)
//   APP_STYLE=a|b|c Grimoire      run with a house style option (UI/HouseStyle.swift, DRAFT)
//   APP_GRID=1 Grimoire           draw the 8 pt grid and the layout probes over the window
//   Grimoire help                 the agent CLI (Agent/), also linked as ~/.local/bin/grimoire

struct GrimoireApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Grimoire", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 900, minHeight: 560)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        AppModel.shared.didLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.flushEdits()
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/Grimoire/
///   Grimoire.store   SwiftData records
///   Definitions/     decks, spreads, Yi Jing (copied from the app on first launch)
///   Attachments/     audio and photos, referenced by relative path
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return folder.appending(path: "Grimoire.store")
    }

    /// The folder that holds the store, Definitions and Attachments.
    static var folder: URL {
        let dir: URL
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            let store = URL(fileURLWithPath: path)
            dir = store.deletingLastPathComponent().appending(path: store.deletingPathExtension().lastPathComponent + "-files")
        } else {
            dir = URL.applicationSupportDirectory.appending(path: "Grimoire", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var definitions: URL { folder.appending(path: "Definitions", directoryHint: .isDirectory) }
    static var attachments: URL {
        let dir = folder.appending(path: "Attachments", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The Definitions folder shipped inside the app (build.sh copies it from GrimoireCore).
    static var bundledDefinitions: URL? {
        Bundle.main.url(forResource: "Definitions", withExtension: nil)
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Schema(Records.all), configurations: ModelConfiguration(url: url))
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}
