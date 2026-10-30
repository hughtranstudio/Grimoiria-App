package app.grimoiria.core

import java.security.SecureRandom
import kotlin.random.Random
import kotlin.random.asKotlinRandom

/**
 * Casting and drawing on the phone, for when there is no deck or coins to hand. The result is a
 * draft like any spoken reading, so it still goes through check on the phone and confirm on the Mac.
 */
object Casting {
    val secure: Random = SecureRandom().asKotlinRandom()

    /** Three coins per line, heads 3 and tails 2: 6 and 9 are 1 in 8, 7 and 8 are 3 in 8. Bottom line first. */
    fun coins(random: Random = secure): List<Int> = List(6) { List(3) { if (random.nextBoolean()) 3 else 2 }.sum() }

    /** Yarrow-stalk odds out of 16: 6 = 1, 7 = 5, 8 = 7, 9 = 3. Bottom line first. */
    fun yarrow(random: Random = secure): List<Int> = List(6) {
        when (random.nextInt(16)) {
            0 -> 6
            in 1..5 -> 7
            in 6..12 -> 8
            else -> 9
        }
    }

    fun lines(method: CastMethod, random: Random = secure) = if (method == CastMethod.YARROW) yarrow(random) else coins(random)

    /**
     * Draws `count` different cards from a shuffled deck. Reversals come up half the time when the
     * deck allows them.
     */
    fun draw(deck: DeckDefinition, count: Int, random: Random = secure): List<Pair<String, Orientation>> =
        deck.cards.shuffled(random).take(count).map {
            it.id to if (deck.reversalsAllowed && random.nextBoolean()) Orientation.REVERSED else Orientation.UPRIGHT
        }
}

/** Draft readings made on the phone instead of heard. Every field is the user's own, so all `high`. */
class PhoneReading(private val library: DefinitionLibrary) {

    /** Fills a cards divination: one card per spread position (three for freeform), keeping any already chosen. */
    fun drawInto(r: DraftReading, div: Int, random: Random = Casting.secure): DraftReading = r.copy(divinations = r.divinations.mapIndexed { i, d ->
        if (i != div) return@mapIndexed d
        val deck = library.deck(d.deckId.value)?.takeIf { !it.isPlaceholder } ?: return@mapIndexed d
        val spread = library.spread(d.spreadId.value) ?: library.freeform
        val count = if (spread.openEnded || spread.positions.isEmpty()) maxOf(d.draws.size, 3) else spread.positions.size
        val kept = d.draws.mapNotNull { it.cardId.value }.toSet()
        val fresh = Casting.draw(DeckDefinition(deck.id, deck.name, deck.status, deck.reversalsAllowed, deck.aliases,
            deck.cards.filter { it.id !in kept }), count, random).iterator()
        val draws = (0 until count).map { k ->
            val existing = d.draws.getOrNull(k)?.takeIf { it.cardId.value != null }
            existing?.copy(positionKey = spread.positionKey(k))
                ?: if (!fresh.hasNext()) DraftDraw(Parsed.missing(), Parsed(Orientation.UPRIGHT, null, Confidence.HIGH), spread.positionKey(k))
                else fresh.next().let { (card, o) -> DraftDraw(Parsed(card, null, Confidence.HIGH), Parsed(o, null, Confidence.HIGH), spread.positionKey(k)) }
        }
        d.copy(draws = draws)
    })

    fun castInto(r: DraftReading, div: Int, random: Random = Casting.secure): DraftReading = r.copy(divinations = r.divinations.mapIndexed { i, d ->
        if (i != div || d.system != DivinationSystem.YIJING) return@mapIndexed d
        val method = d.cast?.method ?: CastMethod.COINS
        d.copy(cast = DraftCast(Parsed(Casting.lines(method, random), d.cast?.lines?.heard, Confidence.HIGH), method))
    })
}
