package app.grimoiria.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The Swift parser's golden cases (Tests/GrimoireCoreTests/Fixtures/parser-golden/cases.json),
 * run through the Kotlin port. Equal objects and equal JSON: the Mac must be able to decode
 * whatever the phone writes.
 */
class ParserGoldenTest {
    private val json = Json { explicitNulls = false; encodeDefaults = true }

    @Test
    fun matchesSwiftParserOnEveryGoldenCase() {
        val cases = Json.parseToJsonElement(TestSupport.fixture("parser-golden/cases.json").readText()).jsonArray
        assertTrue(cases.size > 10)
        for (c in cases.map { it.jsonObject }) {
            val input = c.getValue("input").jsonPrimitive.content
            val expectedJson = c.getValue("expected") as JsonObject
            val actual = when (c.getValue("mode").jsonPrimitive.content) {
                "quick" -> DraftReading(divinations = listOf(TestSupport.parser.parseQuickDraw(
                    input, c.getValue("deckId").jsonPrimitive.content, c["spreadId"]?.jsonPrimitive?.contentOrNull)))
                else -> TestSupport.parser.parse(input)
            }
            assertEquals(json.decodeFromJsonElement(DraftReading.serializer(), expectedJson), actual, input)
            assertEquals(expectedJson, json.encodeToJsonElement(DraftReading.serializer(), actual), "JSON shape: $input")
        }
    }

    @Test
    fun foldsAccentsAndDashesLikeSwift() {
        assertEquals("cafe resume naive", Tokenizer.key("Café – Résumé, naïve"))
        assertEquals("three cups", Tokenizer.key("the 3 of cups"))
        assertEquals("rider waite", Tokenizer.key("Rider–Waite"))
    }

    @Test
    fun weakestConfidenceDrivesHighlighting() {
        val r = TestSupport.parser.parse("Deck Rider-Waite. The hight priestess, temperence")
        assertEquals(Confidence.MEDIUM, r.weakest)
        assertEquals(Confidence.HIGH, TestSupport.parser.parse("Deck RWS single. The Star").weakest)
    }
}
