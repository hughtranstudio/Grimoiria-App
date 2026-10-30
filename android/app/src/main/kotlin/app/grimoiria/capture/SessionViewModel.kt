package app.grimoiria.capture

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.grimoiria.capture.audio.Recorder
import app.grimoiria.capture.audio.WavRecorder
import app.grimoiria.core.CaptureIds
import app.grimoiria.core.CaptureKind
import app.grimoiria.core.CaptureSidecar
import app.grimoiria.core.SessionDraft
import app.grimoiria.core.StateCheck
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Duration
import java.time.OffsetDateTime

/**
 * Records a ritual, meditation or vision (docs/session-recording.md): the clock, phase changes,
 * markers and typed observations, with the microphone on throughout. Saved after every tap in the
 * capture's own draft folder, so nothing is lost if the phone dies mid-session. On Save it goes to
 * the outbox like any capture; the Mac transcribes the audio with timestamps and builds the timeline.
 */
class SessionViewModel(app: Application) : AndroidViewModel(app) {
    private val ctx = app.grimoire
    private val store get() = ctx.store

    var draft by mutableStateOf<SessionDraft?>(null)
        private set
    /** The session has ended and is waiting for the after-ratings and Save. */
    val closing: Boolean get() = draft?.endedAt != null
    var message by mutableStateOf<String?>(null)

    // Setup, before Start
    var type by mutableStateOf(CaptureKind.MEDITATION)
    var intention by mutableStateOf("")
    var technique by mutableStateOf("")
    var tags by mutableStateOf("")
    var before by mutableStateOf(StateCheck())
    var withAudio by mutableStateOf(true)

    init {
        draft = currentId()?.let { id -> load(id) }
        viewModelScope.launch {
            Recorder.state.collect { s ->
                if (s is Recorder.State.Finished && s.session) {
                    Recorder.consume()
                    // Also reached when stopped from the notification: the session ends there too.
                    if (draft?.endedAt == null) finishClock()
                } else if (s is Recorder.State.Failed && s.session) {
                    Recorder.consume()
                    message = s.reason
                    update { it.copy(audioFile = null) }
                }
            }
        }
    }

    private val pointer get() = File(ctx.filesDir, "session-current.txt")
    private fun currentId(): String? = pointer.takeIf { it.exists() }?.readText()?.trim()?.ifEmpty { null }
    private fun file(id: String) = File(store.draftFolder(id), "session.json")
    private fun load(id: String): SessionDraft? = file(id).takeIf { it.exists() }?.let {
        runCatching { CaptureSidecar.json.decodeFromString(SessionDraft.serializer(), it.readText()) }.getOrNull()
    }

    private fun save(d: SessionDraft) {
        val f = file(d.id)
        val tmp = File(f.parentFile, "session.json.tmp")
        tmp.writeText(CaptureSidecar.json.encodeToString(SessionDraft.serializer(), d))
        tmp.renameTo(f)
    }

    private fun update(f: (SessionDraft) -> SessionDraft) {
        val d = draft ?: return
        val next = f(d)
        draft = next
        viewModelScope.launch(Dispatchers.IO) { save(next) }
    }

    /** Seconds since Start, by the wall clock (survives the app being closed). */
    fun offset(at: OffsetDateTime = OffsetDateTime.now()): Double {
        val start = draft?.startedAt?.let(OffsetDateTime::parse) ?: return 0.0
        return Duration.between(start, at).toMillis() / 1000.0
    }

    val recording: Boolean get() = (Recorder.state.value as? Recorder.State.Recording)?.session == true

    // Start, during, end

    /** `micAllowed` is false when the microphone permission was refused; the session runs without audio. */
    fun start(micAllowed: Boolean) {
        if (draft != null) return
        if (Recorder.state.value is Recorder.State.Recording) { message = "A capture is recording; stop it first"; return }
        val now = OffsetDateTime.now()
        val id = CaptureIds.newId(now)
        val audio = withAudio && micAllowed
        val d = SessionDraft(
            id = id, type = type.hint, startedAt = CaptureIds.capturedAt(now),
            intention = intention.trim().ifEmpty { null }, technique = technique.trim().ifEmpty { null },
            tags = tags.split(',', ' ').map { it.trim().trim('#') }.filter { it.isNotEmpty() },
            before = before.takeIf { !it.isEmpty }, audioFile = if (audio) "$id.wav" else null,
        ).setPhase(0.0, "preparation")
        val folder = store.draftFolder(id)
        save(d)
        pointer.writeText(id)
        draft = d
        if (audio) Recorder.start(getApplication<Application>(), id, folder, session = true)
    }

    fun mark() = update { it.mark(offset()) }
    fun phase(p: String) = update { it.setPhase(offset(), p) }
    fun observe(kind: String, text: String, tagText: String) = update {
        it.observe(offset(), kind, text, tagText.split(',', ' ').map { t -> t.trim().trim('#') }.filter { t -> t.isNotEmpty() })
    }
    fun removeMark(index: Int) = update { it.removeMark(index) }

    /** Stops the clock and the microphone; the after-ratings and outcome come next. */
    fun end() {
        if (recording) Recorder.stop(getApplication<Application>()) else finishClock()
    }

    private fun finishClock() = update { d ->
        // The app was closed mid-session: the raw audio is still there, so wrap it now.
        d.audioFile?.let { name ->
            val folder = store.draftFolder(d.id)
            val pcm = Recorder.pcmFile(folder, d.id)
            val wav = File(folder, name)
            if (!wav.exists() && pcm.exists()) runCatching { WavRecorder.writeWav(pcm, wav) }
        }
        val wavOk = d.audioFile?.let { File(store.draftFolder(d.id), it).exists() } ?: false
        d.copy(endedAt = CaptureIds.capturedAt(OffsetDateTime.now()), audioFile = d.audioFile.takeIf { wavOk })
    }

    fun setAfter(c: StateCheck) = update { it.copy(after = c) }
    fun setOutcome(text: String) = update { it.copy(outcome = text) }

    /** Hands the session to the outbox. `then` sends it to the sync folder. */
    fun saveToInbox(then: () -> Unit) {
        val d = draft ?: return
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                val folder = store.draftFolder(d.id)
                Recorder.pcmFile(folder, d.id).delete()
                File(folder, "session.json").delete()
                val c = d.toCapture(ctx.settings.deviceName)
                store.saveDraft(c)
                store.commit(c)
                pointer.delete()
            }
            reset()
            message = "Session saved; the Mac transcribes it and puts it in the Inbox"
            then()
        }
    }

    fun discard() {
        val d = draft ?: return
        if (recording) Recorder.stop(getApplication<Application>())
        Recorder.consume()
        store.discardDraft(d.id)
        pointer.delete()
        reset()
    }

    private fun reset() {
        draft = null
        intention = ""
        technique = ""
        tags = ""
        before = StateCheck()
    }
}
