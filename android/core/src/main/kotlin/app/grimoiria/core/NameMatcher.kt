package app.grimoiria.core

/**
 * Matches spoken or typed phrases against named things (cards, decks, spreads) using their
 * names and aliases. Exact matches score 1.0; near misses score their similarity.
 * Port of GrimoireCore/Parsing/NameMatcher.swift.
 */
class NameMatcher<ID>(names: List<Pair<ID, List<String>>>, val threshold: Double = 0.8) {
    private class Candidate<ID>(val key: String, val wordCount: Int, val id: ID)

    private val candidates: List<Candidate<ID>>
    private val exact: Map<String, ID>
    val maxWords: Int

    init {
        val list = mutableListOf<Candidate<ID>>()
        val ex = mutableMapOf<String, ID>()
        for ((id, ns) in names) {
            for (n in ns) {
                val k = Tokenizer.key(n)
                if (k.isEmpty()) continue
                list += Candidate(k, wordCount(k), id)
                if (k !in ex) ex[k] = id
            }
        }
        candidates = list
        exact = ex
        maxWords = list.maxOfOrNull { it.wordCount } ?: 1
    }

    data class Match<ID>(val id: ID, val score: Double, val wordCount: Int)

    private fun wordCount(key: String) = key.split(' ').count { it.isNotEmpty() }

    /** Best match for an already-normalized key. */
    fun matchKey(key: String): Match<ID>? {
        val words = wordCount(key)
        exact[key]?.let { return Match(it, 1.0, words) }
        // Fuzzy only on phrases long enough that a near miss is meaningful.
        if (key.length < 4) return null
        var best: Match<ID>? = null
        for (c in candidates) {
            if (c.wordCount != words) continue
            val s = Fuzzy.similarity(key, c.key)
            if (s >= threshold && s > (best?.score ?: 0.0)) best = Match(c.id, s, words)
        }
        return best
    }

    /** Match a free phrase such as "3 cups" or "the Tower". */
    fun match(phrase: String): Match<ID>? = matchKey(Tokenizer.key(phrase))

    /** Longest match starting at `start` in a word list (fillers already removed). Exact beats fuzzy. */
    fun longestMatch(words: List<String>, start: Int): Match<ID>? {
        var fuzzy: Match<ID>? = null
        var len = minOf(maxWords, words.size - start)
        while (len >= 1) {
            val m = matchKey(words.subList(start, start + len).joinToString(" "))
            if (m != null) {
                if (m.score == 1.0) return m
                if (fuzzy == null || m.score > fuzzy.score) fuzzy = m
            }
            len--
        }
        return fuzzy
    }
}
