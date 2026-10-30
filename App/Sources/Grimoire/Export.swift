import AppKit
import Foundation
import GrimoireCore
import UniformTypeIdentifiers

extension AppModel {
    /// Writes the Obsidian export and grimoire.jsonl into the vault folder.
    /// Only changed files are written; attachments are copied into _attachments/.
    @discardableResult
    func exportNow(to folder: URL? = nil, quiet: Bool = false) -> ExportWriter.Report? {
        flushEdits()
        let path = folder?.path ?? settings.vaultPath
        guard !path.isEmpty else {
            if !quiet { show("Choose a vault folder in Settings > Export first") }
            return nil
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        var filed = data
        filed.inbox = []
        filed.entries = filed.entries.filter { $0.status == .filed }
        do {
            var files = ObsidianExporter(library: library).files(for: filed)
            files["grimoire.jsonl"] = try JSONLExporter(library: library).export(filed)
            if settings.exportML { files.merge(try MLExporter(library: library).files(for: filed)) { a, _ in a } }
            var report = try ExportWriter.write(files, to: root, prune: true)
            report.written += try copyAttachments(of: filed, to: root.appending(path: "_attachments"))
            if !quiet {
                var parts = [report.written.isEmpty ? "Export is up to date" : "Exported \(report.written.count) file\(report.written.count == 1 ? "" : "s")"]
                if !report.removed.isEmpty { parts.append("removed \(report.removed.count) for deleted records") }
                show(parts.joined(separator: ", "))
            }
            return report
        } catch {
            show("Export failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Copies attachment files that are missing or changed. Returns their vault paths.
    private func copyAttachments(of data: GrimoireData, to folder: URL) throws -> [String] {
        let fm = FileManager.default
        var written: [String] = []
        var all = data.entries.flatMap(\.attachments)
        all += data.entries.compactMap(\.physicalRef?.photo)
        for a in all {
            let source = Store.attachments.appending(path: a.path)
            let target = folder.appending(path: a.path)
            guard fm.fileExists(atPath: source.path) else { continue }
            let same = (try? Data(contentsOf: target)) == (try? Data(contentsOf: source))
            if same { continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: source, to: target)
            written.append("_attachments/\(a.path)")
        }
        return written
    }

    /// Saves the next 90 days as an .ics file for Google or Apple Calendar: planned rituals, outcome
    /// check-ins and lunar phases, with timing and a grimoire:// link only, never the reading itself.
    func exportCalendar() {
        flushEdits()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.nameFieldStringValue = "Grimoire.ics"
        panel.message = "Import this file into Google Calendar or Apple Calendar. It holds times and links, not readings."
        guard panel.runModal() == .OK, let url = panel.url,
              var exporter = CalendarExporter(first: today, days: 90, zone: .current) else { return }
        exporter.location = settings.home
        let events = exporter.events(for: data)
        do {
            try Data(CalendarExporter.ics(events).utf8).write(to: url, options: .atomic)
            show("Saved \(events.count) calendar event\(events.count == 1 ? "" : "s")")
        } catch {
            show("Calendar export failed: \(error.localizedDescription)")
        }
    }
}
