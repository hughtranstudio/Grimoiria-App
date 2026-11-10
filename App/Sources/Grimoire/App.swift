import AppKit
import GrimoireAppKit
import SwiftData
import SwiftUI

// Grimoire
//   Grimoire                      the app
//   APP_STORE=<file> Grimoire     use another database (tests, experiments); definitions and settings go beside it
//   APP_SNAPSHOT=<dir> Grimoire   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 Grimoire           fill an empty /tmp store with sample records (tools/snap.sh)
//   Grimoire --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> Grimoire      run with another accent from Theme.all (UI/Theme.swift)
//   APP_STYLE=a|system Grimoire   run with the house style or Apple's look (UI/HouseStyle.swift)
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
                .onOpenURL { model.open($0) }
        }
        .modelContainer(model.container)
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }

        Window("Session", id: "session") {
            SessionWindow()
                .environment(model)
                .themed()
        }
        .modelContainer(model.container)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

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

    /// The build that writes the schema stamp (Info.plist's CFBundleVersion).
    static var build: String? { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String }

    /// Read before the store opens, since opening creates it.
    static func checkSchema() -> StoreSchema.Check {
        StoreSchema.check(storeExists: FileManager.default.fileExists(atPath: url.path), folder: folder)
    }

    /// Opens the database. When it will not open, its files are first copied aside untouched, then
    /// a dialog offers to quit, try again, or start a new database (the old files move into the
    /// copy's folder, never deleted). The app never crashes on a store it cannot open.
    static func makeContainer() -> ModelContainer {
        var rescued: URL?
        while true {
            do {
                return try ModelContainer(for: Schema(Records.all), configurations: ModelConfiguration(url: url))
            } catch {
                print("Grimoire: could not open the database at \(url.path): \(error)")
                if rescued == nil, FileManager.default.fileExists(atPath: url.path) {
                    rescued = try? StoreRescue.copyAside(url)
                }
                // The self-test, snapshots and seed runs have no one to answer a dialog.
                if SelfTest.requested || ProcessInfo.processInfo.environment["APP_SNAPSHOT"] != nil { exit(1) }
                switch StoreOpenAlert.ask(error: error, store: url, copy: rescued) {
                case .quit: exit(1)
                case .tryAgain: continue
                case .startNew:
                    let shelf = (rescued ?? folder).appending(path: "moved aside", directoryHint: .isDirectory)
                    try? FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
                    for file in StoreRescue.companions(of: url) where FileManager.default.fileExists(atPath: file.path) {
                        do { try FileManager.default.moveItem(at: file, to: shelf.appending(path: file.lastPathComponent)) }
                        catch { print("Grimoire: could not move \(file.path) aside: \(error)"); exit(1) }
                    }
                }
            }
        }
    }
}

/// The dialog for a database that will not open.
enum StoreOpenAlert {
    enum Choice { case quit, tryAgain, startNew }

    static func ask(error: Error, store: URL, copy: URL?) -> Choice {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Grimoire could not open its database"
        var info = "\(error.localizedDescription)\n\n"
        if let copy {
            info += "A copy of the database, exactly as it was, is in “\(copy.lastPathComponent)” beside it:\n\(copy.path)\n\n"
        }
        info += "Quit leaves everything as it is. Start New Database moves the old files into that folder and opens an empty one; nothing is deleted."
        alert.informativeText = info
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Start New Database…")
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .tryAgain
        case .alertThirdButtonReturn: return confirmStartNew() ? .startNew : .quit
        default: return .quit
        }
    }

    private static func confirmStartNew() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Start with an empty database?"
        alert.informativeText = "Your records stay in the copied folder and can be restored from there or from a backup. Grimoire will look empty until then."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Start New Database")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
