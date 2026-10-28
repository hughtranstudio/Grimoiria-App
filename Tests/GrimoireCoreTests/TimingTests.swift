import XCTest
@testable import GrimoireCore

final class TimingTests: XCTestCase {
    func utc(_ s: String) -> ZonedDate { ZonedDate.parse(s, timeZone: "UTC")! }

    func testFullAndNewMoon() {
        // Full moon 2024-04-23 23:49 UTC (Sun in Taurus, Moon in Scorpio)
        let full = TimingContext.compute(at: utc("2024-04-23T23:49:00Z"), location: nil)
        XCTAssertEqual(full.moonPhase, .full)
        XCTAssertGreaterThanOrEqual(full.moonIllumination, 99)
        XCTAssertEqual(full.moonSign, .scorpio)
        XCTAssertEqual(full.sunSign, .taurus)
        // New moon / total eclipse 2024-04-08 18:21 UTC at ~19° Aries
        let new = TimingContext.compute(at: utc("2024-04-08T18:21:00Z"), location: nil)
        XCTAssertEqual(new.moonPhase, .new)
        XCTAssertLessThanOrEqual(new.moonIllumination, 1)
        XCTAssertEqual(new.moonSign, .aries)
        XCTAssertEqual(new.sunSign, .aries)
        XCTAssertNil(new.planetaryDay)
    }

    func testSunSignToday() {
        XCTAssertEqual(TimingContext.compute(at: utc("2026-10-28T12:00:00Z"), location: nil).sunSign, .scorpio)
    }

    func testSunriseLondonMidsummer() throws {
        // 2024-06-21 London: sunrise 04:43 BST (03:43 UTC), sunset 21:21 BST (20:21 UTC)
        let zone = TimeZone(identifier: "Europe/London")!
        let day = utc("2024-06-21T12:00:00Z").instant
        let t = try XCTUnwrap(Astronomy.sunTimes(on: day, latitude: 51.5074, longitude: -0.1278, zone: zone))
        XCTAssertEqual(t.rise.timeIntervalSince(utc("2024-06-21T03:43:00Z").instant), 0, accuracy: 120)
        XCTAssertEqual(t.set.timeIntervalSince(utc("2024-06-21T20:21:00Z").instant), 0, accuracy: 120)
    }

    func testPlanetaryHours() throws {
        let london = GeoLocation(latitude: 51.5074, longitude: -0.1278)
        let zone = TimeZone(identifier: "Europe/London")!
        // Sunday 2024-06-23, just after sunrise: day and first hour belong to the Sun.
        let a = try XCTUnwrap(TimingContext.planetaryHour(at: utc("2024-06-23T03:50:00Z").instant, location: london, zone: zone))
        XCTAssertEqual(a.day, .sun); XCTAssertEqual(a.hour, .sun)
        // Second hour of a Sunday follows the Chaldean order: Venus.
        let b = try XCTUnwrap(TimingContext.planetaryHour(at: utc("2024-06-23T05:30:00Z").instant, location: london, zone: zone))
        XCTAssertEqual(b.hour, .venus)
        // Monday 01:00 local, before sunrise: still Sunday's night.
        let c = try XCTUnwrap(TimingContext.planetaryHour(at: utc("2024-06-24T00:00:00Z").instant, location: london, zone: zone))
        XCTAssertEqual(c.day, .sun)
        // First night hour of Sunday is the 13th hour: Sun, Venus, Mercury, Moon, Saturn, Jupiter, Mars, Sun, Venus, Mercury, Moon, Saturn, → Jupiter
        let d = try XCTUnwrap(TimingContext.planetaryHour(at: utc("2024-06-23T20:30:00Z").instant, location: london, zone: zone))
        XCTAssertEqual(d.hour, .jupiter)
    }

    func testPolarNightHasNoPlanetaryHour() {
        let tromso = GeoLocation(latitude: 69.65, longitude: 18.96)
        let t = TimingContext.compute(at: ZonedDate.parse("2024-12-21T12:00:00+01:00", timeZone: "Europe/Oslo")!, location: tromso)
        XCTAssertNil(t.planetaryHour)
    }
}
