import Foundation

/// The chart of an entry's moment, computed by Uranika (Hugh's Uranian astrology app) and stored
/// on the entry so it is searchable and exportable. Positions are ecliptic longitudes, 0…360°,
/// keyed by Uranika's two-letter formula codes (SU, MO … PO, AS, MC, AR).
public struct AstroSnapshot: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case computed
        /// Uranika was not reachable (or failed); `UranikaAstrologer.fillPending` tries again later.
        case pending
    }

    public var status: Status
    public var source: String
    public var computedAt: Date?
    public var place: AstroPlace?
    /// The sky at the moment: planets, Node and the eight transneptunians.
    public var points: [String: Double]
    /// Ascendant and Meridian at `place`; nil without a place.
    public var asc: Double?
    public var mc: Double?
    /// The natal chart the hits are measured against.
    public var natal: NatalRef?
    public var settings: HitSettings
    /// True solar arc of the natal chart at the moment.
    public var solarArc: Double?
    /// Transits and solar arcs to natal points and midpoints, tightest first.
    public var hits: [AstroHit]
    /// Id of the life event this entry created in Uranika's case file, if any.
    public var uranikaEvent: Int?
    /// Why the snapshot is pending or partial, in plain words.
    public var note: String?

    public init(status: Status, source: String = "uranika", computedAt: Date? = nil, place: AstroPlace? = nil,
                points: [String: Double] = [:], asc: Double? = nil, mc: Double? = nil, natal: NatalRef? = nil,
                settings: HitSettings = HitSettings(), solarArc: Double? = nil, hits: [AstroHit] = [],
                uranikaEvent: Int? = nil, note: String? = nil) {
        self.status = status; self.source = source; self.computedAt = computedAt; self.place = place
        self.points = points; self.asc = asc; self.mc = mc; self.natal = natal; self.settings = settings
        self.solarArc = solarArc; self.hits = hits; self.uranikaEvent = uranikaEvent; self.note = note
    }

    public static func pending(place: AstroPlace?, settings: HitSettings, note: String) -> AstroSnapshot {
        AstroSnapshot(status: .pending, place: place, settings: settings, note: note)
    }
}

/// Where the chart is cast. Coordinates are rounded on arrival (see `UranikaSettings.coordinateDecimals`).
public struct AstroPlace: Codable, Hashable, Sendable {
    public var name: String?
    public var latitude: Double
    public var longitude: Double

    public init(name: String? = nil, latitude: Double, longitude: Double) {
        self.name = name; self.latitude = latitude; self.longitude = longitude
    }

    /// 2 decimals is about 1 km: enough for a chart (the angles move by a few arc-seconds), not a street address.
    public func rounded(_ decimals: Int) -> AstroPlace {
        let f = pow(10, Double(max(0, decimals)))
        return AstroPlace(name: name, latitude: (latitude * f).rounded() / f, longitude: (longitude * f).rounded() / f)
    }
}

public struct NatalRef: Codable, Hashable, Sendable {
    /// The chart's id in Uranika's `charts.db`.
    public var uranikaChart: Int
    public var name: String
    public init(uranikaChart: Int, name: String) { self.uranikaChart = uranikaChart; self.name = name }
}

/// Uranika's own defaults: the 90° dial (hits at the 45° family) with a 1° direction orb, Q2 rate.
public struct HitSettings: Codable, Hashable, Sendable {
    public var modulus: Double
    public var orb: Double
    public var rate: String
    /// Hits kept per method (transit, solar arc), tightest first.
    public var maxHits: Int

    public init(modulus: Double = 45, orb: Double = 1, rate: String = "q2", maxHits: Int = 20) {
        self.modulus = modulus; self.orb = orb; self.rate = rate; self.maxHits = maxHits
    }
}

/// A moving point (transit or solar arc) on a natal point or midpoint.
public struct AstroHit: Codable, Hashable, Sendable {
    public enum Method: String, Codable, Sendable {
        case transit
        case solarArc = "solar-arc"
        var prefix: String { self == .transit ? "T" : "D" }
    }
    public var method: Method
    /// The moving point's code, e.g. SA.
    public var mover: String
    /// One natal point, or the two points of a natal midpoint.
    public var target: [String]
    /// The aspect for a point hit (0, 45, 90 … 180); nil for a midpoint.
    public var angle: Double?
    /// Degrees from exact.
    public var orb: Double

    public init(method: Method, mover: String, target: [String], angle: Double?, orb: Double) {
        self.method = method; self.mover = mover; self.target = target; self.angle = angle; self.orb = orb
    }

    /// Reads like Uranika's Directions table: `T-SA □ R-MC`, `D-JU = R-SU/MO`.
    public var formula: String {
        let r = "R-" + target.joined(separator: "/")
        if target.count == 2 { return "\(method.prefix)-\(mover) = \(r)" }
        return "\(method.prefix)-\(mover) \(UranianMath.aspectSymbol(angle ?? 0)) \(r)"
    }

    /// `T-SA □ R-MC 0°24′`
    public var label: String { "\(formula) \(UranianMath.formatDegrees(orb))" }
}
