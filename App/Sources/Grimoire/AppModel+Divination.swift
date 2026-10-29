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
        if let due = reminder.dueOn(from: at.day) {
            repository.save(Reminder(targetId: inquiry.id, dueOn: due))
            ReminderScheduler.shared.refresh()
        }
        if select {
            if page != .inquiries && page != .timeline { page = .inquiries }
            selection = .inquiry(inquiry.id)
        }
        return inquiry
    }

    /// Outcomes stack in date order; reminders that are due for this Inquiry are done.
    func addOutcome(to id: ULID, _ outcome: Outcome) {
        flushEdits()
        guard var i = inquiry(id) else { return }
        i.addOutcome(outcome)
        i.updatedAt = .now
        repository.save(i)
        for var r in data.reminders where r.targetId == id && r.isDue(today: today) {
            r.complete()
            repository.save(r)
        }
        ReminderScheduler.shared.refresh()
    }

    func addReminder(for target: ULID, _ choice: ReminderChoice) {
        guard let due = choice.dueOn(from: today) else { return }
        repository.save(Reminder(targetId: target, dueOn: due))
        ReminderScheduler.shared.refresh()
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
