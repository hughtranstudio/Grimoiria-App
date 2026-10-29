package app.grimoiria.core

import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** Reads the library file the Swift tests write (PhoneLibraryTests), so both sides agree on the format. */
class LibraryTest {
    private val library = Library.parse(TestSupport.fixture("phone-library/grimoire.jsonl").readText())
    private val search = LibrarySearch(library, TestSupport.library)

    @Test
    fun readsEveryRecordTheMacShares() {
        assertEquals(0, library.skipped)
        assertEquals(2, library.entries.size)
        assertEquals(1, library.inquiries.size)
        assertEquals(1, library.reminders.size)

        val inq = library.inquiries.single()
        assertEquals("Will the move go ahead?", inq.question)
        assertEquals("2026-10-20", inq.askedAt.day)
        assertEquals(listOf("cups-03", "maj-16", "wands-11"), inq.divinations[0].draws.map { it.cardId })
        assertEquals(Orientation.REVERSED, inq.divinations[0].draws[0].orientation)
        assertEquals(listOf(7, 8, 9, 7, 8, 6), inq.divinations[1].cast?.lines)
        assertEquals(Fulfilled.PARTLY, inq.outcomes.single().fulfilled)

        val vision = assertNotNull(library.entries.firstOrNull { it.type == "vision" })
        val session = assertNotNull(vision.session)
        assertEquals(2100L, session.durationSeconds)
        assertEquals("entity", session.observations.single().kind)
        assertEquals(StateCheck(4, 4, 4), session.after)
        assertEquals("2026-10-21", vision.occurredAt.day, "days are in the recorded zone, not UTC")
    }

    @Test
    fun newestFirstAndSearchByTextTagCardAndHexagram() {
        assertEquals(listOf("Woke early. Crow on the fence.", "Inner library", "Will the move go ahead?"), search.all.map { it.title })
        assertEquals(listOf("reading", "journal", "vision"), search.groups)

        fun titles(q: LibraryQuery) = search.search(q).map { it.title }
        assertEquals(listOf("Will the move go ahead?"), titles(LibraryQuery("tower")), "card names are searchable")
        assertEquals(listOf("Will the move go ahead?"), titles(LibraryQuery("landlord")), "outcomes are searchable")
        assertEquals(listOf("Inner library"), titles(LibraryQuery("robed figure")), "session observations are searchable")
        assertEquals(listOf("Inner library"), titles(LibraryQuery("#entity/being")), "a parent tag finds its children")
        assertEquals(listOf("Woke early. Crow on the fence."), titles(LibraryQuery("#entity/animal")))
        assertEquals(listOf("Will the move go ahead?"), titles(LibraryQuery(card = "rws-tarot/maj-16")))
        // 7 8 9 7 8 6 is 55 Abundance changing to 21 Biting Through; both find the reading.
        assertEquals(listOf("Will the move go ahead?"), titles(LibraryQuery(hexagram = 55)))
        assertEquals(listOf("Will the move go ahead?"), titles(LibraryQuery(hexagram = 21)))
        assertEquals(emptyList(), titles(LibraryQuery(hexagram = 1)))
        assertEquals(listOf("Inner library"), titles(LibraryQuery(group = "vision")))
        assertEquals(emptyList(), titles(LibraryQuery("tower", group = "journal")))
    }

    @Test
    fun tagsIncludeParents() {
        assertTrue("entity" in library.allTags && "entity/being/guardian" in library.allTags && "question/home" in library.allTags)
    }

    @Test
    fun unknownRecordsAndNewerVersionsAreSkippedNotFatal() {
        val text = TestSupport.fixture("phone-library/grimoire.jsonl").readText() +
            """{"record_type":"entry","grimoire_export_version":2,"record":{"id":"X"}}""" + "\n" + "not json\n"
        val lib = Library.parse(text)
        assertEquals(2, lib.skipped)
        assertEquals(1, lib.inquiries.size)
    }

    @Test
    fun checksumMatchesTheMac() {
        // Values from PhoneLibrary.checksum in Swift (FNV-1a 64).
        assertEquals("0-cbf29ce484222325", Library.checksum(ByteArray(0)))
        assertEquals("3-e71fa2190541574b", Library.checksum("abc".toByteArray()))
    }

    @Test
    fun manifestReads() {
        val m = assertNotNull(Library.parseManifest("""{"library_version":1,"exported_at":"2026-10-29T21:30:00-07:00","entries":2,"inquiries":1,"reminders":1,"checksum":"9-abc"}"""))
        assertEquals("9-abc", m.checksum)
    }

    @Test
    fun checkInsHideWhatThePhoneAnsweredOrPutOff() {
        val r = library.reminders.single()
        assertEquals("2026-11-19", r.dueOn)
        assertEquals(emptyList(), CheckIns.due(library, PhoneCheckInState(), "2026-11-18"))
        val due = CheckIns.due(library, PhoneCheckInState(), "2026-11-19").single()
        assertEquals("Will the move go ahead?", due.title)
        assertEquals(1, CheckIns.upcoming(library, PhoneCheckInState(), "2026-11-01").size)

        val answered = PhoneCheckInState(answered = mapOf(r.targetId to "2026-11-20"))
        assertEquals(emptyList(), CheckIns.due(library, answered, "2026-11-21"))
        val snoozed = PhoneCheckInState(snoozed = mapOf(r.id to "2026-11-22"))
        assertEquals(emptyList(), CheckIns.due(library, snoozed, "2026-11-21"))
        assertEquals(1, CheckIns.due(library, snoozed, "2026-11-22").size)

        // The answer stays until the Mac files an outcome dated that day or later.
        assertEquals(answered, CheckIns.prune(answered, library, "2026-11-21"))
        val old = PhoneCheckInState(answered = mapOf(r.targetId to "2026-10-27"))
        assertEquals(emptyMap(), CheckIns.prune(old, library, "2026-11-21").answered, "the library already has the 27 Oct outcome")
    }
}

class CastingTest {
    @Test
    fun coinsAndYarrowGiveSixLineValuesWithTheRightOdds() {
        val r = Random(42)
        val coins = List(4000) { Casting.coins(r) }.flatten()
        val yarrow = List(4000) { Casting.yarrow(r) }.flatten()
        assertTrue(coins.all { it in 6..9 } && yarrow.all { it in 6..9 })
        fun share(xs: List<Int>, v: Int) = xs.count { it == v }.toDouble() / xs.size
        assertEquals(0.125, share(coins, 6), 0.02)
        assertEquals(0.375, share(coins, 8), 0.02)
        assertEquals(1 / 16.0, share(yarrow, 6), 0.02)
        assertEquals(7 / 16.0, share(yarrow, 8), 0.02)
    }

    @Test
    fun drawFillsTheSpreadWithDifferentCardsAndKeepsChosenOnes() {
        val lib = TestSupport.library
        val editor = DraftEditor(lib)
        var r = editor.addCards(DraftReading(), "rws-tarot")
        r = editor.setSpread(r, 0, "three-card")
        r = editor.addDraw(r, 0)
        r = editor.setCard(r, 0, 0, "maj-16")
        val drawn = PhoneReading(lib).drawInto(r, 0, Random(3))
        val draws = drawn.divinations[0].draws
        assertEquals(listOf("past", "present", "future"), draws.map { it.positionKey })
        assertEquals("maj-16", draws[0].cardId.value)
        assertEquals(3, draws.mapNotNull { it.cardId.value }.toSet().size)
        assertTrue(editor.issues(drawn).isEmpty(), editor.issues(drawn).toString())

        var y = editor.addYiJing(DraftReading())
        y = editor.setMethod(y, 0, CastMethod.YARROW)
        val cast = PhoneReading(lib).castInto(y, 0, Random(5)).divinations[0].cast!!
        assertEquals(CastMethod.YARROW, cast.method)
        assertTrue(YiJing.isValid(cast.lines.value!!))
    }

    @Test
    fun quareiaCardsCarryTheirMeanings() {
        val card = TestSupport.library.deck("quareia")!!.card("star-father")!!
        assertEquals(listOf("mundane", "magical"), card.significations.keys.toList())
    }
}

class SessionAndOutcomeSidecarTest {
    @Test
    fun sessionSidecarHasTheShapeTheMacReads() {
        var s = SessionDraft("20261029-213000-4821", "vision", "2026-10-29T21:30:00-07:00", intention = "Visit the inner library",
            before = StateCheck(3, 2, 3), audioFile = "20261029-213000-4821.wav")
        s = s.setPhase(0.0, "opening").mark(312.54).observe(640.0, "entity", " Robed figure at the door ", listOf("entity/being/guardian"))
            .setPhase(1800.0, "closing")
        s = s.copy(endedAt = "2026-10-29T22:05:40-07:00", after = StateCheck(4, 4, 4), outcome = "Came back calm.")
        assertEquals(1, s.markerCount)
        assertEquals(1, s.observations.size)

        val o = kotlinx.serialization.json.Json.parseToJsonElement(s.toCapture("pixel").sidecar().encode()).jsonObject
        assertEquals("vision", o.getValue("kind_hint").jsonPrimitive.content)
        assertEquals("20261029-213000-4821.wav", o.getValue("audio").jsonPrimitive.content)
        val session = o.getValue("session").jsonObject
        assertEquals("2026-10-29T21:30:00-07:00", session.getValue("started_at").jsonPrimitive.content)
        val marks = session.getValue("marks").toString()
        assertTrue(marks.contains(""""offset_s":312.5"""), marks)
        assertTrue(marks.contains(""""kind":"entity","text":"Robed figure at the door","tags":["entity/being/guardian"]"""), marks)
        assertTrue(!o.containsKey("draft"), "a session never carries a reading")
    }

    @Test
    fun outcomeSidecarNamesItsReading() {
        val c = Capture("20261110-090000-1234", "2026-11-10T09:00:00-08:00", "outcome", "pixel", text = "Moved in on the 9th.",
            inquiryId = "01JBQ8Y5X0AAAAAAAAAAAAAAAA", fulfilled = Fulfilled.YES)
        val o = kotlinx.serialization.json.Json.parseToJsonElement(c.sidecar().encode()).jsonObject
        assertEquals("01JBQ8Y5X0AAAAAAAAAAAAAAAA", o.getValue("inquiry_id").jsonPrimitive.content)
        assertEquals("yes", o.getValue("outcome").jsonObject.getValue("fulfilled").jsonPrimitive.content)
        assertEquals("outcome", o.getValue("kind_hint").jsonPrimitive.content)
    }
}
