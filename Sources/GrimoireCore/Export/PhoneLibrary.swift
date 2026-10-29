import Foundation

/// The Mac → phone half of the sync folder (docs/phone-library.md). Beside `incoming/`, the Mac
/// keeps `library/` with a read-only copy of the filed records so the phone can browse, search
/// and get check-in reminders without any other link to the Mac:
///
/// - `library/grimoire.jsonl`     the same lines as the JSONL export (export-record v1)
/// - `library/tag-vocabulary.json` the controlled vocabulary, for tag pickers
/// - `library/manifest.json`      written last; the phone reloads when it changes
///
/// Files are only rewritten when their content changed, so Syncthing stays quiet.
public struct PhoneLibrary: Sendable {
    public static let folderName = "library"
    public static let formatVersion = 1

    public let library: DefinitionLibrary
    public let vocabulary: TagVocabulary
    public init(library: DefinitionLibrary, vocabulary: TagVocabulary) {
        self.library = library
        self.vocabulary = vocabulary
    }

    public struct Manifest: Codable, Equatable, Sendable {
        public var libraryVersion: Int
        public var exportedAt: String
        public var entries: Int
        public var inquiries: Int
        public var reminders: Int
        /// Change marker for grimoire.jsonl: its byte count and FNV-1a hash.
        public var checksum: String

        enum CodingKeys: String, CodingKey {
            case libraryVersion = "library_version", exportedAt = "exported_at", entries, inquiries, reminders, checksum
        }
    }

    /// What `write` produces, before it touches the disk.
    public func files(_ data: GrimoireData, now: Date = Date()) throws -> (jsonl: String, vocabulary: String, manifest: Manifest) {
        let jsonl = try JSONLExporter(library: library).export(data)
        let manifest = Manifest(libraryVersion: Self.formatVersion,
                                exportedAt: GrimoireDateFormat.iso(now, in: .current),
                                entries: data.entries.filter { $0.status == .filed }.count,
                                inquiries: data.inquiries.count,
                                reminders: data.reminders.count,
                                checksum: Self.checksum(jsonl))
        return (jsonl, try vocabulary.json(), manifest)
    }

    /// Writes `library/` under `root` (an ingest folder). Returns true when anything changed.
    @discardableResult
    public func write(_ data: GrimoireData, to root: URL, now: Date = Date()) throws -> Bool {
        let folder = root.appendingPathComponent(Self.folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (jsonl, vocab, manifest) = try files(data, now: now)
        var changed = false
        changed = try Self.replace(folder.appendingPathComponent("grimoire.jsonl"), with: Data(jsonl.utf8)) || changed
        changed = try Self.replace(folder.appendingPathComponent("tag-vocabulary.json"), with: Data(vocab.utf8)) || changed
        let manifestURL = folder.appendingPathComponent("manifest.json")
        let old = (try? Data(contentsOf: manifestURL)).flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
        if changed || old == nil || old?.checksum != manifest.checksum || old?.libraryVersion != manifest.libraryVersion {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try Self.replace(manifestURL, with: try enc.encode(manifest) + Data("\n".utf8))
            changed = true
        }
        return changed
    }

    /// Atomic write, skipped when the file already holds exactly these bytes.
    @discardableResult
    static func replace(_ url: URL, with bytes: Data) throws -> Bool {
        if let existing = try? Data(contentsOf: url), existing == bytes { return false }
        try bytes.write(to: url, options: .atomic)
        return true
    }

    /// FNV-1a 64 over the bytes, as hex. Only used to notice change, never for security.
    public static func checksum(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return "\(s.utf8.count)-" + String(h, radix: 16)
    }
}
