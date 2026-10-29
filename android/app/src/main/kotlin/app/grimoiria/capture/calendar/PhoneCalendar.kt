package app.grimoiria.capture.calendar

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.CalendarContract
import app.grimoiria.capture.Settings
import app.grimoiria.core.CheckIns
import app.grimoiria.core.Library
import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Check-ins as all-day events in a "Grimoire" calendar that lives only on this phone (a local
 * account, so Google never sees it). Google Calendar on the phone shows it beside your others.
 * The calendar is Grimoire's alone, so each sync simply rewrites its events.
 */
class PhoneCalendar(private val context: Context) {
    private val resolver get() = context.contentResolver

    private fun asApp(uri: Uri): Uri = uri.buildUpon()
        .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, ACCOUNT)
        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
        .build()

    private fun find(): Long? = resolver.query(
        CalendarContract.Calendars.CONTENT_URI, arrayOf(CalendarContract.Calendars._ID),
        "${CalendarContract.Calendars.ACCOUNT_NAME} = ? AND ${CalendarContract.Calendars.ACCOUNT_TYPE} = ?",
        arrayOf(ACCOUNT, CalendarContract.ACCOUNT_TYPE_LOCAL), null,
    )?.use { if (it.moveToFirst()) it.getLong(0) else null }

    private fun create(): Long? {
        val v = ContentValues().apply {
            put(CalendarContract.Calendars.ACCOUNT_NAME, ACCOUNT)
            put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(CalendarContract.Calendars.NAME, ACCOUNT)
            put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, ACCOUNT)
            put(CalendarContract.Calendars.CALENDAR_COLOR, 0xFFEB0303.toInt())
            put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
            put(CalendarContract.Calendars.OWNER_ACCOUNT, ACCOUNT)
            put(CalendarContract.Calendars.VISIBLE, 1)
            put(CalendarContract.Calendars.SYNC_EVENTS, 1)
        }
        return resolver.insert(asApp(CalendarContract.Calendars.CONTENT_URI), v)?.lastPathSegment?.toLongOrNull()
    }

    /** Rewrites the calendar's events from the open check-ins. Needs the calendar permissions. */
    fun sync(library: Library, settings: Settings): Int {
        val id = find() ?: create() ?: return 0
        resolver.delete(asApp(CalendarContract.Events.CONTENT_URI), "${CalendarContract.Events.CALENDAR_ID} = ?", arrayOf(id.toString()))
        val today = LocalDate.now().toString()
        val state = settings.checkIns
        val checkIns = CheckIns.due(library, state, today) + CheckIns.upcoming(library, state, today)
        for (c in checkIns) {
            // Overdue ones show today, so they stay in sight.
            val day = maxOf(c.reminder.dueOn, today)
            val start = LocalDate.parse(day).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
            val v = ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, id)
                put(CalendarContract.Events.TITLE, "Check-in: ${c.title}")
                put(CalendarContract.Events.DESCRIPTION, c.prompt)
                put(CalendarContract.Events.DTSTART, start)
                put(CalendarContract.Events.DTEND, start + 86_400_000L)
                put(CalendarContract.Events.ALL_DAY, 1)
                put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
            }
            resolver.insert(asApp(CalendarContract.Events.CONTENT_URI), v)
        }
        return checkIns.size
    }

    /** Removes the calendar and its events (Settings, when turned off). */
    fun remove() {
        val id = find() ?: return
        resolver.delete(asApp(CalendarContract.Calendars.CONTENT_URI), "${CalendarContract.Calendars._ID} = ?", arrayOf(id.toString()))
    }

    companion object {
        const val ACCOUNT = "Grimoire"
    }
}
