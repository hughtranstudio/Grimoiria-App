package app.grimoiria.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Kotlin mirror of GrimoireCore/Parsing/Draft.swift. The JSON shape must stay identical:
// the phone writes a DraftReading into the sidecar and the Mac decodes it with Swift's Codable.

/** Confidence attached to every parsed field. The review screen highlights anything not `high`. */
@Serializable
enum class Confidence {
    @SerialName("missing") MISSING,
    @SerialName("low") LOW,
    @SerialName("medium") MEDIUM,
    @SerialName("high") HIGH;

    companion object {
        fun from(score: Double): Confidence = when {
            score >= 0.999 -> HIGH
            score >= 0.9 -> MEDIUM
            else -> LOW
        }
    }
}

/** A value the parser proposed, the words it heard, and how sure it is. */
@Serializable
data class Parsed<T>(
    val value: T? = null,
    val heard: String? = null,
    val confidence: Confidence,
) {
    companion object {
        fun <T> missing(): Parsed<T> = Parsed(null, null, Confidence.MISSING)
    }
}

@Serializable
enum class Orientation {
    @SerialName("upright") UPRIGHT,
    @SerialName("reversed") REVERSED,
    @SerialName("n/a") NA,
}

@Serializable
enum class DivinationSystem {
    @SerialName("cards") CARDS,
    @SerialName("yijing") YIJING,
    @SerialName("other") OTHER,
}

@Serializable
enum class CastMethod {
    @SerialName("coins") COINS,
    @SerialName("yarrow") YARROW,
    @SerialName("other") OTHER,
}

/** Parser output: a draft reading waiting for confirm-and-correct. Nothing here is a filed record. */
@Serializable
data class DraftReading(
    val question: Parsed<String> = Parsed.missing(),
    val divinations: List<DraftDivination> = emptyList(),
    /** Words the parser could not place, shown beside the transcript. */
    val unparsed: List<String> = emptyList(),
    val warnings: List<String> = emptyList(),
) {
    val isEmpty: Boolean get() = divinations.isEmpty()

    /** Lowest confidence across all fields. */
    val weakest: Confidence
        get() {
            val all = mutableListOf<Confidence>()
            for (d in divinations) {
                all += listOf(d.deckId.confidence, d.spreadId.confidence)
                    .filter { it != Confidence.MISSING || d.system == DivinationSystem.CARDS }
                all += d.draws.flatMap { listOf(it.cardId.confidence, it.orientation.confidence) }
                d.cast?.let { all += it.lines.confidence }
            }
            return all.minOrNull() ?: Confidence.MISSING
        }
}

@Serializable
data class DraftDivination(
    val system: DivinationSystem,
    val deckId: Parsed<String> = Parsed.missing(),
    val spreadId: Parsed<String> = Parsed.missing(),
    val draws: List<DraftDraw> = emptyList(),
    val cast: DraftCast? = null,
    val heard: String = "",
)

@Serializable
data class DraftDraw(
    val cardId: Parsed<String>,
    val orientation: Parsed<Orientation>,
    val positionKey: String,
)

@Serializable
data class DraftCast(
    val lines: Parsed<List<Int>>,
    val method: CastMethod,
)
