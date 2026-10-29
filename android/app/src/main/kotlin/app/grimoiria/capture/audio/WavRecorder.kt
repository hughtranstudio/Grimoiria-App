package app.grimoiria.capture.audio

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.io.File
import java.io.RandomAccessFile
import kotlin.math.sqrt

/**
 * Records 16 kHz mono 16-bit PCM to `pcm`. The raw PCM feeds on-device speech recognition;
 * [writeWav] wraps it as the WAV file that goes to the Mac (Whisper's native format).
 */
class WavRecorder(private val pcm: File, private val onLevel: (Float) -> Unit) {
    private var record: AudioRecord? = null
    private var worker: Thread? = null
    @Volatile private var running = false

    @SuppressLint("MissingPermission") // checked by the caller before recording starts
    fun start() {
        val min = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val r = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT, maxOf(min, SAMPLE_RATE))
        check(r.state == AudioRecord.STATE_INITIALIZED) { "Microphone could not be opened" }
        record = r
        running = true
        r.startRecording()
        worker = Thread({
            val buf = ShortArray(SAMPLE_RATE / 10)
            val bytes = ByteArray(buf.size * 2)
            pcm.outputStream().buffered().use { out ->
                while (running) {
                    val n = r.read(buf, 0, buf.size)
                    if (n <= 0) continue
                    var sum = 0.0
                    for (i in 0 until n) {
                        val s = buf[i].toInt()
                        bytes[2 * i] = (s and 0xff).toByte()
                        bytes[2 * i + 1] = (s shr 8 and 0xff).toByte()
                        sum += s * s
                    }
                    out.write(bytes, 0, n * 2)
                    onLevel((sqrt(sum / n) / Short.MAX_VALUE).toFloat().coerceIn(0f, 1f))
                }
            }
        }, "WavRecorder").apply { start() }
    }

    fun stop() {
        running = false
        worker?.join(2000)
        record?.run { runCatching { stop() }; release() }
        record = null
        worker = null
    }

    companion object {
        const val SAMPLE_RATE = 16_000

        fun writeWav(pcm: File, wav: File) {
            val dataLen = pcm.length()
            RandomAccessFile(wav, "rw").use { f ->
                f.setLength(0)
                fun int(v: Int) = f.write(byteArrayOf(v.toByte(), (v shr 8).toByte(), (v shr 16).toByte(), (v shr 24).toByte()))
                fun short(v: Int) = f.write(byteArrayOf(v.toByte(), (v shr 8).toByte()))
                f.writeBytes("RIFF"); int((36 + dataLen).toInt()); f.writeBytes("WAVE")
                f.writeBytes("fmt "); int(16); short(1); short(1); int(SAMPLE_RATE); int(SAMPLE_RATE * 2); short(2); short(16)
                f.writeBytes("data"); int(dataLen.toInt())
                pcm.inputStream().use { input ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        f.write(buf, 0, n)
                    }
                }
            }
        }

        fun durationSeconds(pcm: File): Double = pcm.length() / (SAMPLE_RATE * 2.0)
    }
}
