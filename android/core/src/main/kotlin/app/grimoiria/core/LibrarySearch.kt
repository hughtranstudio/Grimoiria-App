package app.grimoiria.core

/** One row in the phone's library: a reading (Inquiry) or any other filed entry. */
sealed interface LibraryItem {
    val id: String
    /** Instant, for ordering newest first. */
    val sortKey: String
    val day: String
    val title: String
    /** Filter group: "reading" or the entry type. */
    val group: String
    val tags: List<String>

    data class Reading(val inquiry: LibInquiry) : LibraryItem {
        override val id get() = inquiry.id
        override val sortKey get() = inquiry.askedAt.instant
        override val day get() = inquiry.askedAt.day
        override val title get() = inquiry.question
        override val group get() = "reading"
        override val tags get() = inquiry.tags
    }

    data class Record(val entry: LibEntry) : LibraryItem {
        override val id get() = entry.id
        override val sortKey get() = entry.occurredAt.instant
        override val day get() = entry.occurredAt.day
        override val title get() = entry.displayTitle
        override val group get() = entry.type
        override val tags get() = entry.tags + entry.session?.observations?.flatMap { it.tags }.orEmpty()
    }
}

/**
 * What the library is narrowed to. `text` may hold `#tag` words, which filter by tag (a parent tag
 * includes its children, as on the Mac); the other words must all appear somewhere in the record.
 */
data class LibraryQuery(
    val text: String = "",
    val group: String? = null,
    /** "deckId/cardId". */
    val card: String? = null,
    val hexagram: Int? = null,
) {
    val isEmpty: Boolean get() = text.isBlank() && group == null && card == null && hexagram == null
}

class LibrarySearch(private val library: Library, private val definitions: DefinitionLibrary) {

    /** Readings plus entries, without the divination entries that only stand for a reading. */
    val all: List<LibraryItem> by lazy {
        (library.inquiries.map { LibraryItem.Reading(it) } +
            library.entries.filter { !(it.type == "divination" && it.inquiryId != null) }.map { LibraryItem.Record(it) })
            .sortedByDescending { it.sortKey }
    }

    /** Groups present, readings first, for filter chips. */
    val groups: List<String> by lazy {
        all.map { it.group }.distinct().sortedWith(compareBy({ it != "reading" }, { it }))
    }

    fun search(q: LibraryQuery): List<LibraryItem> {
        if (q.isEmpty) return all
        val words = q.text.split(Regex("\\s+")).filter { it.isNotBlank() }
        val tagFilters = words.filter { it.startsWith("#") && it.length > 1 }.map { normalizeTag(it.drop(1)) }
        val terms = words.filterNot { it.startsWith("#") }.map { Tokenizer.key(it) }.filter { it.isNotEmpty() }
        return all.filter { item ->
            (q.group == null || item.group == q.group) &&
                tagFilters.all { f -> item.tags.any { isUnder(normalizeTag(it), f) } } &&
                (q.card == null || cards(item).contains(q.card)) &&
                (q.hexagram == null || hexagrams(item).contains(q.hexagram)) &&
                (terms.isEmpty() || haystack(item).let { h -> terms.all { h.contains(it) } })
        }
    }

    /** "deckId/cardId" for every card drawn in a reading. */
    fun cards(item: LibraryItem): Set<String> = (item as? LibraryItem.Reading)?.inquiry?.divinations
        ?.flatMap { d -> d.draws.map { "${d.deckId}/${it.cardId}" } }?.toSet().orEmpty()

    /** Primary and resulting hexagram numbers in a reading. */
    fun hexagrams(item: LibraryItem): Set<Int> = (item as? LibraryItem.Reading)?.inquiry?.divinations
        ?.mapNotNull { it.cast?.lines }
        ?.flatMap { listOfNotNull(YiJing.primary(it, definitions.yijing)?.number, YiJing.resulting(it, definitions.yijing)?.number) }
        ?.toSet().orEmpty()

    fun cardName(deckId: String?, cardId: String): String = definitions.deck(deckId)?.card(cardId)?.name ?: cardId

    private val haystacks = HashMap<String, String>()

    private fun haystack(item: LibraryItem): String = haystacks.getOrPut(item.id) {
        val parts = mutableListOf(item.title)
        parts += item.tags
        when (item) {
            is LibraryItem.Reading -> {
                val i = item.inquiry
                parts += i.context
                i.synthesis?.let { parts += it.body }
                i.outcomes.forEach { parts += it.body }
                for (d in i.divinations) {
                    definitions.deck(d.deckId)?.let { parts += it.name }
                    d.draws.forEach { parts += cardName(d.deckId, it.cardId); it.notes?.let(parts::add) }
                    d.cast?.lines?.let { lines ->
                        listOfNotNull(YiJing.primary(lines, definitions.yijing), YiJing.resulting(lines, definitions.yijing))
                            .forEach { h -> parts += "${h.name} ${h.pinyin}" }
                    }
                    d.notes?.let(parts::add)
                }
            }
            is LibraryItem.Record -> {
                val e = item.entry
                parts += e.body
                e.extraNotes?.let(parts::add)
                e.session?.observations?.forEach { parts += it.text }
                e.session?.outcome?.let(parts::add)
                e.fields.values.forEach { parts += it.toString() }
            }
        }
        Tokenizer.key(parts.joinToString(" "))
    }

    companion object {
        fun normalizeTag(t: String) = t.lowercase().split('/').map { it.trim().replace(' ', '-') }.filter { it.isNotEmpty() }.joinToString("/")
        fun isUnder(tag: String, ancestor: String) = tag == ancestor || tag.startsWith("$ancestor/")
    }
}
