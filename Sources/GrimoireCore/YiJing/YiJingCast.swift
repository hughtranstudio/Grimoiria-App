import Foundation

/// A Yi Jing cast (spec §4). Hexagrams are derived from the lines so they can't disagree.
public struct YiJingCast: Codable, Hashable, Sendable {
    public enum Method: String, Codable, Sendable { case coins, yarrow, other }

    public var method: Method
    /// Six values bottom → top, each 6, 7, 8 or 9.
    public private(set) var lines: [Int]
    public var notes: String?

    public init(lines: [Int], method: Method = .coins, notes: String? = nil) throws {
        guard lines.count == 6 else { throw YiJingError.wrongLineCount(lines.count) }
        if let bad = lines.first(where: { !(6...9).contains($0) }) { throw YiJingError.invalidLineValue(bad) }
        self.lines = lines
        self.method = method
        self.notes = notes
    }

    /// Parses six digits such as "789676" (quick cast, spec §9.1). Spaces are ignored.
    public init(quick: String, method: Method = .coins) throws {
        let digits = quick.compactMap { $0.wholeNumberValue }
        try self.init(lines: digits, method: method)
    }

    public static func isYang(_ v: Int) -> Bool { v == 7 || v == 9 }
    public static func isChanging(_ v: Int) -> Bool { v == 6 || v == 9 }

    public var primaryLines: [Bool] { lines.map(Self.isYang) }

    /// 1-based positions of changing lines, bottom → top.
    public var changingLines: [Int] { lines.enumerated().filter { Self.isChanging($0.element) }.map { $0.offset + 1 } }

    /// Lines after changing lines flip; nil when nothing changes.
    public var resultingLines: [Bool]? {
        changingLines.isEmpty ? nil : lines.map { Self.isChanging($0) ? !Self.isYang($0) : Self.isYang($0) }
    }

    public func primaryHexagram(in def: YiJingDefinition) -> Int { def.number(forLines: primaryLines)! }
    public func resultingHexagram(in def: YiJingDefinition) -> Int? { resultingLines.flatMap(def.number(forLines:)) }

    enum CodingKeys: String, CodingKey { case method, lines, notes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(lines: try c.decode([Int].self, forKey: .lines),
                      method: try c.decodeIfPresent(Method.self, forKey: .method) ?? .coins,
                      notes: try c.decodeIfPresent(String.self, forKey: .notes))
    }
}

public enum YiJingError: Error, Equatable, CustomStringConvertible {
    case wrongLineCount(Int)
    case invalidLineValue(Int)
    public var description: String {
        switch self {
        case .wrongLineCount(let n): return "A cast needs 6 lines, got \(n)"
        case .invalidLineValue(let v): return "Line value \(v) is not 6, 7, 8 or 9"
        }
    }
}
