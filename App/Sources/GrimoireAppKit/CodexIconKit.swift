/// The Codex icon set as plain data, drawn by UI/CodexIcon.swift. The icons themselves are
/// generated into CodexIcons.swift from Design/codex/icons.ts (the Hugh Tran site's set).
///
/// Optical sizes, as a typeface has caption, text and display cuts: line weights are real points
/// from the Brand Codex, so a small icon gets relatively heavier lines and drops its fine detail.
public enum CodexIconWeight: Sendable { case stroke, hair, fill }

/// One step of a path on the 24-unit grid, already absolute (arcs turned into curves).
public enum CodexPathOp: Sendable, Equatable {
    case move(Double, Double)
    case line(Double, Double)
    case curve(Double, Double, Double, Double, Double, Double)
    case close
}

public struct CodexIconPart: Sendable {
    public let weight: CodexIconWeight
    /// Left out of the caption cut.
    public let detail: Bool
    public let ops: [CodexPathOp]

    public init(weight: CodexIconWeight, detail: Bool, ops: [CodexPathOp]) {
        self.weight = weight
        self.detail = detail
        self.ops = ops
    }
}

public struct CodexIconDef: Sendable, Identifiable {
    public let name: String
    public let title: String
    public let parts: [CodexIconPart]
    public var id: String { name }

    public init(name: String, title: String, parts: [CodexIconPart]) {
        self.name = name
        self.title = title
        self.parts = parts
    }
}

/// The cut an icon is drawn in at a size, and its line weights in points.
public struct CodexIconCut: Equatable, Sendable {
    public enum Kind: Sendable { case caption, text, display }
    public let kind: Kind
    public let stroke: Double
    public let hair: Double

    public static func at(_ size: Double) -> CodexIconCut {
        typealias S = CodexIcons.Scale
        if size <= S.captionTo { return .init(kind: .caption, stroke: S.captionStroke, hair: S.captionHair) }
        if size <= S.textTo { return .init(kind: .text, stroke: S.textStroke, hair: S.textHair) }
        return .init(kind: .display, stroke: S.displayStroke, hair: S.displayHair)
    }

    /// The parts drawn in this cut: the caption cut leaves out fine detail.
    public func parts(of icon: CodexIconDef) -> [CodexIconPart] {
        kind == .caption ? icon.parts.filter { !$0.detail } : icon.parts
    }
}
