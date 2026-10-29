import GrimoireCore
import SwiftUI

/// The menu bar. Every action has a menu item and a keyboard shortcut.
struct AppCommands: Commands {
    let model: AppModel

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
