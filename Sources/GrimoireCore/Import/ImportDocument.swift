import Foundation

/// One file to import, read into Markdown-ish text (spec §11.3). Both import routes produce
/// these: a downloaded .docx/.md/.txt, or a Markdown file Claude wrote from a Google Doc via the
/// connector (with the frontmatter in docs/google-docs-import.md).
public struct ImportDocument: Sendable {
    public enum Format: String, Codable, Sendable { case markdown, text, docx }

    public static let supportedExtensions: [String: Format] = ["md": .markdown, "markdown": .markdown, "txt": .text, "docx": .docx]

    public var name: String
    public var format: Format
    /// Body text with any frontmatter removed.
    public var text: String
    /// The file as it was read, attached to every entry it produces for provenance.
    public var original: Data

    // From frontmatter, all optional.
    public var title: String?
    public var type: EntryType?
    public var tags: [TagPath] = []
    /// A date for the whole document (`date`, `occurred_at` or `created`).
    public var date: String?
    public var timeZone: String?
    public var sourceURL: String?
    public var googleDocId: String?

    /// Used when the text has no dates: frontmatter `modified`, the .docx's own modified date,
    /// or the file's modification time, in that order.
    public var fallbackDate: Date?
    public var fallbackDateSource: String?

    public init(name: String, data: Data, modified: Date? = nil) throws {
        let ext = (name as NSString).pathExtension.lowercased()
        guard let format = Self.supportedExtensions[ext] else { throw ImportError.unsupported(name) }
        self.name = name
        self.format = format
        self.original = data
        switch format {
        case .docx:
            text = try DocxReader.markdown(from: data)
            if let d = DocxReader.modifiedDate(from: data) { fallbackDate = d; fallbackDateSource = "document modified" }
        case .markdown, .text:
            guard var s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw ImportError.badFile("\(name) is not text")
            }
            if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
            s = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let (fm, body) = Frontmatter.split(s)
            text = body
            apply(fm)
        }
        if fallbackDate == nil, let modified { fallbackDate = modified; fallbackDateSource = "file modified" }
    }

    /// Reads a file from disk.
    public static func load(_ url: URL) throws -> ImportDocument {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ImportError.badFile("cannot read \(url.lastPathComponent): \(error)") }
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return try ImportDocument(name: url.lastPathComponent, data: data, modified: modified)
    }

    /// "Magical diary 2024" for display: the frontmatter title or the file name without extension.
    public var displayName: String { title ?? (name as NSString).deletingPathExtension }

    /// Inbox `source`: `import:gdoc:<id>` for connector imports, `import:<file name>` otherwise.
    public var sourceLabel: String { googleDocId.map { "import:gdoc:\($0)" } ?? "import:\(name)" }

    mutating func apply(_ fm: [String: Frontmatter.Value]) {
        title = fm["title"]?.string
        type = fm["type"]?.string.flatMap { EntryType(rawValue: $0.lowercased()) }
        tags = (fm["tags"]?.list ?? []).map { TagPath($0.hasPrefix("#") ? String($0.dropFirst()) : $0) }.filter { !$0.isEmpty }
        date = fm["occurred_at"]?.string ?? fm["date"]?.string ?? fm["created"]?.string
        timeZone = fm["time_zone"]?.string.flatMap { TimeZone(identifier: $0) != nil ? $0 : nil }
        sourceURL = fm["source_url"]?.string ?? fm["google_doc_url"]?.string
        googleDocId = fm["google_doc_id"]?.string
        if let m = fm["modified"]?.string, let d = GrimoireDateFormat.parseISO(m) { fallbackDate = d; fallbackDateSource = "document modified" }
    }
}

/// The small subset of YAML frontmatter that imported notes use: `key: value`, quoted values,
/// inline `[a, b]` lists and block `- item` lists.
public enum Frontmatter {
    public enum Value: Equatable, Sendable {
        case scalar(String)
        case list([String])
        public var string: String? { if case .scalar(let s) = self, !s.isEmpty { return s }; return nil }
        public var list: [String] {
            switch self {
            case .list(let l): return l
            case .scalar(let s): return s.isEmpty ? [] : s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
    }

    /// Splits `---\n…\n---\n` off the top. Text without frontmatter comes back unchanged.
    public static func split(_ s: String) -> ([String: Value], String) {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return ([:], s) }
        var out: [String: Value] = [:]
        var listKey: String?
        for line in lines[1..<end] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            if t.hasPrefix("- "), let k = listKey {
                out[k] = .list((out[k]?.list ?? []) + [unquote(String(t.dropFirst(2)))])
                continue
            }
            guard let colon = t.firstIndex(of: ":") else { continue }
            let key = t[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let raw = t[t.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if raw.isEmpty { listKey = key; out[key] = .list([]); continue }
            listKey = nil
            if raw.hasPrefix("["), raw.hasSuffix("]") {
                out[key] = .list(raw.dropFirst().dropLast().split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty })
            } else {
                out[key] = .scalar(unquote(raw))
            }
        }
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (out, body)
    }

    static func unquote(_ s: String) -> String {
        guard s.count >= 2, let f = s.first, let l = s.last, f == l, f == "\"" || f == "'" else { return s }
        return String(s.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
    }
}

public enum ImportError: Error, Equatable, CustomStringConvertible {
    case unsupported(String)
    case badFile(String)
    public var description: String {
        switch self {
        case .unsupported(let n): return "Not an importable file (.md, .markdown, .txt, .docx): \(n)"
        case .badFile(let s): return "Cannot import: \(s)"
        }
    }
}
