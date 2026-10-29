package app.grimoiria.capture.checkins

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.Manifest
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.grimoiria.capture.MainActivity
import app.grimoiria.capture.R
import app.grimoiria.capture.calendar.PhoneCalendar
import app.grimoiria.capture.grimoire
import app.grimoiria.core.CheckIns
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.concurrent.TimeUnit

/**
 * Once a day (around 9 in the morning): picks up a new library from the sync folder, notifies
 * check-ins that came due, and refreshes the phone calendar. Each check-in notifies once.
 */
class CheckInWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val app = applicationContext.grimoire
        app.refreshLibrary()
        val library = app.records.value
        val settings = app.settings
        val due = CheckIns.due(library, settings.checkIns, LocalDate.now().toString())
        if (settings.notifyCheckIns) {
            val fresh = due.filter { it.reminder.id + "@" + it.reminder.dueOn !in settings.notified }
            if (fresh.isNotEmpty()) notify(applicationContext, due.size, fresh.first().title)
            // Keyed by due day too, so a ladder's next step notifies again.
            settings.notified = due.map { it.reminder.id + "@" + it.reminder.dueOn }.toSet()
        }
        if (settings.calendarSync && hasCalendarPermission(applicationContext)) {
            runCatching { PhoneCalendar(applicationContext).sync(library, settings) }
        }
        return Result.success()
    }

    companion object {
        private const val WORK = "check-ins"
        private const val CHANNEL = "check-ins"
        private const val NOTIFICATION_ID = 7

        fun schedule(context: Context) {
            val now = LocalDateTime.now()
            var next = now.toLocalDate().atTime(9, 0)
            if (!next.isAfter(now)) next = next.plusDays(1)
            val request = PeriodicWorkRequestBuilder<CheckInWorker>(1, TimeUnit.DAYS)
                .setInitialDelay(Duration.between(now, next).toMinutes(), TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        fun hasCalendarPermission(context: Context) =
            context.checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
                context.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED

        fun notify(context: Context, count: Int, first: String) {
            if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Outcome check-ins", NotificationManager.IMPORTANCE_DEFAULT))
            val open = PendingIntent.getActivity(context, 2, Intent(context, MainActivity::class.java)
                .setAction(MainActivity.ACTION_TODAY).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE)
            val n = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_capture)
                .setContentTitle(if (count == 1) "Needs outcome" else "$count readings need an outcome")
                .setContentText(first)
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
            nm.notify(NOTIFICATION_ID, n)
        }
    }
}
