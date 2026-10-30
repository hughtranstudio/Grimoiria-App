package app.grimoiria.core

import java.text.Normalizer

// Port of GrimoireCore/Parsing/Tokenizer.swift. Keep the two in step: the shared golden
// cases (Tests/GrimoireCoreTests/Fixtures/parser-golden) run against both.

/** A word, or sentence punctuation as a boundary so matches never span "One, three of cups". */
sealed interface Token {
    data class Word(val text: String) : Token
    data object Boundary : Token
}

object Tokenizer {
    /** Words dropped before matching card and spread names. */
    val fillers = setOf("the", "of", "a", "an")

    val numberWords: Map<String, Int> = linkedMapOf(
        "zero" to 0, "one" to 1, "two" to 2, "three" to 3, "four" to 4, "five" to 5, "six" to 6, "seven" to 7,
        "eight" to 8, "nine" to 9, "ten" to 10, "eleven" to 11, "twelve" to 12, "thirteen" to 13, "fourteen" to 14,
        "fifteen" to 15, "sixteen" to 16, "seventeen" to 17, "eighteen" to 18, "nineteen" to 19, "twenty" to 20,
        "twenty-one" to 21,
    )
    private val spelled: Map<Int, String> = numberWords.entries.associate { it.value to it.key }

    private val combiningMarks = Regex("\\p{Mn}+")

    /** Lower case without accents, like Swift's case- and diacritic-insensitive folding. */
    fun fold(s: String): String =
        combiningMarks.replace(Normalizer.normalize(s, Normalizer.Form.NFD), "").lowercase(java.util.Locale.ROOT)

    fun tokenize(text: String): List<Token> {
        val out = mutableListOf<Token>()
        val cur = StringBuilder()
        fun flush() {
            if (cur.isNotEmpty()) { out += Token.Word(cur.toString()); cur.clear() }
        }
        for (ch in fold(text)) {
            when {
                ch.isLetter() || ch.isDigit() || ch == '\'' -> cur.append(ch)
                ch == '-' || ch == '–' -> flush() // "Rider-Waite" → rider waite
                ch in ".,;:!?\n()" -> {
                    flush()
                    if (out.lastOrNull() != Token.Boundary) out += Token.Boundary
                }
                else -> flush()
            }
        }
        flush()
        return out
    }

    /** Normalized key for alias comparison: fillers dropped, digits spelled out. */
    fun key(text: String): String =
        tokenize(text).mapNotNull { (it as? Token.Word)?.text?.takeIf { w -> w !in fillers } }.joinToString(" ") { spell(it) }

    fun spell(w: String): String = w.toIntOrNull()?.let { spelled[it] } ?: w
}

object Fuzzy {
    fun levenshtein(a: String, b: String): Int {
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        var prev = IntArray(b.length + 1) { it }
        var cur = IntArray(b.length + 1)
        for (i in 1..a.length) {
            cur[0] = i
            for (j in 1..b.length) {
                cur[j] = minOf(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + if (a[i - 1] == b[j - 1]) 0 else 1)
            }
            val t = prev; prev = cur; cur = t
        }
        return prev[b.length]
    }

    /** 1.0 for identical strings, falling towards 0. */
    fun similarity(a: String, b: String): Double {
        val m = maxOf(a.length, b.length)
        return if (m == 0) 1.0 else 1.0 - levenshtein(a, b).toDouble() / m
    }
}
