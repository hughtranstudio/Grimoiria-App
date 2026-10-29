package app.grimoiria.core

/** Line values 6–9, bottom to top. Hexagrams are derived, as in GrimoireCore/YiJing/YiJingCast.swift. */
object YiJing {
    fun isYang(v: Int) = v == 7 || v == 9
    fun isChanging(v: Int) = v == 6 || v == 9
    fun isValid(lines: List<Int>) = lines.size == 6 && lines.all { it in 6..9 }

    /** 1-based positions of changing lines, bottom to top. */
    fun changingLines(lines: List<Int>): List<Int> = lines.withIndex().filter { isChanging(it.value) }.map { it.index + 1 }

    fun primary(lines: List<Int>, def: YiJingDefinition): YiJingDefinition.Hexagram? =
        if (isValid(lines)) def.number(lines.map(::isYang))?.let(def::hexagram) else null

    /** Nil when nothing changes. */
    fun resulting(lines: List<Int>, def: YiJingDefinition): YiJingDefinition.Hexagram? {
        if (!isValid(lines) || changingLines(lines).isEmpty()) return null
        return def.number(lines.map { if (isChanging(it)) !isYang(it) else isYang(it) })?.let(def::hexagram)
    }
}
