import Foundation

/// Transcripts with times: "[03:12] I see a red door" or "[1:02:05] …" at the start of a line.
public enum TimedTranscript {
    /// Segments from a transcript. Lines without a time join the segment before them; a transcript
    /// with no times at all is one segment at 0.
    public static func parse(_ text: String) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let (t, rest) = stamp(line) {
                out.append(TranscriptSegment(offset: t, text: rest))
            } else if !out.isEmpty {
                out[out.count - 1].text += (out[out.count - 1].text.isEmpty ? "" : " ") + line
            } else {
                out.append(TranscriptSegment(offset: 0, text: line))
            }
        }
        return out.filter { !$0.text.isEmpty }
    }

    /// "[mm:ss]" or "[h:mm:ss]", seconds may have a fraction.
    public static func stamp(_ line: String) -> (Double, String)? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let inside = line[line.index(after: line.startIndex)..<close]
        let parts = inside.split(separator: ":").map { Double($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        let seconds = parts.reduce(0.0) { $0 * 60 + $1! }
        return (seconds, line[line.index(after: close)...].trimmingCharacters(in: .whitespaces))
    }

    /// Writes segments back as "[mm:ss] text" lines (hours when needed).
    public static func format(_ segments: [TranscriptSegment]) -> String {
        segments.map { "[\(clock($0.offset))] \($0.text)" }.joined(separator: "\n")
    }

    public static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// Turns what was said during a session into draft observations and phase changes. Every
/// observation it makes is `spoken` and unreviewed: the Inbox review confirms or fixes it.
public struct ObservationExtractor: Sendable {
    public let vocabulary: TagVocabulary
    /// Words per second, to spread the sentences of a long segment over time.
    public var wordsPerSecond = 2.5

    public init(vocabulary: TagVocabulary = .standard) { self.vocabulary = vocabulary }

    public struct Result: Equatable, Sendable {
        public var observations: [Observation]
        public var phases: [PhaseMark]
    }

    /// `recordingOffset` is when the recording began, in seconds after the session start.
    public func extract(_ segments: [TranscriptSegment], recordingOffset: Double = 0) -> Result {
        var result = Result(observations: [], phases: [])
        let sorted = segments.sorted { $0.offset < $1.offset }
        for (si, seg) in sorted.enumerated() {
            let limit = si + 1 < sorted.count ? sorted[si + 1].offset : .infinity
            var wordsBefore = 0
            for sentence in Self.sentences(seg.text) {
                let words = TagVocabulary.words(sentence)
                let at = recordingOffset + min(seg.offset + Double(wordsBefore) / wordsPerSecond, max(seg.offset, limit - 0.01))
                wordsBefore += words.count
                if let phase = Self.phaseCue(words) {
                    result.phases.append(PhaseMark(phase, at: at))
                    continue
                }
                if Self.isMarkerCue(words) {
                    result.observations.append(Observation(offset: at, kind: .note, capture: .marker, reviewed: false))
                    continue
                }
                guard words.count >= 2 else { continue }
                let tags = vocabulary.suggest(in: sentence)
                result.observations.append(Observation(offset: at, kind: classify(words, tags: tags), text: sentence,
                                                       tags: tags, capture: .spoken, reviewed: false))
            }
        }
        return result
    }

    /// The kind of observation a sentence describes, from cue words and then from its tags.
    public func classify(_ words: [String], tags: [TagPath]) -> ObservationKind {
        let text = " " + words.joined(separator: " ") + " "
        func has(_ cues: [String]) -> Bool { cues.contains { text.contains(" \($0) ") } }
        func tagged(_ facet: String) -> Bool { tags.contains { $0.components.first == facet } }

        if has(["says", "said", "tells me", "told me", "speaks", "spoke", "voice", "words", "message", "whispers", "asks me", "answers"]) { return .message }
        if has(["i hear", "i heard", "hearing", "a sound", "music", "singing"]) { return .sound }
        if has(["i realise", "i realize", "i understand", "i understood", "it means", "insight", "i know that", "the lesson"]) { return .insight }
        if has(["omen", "a sign"]) { return .omen }
        if has(["interrupted", "interruption", "phone", "doorbell", "outside noise", "lost focus", "distracted"]) { return .event }
        if tagged("entity") { return .entity }
        if has(["i feel", "i felt", "feeling", "feels"]) { return tagged("emotion") && !tagged("sense") ? .emotion : .sensation }
        if has(["i am in", "i'm in", "im in", "i find myself", "i stand in", "i arrive", "i am standing in"]) || tagged("place") && !tagged("symbol") { return .place }
        if has(["i invoke", "i call", "i offer", "i light", "i bow", "i ask", "i open", "i close", "i walk", "i step", "i enter", "i place", "i trace"]) { return .action }
        if has(["i see", "i saw", "appears", "appeared", "there is", "there's", "theres", "image", "picture", "shape"]) { return .imagery }
        if tagged("emotion") { return .emotion }
        if tagged("sense") { return .sensation }
        if tagged("symbol") || tagged("color") { return .imagery }
        return .note
    }

    /// "Phase working", "now closing", "begin opening", "starting the closing".
    static func phaseCue(_ words: [String]) -> SessionPhase? {
        func phase(_ w: String) -> SessionPhase? {
            switch w {
            case "preparation", "preparing": return .preparation
            case "opening", "open": return .opening
            case "working", "work": return .working
            case "closing", "close": return .closing
            default: return nil
            }
        }
        guard words.count <= 4, let first = words.first else { return nil }
        // "Closing now", "opening phase"
        if let p = phase(first), words.count > 1, words.dropFirst().allSatisfy({ ["now", "phase", "begins", "starts", "down"].contains($0) }) { return p }
        guard ["phase", "now", "begin", "beginning", "start", "starting", "moving"].contains(first) else { return nil }
        return words.dropFirst().lazy.compactMap(phase).first
    }

    /// A spoken "mark" or "marker" on its own drops a marker.
    static func isMarkerCue(_ words: [String]) -> Bool {
        words.count <= 2 && ["mark", "marker"].contains(words.first ?? "")
    }

    /// Splits at . ! ? and line breaks; keeps the punctuation.
    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in text {
            if ch.isNewline { push(&out, &cur); continue }
            cur.append(ch)
            if ".!?".contains(ch) { push(&out, &cur) }
        }
        push(&out, &cur)
        return out
    }

    private static func push(_ out: inout [String], _ cur: inout String) {
        let t = cur.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { out.append(t) }
        cur = ""
    }
}
