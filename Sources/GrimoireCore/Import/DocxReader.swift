import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Turns a .docx (Word, or Google Docs → File → Download → .docx, or Google Takeout) into
/// Markdown-ish text: headings keep their level as `#`, list items become `- `, table rows
/// become `a | b | c`. Formatting is dropped; the importer only needs structure and words.
public enum DocxReader {
    public static func markdown(from data: Data) throws -> String {
        let zip = try ZipArchive(data: data)
        let xml = try zip.contents(of: "word/document.xml")
        let handler = DocumentXMLHandler()
        let parser = XMLParser(data: xml)
        parser.delegate = handler
        guard parser.parse() else {
            throw ImportError.badFile("word/document.xml is not valid XML: \(parser.parserError.map { "\($0)" } ?? "unknown error")")
        }
        return handler.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// `dcterms:modified` (or `created`) from docProps/core.xml, used when a document has no dates in it.
    public static func modifiedDate(from data: Data) -> Date? {
        guard let zip = try? ZipArchive(data: data), let core = try? zip.contents(of: "docProps/core.xml") else { return nil }
        let s = String(decoding: core, as: UTF8.self)
        for tag in ["dcterms:modified", "dcterms:created"] {
            if let r = s.range(of: "<\(tag)[^>]*>([^<]+)</\(tag)>", options: .regularExpression) {
                let inner = s[r].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                if let d = GrimoireDateFormat.parseISO(inner.trimmingCharacters(in: .whitespaces)) { return d }
            }
        }
        return nil
    }
}

final class DocumentXMLHandler: NSObject, XMLParserDelegate {
    var lines: [String] = []

    private var paragraph = ""
    private var prefix = ""
    private var inText = false
    private var tableDepth = 0
    private var row: [String] = []
    private var cell: [String] = []

    /// "w:p" → "p"; works whether or not the parser reports prefixes.
    private func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch local(elementName) {
        case "p": paragraph = ""; prefix = ""
        case "pStyle":
            let style = (attributes["w:val"] ?? attributes["val"] ?? "").lowercased().replacingOccurrences(of: " ", with: "")
            if style == "title" { prefix = "# " }
            else if style.hasPrefix("heading"), let n = Int(style.dropFirst("heading".count)), (1...6).contains(n) {
                prefix = String(repeating: "#", count: n) + " "
            }
        case "numPr": if prefix.isEmpty { prefix = "- " }
        case "t": inText = true
        case "tab": paragraph += "\t"
        case "br", "cr": paragraph += "\n"
        case "tbl": tableDepth += 1
        case "tr": row = []
        case "tc": cell = []
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { paragraph += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch local(elementName) {
        case "t": inText = false
        case "p":
            let text = paragraph.trimmingCharacters(in: .whitespaces)
            if tableDepth > 0 { if !text.isEmpty { cell.append(text) } }
            else { lines.append(text.isEmpty ? "" : prefix + text) }
        case "tc": row.append(cell.joined(separator: " "))
        case "tr": if tableDepth == 1, row.contains(where: { !$0.isEmpty }) { lines.append(row.joined(separator: " | ")) }
        case "tbl": tableDepth -= 1; if tableDepth == 0 { lines.append("") }
        default: break
        }
    }
}
