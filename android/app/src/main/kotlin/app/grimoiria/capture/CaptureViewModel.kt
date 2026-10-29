package app.grimoiria.capture

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.grimoiria.capture.audio.OnDeviceTranscriber
import app.grimoiria.capture.audio.Recorder
import app.grimoiria.capture.sync.SafDestination
import app.grimoiria.core.Capture
import app.grimoiria.core.CaptureIds
import app.grimoiria.core.CaptureKind
import app.grimoiria.core.CaptureStore
import app.grimoiria.core.DraftEditor
import app.grimoiria.core.DraftReading
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.time.OffsetDateTime

sealed interface Screen {
    data object Home : Screen
    data class Check(val id: String) : Screen
    data object Outbox : Screen
    data object Settings : Screen
}

/** The capture being checked, with the words it was parsed from. */
data class CheckState(
    val capture: Capture,
    val transcribing: Boolean = false,
    val modelMissing: Boolean = false,
) {
    /** Transcript for voice captures, the typed text otherwise. */
    val words: String get() = if (capture.audioFile != null) capture.transcript.orEmpty() else capture.text.orEmpty()
}

class CaptureViewModel(app: Application) : AndroidViewModel(app) {
    private val ctx = app.grimoire
    val library get() = ctx.library
    val editor by lazy { DraftEditor(ctx.library) }
    private val store get() = ctx.store
    private val transcriber = OnDeviceTranscriber(app)
    private val deliverLock = Mutex()

    var screen by mutableStateOf<Screen>(Screen.Home)
        private set
    var kind by mutableStateOf(CaptureKind.fromHint(ctx.settings.lastKind))
        private set
    var tags by mutableStateOf("")
    var note by mutableStateOf("")
    var check by mutableStateOf<CheckState?>(null)
        private set
    var captures by mutableStateOf<List<CaptureStore.Stored>>(emptyList())
        private set
    var inboxLabel by mutableStateOf(ctx.settings.inboxFolder?.let { SafDestination.label(Uri.parse(it)) })
        private set
    var deviceName by mutableStateOf(ctx.settings.deviceName)
        private set
    var message by mutableStateOf<String?>(null)
    var syncing by mutableStateOf(false)
        private set

    init {
        refresh()
        deliver()
        viewModelScope.launch {
            Recorder.state.collect { s -> if (s is Recorder.State.Finished || s is Recorder.State.Failed) onRecordingDone(s) }
        }
    }

    val pendingCount get() = captures.count { it.state == CaptureStore.State.PENDING }
    /** Captures recorded but not yet saved; listed on Home so nothing is lost when the user leaves the check screen. */
    val drafts get() = captures.filter { it.state == CaptureStore.State.DRAFT && (screen !is Screen.Check || it.capture.id != check?.capture?.id) }

    fun refresh() {
        viewModelScope.launch { captures = withContext(Dispatchers.IO) { store.all() } }
    }

    fun go(s: Screen) {
        screen = s
        if (s == Screen.Home || s == Screen.Outbox) refresh()
    }

    fun selectKind(k: CaptureKind) {
        kind = k
        ctx.settings.lastKind = k.hint
    }

    private fun tagList() = tags.split(',', ' ').map { it.trim().trim('#') }.filter { it.isNotEmpty() }

    private fun newCapture(id: String, now: OffsetDateTime) =
        Capture(id = id, capturedAt = CaptureIds.capturedAt(now), kind = kind.hint, device = ctx.settings.deviceName, tags = tagList())

    // Recording

    fun startRecording() {
        if (Recorder.state.value is Recorder.State.Recording) return
        val now = OffsetDateTime.now()
        val id = CaptureIds.newId(now)
        val folder = store.draftFolder(id)
        // Saved before the first sample, so a crash still leaves a draft with whatever audio was captured.
        store.saveDraft(newCapture(id, now).copy(audioFile = "$id.wav"))
        Recorder.start(getApplication<Application>(), id, folder)
    }

    fun stopRecording() = Recorder.stop(getApplication<Application>())

    private fun onRecordingDone(s: Recorder.State) {
        Recorder.consume()
        when (s) {
            is Recorder.State.Failed -> {
                message = s.reason
                store.discardDraft(s.captureId)
            }
            is Recorder.State.Finished -> {
                val stored = store.get(s.captureId) ?: return
                tags = ""
                openCheck(CheckState(stored.capture, transcribing = true))
                transcribe(s.captureId, s.pcm, s.seconds)
            }
            else -> Unit
        }
    }

    private fun transcribe(id: String, pcm: File, seconds: Double) {
        viewModelScope.launch {
            val result = transcriber.transcribe(pcm, ctx.settings.speechLanguage, seconds)
            val current = check?.takeIf { it.capture.id == id } ?: return@launch
            check = when (result) {
                is OnDeviceTranscriber.Result.Text -> {
                    withContext(Dispatchers.IO) { pcm.delete() }
                    current.copy(transcribing = false, capture = withParsed(current.capture.copy(transcript = result.text, transcriptionNote = null), result.text))
                }
                is OnDeviceTranscriber.Result.Unavailable -> current.copy(transcribing = false, modelMissing = result.modelMissing,
                    capture = current.capture.copy(transcriptionNote = "${result.reason}. The Mac will transcribe the audio."))
            }
            persist()
        }
    }

    fun retranscribe() {
        val c = check?.capture ?: return
        val folder = store.get(c.id)?.folder ?: return
        val pcm = Recorder.pcmFile(folder, c.id)
        if (!pcm.exists()) { message = "The raw recording is gone; type the transcript instead"; return }
        check = check?.copy(transcribing = true, modelMissing = false)
        transcribe(c.id, pcm, app.grimoiria.capture.audio.WavRecorder.durationSeconds(pcm))
    }

    fun downloadSpeechModel() {
        transcriber.downloadModel(ctx.settings.speechLanguage)
        message = "Downloading the offline speech model. Try Transcribe again once it's done."
    }

    // Typed capture

    fun saveNote() {
        val text = note.trim()
        if (text.isEmpty()) return
        val now = OffsetDateTime.now()
        val c = withParsed(newCapture(CaptureIds.newId(now), now).copy(text = text), text)
        store.saveDraft(c)
        note = ""
        tags = ""
        if (c.draft != null) openCheck(CheckState(c)) else commit(c)
    }

    // Check (confirm and correct)

    private fun openCheck(s: CheckState) {
        check = s
        screen = Screen.Check(s.capture.id)
    }

    fun resume(id: String) {
        val stored = store.get(id) ?: return
        openCheck(CheckState(stored.capture))
    }

    /** Parsed reading for `words`, or null when there's none and the kind doesn't expect one. */
    private fun withParsed(c: Capture, words: String): Capture {
        val parsed = ctx.parser.parse(words)
        return c.copy(draft = if (!parsed.isEmpty || c.captureKind.expectsReading) parsed else null)
    }

    fun setWords(text: String) = update { c -> if (c.audioFile != null) c.copy(transcript = text) else c.copy(text = text) }

    /** Parses the (edited) words again, replacing the reading. */
    fun readAgain() = update { c -> withParsed(c, if (c.audioFile != null) c.transcript.orEmpty() else c.text.orEmpty()) }

    fun setKind(k: CaptureKind) = update { c ->
        val updated = c.copy(kind = k.hint)
        if (k.expectsReading && updated.draft == null) updated.copy(draft = DraftReading()) else updated
    }

    fun setTags(text: String) = update { c -> c.copy(tags = text.split(',', ' ').map { it.trim().trim('#') }.filter { it.isNotEmpty() }) }

    fun edit(f: (DraftReading) -> DraftReading) = update { c -> c.copy(draft = f(c.draft ?: DraftReading())) }

    private fun update(f: (Capture) -> Capture) {
        val s = check ?: return
        check = s.copy(capture = f(s.capture))
        persist()
    }

    private fun persist() {
        val c = check?.capture ?: return
        viewModelScope.launch(Dispatchers.IO) { if (store.get(c.id)?.state == CaptureStore.State.DRAFT) store.saveDraft(c) }
    }

    fun saveChecked() {
        val c = check?.capture ?: return
        commit(c.copy(draft = c.draft?.let(editor::finalized)))
    }

    private fun commit(c: Capture) {
        store.commit(c)
        check = null
        screen = Screen.Home
        message = "Saved to the Inbox"
        deliver()
    }

    fun discard() {
        val c = check?.capture ?: return
        store.discardDraft(c.id)
        check = null
        go(Screen.Home)
    }

    fun deleteSent(id: String) {
        store.deleteSent(id)
        refresh()
    }

    // Sync folder

    fun setInboxFolder(uri: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        getApplication<Application>().contentResolver.takePersistableUriPermission(uri, flags)
        ctx.settings.inboxFolder = uri.toString()
        inboxLabel = SafDestination.label(uri)
        deliver()
    }

    fun setDevice(name: String) {
        ctx.settings.deviceName = name
        deviceName = ctx.settings.deviceName
    }

    /** Copies pending captures into the sync folder. Runs on start, after each save, and on demand. */
    fun deliver() {
        viewModelScope.launch {
            deliverLock.withLock {
                val folder = ctx.settings.inboxFolder
                if (folder == null) { refresh(); return@withLock }
                syncing = true
                val report = withContext(Dispatchers.IO) {
                    store.deliverPending(SafDestination(getApplication<Application>(), Uri.parse(folder))) { CaptureIds.capturedAt(OffsetDateTime.now()) }
                }
                syncing = false
                report.failed.values.firstOrNull()?.let { message = "Not sent yet: $it" }
                refresh()
            }
        }
    }
}
