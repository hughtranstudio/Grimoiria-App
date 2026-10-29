import Foundation
import GrimoireCore

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
}
