package app.grimoiria.capture.audio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import app.grimoiria.capture.MainActivity
import app.grimoiria.capture.R

/** Keeps the microphone open while the screen is locked. Recording itself lives in [Recorder]. */
class RecordingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Recorder.stop(this)
            return START_NOT_STICKY
        }
        val session = intent?.getBooleanExtra(EXTRA_SESSION, false) == true
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Recording", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, RecordingService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_capture)
            .setContentTitle(if (session) "Recording a session" else "Recording a capture")
            .setContentText(if (session) "Tap to open and mark what happens" else "Tap to open, or stop here")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
        startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        return START_NOT_STICKY
    }

    companion object {
        const val ACTION_STOP = "app.grimoiria.capture.STOP_RECORDING"
        const val EXTRA_SESSION = "session"
        private const val CHANNEL = "recording"
        private const val NOTIFICATION_ID = 1
    }
}
