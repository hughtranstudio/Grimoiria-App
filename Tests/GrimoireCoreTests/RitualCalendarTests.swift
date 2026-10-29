import XCTest
@testable import GrimoireCore

final class RitualCalendarTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!
    let la = TimeZone(identifier: "America/Los_Angeles")!
    let sf = GeoLocation(latitude: 37.77, longitude: -122.42)

    func iso(_ s: String) -> Date { GrimoireDateFormat.parseISO(s)! }

    /// 2026 eclipses mark exact lunations: annular solar 17 Feb, total lunar 3 Mar, total solar 12 Aug, partial lunar 28 Aug.
    func testLunationsMatchKnownEclipses() {
        let events = RitualCalendar.events(from: iso("2026-02-01T00:00:00Z"), to: iso("2026-09-01T00:00:00Z"), kinds: [.newMoon, .fullMoon])
        func near(_ kind: SkyEvent.Kind, _ when: String, hours: Double = 6) -> SkyEvent? {
            events.first { $0.kind == kind && abs($0.at.timeIntervalSince(iso(when))) < hours * 3600 }
        }
        XCTAssertNotNil(near(.newMoon, "2026-02-17T12:01:00Z"), "\(events)")
        XCTAssertNotNil(near(.fullMoon, "2026-03-03T11:38:00Z"))
        XCTAssertNotNil(near(.newMoon, "2026-08-12T17:37:00Z"))
        XCTAssertNotNil(near(.fullMoon, "2026-08-28T04:18:00Z"))
        XCTAssertEqual(near(.newMoon, "2026-02-17T12:01:00Z")?.sign, .aquarius)
        XCTAssertEqual(near(.fullMoon, "2026-03-03T11:38:00Z")?.sign, .virgo)
        // About one new and one full Moon a month, never two of a kind within 25 days.
        let news = events.filter { $0.kind == .newMoon }
        XCTAssertEqual(news.count, 7)
        XCTAssertTrue(zip(news, news.dropFirst()).allSatisfy { $1.at.timeIntervalSince($0.at) > 25 * 86_400 })
    }

    func testIngresses() {
        // The Sun enters Aries at the March equinox, 20 Mar 2026 about 14:46 UTC.
        let sun = RitualCalendar.events(from: iso("2026-03-15T00:00:00Z"), to: iso("2026-03-25T00:00:00Z"), kinds: [.sunIngress])
        XCTAssertEqual(sun.count, 1)
        XCTAssertEqual(sun.first?.sign, .aries)
        XCTAssertLessThan(abs(sun[0].at.timeIntervalSince(iso("2026-03-20T14:46:00Z"))), 2 * 3600)
        // The Moon changes sign every two to three days: 12 or 13 times a month.
        let moon = RitualCalendar.events(from: iso("2026-03-01T00:00:00Z"), to: iso("2026-03-31T00:00:00Z"), kinds: [.moonIngress])
        XCTAssertTrue((11...14).contains(moon.count), "\(moon.count)")
        for (a, b) in zip(moon, moon.dropFirst()) {
            XCTAssertEqual(ZodiacSign.allCases.firstIndex(of: b.sign), (ZodiacSign.allCases.firstIndex(of: a.sign)! + 1) % 12)
        }
    }

    func testPlanetaryHoursOfADay() throws {
        // 2026-10-27 is a Tuesday: the day of Mars, whose first hour is Mars, then the Sun, Venus, …
        let hours = RitualCalendar.hours(on: "2026-10-27", location: sf, zone: la)
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours.prefix(3).map(\.planet), [.mars, .sun, .venus])
        XCTAssertEqual(hours[12].planet, Planet.chaldean[(Planet.chaldean.firstIndex(of: .mars)! + 12) % 7])
        XCTAssertTrue(zip(hours, hours.dropFirst()).allSatisfy { abs($0.end.timeIntervalSince($1.start)) < 1 })
        // In autumn the day hours are shorter than the night hours.
        XCTAssertLessThan(hours[0].end.timeIntervalSince(hours[0].start), hours[12].end.timeIntervalSince(hours[12].start))
        // Agrees with the hour TimingContext gives for a moment inside a slot.
        for slot in [hours[2], hours[15]] {
            let mid = slot.start.addingTimeInterval(slot.end.timeIntervalSince(slot.start) / 2)
            let t = TimingContext.compute(at: ZonedDate(mid, timeZone: la.identifier), location: sf)
            XCTAssertEqual(t.planetaryHour, slot.planet)
            XCTAssertEqual(t.planetaryHourNumber, slot.number)
            XCTAssertEqual(t.planetaryDay, .mars)
        }
    }

    func testDaysAndNextHours() throws {
        let days = RitualCalendar.days(from: "2026-10-26", count: 7, zone: la, location: sf)
        XCTAssertEqual(days.map(\.day), ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01"])
        XCTAssertEqual(days.map(\.ruler), [.moon, .mars, .mercury, .jupiter, .venus, .saturn, .sun])
        XCTAssertTrue(days.allSatisfy { $0.hours.count == 24 && $0.sunrise != nil })
        XCTAssertTrue(days.flatMap(\.events).contains { $0.kind == .moonIngress })
        XCTAssertTrue(RitualCalendar.days(from: "2026-10-26", count: 2, zone: la, location: nil).allSatisfy(\.hours.isEmpty))

        let after = iso("2026-10-28T20:00:00Z")
        let mars = RitualCalendar.nextHours(of: .mars, after: after, location: sf, zone: la, limit: 3)
        XCTAssertEqual(mars.count, 3)
        XCTAssertTrue(mars.allSatisfy { $0.planet == .mars && $0.end > after })
        let onTuesday = RitualCalendar.nextHours(of: .mars, after: after, location: sf, zone: la, onItsDay: true, limit: 2)
        XCTAssertTrue(onTuesday.allSatisfy { RitualCalendar.dayString($0.start, zone: la) == "2026-11-03" })
    }
}
