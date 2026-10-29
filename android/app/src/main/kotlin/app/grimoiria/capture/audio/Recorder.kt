package app.grimoiria.capture.audio

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File

/**
 * The one recording in progress. Lives at process level so the foreground service keeps it alive
 * when the screen is locked mid-capture; the UI just observes [state].
 */
object Recorder {
    sealed interface State {
        data object Idle : State
        data class Recording(val captureId: String, val startedAt: Long, val level: Float = 0f) : State
        /** Stopped; `wav` is ready and `pcm` is kept for transcription. */
        data class Finished(val captureId: String, val wav: File, val pcm: File, val seconds: Double) : State
        data class Failed(val captureId: String, val reason: String) : State
    }

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state

    private var recorder: WavRecorder? = null
    private var folder: File? = null

    fun pcmFile(folder: File, id: String) = File(folder, "$id.pcm")
    fun wavFile(folder: File, id: String) = File(folder, "$id.wav")

    @Synchronized
    fun start(context: Context, captureId: String, folder: File) {
        if (_state.value is State.Recording) return
        this.folder = folder
        context.startForegroundService(Intent(context, RecordingService::class.java))
        val started = SystemClock.elapsedRealtime()
        try {
            recorder = WavRecorder(pcmFile(folder, captureId)) { level ->
                val s = _state.value
                if (s is State.Recording) _state.value = s.copy(level = level)
            }.also { it.start() }
            _state.value = State.Recording(captureId, started)
        } catch (e: Exception) {
            recorder = null
            _state.value = State.Failed(captureId, e.message ?: "Recording failed")
            context.stopService(Intent(context, RecordingService::class.java))
        }
    }

    @Synchronized
    fun stop(context: Context) {
        val s = _state.value as? State.Recording ?: return
        val dir = folder ?: return
        recorder?.stop()
        recorder = null
        context.stopService(Intent(context, RecordingService::class.java))
        _state.value = try {
            val pcm = pcmFile(dir, s.captureId)
            val wav = wavFile(dir, s.captureId)
            WavRecorder.writeWav(pcm, wav)
            State.Finished(s.captureId, wav, pcm, WavRecorder.durationSeconds(pcm))
        } catch (e: Exception) {
            State.Failed(s.captureId, e.message ?: "Could not save the recording")
        }
    }

    /** The UI has taken the finished recording. */
    fun consume() {
        if (_state.value !is State.Recording) _state.value = State.Idle
    }
}
