import GrimoireAppKit
import GrimoireCore
import SwiftUI

/// The menu bar. Every action has a menu item and a keyboard shortcut.
struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    private var session: SessionController { SessionController.shared }

    var body: some Commands {
        SidebarCommands()
        ToolbarCommands()
        CommandGroup(replacing: .newItem) {
            Button("New Journal Entry") { model.newEntry(.journal) }
                .keyboardShortcut("n")
            Button("New Inquiry…") { model.sheet = .newInquiry }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Menu("New Entry") {
                ForEach(Array(EntryType.creatable.enumerated()), id: \.offset) { i, t in
                    Button(t.title) { model.newEntry(t) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .option])
                }
            }
            Button("New Volume…") { model.sheet = .newVolume }
            Button("Index Page Photos…") { model.sheet = .indexPages(nil) }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Divider()
            Button("Quick Log…") { QuickLogController.shared.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button("Record Session…") { openWindow(id: "session") }
                .keyboardShortcut("r", modifiers: [.command, .option])
        }
        CommandGroup(after: .importExport) {
            Button("Import Documents…") { model.sheet = .importDocuments }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Import Deck…") { model.importDeck() }
            Button("Export to Obsidian") { model.exportNow() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Check Inbox Folders") { IngestCoordinator.shared.scanAll() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Button("Search") {
                model.page = .search
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }
        CommandMenu("Calendar") {
            Button("Previous Month") { model.page = .calendar; model.moveCalendar(months: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Next Month") { model.page = .calendar; model.moveCalendar(months: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Today in the Calendar") {
                model.page = .calendar
                model.calendarMonth = .now
                model.selection = .day(model.today)
            }
            .keyboardShortcut("y", modifiers: [.command, .option])
            Divider()
            Button("Fill Timing on Older Records") { model.fillMissingTiming() }
            Button("Add Check-ins to Past Readings") { model.backfillCheckIns() }
        }
        CommandMenu("Session") {
            Button("Record Session…") { openWindow(id: "session") }
            Button("Mark This Moment") { session.mark() }
                .keyboardShortcut("k")
                .disabled(!session.isRunning)
            Menu("Phase") {
                ForEach(Array(SessionPhase.live.enumerated()), id: \.offset) { i, p in
                    Button(p.title) { session.setPhase(p) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.control, .option])
                }
            }
            .disabled(!session.isRunning)
            Menu("Observation Kind") {
                ForEach(ObservationKind.allCases, id: \.self) { k in
                    Button(k.title) { session.kind = k }
                        .keyboardShortcut(KeyEquivalent(k.key), modifiers: [.control, .option])
                }
            }
            .disabled(session.stage == .setup)
            Divider()
            Button("End Session") { session.end() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(!session.isRunning)
        }
        CommandMenu("Go") {
            ForEach(SidebarPage.allCases) { page in
                if let key = page.shortcut {
                    Button(page.title) { model.page = page }.keyboardShortcut(key)
                } else {
                    Button(page.title) { model.page = page }
                }
            }
        }
    }
}
