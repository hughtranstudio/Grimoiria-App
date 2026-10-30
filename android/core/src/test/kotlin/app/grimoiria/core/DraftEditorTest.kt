package app.grimoiria.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DraftEditorTest {
    private val editor = DraftEditor(TestSupport.library)
    private val parser = TestSupport.parser

    @Test
    fun correctingAMisheardCardKeepsWhatWasHeard() {
        var r = parser.parse("Deck Rider-Waite three card. Three of cups. The tour. Page of wands.")
        assertEquals(listOf("Three card has 3 positions but 2 cards are listed"), editor.issues(r))
        r = editor.addDraw(r, 0)
        assertEquals("future", r.divinations[0].draws[2].positionKey)
        assertEquals(listOf("1 card still to pick"), editor.issues(r))
        r = editor.setCard(r, 0, 2, "maj-16")
        r = editor.setOrientation(r, 0, 0, Orientation.REVERSED)
        assertTrue(editor.issues(r).isEmpty())
        assertEquals(Confidence.HIGH, r.weakest)
        assertEquals(emptyList(), editor.finalized(r).warnings)
    }

    @Test
    fun fuzzyCardCorrectedBecomesHighWithHeardText() {
        var r = parser.parse("Deck Rider-Waite. The hight priestess")
        assertEquals(Confidence.MEDIUM, r.weakest)
        r = editor.setCard(r, 0, 0, "maj-02")
        assertEquals(Parsed("maj-02", "hight priestess", Confidence.HIGH), r.divinations[0].draws[0].cardId)
    }

    @Test
    fun changingSpreadRenumbersPositions() {
        var r = parser.parse("Deck RWS. The Fool, the Magician, the Empress")
        assertEquals(listOf("1", "2", "3"), r.divinations[0].draws.map { it.positionKey })
        r = editor.setSpread(r, 0, "three-card")
        assertEquals(listOf("past", "present", "future"), r.divinations[0].draws.map { it.positionKey })
        r = editor.removeDraw(r, 0, 0)
        assertEquals(listOf("past", "present"), r.divinations[0].draws.map { it.positionKey })
    }

    @Test
    fun placeholderDeckIsFlaggedNotBlocked() {
        val r = parser.parse("Deck Mystagogos, the oracle")
        assertEquals(listOf("Mystagogos Deck has no card list yet; enter its cards on the Mac"), editor.issues(r))
    }

    @Test
    fun yiJingLinesCanBeEnteredByHand() {
        var r = editor.addYiJing(DraftReading())
        assertEquals(1, editor.issues(r).size)
        for ((i, v) in listOf(7, 8, 9, 6, 7, 7).withIndex()) r = editor.setLine(r, 0, i, v)
        assertEquals(listOf(7, 8, 9, 6, 7, 7), r.divinations[0].cast!!.lines.value)
        assertTrue(editor.issues(r).isEmpty())
        r = editor.setLine(parser.parse("Yi Jing yarrow. seven eight nine"), 0, 5, 6)
        assertEquals(listOf(7, 8, 9, 7, 7, 6), r.divinations[0].cast!!.lines.value)
        assertEquals(CastMethod.YARROW, r.divinations[0].cast!!.method)
    }
}
