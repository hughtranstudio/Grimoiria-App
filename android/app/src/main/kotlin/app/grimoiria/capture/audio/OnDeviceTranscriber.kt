package app.grimoiria.capture.audio

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import kotlin.coroutines.resume

/**
 * Transcribes a finished recording on the phone with Android's on-device recognizer, fed from
 * the PCM file (nothing is sent to a server). If it can't run, the capture still goes out with
 * its audio and the Mac transcribes it with Whisper instead.
 */
class OnDeviceTranscriber(private val context: Context) {
    sealed interface Result {
        data class Text(val text: String) : Result
        data class Unavailable(val reason: String, val modelMissing: Boolean = false) : Result
    }

    fun isAvailable(): Boolean = SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    suspend fun transcribe(pcm: File, language: String, seconds: Double): Result {
        if (!isAvailable()) return Result.Unavailable("On-device speech recognition isn't available on this phone")
        val timeoutMs = (seconds * 3_000).toLong().coerceAtLeast(30_000)
        return withContext(Dispatchers.Main) {
            withTimeoutOrNull(timeoutMs) { run(pcm, language) }
                ?: Result.Unavailable("Speech recognition timed out")
        }
    }

    private suspend fun run(pcm: File, language: String): Result = suspendCancellableCoroutine { cont ->
        val main = Handler(Looper.getMainLooper())
        val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        val pfd = ParcelFileDescriptor.open(pcm, ParcelFileDescriptor.MODE_READ_ONLY)
        val segments = mutableListOf<String>()
        var done = false

        fun finish(result: Result) {
            if (done) return
            done = true
            main.post { recognizer.destroy(); runCatching { pfd.close() } }
            if (cont.isActive) cont.resume(result)
        }
        fun joined() = Result.Text(segments.joinToString(". ") { it.trim().trimEnd('.') })
        fun first(b: Bundle?) = b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.takeIf { it.isNotBlank() }

        recognizer.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
            override fun onSegmentResults(segmentResults: Bundle) { first(segmentResults)?.let { segments += it } }
            override fun onEndOfSegmentedSession() = finish(joined())
            override fun onResults(results: Bundle?) {
                first(results)?.let { segments += it }
                finish(joined())
            }
            override fun onError(error: Int) {
                if (segments.isNotEmpty()) return finish(joined())
                val missing = error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE || error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED
                finish(Result.Unavailable(describe(error), modelMissing = missing))
            }
        })
        cont.invokeOnCancellation { main.post { recognizer.destroy(); runCatching { pfd.close() } } }
        recognizer.startListening(intent(language).apply {
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pfd)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, WavRecorder.SAMPLE_RATE)
            // One session for the whole file, split into segments at pauses.
            putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
            putExtra(RecognizerIntent.EXTRA_ENABLE_FORMATTING, RecognizerIntent.FORMATTING_OPTIMIZE_QUALITY)
        })
    }

    /** Asks the system to download the offline speech model for `language`. */
    fun downloadModel(language: String) {
        val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        recognizer.triggerModelDownload(intent(language))
        Handler(Looper.getMainLooper()).postDelayed({ recognizer.destroy() }, 5_000)
    }

    private fun intent(language: String) = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
        putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
    }

    private fun describe(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE, SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ->
            "The offline speech model isn't downloaded yet (Settings → Download speech model)"
        SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech was recognised"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Speech recognition needs the microphone permission"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "The speech recognizer is busy; try Transcribe again"
        else -> "Speech recognition failed (code $error)"
    }
}
