import Foundation

/// Astro context auto-fill (spec §8). New records get timing at save; this pass fills records that
/// have none (older stores, manual adds) or, with `overwrite`, recomputes all of them. A record keeps
/// the location it was reckoned at; `location` (the home location) is used for records without one.
/// Transits and Uranian midpoints come later.
public extension GrimoireRepository {
    /// Returns how many entries and inquiries were updated. Inbox items are left to confirm.
    /// "Missing" also covers timing saved without a location, which has no planetary day or hour.
    @discardableResult
    func fillTiming(location: GeoLocation?, overwrite: Bool = false) -> Int {
        func needs(_ t: TimingContext?) -> Bool {
            guard let t else { return true }
            return overwrite || (location != nil && t.location == nil && t.planetaryDay == nil)
        }
        var n = 0
        for var e in data.entries where needs(e.timing) {
            e.timing = TimingContext.compute(at: e.occurredAt, location: e.timing?.location ?? location, timeKnown: e.timing.map(\.timeKnown) ?? true)
            save(e); n += 1
        }
        for var i in data.inquiries where needs(i.timing) {
            i.timing = TimingContext.compute(at: i.askedAt, location: i.timing?.location ?? location, timeKnown: i.timing.map(\.timeKnown) ?? true)
            save(i); n += 1
        }
        return n
    }
}

extension TimingContext {
    /// A record that was reckoned with a location but has a day and no hour was dated without a time.
    var timeKnown: Bool { !(planetaryDay != nil && planetaryHour == nil) }
}
