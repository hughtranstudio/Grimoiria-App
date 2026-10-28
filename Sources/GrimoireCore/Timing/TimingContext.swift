import Foundation

public enum ZodiacSign: String, Codable, CaseIterable, Sendable {
    case aries, taurus, gemini, cancer, leo, virgo, libra, scorpio, sagittarius, capricorn, aquarius, pisces

    public static func of(longitude: Double) -> ZodiacSign { allCases[Int(longitude / 30) % 12] }
}

public enum Planet: String, Codable, CaseIterable, Sendable {
    case saturn, jupiter, mars, sun, venus, mercury, moon

    /// Chaldean order, which drives the sequence of planetary hours.
    public static let chaldean: [Planet] = [.saturn, .jupiter, .mars, .sun, .venus, .mercury, .moon]
    /// Ruler of each weekday, Sunday first (Calendar weekday 1…7).
    public static let dayRulers: [Planet] = [.sun, .moon, .mars, .mercury, .jupiter, .venus, .saturn]
}

public enum MoonPhase: String, Codable, Sendable {
    case new = "new", waxingCrescent = "waxing-crescent", firstQuarter = "first-quarter", waxingGibbous = "waxing-gibbous"
    case full = "full", waningGibbous = "waning-gibbous", lastQuarter = "last-quarter", waningCrescent = "waning-crescent"

    /// From the Sun–Moon elongation, 0…360°.
    public static func of(elongation e: Double) -> MoonPhase {
        let order: [MoonPhase] = [.new, .waxingCrescent, .firstQuarter, .waxingGibbous, .full, .waningGibbous, .lastQuarter, .waningCrescent]
        return order[Int(((e + 22.5).truncatingRemainder(dividingBy: 360)) / 45) % 8]
    }
}

public struct GeoLocation: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var name: String?
    public init(latitude: Double, longitude: Double, name: String? = nil) {
        self.latitude = latitude; self.longitude = longitude; self.name = name
    }
}

/// Auto-filled at `occurredAt` and stored on the record so it's exportable (spec §8).
public struct TimingContext: Codable, Hashable, Sendable {
    public var moonPhase: MoonPhase
    /// 0…100
    public var moonIllumination: Int
    public var moonSign: ZodiacSign
    public var sunSign: ZodiacSign
    /// Nil when no location is set or in polar day/night.
    public var planetaryDay: Planet?
    public var planetaryHour: Planet?
    /// True if the Moon or Sun is within 0.5° of a sign boundary (low-precision ephemeris).
    public var nearCusp: Bool

    public init(moonPhase: MoonPhase, moonIllumination: Int, moonSign: ZodiacSign, sunSign: ZodiacSign, planetaryDay: Planet?, planetaryHour: Planet?, nearCusp: Bool) {
        self.moonPhase = moonPhase
        self.moonIllumination = moonIllumination
        self.moonSign = moonSign
        self.sunSign = sunSign
        self.planetaryDay = planetaryDay
        self.planetaryHour = planetaryHour
        self.nearCusp = nearCusp
    }

    public static func compute(at date: ZonedDate, location: GeoLocation?) -> TimingContext {
        let sun = Astronomy.sunLongitude(date.instant)
        let moon = Astronomy.moonLongitude(date.instant)
        let elong = Astronomy.norm360(moon - sun)
        let illum = Int(((1 - cos(elong * Astronomy.deg)) / 2 * 100).rounded())
        func cusp(_ lon: Double) -> Bool { let r = lon.truncatingRemainder(dividingBy: 30); return r < 0.5 || r > 29.5 }
        var day: Planet?
        var hour: Planet?
        if let loc = location, let ph = planetaryHour(at: date.instant, location: loc, zone: date.zone) {
            day = ph.day; hour = ph.hour
        }
        return TimingContext(moonPhase: .of(elongation: elong), moonIllumination: illum, moonSign: .of(longitude: moon),
                             sunSign: .of(longitude: sun), planetaryDay: day, planetaryHour: hour, nearCusp: cusp(sun) || cusp(moon))
    }

    /// Planetary day and hour. The magical day runs sunrise to sunrise; day and night are each
    /// split into 12 unequal hours, and hours follow the Chaldean order from the day's ruler.
    public static func planetaryHour(at instant: Date, location: GeoLocation, zone: TimeZone) -> (day: Planet, hour: Planet)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        func times(_ d: Date) -> (rise: Date, set: Date)? {
            Astronomy.sunTimes(on: d, latitude: location.latitude, longitude: location.longitude, zone: zone)
        }
        guard let today = times(instant) else { return nil }
        let dayStart: Date, periodStart: Date, periodEnd: Date, isNight: Bool
        if instant < today.rise {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: instant), let y = times(yesterday) else { return nil }
            dayStart = y.rise; periodStart = y.set; periodEnd = today.rise; isNight = true
        } else if instant < today.set {
            dayStart = today.rise; periodStart = today.rise; periodEnd = today.set; isNight = false
        } else {
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: instant), let t = times(tomorrow) else { return nil }
            dayStart = today.rise; periodStart = today.set; periodEnd = t.rise; isNight = true
        }
        let weekday = cal.component(.weekday, from: dayStart.addingTimeInterval(60))
        let ruler = Planet.dayRulers[weekday - 1]
        let length = periodEnd.timeIntervalSince(periodStart) / 12
        let n = min(11, Int(instant.timeIntervalSince(periodStart) / length)) + (isNight ? 12 : 0)
        let start = Planet.chaldean.firstIndex(of: ruler)!
        return (ruler, Planet.chaldean[(start + n) % 7])
    }
}
