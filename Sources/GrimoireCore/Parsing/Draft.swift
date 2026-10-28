import Foundation

/// Confidence attached to every parsed field. The Inbox highlights anything not `high`.
public enum Confidence: String, Codable, Comparable, Sendable {
    case missing, low, medium, high
    static func from(score: Double) -> Confidence { score >= 0.999 ? .high : score >= 0.9 ? .medium : .low }
    public static func < (a: Confidence, b: Confidence) -> Bool {
        let order: [Confidence] = [.missing, .low, .medium, .high]
        return order.firstIndex(of: a)! < order.firstIndex(of: b)!
    }
}

/// A value the parser proposed, the words it heard, and how sure it is.
public struct Parsed<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var value: Value?
    public var heard: String?
    public var confidence: Confidence
    public init(_ value: Value?, heard: String? = nil, confidence: Confidence) {
        self.value = value; self.heard = heard; self.confidence = confidence
    }
    public static var missing: Parsed { Parsed(nil, confidence: .missing) }
}

/// Parser output: a draft Inquiry waiting for confirm-and-correct (spec §12 step 2a/3a).
/// Nothing here is a filed record.
public struct DraftReading: Codable, Hashable, Sendable {
    public var question: Parsed<String>
    public var divinations: [DraftDivination]
    /// Words the parser could not place, shown beside the transcript.
    public var unparsed: [String]
    public var warnings: [String]

    public init(question: Parsed<String> = .missing, divinations: [DraftDivination] = [], unparsed: [String] = [], warnings: [String] = []) {
        self.question = question; self.divinations = divinations; self.unparsed = unparsed; self.warnings = warnings
    }

    public var isEmpty: Bool { divinations.isEmpty }

    /// Lowest confidence across all fields; drives the Inbox badge.
    public var weakest: Confidence {
        var all: [Confidence] = []
        for d in divinations {
            all.append(contentsOf: [d.deckId.confidence, d.spreadId.confidence].filter { $0 != .missing || d.system == .cards })
            all.append(contentsOf: d.draws.flatMap { [$0.cardId.confidence, $0.orientation.confidence] })
            if let c = d.cast { all.append(c.lines.confidence) }
        }
        return all.min() ?? .missing
    }
}

public struct DraftDivination: Codable, Hashable, Sendable {
    public var system: Divination.System
    public var deckId: Parsed<String>
    public var spreadId: Parsed<String>
    public var draws: [DraftDraw]
    public var cast: DraftCast?
    public var heard: String

    public init(system: Divination.System, deckId: Parsed<String> = .missing, spreadId: Parsed<String> = .missing, draws: [DraftDraw] = [], cast: DraftCast? = nil, heard: String = "") {
        self.system = system; self.deckId = deckId; self.spreadId = spreadId; self.draws = draws; self.cast = cast; self.heard = heard
    }
}

public struct DraftDraw: Codable, Hashable, Sendable {
    public var cardId: Parsed<String>
    public var orientation: Parsed<Orientation>
    public var positionKey: String
    public init(cardId: Parsed<String>, orientation: Parsed<Orientation>, positionKey: String) {
        self.cardId = cardId; self.orientation = orientation; self.positionKey = positionKey
    }
}

public struct DraftCast: Codable, Hashable, Sendable {
    public var lines: Parsed<[Int]>
    public var method: YiJingCast.Method
    public init(lines: Parsed<[Int]>, method: YiJingCast.Method) { self.lines = lines; self.method = method }
}
