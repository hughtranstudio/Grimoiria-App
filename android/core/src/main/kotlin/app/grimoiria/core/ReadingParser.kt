package app.grimoiria.core

/**
 * Parses a transcript (or typed text) into a [DraftReading] against the loaded definitions.
 * Port of GrimoireCore/Parsing/ReadingParser.swift; the shared golden cases keep them identical.
 *
 * Spoken pattern:
 *   "Question: will the move go ahead. Deck Rider-Waite. Three card. One, three of cups reversed.
 *    Two, the Tower. Three, page of wands. Yi Jing, coins. Seven eight nine six seven seven."
 *
 * Each "deck …" or "Yi Jing" starts a new divination under the same question.
 */
class ReadingParser(val library: DefinitionLibrary) {
    private val deckMatcher = NameMatcher(library.decks.map { it.id to (listOf(it.name, it.id) + it.aliases) }, threshold = 0.75)
    private val spreadMatcher = NameMatcher(library.spreads.map { it.id to (listOf(it.name) + it.aliases) }, threshold = 0.85)
    private val cardMatchers: Map<String, NameMatcher<String>> =
        library.decks.filter { it.cards.isNotEmpty() }.associate { it.id to it.cardMatcher }
    private val yijingKeys: List<List<String>> =
        library.yijing.aliases.map { Tokenizer.key(it).split(' ') }.sortedByDescending { it.size }

    companion object {
        val reversedWords = setOf("reversed", "reverse", "inverted", "upside", "r", "rev", "rx")
        val uprightWords = setOf("upright")
        const val DECK_KEYWORD = "deck"
        const val QUESTION_KEYWORD = "question"
        val ignorable = setOf("and", "then", "next", "card", "cards", "position", "spread", "is", "was", "in", "first",
            "second", "third", "last", "i", "drew", "pulled", "got", "um", "uh", "so", "with")

        /** Keeps the question's original casing and punctuation from the raw transcript. */
        fun recoverQuestion(transcript: String): String? {
            val r = transcript.indexOf("question", ignoreCase = true)
            if (r < 0) return null
            var rest = transcript.substring(r + "question".length).dropWhile { it in ":,-–— " }
            val end = rest.indexOfFirst { it in ".?!\n" }
            if (end >= 0) {
                val isQ = rest[end] == '?'
                rest = rest.substring(0, end)
                val q = rest.trim(' ', '\t')
                return if (q.isEmpty()) null else q + if (isQ) "?" else ""
            }
            val q = rest.trim(' ', '\t')
            return q.ifEmpty { null }
        }
    }

    // Quick draw

    /** Typed quick draw: "3 cups r, tower, page wands". Positions fill in the spread's order. */
    fun parseQuickDraw(text: String, deckId: String, spreadId: String? = null): DraftDivination {
        val div = DraftDivination(DivinationSystem.CARDS, deckId = Parsed(deckId, null, Confidence.HIGH),
            spreadId = Parsed(spreadId ?: SpreadDefinition.FREEFORM_ID, null, Confidence.HIGH), heard = text)
        return parseCards(Tokenizer.tokenize(text), div, mutableListOf())
    }

    // Full transcript

    fun parse(transcript: String): DraftReading {
        var question = Parsed.missing<String>()
        val divinations = mutableListOf<DraftDivination>()
        val unparsed = mutableListOf<String>()
        val warnings = mutableListOf<String>()
        val tokens = Tokenizer.tokenize(transcript).toMutableList()

        // Question: from "question" to the end of that sentence.
        val qi = tokens.indexOf(Token.Word(QUESTION_KEYWORD))
        if (qi >= 0) {
            var end = qi + 1
            if (end < tokens.size && tokens[end] == Token.Boundary) end++ // "Question: …"
            val start = end
            while (end < tokens.size && tokens[end] != Token.Boundary) end++
            val words = words(tokens.subList(start, end))
            if (words.isNotEmpty()) {
                val q = recoverQuestion(transcript) ?: words.joinToString(" ")
                question = Parsed(q, words.joinToString(" "), Confidence.HIGH)
            }
            tokens.subList(qi, end).clear()
        }

        // Split into segments at "deck" and Yi Jing keywords.
        for (segment in segments(tokens)) {
            when (segment.kind) {
                SegmentKind.CARDS -> {
                    var div = DraftDivination(DivinationSystem.CARDS, heard = segment.text)
                    var rest = segment.tokens
                    val deck = matchDeck(rest)
                    if (deck != null) {
                        div = div.copy(deckId = deck.first)
                        rest = rest.drop(deck.second)
                    } else {
                        warnings += "No deck recognised after \"deck\"; pick one in the Inbox"
                    }
                    div = parseCards(rest, div, unparsed)
                    val deckId = div.deckId.value
                    if (deckId != null && deckId !in cardMatchers) {
                        warnings += "Deck $deckId has no card list yet; draws must be entered by hand"
                    }
                    if (div.spreadId.value == null) div = div.copy(spreadId = Parsed(SpreadDefinition.FREEFORM_ID, null, Confidence.MEDIUM))
                    val spread = library.spread(div.spreadId.value)
                    if (spread != null && !spread.openEnded && div.draws.size != spread.positions.size) {
                        warnings += "${spread.name} has ${spread.positions.size} positions but ${div.draws.size} cards were heard"
                    }
                    divinations += div
                }
                SegmentKind.YIJING -> {
                    divinations += DraftDivination(DivinationSystem.YIJING, heard = segment.text, cast = parseCast(segment.tokens, warnings))
                }
                SegmentKind.PREAMBLE -> Unit
            }
        }
        return DraftReading(question, divinations, unparsed, warnings)
    }

    // Segmenting

    private enum class SegmentKind { PREAMBLE, CARDS, YIJING }
    private class Segment(val kind: SegmentKind, val tokens: List<Token>, val text: String)

    private fun segments(tokens: List<Token>): List<Segment> {
        val result = mutableListOf<Segment>()
        var kind = SegmentKind.PREAMBLE
        var buf = mutableListOf<Token>()
        fun flush() {
            if (kind != SegmentKind.PREAMBLE || buf.isNotEmpty()) result += Segment(kind, buf, words(buf).joinToString(" "))
            buf = mutableListOf()
        }
        var i = 0
        while (i < tokens.size) {
            if (tokens[i] == Token.Word(DECK_KEYWORD)) {
                flush(); kind = SegmentKind.CARDS; i++; continue
            }
            val len = yijingKeywordLength(tokens, i)
            if (len != null) {
                flush(); kind = SegmentKind.YIJING; i += len; continue
            }
            buf += tokens[i]; i++
        }
        flush()
        return result.filter { it.kind != SegmentKind.PREAMBLE }
    }

    private fun yijingKeywordLength(tokens: List<Token>, i: Int): Int? {
        for (key in yijingKeys) {
            if (i + key.size > tokens.size) continue
            val ws = tokens.subList(i, i + key.size).map { (it as? Token.Word)?.text ?: "" }
            if (ws == key) return key.size
        }
        return null
    }

    // Decks and cards

    private fun words(tokens: List<Token>): List<String> = tokens.mapNotNull { (it as? Token.Word)?.text }

    /** Matches the deck name at the start of a segment. Returns the number of tokens consumed. */
    private fun matchDeck(tokens: List<Token>): Pair<Parsed<String>, Int>? {
        var idx = 0
        val ws = mutableListOf<String>()
        val positions = mutableListOf<Int>()
        while (idx < tokens.size && ws.size < 4) {
            val t = tokens[idx]
            if (t is Token.Word) {
                if (t.text !in Tokenizer.fillers) { ws += Tokenizer.spell(t.text); positions += idx }
            } else if (ws.isNotEmpty()) break
            idx++
        }
        if (ws.isEmpty()) return null
        val m = deckMatcher.longestMatch(ws, 0) ?: return null
        val consumed = positions[m.wordCount - 1] + 1
        return Parsed(m.id, ws.take(m.wordCount).joinToString(" "), Confidence.from(m.score)) to consumed
    }

    private fun parseCards(tokens: List<Token>, start: DraftDivination, unparsed: MutableList<String>): DraftDivination {
        var div = start
        val draws = div.draws.toMutableList()
        val matcher = div.deckId.value?.let { cardMatchers[it] }
        // Work on runs between boundaries so a match never spans "One, three of cups".
        val runs = mutableListOf(mutableListOf<String>())
        for (t in tokens) {
            when (t) {
                Token.Boundary -> if (runs.last().isNotEmpty()) runs += mutableListOf<String>()
                is Token.Word -> if (t.text !in Tokenizer.fillers) runs.last() += Tokenizer.spell(t.text)
            }
        }
        for (run in runs) {
            if (run.isEmpty()) continue
            var i = 0
            while (i < run.size) {
                val w = run[i]
                val upsideDown = w == "upside" && i + 1 < run.size && run[i + 1] == "down"
                if (w in reversedWords || upsideDown) {
                    if (draws.isNotEmpty()) {
                        draws[draws.lastIndex] = draws.last().copy(
                            orientation = Parsed(Orientation.REVERSED, w, if (w == "r") Confidence.MEDIUM else Confidence.HIGH))
                    }
                    i += if (upsideDown) 2 else 1
                    continue
                }
                if (w in uprightWords) { i++; continue }
                // Spread name, only before the first card.
                if (draws.isEmpty() && (div.spreadId.value == null || div.spreadId.confidence < Confidence.HIGH)) {
                    val sm = spreadMatcher.longestMatch(run, i)
                    if (sm != null && sm.score >= 0.85) {
                        div = div.copy(spreadId = Parsed(sm.id, run.subList(i, i + sm.wordCount).joinToString(" "), Confidence.from(sm.score)))
                        i += sm.wordCount
                        if (i < run.size && run[i] == "spread") i++
                        continue
                    }
                }
                val cm = matcher?.longestMatch(run, i)
                if (cm != null) {
                    val heard = run.subList(i, i + cm.wordCount).joinToString(" ")
                    val spread = library.spread(div.spreadId.value) ?: library.freeform
                    draws += DraftDraw(Parsed(cm.id, heard, Confidence.from(cm.score)),
                        Parsed(Orientation.UPRIGHT, null, Confidence.HIGH), spread.positionKey(draws.size))
                    i += cm.wordCount
                    continue
                }
                if (w !in ignorable && w.toIntOrNull() == null && w !in Tokenizer.numberWords) unparsed += w
                i++
            }
        }
        // Mark overflow positions as low confidence so they stand out.
        val spread = library.spread(div.spreadId.value)
        if (spread != null && !spread.openEnded) {
            for (k in draws.indices) {
                if (k >= spread.positions.size) {
                    draws[k] = draws[k].copy(cardId = draws[k].cardId.copy(confidence = minOf(draws[k].cardId.confidence, Confidence.LOW)))
                }
            }
        }
        return div.copy(draws = draws)
    }

    // Yi Jing

    private fun parseCast(tokens: List<Token>, warnings: MutableList<String>): DraftCast {
        var method = CastMethod.COINS
        val values = mutableListOf<Int>()
        val heard = mutableListOf<String>()
        for (w in words(tokens)) {
            if (w == "coins" || w == "coin") { method = CastMethod.COINS; continue }
            if (w == "yarrow" || w == "stalks") { method = CastMethod.YARROW; continue }
            val n = Tokenizer.numberWords[w]
            if (n != null && n in 6..9) { values += n; heard += w; continue }
            if (w.all { it.isDigit() }) {
                val digits = w.map { it.digitToInt() }
                if (digits.all { it in 6..9 }) { values += digits; heard += w }
            }
        }
        val conf = if (values.size == 6) Confidence.HIGH else Confidence.LOW
        if (values.size != 6) warnings += "Yi Jing: heard ${values.size} line values, need 6 (bottom to top)"
        return DraftCast(Parsed(values, heard.joinToString(" "), if (values.isEmpty()) Confidence.MISSING else conf), method)
    }
}
