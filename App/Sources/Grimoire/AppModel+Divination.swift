import Foundation
import GrimoireAppKit
import GrimoireCore

extension AppModel {
    /// Shows a record in the window: the right page and the selection.
    func reveal(_ id: ULID) {
        flushEdits()
        if inquiry(id) != nil {
            if page != .inquiries && page != .timeline && page != .today { page = .inquiries }
            selection = .inquiry(id)
        } else if entry(id) != nil {
            if page != .timeline && page != .today && page != .search { page = .timeline }
            selection = .entry(id)
        } else if volume(id) != nil {
            page = .volumes
            selection = .volume(id)
        }
    }

    @discardableResult
    func newInquiry(question: String, context: String = "", reminder: ReminderChoice = .preset(.none),
                    divinations: [Divination] = [], select: Bool = true) -> Inquiry {
        let at = now()
        let inquiry = Inquiry(question: question.trimmingCharacters(in: .whitespacesAndNewlines), askedAt: at, context: context,
                              divinations: divinations, timing: timing(at: at))
        repository.save(inquiry)
        addReminder(for: inquiry.id, reminder, askedOn: at.day)
        if select {
            if page != .inquiries && page != .timeline { page = .inquiries }
            selection = .inquiry(inquiry.id)
        }
        return inquiry
    }

    /// Outcomes stack in date order. Reminders due by the outcome's day are done; a 7/30/90
    /// check-in rolls on to its next step, so later outcomes layer on.
    func addOutcome(to id: ULID, _ outcome: Outcome) {
        flushEdits()
        _ = try? repository.addOutcome(outcome, to: id)
        ReminderScheduler.shared.refresh()
    }

    /// A reminder for a record. The 7/30/90 ladder counts from the day the question was asked.
    func addReminder(for target: ULID, _ choice: ReminderChoice, askedOn: String? = nil) {
        if case .preset(.ladder) = choice {
            let anchor = askedOn ?? inquiry(target)?.askedAt.day ?? entry(target)?.occurredAt.day ?? today
            guard let r = OutcomeCheckIn.reminder(for: target, askedOn: anchor, today: today, preset: .ladder) else { return }
            repository.save(r)
        } else {
            guard let due = choice.dueOn(from: askedOn ?? today) else { return }
            repository.save(Reminder(targetId: target, dueOn: due))
        }
        ReminderScheduler.shared.refresh()
    }

    /// Open readings with no outcome and no reminder get a 7/30/90 check-in (after importing old notes).
    @discardableResult
    func backfillCheckIns() -> Int {
        flushEdits()
        let added = repository.backfillOutcomeCheckIns(today: today, preset: .ladder)
        ReminderScheduler.shared.refresh()
        show(added.isEmpty ? "Every open reading already has a check-in" : "Added check-ins to \(added.count) past reading\(added.count == 1 ? "" : "s")")
        return added.count
    }

    /// Fills moon, Sun and planetary hours on records saved before a home location was set.
    @discardableResult
    func fillMissingTiming() -> Int {
        flushEdits()
        guard let home = settings.home else {
            show("Set a home location in Settings > General first")
            return 0
        }
        let n = repository.fillTiming(location: home)
        show(n == 0 ? "Every record already has its timing" : "Filled timing on \(n) record\(n == 1 ? "" : "s")")
        return n
    }

    func snooze(_ reminderId: ULID) {
        guard var r = data.reminders.first(where: { $0.id == reminderId }) else { return }
        r.snooze(days: 3)
        repository.save(r)
        ReminderScheduler.shared.refresh()
    }

    func complete(_ reminderId: ULID) {
        guard var r = data.reminders.first(where: { $0.id == reminderId }) else { return }
        r.complete()
        repository.save(r)
        ReminderScheduler.shared.refresh()
    }
}
