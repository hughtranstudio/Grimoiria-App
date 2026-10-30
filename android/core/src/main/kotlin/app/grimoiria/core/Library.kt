package app.grimoiria.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

// Read-only views of the records the Mac shares in `library/grimoire.jsonl` (docs/phone-library.md).
// Field names follow the Swift Codable models (GrimoireCore/Model); unknown keys are ignored so the
// Mac can add fields without breaking the phone.

/** An instant plus the IANA zone it was recorded in (Swift `ZonedDate`). */
@Serializable
data class ZonedDate(val instant: String, val timeZone: String = "UTC") {
    val zone: ZoneId get() = runCatching { ZoneId.of(timeZone) }.getOrDefault(ZoneId.of("UTC"))
    val dateTime: ZonedDateTime get() = Instant.parse(instant).atZone(zone)
    /** yyyy-MM-dd in the recorded zone. */
    val day: String get() = dateTime.toLocalDate().toString()
}

@Serializable
data class LibAttachment(val kind: String, val path: String, val originalName: String? = null)

@Serializable
data class LibObservation(
    val id: String,
    val offset: Double,
    val phase: String? = null,
    val kind: String = "note",
    val text: String = "",
    val tags: List<String> = emptyList(),
    val intensity: Int? = null,
    val clarity: Int? = null,
    val capture: String = "live",
)

@Serializable
data class LibPhaseMark(val phase: String, val offset: Double)

@Serializable
data class StateCheck(val energy: Int? = null, val calm: Int? = null, val focus: Int? = null) {
    val isEmpty: Boolean get() = energy == null && calm == null && focus == null
}

@Serializable
data class LibSession(
    val startedAt: ZonedDate,
    val endedAt: ZonedDate? = null,
    val phases: List<LibPhaseMark> = emptyList(),
    val observations: List<LibObservation> = emptyList(),
    val before: StateCheck? = null,
    val after: StateCheck? = null,
    val outcome: String? = null,
) {
    val durationSeconds: Long? get() = endedAt?.let { Instant.parse(it.instant).epochSecond - Instant.parse(startedAt.instant).epochSecond }
}

@Serializable
data class LibEntry(
    val id: String,
    val type: String,
    val title: String? = null,
    val occurredAt: ZonedDate,
    val body: String = "",
    val tags: List<String> = emptyList(),
    val inquiryId: String? = null,
    val attachments: List<LibAttachment> = emptyList(),
    val fields: JsonObject = JsonObject(emptyMap()),
    val timing: JsonObject? = null,
    val extraNotes: String? = null,
    val transcript: String? = null,
    val session: LibSession? = null,
    val status: String = "filed",
) {
    /** Title, or the first line of the body (as on the Mac). */
    val displayTitle: String
        get() {
            title?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
            val first = body.lineSequence().firstOrNull { it.isNotBlank() }?.trim()?.trim('#', ' ').orEmpty()
            if (first.isEmpty()) return type.replaceFirstChar { it.uppercase() }
            return if (first.length > 60) first.take(57) + "…" else first
        }
}

@Serializable
data class LibDraw(val cardId: String, val positionKey: String, val orientation: Orientation = Orientation.UPRIGHT, val notes: String? = null)

@Serializable
data class LibCast(val lines: List<Int>, val method: String = "coins")

@Serializable
data class LibDivination(
    val id: String,
    val system: DivinationSystem,
    val deckId: String? = null,
    val spreadId: String? = null,
    val method: String? = null,
    val notes: String? = null,
    val order: Int = 0,
    val draws: List<LibDraw> = emptyList(),
    val cast: LibCast? = null,
)

@Serializable
data class LibSynthesis(val body: String, val confidence: Int? = null)

@Serializable
enum class Fulfilled {
    @SerialName("yes") YES,
    @SerialName("partly") PARTLY,
    @SerialName("no") NO,
    @SerialName("unclear") UNCLEAR;

    val wire: String get() = name.lowercase()
}

@Serializable
data class LibOutcome(val id: String, val recordedAt: ZonedDate, val body: String, val fulfilled: Fulfilled)

@Serializable
data class LibInquiry(
    val id: String,
    val question: String,
    val askedAt: ZonedDate,
    val context: String = "",
    val status: String = "open",
    val tags: List<String> = emptyList(),
    val divinations: List<LibDivination> = emptyList(),
    val synthesis: LibSynthesis? = null,
    val outcomes: List<LibOutcome> = emptyList(),
    val timing: JsonObject? = null,
)

@Serializable
data class LibReminder(
    val id: String,
    val targetId: String,
    val dueOn: String,
    val prompt: String? = null,
    val status: String = "pending",
    val repeat: String = "none",
    val step: Int? = null,
) {
    val isOpen: Boolean get() = status != "done"
    fun isDue(today: String) = isOpen && dueOn <= today
}

@Serializable
data class LibraryManifest(
    @SerialName("library_version") val libraryVersion: Int,
    @SerialName("exported_at") val exportedAt: String,
    val entries: Int = 0,
    val inquiries: Int = 0,
    val reminders: Int = 0,
    val checksum: String = "",
)

/** Everything filed on the Mac, as the phone sees it. */
class Library(
    val entries: List<LibEntry>,
    val inquiries: List<LibInquiry>,
    val reminders: List<LibReminder>,
    val manifest: LibraryManifest? = null,
    /** Lines that could not be read (newer formats, damage); shown in Settings, never fatal. */
    val skipped: Int = 0,
) {
    private val entryById = entries.associateBy { it.id }
    private val inquiryById = inquiries.associateBy { it.id }

    fun entry(id: String) = entryById[id]
    fun inquiry(id: String) = inquiryById[id]

    val isEmpty: Boolean get() = entries.isEmpty() && inquiries.isEmpty()

    /** Every tag in use, with all their parents, sorted. */
    val allTags: List<String> by lazy {
        val out = sortedSetOf<String>()
        fun add(t: String) {
            val parts = t.split('/').filter { it.isNotEmpty() }
            for (i in 1..parts.size) out += parts.take(i).joinToString("/")
        }
        entries.forEach { e -> e.tags.forEach(::add); e.session?.observations?.forEach { o -> o.tags.forEach(::add) } }
        inquiries.forEach { i -> i.tags.forEach(::add) }
        out.toList()
    }

    companion object {
        val EMPTY = Library(emptyList(), emptyList(), emptyList())
        const val SUPPORTED_VERSION = 1

        val json = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true }

        /** Same as PhoneLibrary.checksum on the Mac: byte count, then FNV-1a 64 of the UTF-8 bytes in hex. */
        fun checksum(bytes: ByteArray): String {
            var h = 0xcbf29ce484222325uL
            for (b in bytes) h = (h xor (b.toUByte().toULong())) * 0x100000001b3uL
            return "${bytes.size}-${h.toString(16)}"
        }

        fun parseManifest(text: String): LibraryManifest? = runCatching { json.decodeFromString(LibraryManifest.serializer(), text) }.getOrNull()

        /** Reads `grimoire.jsonl`. Records the phone doesn't know (volumes, future types) are skipped. */
        fun parse(jsonl: String, manifest: LibraryManifest? = null): Library {
            val entries = mutableListOf<LibEntry>()
            val inquiries = mutableListOf<LibInquiry>()
            val reminders = mutableListOf<LibReminder>()
            var skipped = 0
            for (line in jsonl.lineSequence()) {
                if (line.isBlank()) continue
                val ok = runCatching {
                    val o = json.parseToJsonElement(line).jsonObject
                    val version = (o["grimoire_export_version"] as? JsonPrimitive)?.content?.toIntOrNull() ?: 1
                    if (version > SUPPORTED_VERSION) return@runCatching false
                    val record: JsonElement = o.getValue("record")
                    when (o["record_type"]?.jsonPrimitive?.content) {
                        "entry" -> entries += json.decodeFromJsonElement(LibEntry.serializer(), record)
                        "inquiry" -> inquiries += json.decodeFromJsonElement(LibInquiry.serializer(), record)
                        "reminder" -> reminders += json.decodeFromJsonElement(LibReminder.serializer(), record)
                        else -> Unit
                    }
                    true
                }.getOrDefault(false)
                if (!ok) skipped++
            }
            return Library(entries.filter { it.status == "filed" }, inquiries, reminders, manifest, skipped)
        }
    }
}
