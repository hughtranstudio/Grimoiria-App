import Foundation

/// Outcome check-ins (spec §4): nudges at 7, 30 and 90 days to log what actually happened.
/// One ladder `Reminder` per Inquiry rolls forward through the steps, so outcomes layer over time
/// instead of the first one closing the question for good.
public enum OutcomeCheckIn {
    public static let ladderDays = [7, 30, 90]

    public static func prompt(days: Int) -> String {
        switch days {
        case 7: return "One week on: what has happened since you asked?"
        case 30: return "One month on: has anything moved? Add to the outcome."
        case 90: return "Three months on: looking back, how did it play out?"
        default: return "\(days) days on: what actually happened?"
        }
    }

    /// The reminder for a question asked on `askedOn`, filed on `today` (both yyyy-MM-dd).
    /// Backfill: a reading filed late (old notes, imports) skips the check-ins already past and
    /// starts at the latest of them, due today, so a years-old reading gets one 90-day nudge.
    public static func reminder(for targetId: ULID, askedOn: String, today: String, preset: ReminderPreset = .ladder,
                                calendar: Calendar = .grimoire) -> Reminder? {
        switch preset {
        case .none:
            return nil
        case .ladder:
            let due = ladderDays.map { ($0, ReminderPreset.add(days: $0, to: askedOn, calendar: calendar)) }
            if let past = due.last(where: { $0.1 <= today }) {
                return Reminder(targetId: targetId, dueOn: today, prompt: prompt(days: past.0), repeat: .ladder, anchorOn: askedOn, step: past.0)
            }
            return Reminder(targetId: targetId, dueOn: due[0].1, prompt: prompt(days: due[0].0), repeat: .ladder, anchorOn: askedOn, step: due[0].0)
        case .oneWeek, .oneMonth, .threeMonths:
            guard let d = preset.dueOn(from: askedOn, calendar: calendar) else { return nil }
            return Reminder(targetId: targetId, dueOn: max(d, today))
        }
    }
}
