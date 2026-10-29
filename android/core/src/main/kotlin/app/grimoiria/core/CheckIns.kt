package app.grimoiria.core

/**
 * Outcome check-ins as the phone shows them: the Mac's reminders from the library, less what the
 * phone has already answered or put off. The Mac stays the owner of reminders; the phone only
 * keeps its own notes until the next library update catches up.
 */
data class CheckIn(val reminder: LibReminder, val inquiry: LibInquiry?, val entry: LibEntry?) {
    val title: String get() = inquiry?.question ?: entry?.displayTitle ?: "A reading"
    val prompt: String get() = reminder.prompt ?: "What actually happened?"
}

@kotlinx.serialization.Serializable
data class PhoneCheckInState(
    /** Inquiry id → the day (yyyy-MM-dd) an outcome for it was sent from the phone. */
    val answered: Map<String, String> = emptyMap(),
    /** Reminder id → the day it comes back after "Later". */
    val snoozed: Map<String, String> = emptyMap(),
)

object CheckIns {
    /** Due on or before `today`, oldest first. */
    fun due(library: Library, state: PhoneCheckInState, today: String): List<CheckIn> =
        open(library, state).filter { it.reminder.dueOn <= today && (state.snoozed[it.reminder.id]?.let { s -> s <= today } ?: true) }

    /** Not yet due, soonest first (for the calendar and the Today list). */
    fun upcoming(library: Library, state: PhoneCheckInState, today: String): List<CheckIn> =
        open(library, state).filter { it.reminder.dueOn > today }

    private fun open(library: Library, state: PhoneCheckInState): List<CheckIn> = library.reminders
        .filter { it.isOpen }
        // An outcome sent from the phone answers every step due by the day it was sent, as on the Mac.
        .filter { r -> state.answered[r.targetId]?.let { sent -> r.dueOn > sent } ?: true }
        .sortedWith(compareBy({ it.dueOn }, { it.id }))
        .map { CheckIn(it, library.inquiry(it.targetId), library.entry(it.targetId)) }

    /**
     * Drops phone notes the library has caught up with: an answer once its outcome is filed on the
     * Mac (or after 60 days, if it was discarded there), a snooze once it has passed.
     */
    fun prune(state: PhoneCheckInState, library: Library, today: String): PhoneCheckInState {
        val reminderIds = library.reminders.map { it.id }.toSet()
        val giveUp = java.time.LocalDate.parse(today).minusDays(60).toString()
        return state.copy(
            answered = state.answered.filter { (inquiryId, sent) ->
                sent > giveUp && library.inquiry(inquiryId)?.outcomes?.none { it.recordedAt.day >= sent } != false
            },
            snoozed = state.snoozed.filter { (id, until) -> id in reminderIds && until > today },
        )
    }
}
