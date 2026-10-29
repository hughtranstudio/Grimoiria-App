import XCTest
@testable import GrimoireCore

final class CalendarExportTests: XCTestCase {
    let la = TimeZone(identifier: "America/Los_Angeles")!
    let sf = GeoLocation(latitude: 37.77, longitude: -122.42)
    let now = GrimoireDateFormat.parseISO("2026-10-29T08:00:00Z")!

    func sample() -> (GrimoireData, Entry, Inquiry, Reminder) {
        var data = GrimoireData()
        var ritual = Entry(type: .ritual, title: "Banishing before the job interview", occurredAt: TestSupport.date("2026-11-06T20:00:00-08:00"),
                           body: "Secret working notes", status: .filed)
        ritual.fields.durationMin = 45
        ritual.fields.intention = "Private intention"
        let inquiry = Inquiry(question: "Will I get the job?", askedAt: TestSupport.date("2026-10-28T09:00:00-07:00"))
        let reminder = OutcomeCheckIn.reminder(for: inquiry.id, askedOn: "2026-10-28", today: "2026-10-28")!
        var past = Entry(type: .ritual, occurredAt: TestSupport.date("2026-10-01T20:00:00-07:00"))
        past.status = .filed
        let journal = Entry(type: .journal, occurredAt: TestSupport.date("2026-11-02T08:00:00-08:00"), body: "Dream of the tower")
        data.entries = [ritual, past, journal]
        data.inquiries = [inquiry]
        data.reminders = [reminder]
        return (data, ritual, inquiry, reminder)
    }

    func testRitualsAndCheckInsCarryTimingAndLinkOnly() throws {
        let (data, ritual, inquiry, reminder) = sample()
        var x = try XCTUnwrap(CalendarExporter(first: "2026-10-29", days: 30, zone: la))
        x.sky = []
        let events = x.events(for: data)
        XCTAssertEqual(events.count, 2, "\(events)")

        let r = try XCTUnwrap(events.first { $0.uid == "ritual-\(ritual.id)@grimoire" })
        XCTAssertEqual(r.summary, "Ritual")
        XCTAssertEqual(r.url, "grimoire://entry/\(ritual.id)")
        XCTAssertEqual(r.when, .timed(start: ritual.occurredAt.instant, end: ritual.occurredAt.instant.addingTimeInterval(45 * 60)))
        XCTAssertTrue(r.busy)

        let c = try XCTUnwrap(events.first { $0.uid == "checkin-\(reminder.id)@grimoire" })
        XCTAssertEqual(c.summary, "Outcome check-in (7 days)")
        XCTAssertEqual(c.when, .allDay("2026-11-04"))
        XCTAssertEqual(c.url, "grimoire://inquiry/\(inquiry.id)")

        // Nothing written by Hugh crosses into the file.
        let ics = x.ics(for: data, now: now)
        for secret in ["Banishing", "interview", "Secret", "Private", "Will I get", "tower"] {
            XCTAssertFalse(ics.contains(secret), secret)
        }
    }

    func testWindowAndOptions() throws {
        let (data, _, _, _) = sample()
        var x = try XCTUnwrap(CalendarExporter(first: "2026-11-05", days: 1, zone: la))
        x.sky = []
        XCTAssertTrue(x.events(for: data).isEmpty, "the ritual is on the 6th and the check-in on the 4th")
        x = try XCTUnwrap(CalendarExporter(first: "2026-10-29", days: 30, zone: la))
        x.sky = []
        x.rituals = false
        XCTAssertEqual(x.events(for: data).map(\.summary), ["Outcome check-in (7 days)"])
        x.checkIns = false
        XCTAssertTrue(x.events(for: data).isEmpty)
    }

    func testLunationsAndPlanetaryHours() throws {
        var x = try XCTUnwrap(CalendarExporter(first: "2026-11-01", days: 30, zone: la))
        x.rituals = false
        x.checkIns = false
        let moons = x.events(for: GrimoireData())
        // A quarter phase every seven or eight days: four or five in 30 days.
        XCTAssertTrue((4...5).contains(moons.count), "\(moons.map(\.summary))")
        XCTAssertTrue(moons.allSatisfy { !$0.busy && $0.url == nil })
        XCTAssertTrue(moons.contains { $0.summary.hasPrefix("Full Moon in") })

        x.sky = []
        x.hoursOf = [.venus]
        x.hoursOnTheirDay = true
        XCTAssertTrue(x.events(for: GrimoireData()).isEmpty, "hours need a location")
        x.location = sf
        let hours = x.events(for: GrimoireData())
        // Four or five Fridays in the window, three or four Venus hours on each.
        XCTAssertTrue((12...20).contains(hours.count), "\(hours.count)")
        let cal = RitualCalendar.calendar(la)
        for h in hours {
            guard case .timed(let start, let end?) = h.when else { return XCTFail("hour without an end") }
            XCTAssertEqual(h.summary, "Hour of Venus")
            XCTAssertLessThan(start, end)
            XCTAssertGreaterThanOrEqual(end, x.from)
            XCTAssertLessThan(start, x.to)
            // A Venus hour on Venus's day: its magical day began at sunrise on a Friday.
            let dayOfStart = cal.component(.weekday, from: start)
            XCTAssertTrue(dayOfStart == 6 || dayOfStart == 7, "\(start)")
        }
        XCTAssertEqual(Set(hours.map(\.uid)).count, hours.count)
    }

    func testICSFormat() throws {
        let (data, ritual, _, _) = sample()
        var x = try XCTUnwrap(CalendarExporter(first: "2026-10-29", days: 30, zone: la))
        x.sky = [.fullMoon]
        let ics = x.ics(for: data, now: now)
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"))
        XCTAssertFalse(ics.replacingOccurrences(of: "\r\n", with: "").contains("\n"), "every line ends in CRLF")
        XCTAssertTrue(ics.contains("DTSTAMP:20261029T080000Z"))
        XCTAssertTrue(ics.contains("DTSTART:20261107T040000Z\r\nDTEND:20261107T044500Z"), "20:00 PST is 04:00 UTC")
        XCTAssertTrue(ics.contains("DTSTART;VALUE=DATE:20261104\r\nDTEND;VALUE=DATE:20261105"))
        XCTAssertTrue(ics.contains("URL:grimoire://entry/\(ritual.id)"))
        XCTAssertTrue(ics.contains("CATEGORIES:Grimoire,Ritual"))
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, 3)
        XCTAssertEqual(ics.components(separatedBy: "END:VEVENT").count - 1, 3)
        // The same export twice gives the same UIDs, so a re-import updates instead of duplicating.
        XCTAssertEqual(x.events(for: data).map(\.uid), x.events(for: data).map(\.uid))
    }

    func testEscapingAndFolding() {
        XCTAssertEqual(CalendarExporter.escape("a,b;c\\d\ne"), "a\\,b\\;c\\\\d\\ne")
        let long = "SUMMARY:" + String(repeating: "☾", count: 40)
        let folded = CalendarExporter.fold(long)
        let lines = folded.components(separatedBy: "\r\n")
        XCTAssertGreaterThan(lines.count, 1)
        XCTAssertTrue(lines.allSatisfy { $0.utf8.count <= 75 })
        XCTAssertTrue(lines.dropFirst().allSatisfy { $0.hasPrefix(" ") })
        XCTAssertEqual(lines.enumerated().map { $0.offset == 0 ? $0.element : String($0.element.dropFirst()) }.joined(), long)
        XCTAssertEqual(CalendarExporter.fold("SHORT:x"), "SHORT:x")
    }
}
