package app.grimoiria.core

import kotlinx.serialization.Serializable
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * One capture as the phone keeps it until it has been handed to the sync folder.
 * `audioFile` is a bare file name inside the capture's own folder.
 */
@Serializable
data class Capture(
    val id: String,
    val capturedAt: String,
    val kind: String,
    val device: String,
    val tags: List<String> = emptyList(),
    val audioFile: String? = null,
    val text: String? = null,
    val transcript: String? = null,
    val draft: DraftReading? = null,
    /** Why on-phone transcription did not run; the Mac transcribes instead. */
    val transcriptionNote: String? = null,
    val deliveredAt: String? = null,
    val lastError: String? = null,
) {
    val captureKind: CaptureKind get() = CaptureKind.fromHint(kind)

    /** The sidecar for this capture. Empty readings are left out unless the kind expects one. */
    fun sidecar(): CaptureSidecar = CaptureSidecar(
        id = id,
        capturedAt = capturedAt,
        device = device,
        kindHint = kind,
        text = text?.takeIf { it.isNotBlank() },
        audio = audioFile,
        tags = tags,
        transcript = transcript?.takeIf { it.isNotBlank() && audioFile != null },
        draft = draft?.takeIf { !it.isEmpty || captureKind.expectsReading },
    )
}

/** The synced Inbox folder (the one holding `incoming/`) as seen from the phone. */
interface InboxDestination {
    /**
     * Copies `source` into `incoming/` as `name`, replacing a file of that name. Implementations
     * write under a hidden temporary name first and rename, so the Mac never reads half a file.
     */
    @Throws(IOException::class)
    fun write(name: String, source: File)
}

/** A plain folder on disk; used in tests and by desktop tools. */
class FolderDestination(private val root: File) : InboxDestination {
    override fun write(name: String, source: File) {
        val incoming = File(root, "incoming").apply { mkdirs() }
        val tmp = File(incoming, ".$name.part")
        source.copyTo(tmp, overwrite = true)
        Files.move(tmp.toPath(), File(incoming, name).toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }
}

/**
 * Offline-first storage for captures on the phone, in three folders under `root`:
 *
 * - `drafts/<id>/`  recorded or typed, still being checked by the user
 * - `outbox/<id>/`  saved; waiting to be copied to the sync folder
 * - `sent/<id>/`    copied to the sync folder (kept so the user can see what went)
 *
 * Every step is a rename of the capture's folder, so a crash never leaves a half-saved capture.
 */
class CaptureStore(val root: File) {
    enum class State { DRAFT, PENDING, SENT }

    data class Stored(val capture: Capture, val state: State, val folder: File)

    private val drafts = File(root, "drafts")
    private val outbox = File(root, "outbox")
    private val sent = File(root, "sent")

    init {
        listOf(drafts, outbox, sent).forEach { it.mkdirs() }
    }

    private fun meta(folder: File) = File(folder, "capture.json")
    private fun write(folder: File, c: Capture) {
        val tmp = File(folder, "capture.json.tmp")
        tmp.writeText(CaptureSidecar.json.encodeToString(Capture.serializer(), c))
        Files.move(tmp.toPath(), meta(folder).toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }

    private fun read(folder: File): Capture? = meta(folder).takeIf { it.exists() }?.let {
        runCatching { CaptureSidecar.json.decodeFromString(Capture.serializer(), it.readText()) }.getOrNull()
    }

    /** Folder a new draft's audio is recorded into. */
    fun draftFolder(id: String): File = File(drafts, id).apply { mkdirs() }

    fun saveDraft(c: Capture): Stored {
        val folder = draftFolder(c.id)
        write(folder, c)
        return Stored(c, State.DRAFT, folder)
    }

    fun get(id: String): Stored? = listOf(drafts to State.DRAFT, outbox to State.PENDING, sent to State.SENT)
        .firstNotNullOfOrNull { (dir, state) -> File(dir, id).let { f -> read(f)?.let { Stored(it, state, f) } } }

    /** Newest first. */
    fun all(): List<Stored> = listOf(drafts to State.DRAFT, outbox to State.PENDING, sent to State.SENT).flatMap { (dir, state) ->
        (dir.listFiles() ?: emptyArray()).filter { it.isDirectory }.mapNotNull { f -> read(f)?.let { Stored(it, state, f) } }
    }.sortedByDescending { it.capture.id }

    fun drafts(): List<Stored> = all().filter { it.state == State.DRAFT }
    fun pending(): List<Stored> = all().filter { it.state == State.PENDING }

    /** Finishes the user's check: writes the final capture and moves it to the outbox. */
    fun commit(c: Capture): Stored {
        val from = draftFolder(c.id)
        write(from, c.copy(lastError = null))
        val to = File(outbox, c.id)
        Files.move(from.toPath(), to.toPath(), StandardCopyOption.ATOMIC_MOVE)
        return Stored(c, State.PENDING, to)
    }

    fun discardDraft(id: String) {
        File(drafts, id).deleteRecursively()
    }

    fun deleteSent(id: String) {
        File(sent, id).deleteRecursively()
    }

    data class DeliveryReport(val delivered: List<String>, val failed: Map<String, String>)

    /**
     * Copies every pending capture into the sync folder: audio first, sidecar last (the Mac acts
     * on the sidecar only once its audio is there). Safe to repeat; the Mac ignores capture ids
     * it already has.
     */
    fun deliverPending(destination: InboxDestination, now: () -> String): DeliveryReport {
        val delivered = mutableListOf<String>()
        val failed = linkedMapOf<String, String>()
        for (s in pending().sortedBy { it.capture.id }) {
            val c = s.capture
            try {
                val sidecar = c.sidecar()
                c.audioFile?.let { destination.write(it, File(s.folder, it)) }
                val sidecarFile = File(s.folder, "${c.id}.json")
                sidecarFile.writeText(sidecar.encode())
                destination.write(sidecarFile.name, sidecarFile)
                write(s.folder, c.copy(deliveredAt = now(), lastError = null))
                Files.move(s.folder.toPath(), File(sent, c.id).toPath(), StandardCopyOption.ATOMIC_MOVE)
                delivered += c.id
            } catch (e: Exception) {
                val reason = e.message ?: e::class.java.simpleName
                runCatching { write(s.folder, c.copy(lastError = reason)) }
                failed[c.id] = reason
            }
        }
        return DeliveryReport(delivered, failed)
    }
}
