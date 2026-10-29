import Foundation

/// A colour from the house palette, with an opacity.
public struct HouseInk: Hashable, Sendable {
    public let hex: UInt32
    public let alpha: Double

    public init(_ hex: UInt32, _ alpha: Double = 1) {
        self.hex = hex
        self.alpha = alpha
    }

    /// Red, green and blue from 0 to 1, laid over `ground` when see-through.
    public func rgb(over ground: HouseInk? = nil) -> (r: Double, g: Double, b: Double) {
        func parts(_ hex: UInt32) -> (Double, Double, Double) {
            (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
        }
        let top = parts(hex)
        guard alpha < 1, let ground else { return top }
        let under = ground.rgb()
        return (top.0 * alpha + under.r * (1 - alpha),
                top.1 * alpha + under.g * (1 - alpha),
                top.2 * alpha + under.b * (1 - alpha))
    }

    /// WCAG contrast ratio of this colour (laid over `ground`) against `ground`.
    public func contrast(on ground: HouseInk) -> Double {
        func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
            func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
        }
        let a = luminance(rgb(over: ground)), b = luminance(ground.rgb())
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// The colours of one style in light or dark mode. nil keeps Apple's own.
public struct HouseMode: Hashable, Sendable {
    public let ground, surface, ink, muted, rule, rubric, rubricText: HouseInk?

    public init(ground: HouseInk?, surface: HouseInk?, ink: HouseInk?, muted: HouseInk?,
                rule: HouseInk?, rubric: HouseInk?, rubricText: HouseInk?) {
        self.ground = ground
        self.surface = surface
        self.ink = ink
        self.muted = muted
        self.rule = rule
        self.rubric = rubric
        self.rubricText = rubricText
    }
}

/// An easing curve and its length.
public struct HouseMotion: Hashable, Sendable {
    public let curve: (Double, Double, Double, Double)
    public let seconds: Double

    public init(curve: (Double, Double, Double, Double), seconds: Double) {
        self.curve = curve
        self.seconds = seconds
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.curve == b.curve && a.seconds == b.seconds
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(seconds)
    }
}

/// One style option (System, A, B, C). Font names nil keep Apple's San Francisco.
public struct HouseStyleTokens: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let titleFont: String?
    public let textFont: String?
    public let labelFont: String?
    /// Titles in tracked capitals.
    public let titleCaps: Bool
    /// Corner radius for drawn cards and tags. nil keeps Apple's.
    public let radius: Double?
    /// The style is always dark, whatever the Mac's mode.
    public let forceDark: Bool
    /// The accent becomes rubric red, replacing the accent chosen in Settings.
    public let accentIsRubric: Bool
    public let light: HouseMode
    public let dark: HouseMode

    /// Apple's look, with no house style.
    public var isSystem: Bool { id == "system" }

    /// The style with this id, or System.
    public static func style(_ id: String) -> HouseStyleTokens {
        HouseTokens.styles.first { $0.id == id } ?? HouseTokens.styles[0]
    }
}
