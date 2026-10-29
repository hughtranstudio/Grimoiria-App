import Foundation

/// Turns existing records (Google Docs, downloaded .docx/.md/.txt) into Inbox items for
/// confirm-and-correct (spec §11.3). Nothing is filed here.
///
/// Splitting rules: a dated heading or a date line starts a new entry. When a document has
/// dated headings, only those split it, so a date mentioned in a line of prose stays in its
/// entry. Recognised card names and Yi Jing lines become a draft reading; everything else is
/// body text. The original file is attached to every entry it produces.
public struct DocumentImporter: Sendable {
    public let parser: ReadingParser
    /// Zone for dates written without one. Frontmatter `time_zone` overrides it per file.
    public var timeZone: String = TimeZone.current.identifier
    public var location: GeoLocation?
    public var slashOrder: DateLine.SlashOrder = .monthFirst
    /// Added to every imported entry, e.g. `source/google-docs`.
    public var tags: [TagPath] = []
    /// A date line followed by more than this many characters is prose, not a title.
    public var maxTitleLength = 80

    public init(parser: ReadingParser) { self.parser = parser }

    /// One candidate entry before it becomes an Inbox item.
    public struct Section: Equatable, Sendable {
        public var date: DateLine?
        /// The line that started the section (heading or date line); nil for undated text.
        public var header: String?
        public var lines: [String]
    }

    // MARK: Splitting

    public func sections(of text: String) -> [Section] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let dated = lines.map { DateLine.parse($0, slashOrder: slashOrder) }
        let headingsOnly = lines.indices.contains { dated[$0] != nil && Self.isHeading(lines[$0]) }

        var out: [Section] = []
        var current = Section(date: nil, header: nil, lines: [])
        for (i, line) in lines.enumerated() {
            if let d = dated[i], !headingsOnly || Self.isHeading(line) {
                out.append(current)
                current = Section(date: d, header: line, lines: [])
            } else {
                current.lines.append(line)
            }
        }
        out.append(current)

        // Text before the first date: dropped when it is only a document title, kept otherwise.
        if out.count > 1, out[0].date == nil {
            let text = out[0].lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if text.allSatisfy(Self.isHeading) || (text.count == 1 && text[0].count <= maxTitleLength) { out.removeFirst() }
        }
        return out.filter { $0.date != nil || $0.lines.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    static func isHeading(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).range(of: #"^#{1,6}\s"#, options: .regularExpression) != nil
    }

    // MARK: Inbox items

    /// Inbox items for one document. `attachment` is the stored copy of the original file.
    public func items(for doc: ImportDocument, attachment: Attachment? = nil, now: Date = Date()) -> [InboxItem] {
        let sections = sections(of: doc.text)
        let zone = doc.timeZone ?? timeZone
        return sections.enumerated().map { n, section in
            var notes: [String] = []
            var bodyLines = section.lines
            var title: String?

            // Date and time.
            var occurred: ZonedDate
            var timeKnown = false
            if let d = section.date {
                occurred = Self.zoned(d, zone: zone)
                timeKnown = d.hour != nil
                if d.ambiguous { notes.append("Date in \"\(Self.cleanLine(section.header ?? ""))\" could be read either way; read as \(occurred.day)") }
                if d.rest.count > maxTitleLength { bodyLines.insert(d.rest, at: 0) } else if !d.rest.isEmpty { title = d.rest }
            } else if let s = doc.date, let z = ZonedDate.parse(s, timeZone: doc.timeZone) {
                occurred = z
                timeKnown = true
            } else if let s = doc.date, let d = DateLine.parse(s, slashOrder: slashOrder) {
                occurred = Self.zoned(d, zone: zone)
                timeKnown = d.hour != nil
            } else {
                let fallback = doc.fallbackDate ?? now
                occurred = ZonedDate(fallback, timeZone: zone)
                timeKnown = doc.fallbackDate != nil
                notes.append("No date in the text; used the \(doc.fallbackDate == nil ? "import" : doc.fallbackDateSource ?? "file") date \(occurred.day)")
            }
            if !timeKnown && section.date != nil { notes.append("No time given; noon used, so the planetary hour is left blank") }
            if sections.count == 1 && section.date == nil { title = doc.title ?? firstHeading(bodyLines) }

            let body = Self.trimBlankLines(bodyLines).joined(separator: "\n")

            // Reading: only keep divinations that actually name cards or lines.
            var draft: DraftReading?
            var parsed = parser.parse(body)
            parsed.divinations.removeAll { d in !d.draws.contains { $0.cardId.value != nil } && (d.cast?.lines.value ?? []).isEmpty }
            if !parsed.isEmpty { draft = parsed }

            // Type: frontmatter for a single undated note, else a keyword in the title, else divination
            // when a reading was found, else journal.
            var type: EntryType
            if sections.count == 1, let t = doc.type { type = t }
            else if let t = Self.entryType(in: title ?? Self.cleanLine(section.header ?? "")) { type = t }
            else if draft != nil { type = .divination }
            else { type = doc.type ?? .journal; if doc.type == nil { notes.append("Type not stated; set to journal") } }

            let timing = TimingContext.compute(at: occurred, location: location, timeKnown: timeKnown)

            var tags = doc.tags + self.tags + Self.hashtags(in: body)
            tags = tags.reduce(into: [TagPath]()) { if !$0.contains($1) { $0.append($1) } }

            var provenance = "Imported from \"\(doc.displayName)\""
            if sections.count > 1 { provenance += ", part \(n + 1) of \(sections.count)" }
            if let u = doc.sourceURL { provenance += " (\(u))" }

            let entry = Entry(id: ULID(date: occurred.instant), type: type, title: title, occurredAt: occurred, createdAt: now,
                              body: body, tags: tags, attachments: attachment.map { [$0] } ?? [], timing: timing,
                              mode: .reflective, status: .inbox, extraNotes: provenance,
                              captureId: Self.importId(day: occurred.day, title: title, body: body))
            return InboxItem(entry: entry, draft: draft, source: doc.sourceLabel, notes: notes)
        }
    }

    func firstHeading(_ lines: [String]) -> String? {
        lines.first { Self.isHeading($0) }.map(Self.cleanLine)
    }

    static func zoned(_ d: DateLine, zone: String) -> ZonedDate {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone) ?? TimeZone(secondsFromGMT: 0)!
        let date = cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: d.hour ?? 12, minute: d.minute ?? 0))!
        return ZonedDate(date, timeZone: cal.timeZone.identifier)
    }

    static func cleanLine(_ s: String) -> String {
        s.replacingOccurrences(of: #"^\s*#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "\\", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static func trimBlankLines(_ lines: [String]) -> [String] {
        var l = lines[...]
        while let f = l.first, f.trimmingCharacters(in: .whitespaces).isEmpty { l = l.dropFirst() }
        while let x = l.last, x.trimmingCharacters(in: .whitespaces).isEmpty { l = l.dropLast() }
        return Array(l)
    }

    /// Words in a title that name an entry type. Checked in order, so "Dream about a ritual" is a dream.
    static let typeWords: [(EntryType, [String])] = [
        (.dream, ["dream", "dreams", "dreamt", "dreamed", "nightmare"]),
        (.omen, ["omen", "omens", "portent", "synchronicity"]),
        (.contact, ["contact", "contacts"]),
        (.vision, ["vision", "visions", "pathworking", "inner work", "visionary"]),
        (.meditation, ["meditation", "meditations", "meditated", "contemplation"]),
        (.ritual, ["ritual", "rituals", "rite", "invocation", "evocation", "banishing", "lbrp", "ceremony", "working"]),
        (.divination, ["reading", "divination", "tarot", "draw", "spread", "yi jing", "i ching", "hexagram", "oracle"]),
        (.insight, ["insight", "insights", "realisation", "realization"]),
        (.journal, ["journal", "diary", "log"]),
    ]

    static func entryType(in text: String) -> EntryType? {
        let words = " " + Tokenizer.tokenize(text).compactMap { if case .word(let w) = $0 { return w } else { return nil } }.joined(separator: " ") + " "
        return typeWords.first { _, keys in keys.contains { words.contains(" \($0) ") } }?.0
    }

    /// `#entity/crow` style tags written inline in the text. Markdown headings (`# `) are not tags.
    static func hashtags(in body: String) -> [TagPath] {
        let re = try! NSRegularExpression(pattern: #"(?<![\w&/#\]])#([A-Za-z][\w\-/]*)"#)
        return re.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { m in
            Range(m.range(at: 1), in: body).map { TagPath(String(body[$0])) }
        }.filter { !$0.isEmpty }
    }

    /// Stable id for de-duplication: the same text imported again, or the same Google Doc via
    /// the other route (connector Markdown vs downloaded .docx), gets the same id.
    public static func importId(day: String, title: String?, body: String) -> String {
        let words = Tokenizer.tokenize([title ?? "", body].joined(separator: "\n"))
            .compactMap { if case .word(let w) = $0 { return w } else { return nil } }
        return "import-" + fnv1a(day + "|" + words.joined(separator: " "))
    }

    static func fnv1a(_ s: String) -> String { fnv1a(s.utf8) }

    static func fnv1a<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in bytes { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01B3 }
        let hex = String(h, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

/// Imports files and folders into the Inbox, the way the app handles drops on `Imports/`.
public struct ImportRun: Sendable {
    public enum Outcome: Equatable, Sendable {
        case imported(file: String, entryId: ULID, captureId: String)
        case duplicate(file: String, captureId: String)
        case failed(file: String, reason: String)
    }

    public var importer: DocumentImporter
    /// Originals are copied to `imports/` here; entries store a path relative to it.
    public var attachmentsFolder: URL?

    public init(importer: DocumentImporter, attachmentsFolder: URL? = nil) {
        self.importer = importer
        self.attachmentsFolder = attachmentsFolder
    }

    /// Files to import under `paths`: folders are walked (Google Takeout nests them), hidden files
    /// and unsupported extensions skipped. Sorted for a stable order.
    public static func files(at paths: [URL]) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for p in paths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p.path, isDirectory: &isDir) else { out.append(p); continue }
            if !isDir.boolValue { out.append(p); continue }
            let walker = fm.enumerator(at: p, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            while let u = walker?.nextObject() as? URL {
                if ImportDocument.supportedExtensions[u.pathExtension.lowercased()] != nil, !u.lastPathComponent.hasPrefix("~$") { out.append(u) }
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    public func run(_ paths: [URL], now: Date = Date(), isKnown: (String) -> Bool, deliver: (InboxItem) throws -> Void) -> [Outcome] {
        var outcomes: [Outcome] = []
        for url in Self.files(at: paths) {
            let name = url.lastPathComponent
            do {
                let doc = try ImportDocument.load(url)
                let attachment = try store(doc)
                for item in importer.items(for: doc, attachment: attachment, now: now) {
                    let cid = item.entry.captureId!
                    if isKnown(cid) { outcomes.append(.duplicate(file: name, captureId: cid)); continue }
                    try deliver(item)
                    outcomes.append(.imported(file: name, entryId: item.id, captureId: cid))
                }
            } catch {
                outcomes.append(.failed(file: name, reason: "\(error)"))
            }
        }
        return outcomes
    }

    /// Copies the original into `imports/`, named by content so re-imports reuse the same file.
    func store(_ doc: ImportDocument) throws -> Attachment {
        let rel = "imports/\(DocumentImporter.fnv1a(doc.original).prefix(8))-\(doc.name)"
        guard let folder = attachmentsFolder else { return Attachment(kind: .document, path: doc.name, originalName: doc.name) }
        let dest = folder.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: dest.path) { try doc.original.write(to: dest, options: .atomic) }
        return Attachment(kind: .document, path: rel, originalName: doc.name)
    }
}
