import Foundation

/// Page labels for photos of a physical notebook, in order (spec §7 bulk indexing).
public enum PageNumbering {
    /// One label per photo, starting at `start`. Pages count 40, 41, 42; folios count 12r, 12v, 13r.
    /// With `pagesPerPhoto` 2 (a photo of an open spread) labels are ranges: "40–41", "42–43".
    /// A start the numbering can't read ("frontispiece") gives nil.
    public static func labels(from start: String, count: Int, pagination: Volume.Pagination, pagesPerPhoto: Int = 1) -> [String]? {
        guard count > 0, let first = Self.ordinal(start, pagination: pagination) else { return count == 0 ? [] : nil }
        let per = max(1, pagesPerPhoto)
        return (0..<count).map { i in
            let lo = first + i * per, hi = lo + per - 1
            return lo == hi ? label(lo, pagination) : "\(label(lo, pagination))–\(label(hi, pagination))"
        }
    }

    /// Position counting from 0: page 1 → 0; folio 1r → 0, 1v → 1, 2r → 2.
    static func ordinal(_ s: String, pagination: Volume.Pagination) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        let digits = t.prefix { $0.isNumber }
        guard let n = Int(digits), n >= 0 else { return nil }
        let rest = t.dropFirst(digits.count)
        switch pagination {
        case .page:
            return rest.isEmpty ? n - 1 : nil
        case .folio:
            if rest.isEmpty || rest == "r" { return (n - 1) * 2 }
            if rest == "v" { return (n - 1) * 2 + 1 }
            return nil
        }
    }

    static func label(_ ordinal: Int, _ pagination: Volume.Pagination) -> String {
        switch pagination {
        case .page: return "\(ordinal + 1)"
        case .folio: return "\(ordinal / 2 + 1)\(ordinal % 2 == 0 ? "r" : "v")"
        }
    }
}

/// Turns photos of notebook pages into photo-first records: one filed entry per photo, carrying the
/// volume, the page and the photo, marked physical only so it can be transcribed later.
public struct PageIndexer: Sendable {
    public var volume: Volume
    public var firstPage: String
    public var pagesPerPhoto: Int
    /// When the pages were written, if known; the day alone, so timing has no planetary hour.
    public var writtenOn: ZonedDate?
    public var type: EntryType
    public var tags: [TagPath]
    public var location: GeoLocation?

    public init(volume: Volume, firstPage: String, pagesPerPhoto: Int = 1, writtenOn: ZonedDate? = nil,
                type: EntryType = .journal, tags: [TagPath] = [], location: GeoLocation? = nil) {
        self.volume = volume; self.firstPage = firstPage; self.pagesPerPhoto = pagesPerPhoto
        self.writtenOn = writtenOn; self.type = type; self.tags = tags; self.location = location
    }

    public enum IndexError: Error, CustomStringConvertible, Equatable {
        case unreadableStart(String)
        public var description: String {
            switch self {
            case .unreadableStart(let s): return "Can't count pages on from “\(s)”. Use a number like 40, or 12r for folios."
            }
        }
    }

    /// Entries for `photos`, in the order given. Each gets the page that photo shows.
    public func entries(for photos: [Attachment], now: Date = Date()) throws -> [Entry] {
        guard let pages = PageNumbering.labels(from: firstPage, count: photos.count, pagination: volume.pagination, pagesPerPhoto: pagesPerPhoto)
        else { throw IndexError.unreadableStart(firstPage) }
        let when = writtenOn ?? ZonedDate(now)
        let timing = writtenOn.map { TimingContext.compute(at: $0, location: location, timeKnown: false) }
        return zip(photos, pages).map { photo, page in
            Entry(type: type, title: "\(volume.name) p. \(page)", occurredAt: when, createdAt: now, tags: tags,
                  physicalRef: PhysicalRef(volumeId: volume.id, page: page, photo: photo, physicalOnly: true),
                  timing: timing, mode: .quick, status: .filed)
        }
    }
}

public extension GrimoireRepository {
    /// Records with a page photo that are still physical only: the transcription queue.
    func pagesToTranscribe(in volumeId: ULID? = nil) -> [Entry] {
        data.entries.filter {
            guard let ref = $0.physicalRef, ref.physicalOnly, ref.photo != nil, $0.status == .filed else { return false }
            return volumeId.map { ref.volumeId == $0 } ?? true
        }
        .sorted { (($0.physicalRef?.pageRange?.lowerBound ?? .max), $0.id) < (($1.physicalRef?.pageRange?.lowerBound ?? .max), $1.id) }
    }
}
