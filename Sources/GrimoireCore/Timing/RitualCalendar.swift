import Foundation

/// A moment in the sky worth planning around: the four lunar phases and the Moon or Sun entering a sign.
public struct SkyEvent: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case newMoon = "new-moon", firstQuarter = "first-quarter", fullMoon = "full-moon", lastQuarter = "last-quarter"
        case moonIngress = "moon-ingress", sunIngress = "sun-ingress"
    }
    public var kind: Kind
    public var at: Date
    /// The sign entered (ingress), or the sign the Moon is in (phases).
    public var sign: ZodiacSign

    public var title: String {
        switch kind {
        case .newMoon: return "New Moon in \(sign.rawValue.capitalized)"
        case .firstQuarter: return "First Quarter Moon in \(sign.rawValue.capitalized)"
        case .fullMoon: return "Full Moon in \(sign.rawValue.capitalized)"
        case .lastQuarter: return "Last Quarter Moon in \(sign.rawValue.capitalized)"
        case .moonIngress: return "Moon enters \(sign.rawValue.capitalized)"
        case .sunIngress: return "Sun enters \(sign.rawValue.capitalized)"
        }
    }

    public var isPhase: Bool { [.newMoon, .firstQuarter, .fullMoon, .lastQuarter].contains(kind) }
}

/// One planetary hour: 1–12 run sunrise to sunset, 13–24 sunset to the next sunrise.
public struct PlanetaryHourSlot: Hashable, Codable, Sendable {
    public var number: Int
    public var planet: Planet
    public var start: Date
    public var end: Date
    public var isNight: Bool { number > 12 }
}

/// A civil day as a practitioner plans it: the day's ruler, the Moon at noon, the day's events, and
/// (with a location) sunrise, sunset and the 24 planetary hours of the magical day that starts at sunrise.
public struct CalendarDay: Hashable, Sendable {
    public var day: String
    /// Ruler of the weekday (Sunday the Sun, Monday the Moon, …). The magical day begins at sunrise.
    public var ruler: Planet
    public var moonPhase: MoonPhase
    public var moonIllumination: Int
    public var moonSign: ZodiacSign
    public var sunSign: ZodiacSign
    public var events: [SkyEvent]
    public var sunrise: Date?
    public var sunset: Date?
    public var hours: [PlanetaryHourSlot]
}

/// Moon phases, ingresses and planetary hours ahead, for timing rituals (low-precision ephemeris: event
/// times are good to a few minutes for the Sun and roughly a quarter hour for the Moon).
public enum RitualCalendar {
    static func calendar(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    /// Midnight starting a yyyy-MM-dd day in `zone`.
    public static func start(of day: String, zone: TimeZone) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar(zone).date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    public static func dayString(_ date: Date, zone: TimeZone) -> String { GrimoireDateFormat.day(date, in: zone) }

    /// Every phase and ingress between two instants, in time order.
    public static func events(from: Date, to: Date, kinds: Set<SkyEvent.Kind> = Set(SkyEvent.Kind.allCases)) -> [SkyEvent] {
        guard to > from else { return [] }
        func elongation(_ t: Date) -> Double { Astronomy.norm360(Astronomy.moonLongitude(t) - Astronomy.sunLongitude(t)) }
        let measures: [(SkyEvent.Kind?, (Date) -> Double, Double)] = [
            (nil, elongation, 90),
            (.moonIngress, Astronomy.moonLongitude, 30),
            (.sunIngress, Astronomy.sunLongitude, 30),
        ]
        let phaseKinds: [SkyEvent.Kind] = [.newMoon, .firstQuarter, .fullMoon, .lastQuarter]
        var out: [SkyEvent] = []
        let step: TimeInterval = 3 * 3600
        for (kind, f, size) in measures {
            var t = from
            var bucket = Int(f(t) / size)
            while t < to {
                let next = min(t.addingTimeInterval(step), to)
                let b = Int(f(next) / size)
                if b != bucket {
                    // Bisect to the crossing: the moment the value enters bucket b.
                    var lo = t, hi = next
                    for _ in 0..<24 {
                        let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                        if Int(f(mid) / size) == bucket { lo = mid } else { hi = mid }
                    }
                    let k = kind ?? phaseKinds[b % 4]
                    let sign = ZodiacSign.of(longitude: Astronomy.moonLongitude(hi) + (kind == .moonIngress ? 0.01 : 0))
                    let entered = kind == .sunIngress ? ZodiacSign.of(longitude: Astronomy.sunLongitude(hi) + 0.01) : sign
                    if kinds.contains(k) { out.append(SkyEvent(kind: k, at: hi, sign: entered)) }
                    bucket = b
                }
                t = next
            }
        }
        return out.sorted { $0.at < $1.at }
    }

    /// The 24 planetary hours of the magical day beginning at sunrise on `day`. Empty in polar day or night.
    public static func hours(on day: String, location: GeoLocation, zone: TimeZone) -> [PlanetaryHourSlot] {
        guard let midnight = start(of: day, zone: zone),
              let today = Astronomy.sunTimes(on: midnight.addingTimeInterval(12 * 3600), latitude: location.latitude, longitude: location.longitude, zone: zone),
              let tomorrow = Astronomy.sunTimes(on: midnight.addingTimeInterval(36 * 3600), latitude: location.latitude, longitude: location.longitude, zone: zone)
        else { return [] }
        let ruler = Planet.dayRulers[calendar(zone).component(.weekday, from: midnight.addingTimeInterval(12 * 3600)) - 1]
        let first = Planet.chaldean.firstIndex(of: ruler)!
        let dayLength = today.set.timeIntervalSince(today.rise) / 12
        let nightLength = tomorrow.rise.timeIntervalSince(today.set) / 12
        return (0..<24).map { i in
            let night = i >= 12
            let start = night ? today.set.addingTimeInterval(Double(i - 12) * nightLength) : today.rise.addingTimeInterval(Double(i) * dayLength)
            return PlanetaryHourSlot(number: i + 1, planet: Planet.chaldean[(first + i) % 7], start: start,
                                     end: start.addingTimeInterval(night ? nightLength : dayLength))
        }
    }

    public static func day(_ day: String, zone: TimeZone, location: GeoLocation?) -> CalendarDay? {
        guard let midnight = start(of: day, zone: zone), let next = calendar(zone).date(byAdding: .day, value: 1, to: midnight) else { return nil }
        let noon = midnight.addingTimeInterval(12 * 3600)
        let t = TimingContext.compute(at: ZonedDate(noon, timeZone: zone.identifier), location: nil)
        let sun = location.flatMap { Astronomy.sunTimes(on: noon, latitude: $0.latitude, longitude: $0.longitude, zone: zone) }
        return CalendarDay(day: day, ruler: Planet.dayRulers[calendar(zone).component(.weekday, from: noon) - 1],
                           moonPhase: t.moonPhase, moonIllumination: t.moonIllumination, moonSign: t.moonSign, sunSign: t.sunSign,
                           events: events(from: midnight, to: next), sunrise: sun?.rise, sunset: sun?.set,
                           hours: location.map { hours(on: day, location: $0, zone: zone) } ?? [])
    }

    /// `count` days starting at `first` (yyyy-MM-dd).
    public static func days(from first: String, count: Int, zone: TimeZone, location: GeoLocation?) -> [CalendarDay] {
        guard let start = start(of: first, zone: zone) else { return [] }
        let cal = calendar(zone)
        return (0..<max(0, count)).compactMap { i in
            cal.date(byAdding: .day, value: i, to: start).flatMap { day(dayString($0, zone: zone), zone: zone, location: location) }
        }
    }

    /// The next hours ruled by `planet` after `after`, optionally only on that planet's own day
    /// (the traditional strongest time: an hour of Mars on a Tuesday).
    public static func nextHours(of planet: Planet, after: Date, location: GeoLocation, zone: TimeZone,
                                 onItsDay: Bool = false, limit: Int = 5, searchDays: Int = 21) -> [PlanetaryHourSlot] {
        var out: [PlanetaryHourSlot] = []
        let cal = calendar(zone)
        // Start a day early: the magical day that began yesterday at sunrise runs into this morning.
        guard let first = cal.date(byAdding: .day, value: -1, to: after) else { return [] }
        for i in 0..<searchDays {
            guard let d = cal.date(byAdding: .day, value: i, to: first) else { break }
            let day = dayString(d, zone: zone)
            if onItsDay, Planet.dayRulers[cal.component(.weekday, from: d) - 1] != planet { continue }
            for h in hours(on: day, location: location, zone: zone) where h.planet == planet && h.end > after {
                out.append(h)
                if out.count == limit { return out }
            }
        }
        return out
    }
}
