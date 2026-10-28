import Foundation

/// Minimal, deterministic YAML emitter for frontmatter. Keys keep insertion order.
public indirect enum YAMLValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case list([YAMLValue])
    case map([(String, YAMLValue)])

    public static func == (a: YAMLValue, b: YAMLValue) -> Bool { a.render(indent: 0) == b.render(indent: 0) }

    static func str(_ s: String?) -> YAMLValue { s.map { .string($0) } ?? .null }

    var isScalar: Bool {
        switch self { case .list, .map: return false; default: return true }
    }

    var isEmptyCollection: Bool {
        switch self { case .list(let l): return l.isEmpty; case .map(let m): return m.isEmpty; default: return false }
    }

    func scalar() -> String {
        switch self {
        case .string(let s): return YAML.quote(s)
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .list(let l) where l.isEmpty: return "[]"
        case .map(let m) where m.isEmpty: return "{}"
        default: return ""
        }
    }

    /// Lists of scalars render inline (`[a, b]`), everything else in block style.
    func render(indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch self {
        case .map(let pairs) where !pairs.isEmpty:
            return pairs.map { k, v in
                if v.isScalar || v.isEmptyCollection || v.isInlineList { return "\(pad)\(k): \(v.inline())" }
                return "\(pad)\(k):\n\(v.render(indent: indent + 1))"
            }.joined(separator: "\n")
        case .list(let items) where !items.isEmpty:
            return items.map { item in
                if item.isScalar || item.isInlineList { return "\(pad)- \(item.inline())" }
                let body = item.render(indent: indent + 1)
                // "- key: v" on the first line, the rest aligned under it.
                let trimmed = body.drop(while: { $0 == " " })
                return "\(pad)- \(trimmed)"
            }.joined(separator: "\n")
        default:
            return pad + scalar()
        }
    }

    var isInlineList: Bool {
        if case .list(let l) = self { return !l.isEmpty && l.allSatisfy(\.isScalar) }
        return false
    }

    func inline() -> String {
        if case .list(let l) = self, isInlineList { return "[" + l.map { $0.scalar() }.joined(separator: ", ") + "]" }
        return scalar()
    }
}

public enum YAML {
    static let reserved: Set<String> = ["true", "false", "yes", "no", "on", "off", "null", "~", "y", "n"]

    public static func quote(_ s: String) -> String {
        func matches(_ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }
        let safe = matches(#"^[A-Za-z0-9_][A-Za-z0-9 _/.\-]*$"#)
        // Things a YAML parser would turn into numbers or dates.
        let numberLike = matches(#"^[-+]?[0-9_.]+([eE][-+]?[0-9]+)?$"#) || matches(#"^0[xXoObB]"#) || matches(#"^[0-9]{4}-[0-9]{2}-[0-9]{2}"#)
        if safe && !numberLike && !s.hasSuffix(" ") && !reserved.contains(s.lowercased()) { return s }
        var out = "\""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default: out.append(ch)
            }
        }
        return out + "\""
    }

    public static func frontmatter(_ value: YAMLValue, comment: String? = nil) -> String {
        var s = "---\n"
        if let comment { s += "# \(comment)\n" }
        s += value.render(indent: 0) + "\n---\n"
        return s
    }
}
