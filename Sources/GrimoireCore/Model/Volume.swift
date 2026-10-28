import Foundation

/// A physical grimoire (spec §7).
public struct Volume: Codable, Hashable, Sendable, Identifiable {
    public enum Pagination: String, Codable, Sendable { case page, folio }
    public var id: ULID
    public var name: String
    public var startedOn: String?
    public var endedOn: String?
    public var notes: String?
    public var pagination: Pagination

    public init(id: ULID = ULID(), name: String, startedOn: String? = nil, endedOn: String? = nil, notes: String? = nil, pagination: Pagination = .page) {
        self.id = id; self.name = name; self.startedOn = startedOn; self.endedOn = endedOn; self.notes = notes; self.pagination = pagination
    }
}

/// Where in a physical volume something was written. `page` is free text: "12v", "43–45".
public struct PhysicalRef: Codable, Hashable, Sendable {
    public var volumeId: ULID
    public var page: String
    public var photo: Attachment?
    /// True for photo-first bulk indexing entries with minimal text.
    public var physicalOnly: Bool

    public init(volumeId: ULID, page: String, photo: Attachment? = nil, physicalOnly: Bool = false) {
        self.volumeId = volumeId; self.page = page; self.photo = photo; self.physicalOnly = physicalOnly
    }

    /// Numeric page span, ignoring recto/verso letters: "12v" → 12…12, "43–45" → 43…45.
    public var pageRange: ClosedRange<Int>? {
        let parts = page.split(whereSeparator: { "-–—".contains($0) })
            .compactMap { Int($0.filter(\.isNumber)) }
        guard let lo = parts.first else { return nil }
        let hi = parts.count > 1 ? parts[1] : lo
        return min(lo, hi)...max(lo, hi)
    }

    public func overlaps(_ range: ClosedRange<Int>) -> Bool { pageRange?.overlaps(range) ?? false }
}
