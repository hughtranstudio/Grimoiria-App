package app.grimoiria.core

import kotlinx.serialization.json.Json
import java.io.File
import java.io.IOException
import java.time.OffsetDateTime
import java.time.ZoneOffset
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CaptureStoreTest {
    private val at = OffsetDateTime.of(2026, 10, 29, 7, 15, 0, 0, ZoneOffset.ofHours(-7))

    private fun voiceDraw(store: CaptureStore): Capture {
        val id = CaptureIds.newId(at, Random(1))
        File(store.draftFolder(id), "$id.wav").writeBytes(ByteArray(64) { 1 })
        val transcript = "Question: will the move go ahead. Deck Rider-Waite. Three card. One, three of cups reversed. Two, the Tower. Three, page of wands."
        val c = Capture(id, CaptureIds.capturedAt(at), "draw", "pixel", listOf("theme/threshold"), "$id.wav",
            transcript = transcript, draft = TestSupport.parser.parse(transcript))
        store.saveDraft(c)
        return c
    }

    @Test
    fun idsAndTimestampsMatchTheShortcutContract() {
        val id = CaptureIds.newId(at, Random(7))
        assertTrue(Regex("""20261029-071500-\d{4}""").matches(id), id)
        assertEquals("2026-10-29T07:15:00-07:00", CaptureIds.capturedAt(at))
        assertEquals("2026-10-29T14:15:00Z", CaptureIds.capturedAt(at.withOffsetSameInstant(ZoneOffset.UTC)))
    }

    @Test
    fun draftCommitDeliverWritesAudioThenSidecar() {
        val store = CaptureStore(TestSupport.tempDir())
        val c = voiceDraw(store)
        assertEquals(CaptureStore.State.DRAFT, store.get(c.id)?.state)
        store.commit(c)
        assertEquals(CaptureStore.State.PENDING, store.get(c.id)?.state)

        val order = mutableListOf<String>()
        val inbox = TestSupport.tempDir()
        val folder = FolderDestination(inbox)
        val report = store.deliverPending(object : InboxDestination {
            override fun write(name: String, source: File) { order += name; folder.write(name, source) }
        }) { "2026-10-29T07:16:00-07:00" }

        assertEquals(listOf(c.id), report.delivered)
        assertEquals(listOf("${c.id}.wav", "${c.id}.json"), order)
        val sent = store.get(c.id)!!
        assertEquals(CaptureStore.State.SENT, sent.state)
        assertEquals("2026-10-29T07:16:00-07:00", sent.capture.deliveredAt)
        val incoming = File(inbox, "incoming").list()!!.sorted()
        assertEquals(listOf("${c.id}.json", "${c.id}.wav"), incoming) // no .part files left behind

        val sidecar = CaptureSidecar.decode(File(inbox, "incoming/${c.id}.json").readText())
        assertEquals(1, sidecar.contractVersion)
        assertEquals("draw", sidecar.kindHint)
        assertEquals("${c.id}.wav", sidecar.audio)
        assertEquals(listOf("cups-03", "maj-16", "wands-11"), sidecar.draft!!.divinations[0].draws.map { it.cardId.value })
    }

    @Test
    fun failedDeliveryStaysInOutboxWithReason() {
        val store = CaptureStore(TestSupport.tempDir())
        val c = voiceDraw(store)
        store.commit(c)
        val report = store.deliverPending(object : InboxDestination {
            override fun write(name: String, source: File) = throw IOException("folder not reachable")
        }) { "now" }
        assertEquals(mapOf(c.id to "folder not reachable"), report.failed)
        val s = store.get(c.id)!!
        assertEquals(CaptureStore.State.PENDING, s.state)
        assertEquals("folder not reachable", s.capture.lastError)
    }

    @Test
    fun sidecarUsesSnakeCaseKeysAndOmitsEmptyFields() {
        val text = Capture("20261029-090000-1111", "2026-10-29T09:00:00Z", "omen", "pixel", listOf("entity/crow"), text = "Crow on the gate")
        val o = Json.parseToJsonElement(text.sidecar().encode()).toString()
        assertEquals("""{"contract_version":1,"id":"20261029-090000-1111","captured_at":"2026-10-29T09:00:00Z","device":"pixel","kind_hint":"omen","text":"Crow on the gate","tags":["entity/crow"]}""", o)
        // Plain speech with no reading: no draft; a draw kind always carries its (possibly empty) draft.
        val omen = text.copy(text = null, audioFile = "a.wav", transcript = "crow on the gate", draft = DraftReading())
        assertNull(omen.sidecar().draft)
        assertEquals(DraftReading(), omen.copy(kind = "draw").sidecar().draft)
    }

    @Test
    fun androidFixtureRoundTrips() {
        val raw = TestSupport.fixture("capture-android/20261029-071500-3307.json").readText()
        val s = CaptureSidecar.decode(raw)
        assertEquals("maj-16", s.draft!!.divinations[0].draws[1].cardId.value)
        assertEquals(Json.parseToJsonElement(raw), Json.parseToJsonElement(s.encode()))
    }

    @Test
    fun discardRemovesDraft() {
        val store = CaptureStore(TestSupport.tempDir())
        val c = voiceDraw(store)
        store.discardDraft(c.id)
        assertNull(store.get(c.id))
        assertFalse(store.all().any { it.capture.id == c.id })
    }
}
