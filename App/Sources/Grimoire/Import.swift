import AppKit
import GrimoireAppKit
import GrimoireCore
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    /// Imports downloaded Google Docs and other .docx, .md and .txt files (or folders of them,
    /// like a Google Takeout export) into the Inbox. Nothing is filed until Confirm.
    @discardableResult
    func importDocuments(_ urls: [URL], dayFirst: Bool = false, tags: [TagPath] = []) -> [ImportRun.Outcome] {
        var importer = DocumentImporter(parser: ReadingParser(library: library))
        importer.timeZone = TimeZone.current.identifier
        importer.location = settings.home
        importer.slashOrder = dayFirst ? .dayFirst : .monthFirst
        importer.tags = tags
        let run = ImportRun(importer: importer, attachmentsFolder: Store.attachments)
        let known = Set(data.inbox.compactMap(\.entry.captureId) + data.entries.compactMap(\.captureId))
        let outcomes = run.run(urls, isKnown: { known.contains($0) }, deliver: { repository.addToInbox($0) })
        var imported = 0, duplicates = 0, failed: [String] = []
        for o in outcomes {
            switch o {
            case .imported: imported += 1
            case .duplicate: duplicates += 1
            case .failed(let file, let reason): failed.append("\(file): \(reason)")
            }
        }
        var parts = ["Imported \(imported) entr\(imported == 1 ? "y" : "ies") to the Inbox"]
        if duplicates > 0 { parts.append("\(duplicates) already here") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        show(parts.joined(separator: ", "))
        importProblems = failed
        if imported > 0 { page = .inbox }
        return outcomes
    }

    /// Lets the person pick documents or folders to import.
    static func chooseDocuments() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImportDocument.supportedExtensions.keys.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose Google Docs you downloaded (.docx), Markdown or text files, or a folder of them."
        panel.prompt = "Import"
        return panel.runModal() == .OK ? panel.urls : []
    }
}

/// Import Documents: choose files, say how dates are written, add a tag.
struct ImportDocumentsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var dayFirst = false
    @State private var tags: [TagPath] = [TagPath("source/import")]

    var body: some View {
        Form {
            Section {
                LabeledContent("Files") {
                    HStack {
                        Text(files.isEmpty ? "None" : files.count == 1 ? files[0].lastPathComponent : "\(files.count) chosen")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button("Choose…") { files = AppModel.chooseDocuments() }
                    }
                }
                Picker("Dates like 3/4/2025 mean", selection: $dayFirst) {
                    Text("March 4 (month first)").tag(false)
                    Text("3 April (day first)").tag(true)
                }
                LabeledContent("Tags") { TagField(tags: $tags) }
            } header: {
                Text("Import Documents")
            } footer: {
                Text("Each dated heading or date line becomes its own entry in the Inbox, with any cards or Yi Jing lines found. Check each one, then Confirm.")
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 480)
        .noInitialFocus()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    model.importDocuments(files, dayFirst: dayFirst, tags: tags)
                    dismiss()
                }
                .disabled(files.isEmpty)
            }
        }
    }
}
