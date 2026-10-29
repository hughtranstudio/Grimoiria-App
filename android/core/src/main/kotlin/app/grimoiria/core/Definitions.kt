package app.grimoiria.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// Read-only views of the same deck, spread and Yi Jing JSON the Mac app ships
// (Sources/GrimoireCore/Resources/Definitions). The Android build copies that folder into assets.

data class DeckDefinition(
    val id: String,
    val name: String,
    val status: String,
    val reversalsAllowed: Boolean,
    val aliases: List<String>,
    val cards: List<Card>,
) {
    data class Card(
        val id: String,
        val name: String,
        val aliases: List<String>,
        /** Flat per-deck attributes (arcana, suit, number, element, …). */
        val attributes: Map<String, JsonElement>,
    )

    val isPlaceholder: Boolean get() = cards.isEmpty()
    fun card(id: String): Card? = cards.firstOrNull { it.id == id }

    /** Matcher over every card's name and aliases. */
    val cardMatcher: NameMatcher<String> by lazy { NameMatcher(cards.map { it.id to (listOf(it.name) + it.aliases) }) }
}

data class SpreadDefinition(
    val id: String,
    val name: String,
    val aliases: List<String>,
    val positions: List<Position>,
    val decks: List<String> = listOf("*"),
    val openEnded: Boolean = false,
) {
    data class Position(val key: String, val label: String)

    /** Position key for the n-th draw (0-based). Overflow positions get `extra-N`. */
    fun positionKey(index: Int): String = when {
        index < positions.size -> positions[index].key
        openEnded -> (index + 1).toString()
        else -> "extra-${index - positions.size + 1}"
    }

    fun label(key: String): String = positions.firstOrNull { it.key == key }?.label ?: key
    fun appliesTo(deckId: String): Boolean = "*" in decks || deckId in decks

    companion object {
        const val FREEFORM_ID = "freeform"
    }
}

data class YiJingDefinition(
    val aliases: List<String>,
    val hexagrams: List<Hexagram>,
) {
    data class Hexagram(val number: Int, val pinyin: String, val name: String, val lines: List<Int>)

    fun hexagram(number: Int): Hexagram? = hexagrams.firstOrNull { it.number == number }

    /** Hexagram number for six yin/yang lines, bottom to top. */
    fun number(lines: List<Boolean>): Int? {
        val bits = lines.map { if (it) 1 else 0 }
        return hexagrams.firstOrNull { it.lines == bits }?.number
    }
}

/** Where definition files come from: a folder in tests, the APK's assets on the phone. */
interface DefinitionSource {
    /** File names (not paths) in a sub-folder such as `decks`. */
    fun list(dir: String): List<String>
    fun read(path: String): String
}

class DefinitionLibrary(decks: List<DeckDefinition>, spreads: List<SpreadDefinition>, val yijing: YiJingDefinition) {
    val decks: List<DeckDefinition> = decks.sortedBy { it.id }
    val spreads: List<SpreadDefinition> = spreads.sortedBy { it.id }

    fun deck(id: String?): DeckDefinition? = decks.firstOrNull { it.id == id }
    fun spread(id: String?): SpreadDefinition? = spreads.firstOrNull { it.id == id }
    val freeform: SpreadDefinition
        get() = spread(SpreadDefinition.FREEFORM_ID)
            ?: SpreadDefinition(SpreadDefinition.FREEFORM_ID, "Freeform", emptyList(), emptyList(), openEnded = true)

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun load(source: DefinitionSource): DefinitionLibrary {
            fun files(dir: String) = source.list(dir).filter { it.endsWith(".json") }.sorted().map { "$dir/$it" }
            val decks = files("decks").map { parseDeck(source.read(it)) }
            val spreads = files("spreads").map { parseSpread(source.read(it)) }
            return DefinitionLibrary(decks, spreads, parseYiJing(source.read("yijing.json")))
        }

        private val knownCardKeys = setOf("id", "name", "aliases", "significations")

        private fun JsonObject.str(key: String) = getValue(key).jsonPrimitive.content
        private fun JsonObject.strings(key: String) = (get(key) as? JsonArray)?.map { it.jsonPrimitive.content } ?: emptyList()

        fun parseDeck(text: String): DeckDefinition {
            val o = json.parseToJsonElement(text).jsonObject
            val cards = o.getValue("cards").jsonArray.map { e ->
                val c = e.jsonObject
                DeckDefinition.Card(c.str("id"), c.str("name"), c.strings("aliases"), c.filterKeys { it !in knownCardKeys })
            }
            return DeckDefinition(
                id = o.str("id"),
                name = o.str("name"),
                status = (o["status"] as? JsonPrimitive)?.content ?: "complete",
                reversalsAllowed = (o["reversalsAllowed"] as? JsonPrimitive)?.booleanOrNull ?: true,
                aliases = o.strings("aliases"),
                cards = cards,
            )
        }

        fun parseSpread(text: String): SpreadDefinition {
            val o = json.parseToJsonElement(text).jsonObject
            return SpreadDefinition(
                id = o.str("id"),
                name = o.str("name"),
                aliases = o.strings("aliases"),
                positions = o.getValue("positions").jsonArray.map { SpreadDefinition.Position(it.jsonObject.str("key"), it.jsonObject.str("label")) },
                decks = if (o.containsKey("decks")) o.strings("decks") else listOf("*"),
                openEnded = (o["openEnded"] as? JsonPrimitive)?.boolean ?: false,
            )
        }

        fun parseYiJing(text: String): YiJingDefinition {
            val o = json.parseToJsonElement(text).jsonObject
            return YiJingDefinition(
                aliases = o.strings("aliases"),
                hexagrams = o.getValue("hexagrams").jsonArray.map { e ->
                    val h = e.jsonObject
                    YiJingDefinition.Hexagram(h.getValue("number").jsonPrimitive.int, h.str("pinyin"), h.str("name"),
                        h.getValue("lines").jsonArray.map { it.jsonPrimitive.int })
                },
            )
        }
    }
}

/** Definitions read from a folder on disk (tests, desktop tools). */
class FolderDefinitionSource(private val root: java.io.File) : DefinitionSource {
    override fun list(dir: String): List<String> = java.io.File(root, dir).list()?.toList() ?: emptyList()
    override fun read(path: String): String = java.io.File(root, path).readText()
}
