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

    func testHourNumberAndLocationAreRecorded() {
        let london = GeoLocation(latitude: 51.5074, longitude: -0.1278)
        // Sunday 2024-06-23 21:30 BST: first hour of the night is the 13th hour.
        let t = TimingContext.compute(at: utc("2024-06-23T20:30:00Z"), location: london)
        XCTAssertEqual(t.planetaryHourNumber, 13)
        XCTAssertEqual(t.isNightHour, true)
        XCTAssertEqual(t.location, london)
        let morning = TimingContext.compute(at: utc("2024-06-23T03:50:00Z"), location: london)
        XCTAssertEqual(morning.planetaryHourNumber, 1)
        XCTAssertEqual(morning.isNightHour, false)
    }

    func testDateWithoutTimeKeepsDayDropsHour() {
        let london = GeoLocation(latitude: 51.5074, longitude: -0.1278)
        let t = TimingContext.compute(at: utc("2024-06-23T12:00:00Z"), location: london, timeKnown: false)
        XCTAssertEqual(t.planetaryDay, .sun)
        XCTAssertNil(t.planetaryHour)
        XCTAssertNil(t.planetaryHourNumber)
        XCTAssertFalse(t.timeKnown)
    }

    func testFillTimingOnRecordsMissingIt() {
        let london = GeoLocation(latitude: 51.5074, longitude: -0.1278)
        let paris = GeoLocation(latitude: 48.8566, longitude: 2.3522)
        let repo = MemoryRepository()
        let bare = Entry(type: .ritual, occurredAt: utc("2024-06-23T20:30:00Z"), body: "LBRP")
        var abroad = Entry(type: .vision, occurredAt: utc("2024-06-23T20:30:00Z"), body: "In Paris")
        abroad.timing = TimingContext.compute(at: abroad.occurredAt, location: paris)
        let inq = Inquiry(question: "Q", askedAt: utc("2024-04-23T23:49:00Z"))
        // Saved before a home location was set: moon only, no planetary hour.
        let early = Entry(type: .journal, occurredAt: utc("2024-06-23T03:50:00Z"), timing: TimingContext.compute(at: utc("2024-06-23T03:50:00Z"), location: nil))
        repo.save(bare); repo.save(abroad); repo.save(inq); repo.save(early)

        XCTAssertEqual(repo.fillTiming(location: nil), 2, "without a location only records with no timing at all")
        XCTAssertEqual(repo.fillTiming(location: london), 3)
        XCTAssertEqual(repo.entry(early.id)?.timing?.planetaryHour, .sun)
        XCTAssertEqual(repo.entry(bare.id)?.timing?.planetaryHour, .jupiter)
        XCTAssertEqual(repo.entry(bare.id)?.timing?.location, london)
        XCTAssertEqual(repo.inquiry(inq.id)?.timing?.moonPhase, .full)
        XCTAssertEqual(repo.fillTiming(location: london), 0, "nothing left to fill")
        // Overwrite recomputes everything but keeps a record's own location.
        XCTAssertEqual(repo.fillTiming(location: london, overwrite: true), 4)
        XCTAssertEqual(repo.entry(abroad.id)?.timing?.location, paris)
    }

    func testOlderStoredTimingStillDecodes() throws {
        let json = #"{"moonPhase":"full","moonIllumination":100,"moonSign":"scorpio","sunSign":"taurus","planetaryDay":"sun","planetaryHour":"venus","nearCusp":false}"#
        let t = try JSONDecoder().decode(TimingContext.self, from: Data(json.utf8))
        XCTAssertNil(t.planetaryHourNumber)
        XCTAssertNil(t.location)
    }
}
