package app.grimoiria.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import kotlin.random.Random

/** What the user says a capture is; the `kind_hint` values of sidecar contract v1. */
enum class CaptureKind(val hint: String, val label: String) {
    DRAW("draw", "Card draw"),
    YIJING("yijing", "Yi Jing"),
    OMEN("omen", "Omen"),
    INSIGHT("insight", "Insight"),
    VISION("vision", "Vision"),
    CONTACT("contact", "Contact"),
    DREAM("dream", "Dream"),
    RITUAL("ritual", "Ritual"),
    MEDITATION("meditation", "Meditation"),
    JOURNAL("journal", "Journal");

    val expectsReading: Boolean get() = this == DRAW || this == YIJING

    companion object {
        fun fromHint(hint: String?): CaptureKind = entries.firstOrNull { it.hint == hint } ?: INSIGHT
    }
}

/**
 * The phone → Mac sidecar, contract v1 (schemas/capture-sidecar.v1.schema.json).
 * Written last, beside the audio file with the same base name, into `incoming/`.
 */
@Serializable
data class CaptureSidecar(
    @SerialName("contract_version") val contractVersion: Int = 1,
    val id: String,
    @SerialName("captured_at") val capturedAt: String,
    val device: String? = null,
    @SerialName("kind_hint") val kindHint: String? = null,
    val text: String? = null,
    val audio: String? = null,
    val tags: List<String>? = null,
    /** On-phone transcript of `audio`, as corrected by the user. The Mac skips transcription when present. */
    val transcript: String? = null,
    /** Reading as checked on the phone. The Mac uses it instead of re-parsing; Inbox confirm still applies. */
    val draft: DraftReading? = null,
) {
    fun encode(): String = json.encodeToString(serializer(), this) + "\n"

    companion object {
        val json = Json {
            prettyPrint = true
            explicitNulls = false
            encodeDefaults = true
            ignoreUnknownKeys = true
        }

        fun decode(text: String): CaptureSidecar = json.decodeFromString(serializer(), text)
    }
}

object CaptureIds {
    private val stamp = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")
    private val iso = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX")

    /** Same shape as the iPhone Shortcut's ids: `20261028-081400-4821`. Opaque to the Mac. */
    fun newId(at: OffsetDateTime, random: Random = Random.Default): String =
        "${stamp.format(at)}-${random.nextInt(1000, 10000)}"

    /** ISO 8601 with offset, seconds precision: `2026-10-28T08:14:00-07:00`. */
    fun capturedAt(at: OffsetDateTime): String = iso.format(at)
}
