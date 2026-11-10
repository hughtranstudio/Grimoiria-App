import Foundation

/// The database's schema version, kept in `store-schema.json` beside the store.
///
/// SwiftData keeps each record as a JSON payload (Records.swift), so the shape that matters is
/// the payload's. Bump `current` whenever a payload changes in a way an older build would
/// mishandle, such as a field an older build would drop when it rewrites the record. An older
/// build that finds a newer stamp refuses to write instead of losing that field.
public enum StoreSchema {
    public static let current = 1
    public static let fileName = "store-schema.json"

    public struct Stamp: Codable, Equatable, Sendable {
        public var schemaVersion: Int
        public var writtenBy: String?
        public var updatedAt: Date
    }

    public enum Check: Equatable, Sendable {
        /// No store yet: the stamp is written with the store.
        case fresh
        /// Same version, or a store from before stamps existed (version 1).
        case ok
        /// Written by an older schema; this build upgrades it as it saves.
        case older(Int)
        /// Written by a newer build. Writing could lose what this build does not know.
        case newer(Int)
    }

    public static func stampURL(in folder: URL) -> URL { folder.appending(path: fileName) }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func check(storeExists: Bool, folder: URL, current: Int = current) -> Check {
        guard let data = try? Data(contentsOf: stampURL(in: folder)),
              let stamp = try? decoder.decode(Stamp.self, from: data) else {
            return storeExists ? (current == 1 ? .ok : .older(1)) : .fresh
        }
        if stamp.schemaVersion > current { return .newer(stamp.schemaVersion) }
        if stamp.schemaVersion < current { return .older(stamp.schemaVersion) }
        return .ok
    }

    /// Writes the stamp. Never lowers a newer version that is already there.
    public static func stamp(folder: URL, build: String?, current: Int = current, now: Date = .now) throws {
        if case .newer = check(storeExists: true, folder: folder, current: current) { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(Stamp(schemaVersion: current, writtenBy: build, updatedAt: now))
            .write(to: stampURL(in: folder), options: .atomic)
    }
}

/// Copies a store that would not open (and its -shm and -wal files) into a dated folder beside
/// it, before anything else touches it. Nothing is moved or deleted.
public enum StoreRescue {
    public static func companions(of store: URL) -> [URL] {
        [store, URL(fileURLWithPath: store.path + "-shm"), URL(fileURLWithPath: store.path + "-wal")]
    }

    /// Returns the folder that now holds the copies.
    @discardableResult
    public static func copyAside(_ store: URL, now: Date = .now, fileManager fm: FileManager = .default) throws -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmmss"
        var folder = store.deletingLastPathComponent().appending(path: "Unopened store \(f.string(from: now))", directoryHint: .isDirectory)
        var n = 2
        while fm.fileExists(atPath: folder.path) {
            folder = store.deletingLastPathComponent().appending(path: "Unopened store \(f.string(from: now)) \(n)", directoryHint: .isDirectory)
            n += 1
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in companions(of: store) where fm.fileExists(atPath: file.path) {
            try fm.copyItem(at: file, to: folder.appending(path: file.lastPathComponent))
        }
        return folder
    }
}

/// Records the store could not read or write. Any problem here blocks the steps that would turn
/// a missing record into a deletion elsewhere (export pruning, the phone's library).
public struct StoreHealth: Equatable, Sendable {
    public struct Unreadable: Equatable, Sendable {
        public var kind: String
        public var id: String
        public var reason: String
        public init(kind: String, id: String, reason: String) { self.kind = kind; self.id = id; self.reason = reason }
    }

    public var unreadable: [Unreadable] = []
    /// The last save that failed, until a save succeeds.
    public var saveError: String?
    public var writesBlocked: String?

    public init() {}

    public var isHealthy: Bool { unreadable.isEmpty && saveError == nil && writesBlocked == nil }
    /// Safe to remove exported or shared files whose record seems gone.
    public var canPrune: Bool { unreadable.isEmpty }

    /// One line for the banner, nil when all is well.
    public var banner: String? {
        var parts: [String] = []
        if let writesBlocked { parts.append(writesBlocked) }
        if let saveError { parts.append("The last change was not saved: \(saveError)") }
        if !unreadable.isEmpty {
            let n = unreadable.count
            parts.append("\(n) record\(n == 1 ? "" : "s") could not be read and \(n == 1 ? "is" : "are") hidden. Export pruning and the phone’s library are paused until this is fixed; nothing has been deleted.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
