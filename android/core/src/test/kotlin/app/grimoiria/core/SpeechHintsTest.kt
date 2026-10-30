package app.grimoiria.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SpeechHintsTest {
    @Test
    fun hintsCoverDecksCardsSpreadsAndHexagrams() {
        val lib = TestSupport.library
        val hints = lib.speechHints()
        assertEquals(hints.size, hints.toSet().size)
        assertTrue("reversed" in hints)
        lib.decks.forEach { d -> assertTrue(d.name in hints); d.cards.forEach { assertTrue(it.name in hints) } }
        lib.spreads.forEach { assertTrue(it.name in hints) }
        lib.yijing.hexagrams.forEach { assertTrue(it.pinyin in hints) }
    }
}
