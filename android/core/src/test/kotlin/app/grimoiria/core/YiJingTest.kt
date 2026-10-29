package app.grimoiria.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class YiJingTest {
    private val def = TestSupport.library.yijing

    @Test
    fun derivesPrimaryChangingAndResulting() {
        val lines = listOf(7, 8, 9, 6, 7, 7)
        assertEquals(listOf(3, 4), YiJing.changingLines(lines))
        assertEquals(def.number(listOf(true, false, true, false, true, true)), YiJing.primary(lines, def)?.number)
        assertEquals(def.number(listOf(true, false, false, true, true, true)), YiJing.resulting(lines, def)?.number)
    }

    @Test
    fun allYangIsTheCreativeAndNothingChanges() {
        assertEquals(1, YiJing.primary(listOf(7, 7, 7, 7, 7, 7), def)?.number)
        assertNull(YiJing.resulting(listOf(7, 7, 7, 7, 7, 7), def))
        assertEquals(2, YiJing.resulting(listOf(9, 9, 9, 9, 9, 9), def)?.number)
        assertNull(YiJing.primary(listOf(7, 7, 7), def))
    }
}
