package app.grimoiria.core

/**
 * Corrections the user makes on the phone's check screen. Every corrected field becomes
 * `high` confidence and keeps the words that were heard, so the Mac's correction log still
 * sees "heard → corrected".
 */
class DraftEditor(private val library: DefinitionLibrary) {

    private fun DraftReading.update(index: Int, f: (DraftDivination) -> DraftDivination) =
        copy(divinations = divinations.mapIndexed { i, d -> if (i == index) f(d) else d })

    private fun <T> Parsed<T>.corrected(value: T?) = Parsed(value, heard, if (value == null) Confidence.MISSING else Confidence.HIGH)

    fun setQuestion(r: DraftReading, text: String) =
        r.copy(question = r.question.corrected(text.trim().ifEmpty { null }))

    fun setDeck(r: DraftReading, div: Int, deckId: String) = r.update(div) { d ->
        val spread = library.spread(d.spreadId.value)?.takeIf { it.appliesTo(deckId) } ?: library.freeform
        d.copy(deckId = d.deckId.corrected(deckId), spreadId = d.spreadId.copy(value = spread.id),
            // Cards of another deck mean nothing here; keep the slots so positions survive.
            draws = if (d.deckId.value == deckId) d.draws else d.draws.map { it.copy(cardId = it.cardId.corrected(null)) })
    }

    fun setSpread(r: DraftReading, div: Int, spreadId: String) = r.update(div) { d ->
        val spread = library.spread(spreadId) ?: library.freeform
        d.copy(spreadId = d.spreadId.corrected(spread.id),
            draws = d.draws.mapIndexed { i, draw -> draw.copy(positionKey = spread.positionKey(i)) })
    }

    fun setCard(r: DraftReading, div: Int, draw: Int, cardId: String) = r.update(div) { d ->
        d.copy(draws = d.draws.mapIndexed { i, x -> if (i == draw) x.copy(cardId = x.cardId.corrected(cardId)) else x })
    }

    fun setOrientation(r: DraftReading, div: Int, draw: Int, o: Orientation) = r.update(div) { d ->
        d.copy(draws = d.draws.mapIndexed { i, x -> if (i == draw) x.copy(orientation = x.orientation.corrected(o)) else x })
    }

    fun addDraw(r: DraftReading, div: Int) = r.update(div) { d ->
        val spread = library.spread(d.spreadId.value) ?: library.freeform
        d.copy(draws = d.draws + DraftDraw(Parsed.missing(), Parsed(Orientation.UPRIGHT, null, Confidence.HIGH), spread.positionKey(d.draws.size)))
    }

    fun removeDraw(r: DraftReading, div: Int, draw: Int) = r.update(div) { d ->
        val spread = library.spread(d.spreadId.value) ?: library.freeform
        d.copy(draws = d.draws.filterIndexed { i, _ -> i != draw }.mapIndexed { i, x -> x.copy(positionKey = spread.positionKey(i)) })
    }

    fun addCards(r: DraftReading, deckId: String?): DraftReading {
        val deck = deckId?.let { library.deck(it) } ?: library.decks.firstOrNull { !it.isPlaceholder }
        return r.copy(divinations = r.divinations + DraftDivination(DivinationSystem.CARDS,
            deckId = Parsed(deck?.id, null, if (deck == null) Confidence.MISSING else Confidence.HIGH),
            spreadId = Parsed(SpreadDefinition.FREEFORM_ID, null, Confidence.HIGH)))
    }

    fun addYiJing(r: DraftReading) = r.copy(divinations = r.divinations + DraftDivination(DivinationSystem.YIJING,
        cast = DraftCast(Parsed(emptyList(), null, Confidence.MISSING), CastMethod.COINS)))

    fun removeDivination(r: DraftReading, div: Int) = r.copy(divinations = r.divinations.filterIndexed { i, _ -> i != div })

    /** Sets line `line` (0 = bottom) to 6–9, padding missing lower lines with 7 (young yang). */
    fun setLine(r: DraftReading, div: Int, line: Int, value: Int) = r.update(div) { d ->
        val cast = d.cast ?: DraftCast(Parsed.missing(), CastMethod.COINS)
        val lines = (cast.lines.value ?: emptyList()).toMutableList()
        while (lines.size <= line) lines += 7
        lines[line] = value
        d.copy(cast = cast.copy(lines = Parsed(lines.take(6), cast.lines.heard, if (lines.size >= 6) Confidence.HIGH else Confidence.LOW)))
    }

    fun setMethod(r: DraftReading, div: Int, method: CastMethod) = r.update(div) { d ->
        d.copy(cast = (d.cast ?: DraftCast(Parsed.missing(), CastMethod.COINS)).copy(method = method))
    }

    /**
     * What still needs attention, in the parser's warning style. Replaces the parser's warnings
     * when the capture is saved, so the Mac shows what is still open rather than what was fixed.
     */
    fun issues(r: DraftReading): List<String> = r.divinations.flatMapIndexed { _, d ->
        when (d.system) {
            DivinationSystem.CARDS -> buildList {
                val deck = library.deck(d.deckId.value)
                if (deck == null) add("Pick a deck")
                else if (deck.isPlaceholder) add("${deck.name} has no card list yet; enter its cards on the Mac")
                val missing = d.draws.count { it.cardId.value == null }
                if (deck?.isPlaceholder == false && missing > 0) add("$missing card${if (missing == 1) "" else "s"} still to pick")
                val spread = library.spread(d.spreadId.value)
                if (spread != null && !spread.openEnded && d.draws.size != spread.positions.size) {
                    add("${spread.name} has ${spread.positions.size} positions but ${d.draws.size} cards are listed")
                }
            }
            DivinationSystem.YIJING -> {
                val lines = d.cast?.lines?.value ?: emptyList()
                if (YiJing.isValid(lines)) emptyList() else listOf("Yi Jing needs six line values, 6 to 9 (has ${lines.size})")
            }
            DivinationSystem.OTHER -> emptyList()
        }
    }

    /** The draft as it is saved: warnings are the issues still open. */
    fun finalized(r: DraftReading) = r.copy(warnings = issues(r))
}
