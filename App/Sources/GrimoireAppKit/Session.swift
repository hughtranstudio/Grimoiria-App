import Foundation
import GrimoireCore

/// Names, icons and one-key shortcuts for observation kinds in the session window and editors.
public extension ObservationKind {
    var title: String {
        switch self {
        case .emotion: "Feeling"
        default: rawValue.capitalized
        }
    }

    /// Control-Option-<key> (Session > Observation Kind) picks the kind.
    var key: Character {
        switch self {
        case .imagery: "i"
        case .entity: "e"
        case .place: "p"
        case .symbol: "y"
        case .message: "m"
        case .sound: "h"
        case .sensation: "s"
        case .emotion: "f"
        case .insight: "t"
        case .omen: "o"
        case .event: "v"
        case .action: "a"
        case .note: "n"
        }
    }

    var symbol: String {
        switch self {
        case .imagery: "photo"
        case .entity: "person.wave.2"
        case .place: "mountain.2"
        case .symbol: "seal"
        case .message: "text.bubble"
        case .sound: "ear"
        case .sensation: "hand.raised"
        case .emotion: "heart"
        case .insight: "lightbulb"
        case .omen: "bird"
        case .event: "exclamationmark.circle"
        case .action: "figure.walk"
        case .note: "note.text"
        }
    }

    static func forKey(_ c: Character) -> ObservationKind? {
        allCases.first { $0.key == Character(c.lowercased()) }
    }
}

public extension SessionPhase {
    var title: String { rawValue.capitalized }
    /// The phases you move through while the clock runs; aftermath is for things written later.
    static let live: [SessionPhase] = [.preparation, .opening, .working, .closing]
}

public extension ObservationCapture {
    var title: String {
        switch self {
        case .live: "Typed during"
        case .spoken: "Heard in recording"
        case .recalled: "Written after"
        case .marker: "Marker"
        }
    }
}

/// Text for the session clock and the observation list.
public enum SessionText {
    /// 0:00 style clock: m:ss under an hour, h:mm:ss after.
    public static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "32 min · 12 observations · 3 to check"
    public static func summary(_ s: PracticeSession) -> String {
        var parts: [String] = []
        if let d = s.duration { parts.append("\(Int((d / 60).rounded())) min") }
        parts.append("\(s.observations.count) observation\(s.observations.count == 1 ? "" : "s")")
        if s.unreviewedCount > 0 { parts.append("\(s.unreviewedCount) to check") }
        return parts.joined(separator: " · ")
    }

    /// Tags for a typed observation: the ones typed, else the ones the vocabulary hears in the text.
    public static func tags(typed: String, text: String, vocabulary: TagVocabulary) -> [TagPath] {
        let typedTags = TagInput.parse(typed).map(vocabulary.canonical)
        return typedTags.isEmpty ? vocabulary.suggest(in: text) : typedTags
    }
}

/// The free tags in use, most used first, for promoting into the vocabulary.
public enum FreeTags {
    public static func counts(_ data: GrimoireData, vocabulary: TagVocabulary) -> [(tag: TagPath, count: Int)] {
        var all: [TagPath] = data.entries.flatMap(\.tags)
        all += data.entries.flatMap { $0.session?.observations.flatMap(\.tags) ?? [] }
        all += data.inquiries.flatMap(\.tags)
        let free = all.map(vocabulary.canonical).filter { !vocabulary.isControlled($0) }
        return Dictionary(grouping: free, by: { $0 }).map { ($0.key, $0.value.count) }
            .sorted { ($1.count, $0.tag.path) < ($0.count, $1.tag.path) }
    }
}
