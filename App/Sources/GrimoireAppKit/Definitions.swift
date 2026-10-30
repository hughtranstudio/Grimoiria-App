import Foundation
import GrimoireCore

/// Where the app keeps decks, spreads and Yi Jing: a copy of the bundled
/// Definitions folder in Application Support, so the deck editor can write it.
public enum DefinitionsFolder {
    /// Copies `bundled` to `destination` when the destination has no
    /// definitions yet, then loads from the destination. Existing files are
    /// never overwritten, so edits survive app updates; files a newer app
    /// adds (a new spread, the correspondences table) are copied in, and an
    /// empty placeholder deck is replaced once the app ships its card list.
    @discardableResult
    public static func install(from bundled: URL, to destination: URL) throws -> DefinitionLibrary {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destination.appendingPathComponent("yijing.json").path) {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: bundled, to: destination)
        } else {
            try addMissing(from: bundled, to: destination)
        }
        return try DefinitionLibrary.load(from: destination)
    }

    /// Copies bundled files that the destination doesn't have yet, keeping everything that is there.
    static func addMissing(from bundled: URL, to destination: URL) throws {
        let fm = FileManager.default
        let walker = fm.enumerator(at: bundled, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let base = bundled.standardizedFileURL.path
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let rel = String(url.standardizedFileURL.path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let target = destination.appendingPathComponent(rel)
            if fm.fileExists(atPath: target.path) {
                guard rel.hasPrefix("decks/"), isEmptyPlaceholder(target), !isEmptyPlaceholder(url) else { continue }
                try fm.removeItem(at: target)
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: target)
        }
    }

    /// A deck file still marked placeholder with no cards: nothing in it can be the user's work.
    static func isEmptyPlaceholder(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let deck = try? JSONDecoder().decode(DeckDefinition.self, from: data) else { return false }
        return deck.status == .placeholder && deck.cards.isEmpty
    }

    /// Writes one deck back as JSON, but only when the whole library still
    /// validates with it. Returns the new library.
    public static func save(_ deck: DeckDefinition, in library: DefinitionLibrary, folder: URL) throws -> DefinitionLibrary {
        var decks = library.decks.filter { $0.id != deck.id }
        decks.append(deck)
        let next = DefinitionLibrary(decks: decks, spreads: library.spreads, yijing: library.yijing, correspondences: library.correspondences)
        let report = next.validate()
        guard report.isValid else { throw DeckSaveError.invalid(report.errors) }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let dir = folder.appendingPathComponent("decks")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try enc.encode(deck).write(to: dir.appendingPathComponent("\(deck.id).json"), options: .atomic)
        return next
    }
}

public enum DeckSaveError: Error, CustomStringConvertible {
    case invalid([String])
    public var description: String {
        switch self { case .invalid(let errors): return errors.joined(separator: "\n") }
    }
}
