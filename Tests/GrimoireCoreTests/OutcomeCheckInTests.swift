import XCTest
@testable import GrimoireCore

final class OutcomeCheckInTests: XCTestCase {
    func asked(_ day: String) -> ZonedDate { ZonedDate.parse("\(day)T09:00:00Z", timeZone: "UTC")! }

    func testLadderStepsThrough7_30_90() throws {
        var r = try XCTUnwrap(OutcomeCheckIn.reminder(for: ULID(), askedOn: "2026-10-28", today: "2026-10-28"))
        XCTAssertEqual(r.repeat, .ladder)
        XCTAssertEqual(r.step, 7)
        XCTAssertEqual(r.dueOn, "2026-11-04")
        r.complete()
        XCTAssertEqual(r.step, 30)
        XCTAssertEqual(r.dueOn, "2026-11-27")
        XCTAssertEqual(r.status, .pending)
        XCTAssertEqual(r.prompt, OutcomeCheckIn.prompt(days: 30))
        r.complete()
        XCTAssertEqual(r.step, 90)
        XCTAssertEqual(r.dueOn, "2027-01-26")
        r.complete()
        XCTAssertEqual(r.status, .done)
    }

    func testSnoozePastNextStepSkipsIt() throws {
        var r = try XCTUnwrap(OutcomeCheckIn.reminder(for: ULID(), askedOn: "2026-10-28", today: "2026-10-28"))
        r.snooze(days: 30) // 7-day nudge pushed to 2026-12-04, beyond the 30-day point
        r.complete()
        XCTAssertEqual(r.step, 90)
    }

    func testBackfillStartsAtLatestPastStepDueToday() throws {
        // Asked 40 days ago: the 7 and 30 day check-ins are past, so one 30-day nudge is due today.
        let r = try XCTUnwrap(OutcomeCheckIn.reminder(for: ULID(), askedOn: "2026-09-19", today: "2026-10-29"))
        XCTAssertEqual(r.step, 30)
        XCTAssertEqual(r.dueOn, "2026-10-29")
        // A years-old reading from the notebooks gets one 90-day nudge, then the ladder ends.
        var old = try XCTUnwrap(OutcomeCheckIn.reminder(for: ULID(), askedOn: "2024-03-01", today: "2026-10-29"))
        XCTAssertEqual(old.step, 90)
        old.complete()
        XCTAssertEqual(old.status, .done)
        XCTAssertNil(OutcomeCheckIn.reminder(for: ULID(), askedOn: "2026-10-28", today: "2026-10-28", preset: .none))
    }

    func testOutcomeLayersAndLadderRollsOn() throws {
        let repo = MemoryRepository()
        let inq = Inquiry(question: "Will the move go well?", askedAt: asked("2026-10-28"))
        repo.save(inq)
        repo.scheduleOutcomeCheckIn(for: inq, today: "2026-10-28")
        XCTAssertNil(repo.scheduleOutcomeCheckIn(for: inq, today: "2026-10-28"), "one open check-in per inquiry")
        XCTAssertTrue(repo.needsOutcome(today: "2026-11-03").isEmpty)
        XCTAssertEqual(repo.needsOutcome(today: "2026-11-04").first?.step, 7)

        // An outcome on day 8 answers the 7-day nudge; the 30-day one is next.
        let first = try repo.addOutcome(Outcome(recordedAt: asked("2026-11-05"), body: "Contract signed", fulfilled: .partly), to: inq.id)
        XCTAssertEqual(first.status, .resolved)
        XCTAssertTrue(repo.needsOutcome(today: "2026-11-05").isEmpty)
        XCTAssertEqual(repo.data.reminders.count, 1)
        XCTAssertEqual(repo.data.reminders[0].dueOn, "2026-11-27")

        // A second outcome stacks and moves the ladder to 90 days.
        let second = try repo.addOutcome(Outcome(recordedAt: asked("2026-11-30"), body: "Moved in, smooth", fulfilled: .yes), to: inq.id)
        XCTAssertEqual(second.outcomes.map(second.daysAfter), [8, 33])
        XCTAssertEqual(second.status, .revisited)
        XCTAssertEqual(repo.data.reminders[0].step, 90)

        repo.stopReminders(for: inq.id)
        XCTAssertEqual(repo.data.reminders[0].status, .done)
        XCTAssertTrue(repo.needsOutcome(today: "2027-06-01").isEmpty)
        XCTAssertThrowsError(try repo.addOutcome(Outcome(recordedAt: asked("2026-11-30"), body: "x", fulfilled: .no), to: ULID()))
    }

    func testEarlyOutcomeKeepsTheNudge() throws {
        let repo = MemoryRepository()
        let inq = Inquiry(question: "Q", askedAt: asked("2026-10-28"))
        repo.save(inq)
        repo.scheduleOutcomeCheckIn(for: inq, today: "2026-10-28")
        try repo.addOutcome(Outcome(recordedAt: asked("2026-10-30"), body: "early sign", fulfilled: .unclear), to: inq.id)
        XCTAssertEqual(repo.data.reminders[0].step, 7, "an outcome before the check-in is due doesn't skip it")
    }

    func testBackfillOnlyOpenInquiriesWithoutReminders() {
        let repo = MemoryRepository()
        let old = Inquiry(question: "Old notebook reading", askedAt: asked("2025-01-10"))
        var answered = Inquiry(question: "Already answered", askedAt: asked("2025-02-01"))
        answered.addOutcome(Outcome(recordedAt: asked("2025-03-01"), body: "yes", fulfilled: .yes))
        let reminded = Inquiry(question: "Has one", askedAt: asked("2026-10-20"))
        [old, answered, reminded].forEach(repo.save)
        repo.scheduleOutcomeCheckIn(for: reminded, today: "2026-10-20")
        let made = repo.backfillOutcomeCheckIns(today: "2026-10-29")
        XCTAssertEqual(made.map(\.targetId), [old.id])
        XCTAssertEqual(made.first?.dueOn, "2026-10-29")
        XCTAssertTrue(repo.backfillOutcomeCheckIns(today: "2026-10-29").isEmpty, "idempotent")
    }

    func testFixedPresetsStillWorkAndNeverLandInThePast() {
        let r = OutcomeCheckIn.reminder(for: ULID(), askedOn: "2026-10-01", today: "2026-10-29", preset: .oneWeek)
        XCTAssertEqual(r?.dueOn, "2026-10-29")
        XCTAssertEqual(r?.repeat, Reminder.Repeat.none)
        XCTAssertEqual(OutcomeCheckIn.reminder(for: ULID(), askedOn: "2026-10-28", today: "2026-10-28", preset: .threeMonths)?.dueOn, "2027-01-28")
    }

    func testOldStoredRemindersStillDecode() throws {
        let json = #"{"id":"01JBXA0000000000000000R001","targetId":"01JBXA0000000000000000R002","dueOn":"2026-11-04","status":"pending","repeat":"none"}"#
        let r = try JSONDecoder().decode(Reminder.self, from: Data(json.utf8))
        XCTAssertNil(r.step)
        XCTAssertNil(r.anchorOn)
    }
}
