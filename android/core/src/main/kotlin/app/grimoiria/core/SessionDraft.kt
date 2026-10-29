package app.grimoiria.core

import kotlinx.serialization.Serializable

/** Phases and observation kinds, as GrimoireCore/Model/Session.swift spells them. */
object SessionVocab {
    val phases = listOf("preparation", "opening", "working", "closing", "aftermath")
    /** The phases offered as buttons during a session (aftermath is derived on the Mac). */
    val livePhases = listOf("preparation", "opening", "working", "closing")
    val observationKinds = listOf(
        "imagery", "entity", "place", "symbol", "message", "sound", "sensation", "emotion", "insight", "omen", "event", "action", "note",
    )
}

/**
 * A ritual, meditation or vision being recorded on the phone. Saved after every tap, so a crash or
 * a dead battery loses nothing. On Stop it becomes a capture whose sidecar carries a `session` block.
 */
@Serializable
data class SessionDraft(
    val id: String,
    val type: String,
    /** ISO 8601 with offset. */
    val startedAt: String,
    val intention: String? = null,
    val technique: String? = null,
    val tags: List<String> = emptyList(),
    val before: StateCheck? = null,
    val marks: List<SessionMark> = emptyList(),
    val phase: String? = null,
    val endedAt: String? = null,
    val after: StateCheck? = null,
    val outcome: String? = null,
    /** Bare file name of the recording in the session's folder, when the microphone was on. */
    val audioFile: String? = null,
) {
    val observations: List<SessionMark> get() = marks.filter { it.kind != null }
    val markerCount: Int get() = marks.count { it.kind == null && it.phase == null }

    fun mark(offset: Double) = copy(marks = marks + SessionMark(offset.round()))

    fun setPhase(offset: Double, p: String): SessionDraft {
        require(p in SessionVocab.phases) { "unknown phase $p" }
        return copy(phase = p, marks = marks + SessionMark(offset.round(), phase = p))
    }

    fun observe(offset: Double, kind: String, text: String, tags: List<String> = emptyList()): SessionDraft {
        require(kind in SessionVocab.observationKinds) { "unknown kind $kind" }
        return copy(marks = marks + SessionMark(offset.round(), kind = kind, text = text.trim(), tags = tags.ifEmpty { null }))
    }

    /** Removes the n-th mark (as listed), for an observation typed by mistake. */
    fun removeMark(index: Int) = copy(marks = marks.filterIndexed { i, _ -> i != index })

    fun toCapture(device: String): Capture = Capture(
        id = id,
        capturedAt = startedAt,
        kind = type,
        device = device,
        tags = tags,
        audioFile = audioFile,
        text = outcome?.takeIf { it.isNotBlank() },
        session = SidecarSession(
            type = type,
            startedAt = startedAt,
            endedAt = endedAt,
            intention = intention?.takeIf { it.isNotBlank() },
            technique = technique?.takeIf { it.isNotBlank() },
            marks = marks.sortedBy { it.offsetS },
            before = before?.takeIf { !it.isEmpty },
            after = after?.takeIf { !it.isEmpty },
            outcome = outcome?.takeIf { it.isNotBlank() },
        ),
    )

    private fun Double.round() = Math.round(this * 10) / 10.0
}
