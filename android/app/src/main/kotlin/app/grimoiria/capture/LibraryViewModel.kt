package app.grimoiria.capture

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.grimoiria.capture.calendar.PhoneCalendar
import app.grimoiria.core.CheckIn
import app.grimoiria.core.CheckIns
import app.grimoiria.core.Library
import app.grimoiria.core.LibraryItem
import app.grimoiria.core.LibraryQuery
import app.grimoiria.core.LibrarySearch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate

/** The Mac's records on the phone: search, the open record, and the check-ins due. */
class LibraryViewModel(app: Application) : AndroidViewModel(app) {
    private val ctx = app.grimoire
    val definitions get() = ctx.library

    var library by mutableStateOf(ctx.records.value)
        private set
    var search by mutableStateOf(LibrarySearch(library, ctx.library))
        private set
    var query by mutableStateOf(LibraryQuery())
        private set
    var results by mutableStateOf<List<LibraryItem>>(search.all)
        private set
    var refreshing by mutableStateOf(false)
        private set
    var status by mutableStateOf<String?>(null)
        private set
    var checkInState by mutableStateOf(ctx.settings.checkIns)
        private set

    val today: String get() = LocalDate.now().toString()
    val due: List<CheckIn> get() = CheckIns.due(library, checkInState, today)
    val upcoming: List<CheckIn> get() = CheckIns.upcoming(library, checkInState, today)

    init {
        viewModelScope.launch { ctx.records.collect { setLibrary(it) } }
        refresh()
    }

    private fun setLibrary(lib: Library) {
        library = lib
        search = LibrarySearch(lib, ctx.library)
        checkInState = ctx.settings.checkIns
        run()
    }

    /** Looks for a newer library in the sync folder. Runs on start, on resume and on pull. */
    fun refresh() {
        if (refreshing) return
        refreshing = true
        viewModelScope.launch {
            val changed = withContext(Dispatchers.IO) { ctx.refreshLibrary() }
            status = ctx.libraryStatus
            refreshing = false
            checkInState = ctx.settings.checkIns
            if (changed && ctx.settings.calendarSync) {
                withContext(Dispatchers.IO) { runCatching { PhoneCalendar(getApplication<Application>()).sync(ctx.records.value, ctx.settings) } }
            }
        }
    }

    fun setText(text: String) { query = query.copy(text = text); run() }
    fun setGroup(group: String?) { query = query.copy(group = group); run() }
    fun showCard(deckId: String, cardId: String) { query = LibraryQuery(card = "$deckId/$cardId"); run() }
    fun showHexagram(n: Int) { query = LibraryQuery(hexagram = n); run() }
    fun showTag(tag: String) { query = LibraryQuery(text = "#$tag"); run() }
    fun clear() { query = LibraryQuery(); run() }

    private fun run() {
        results = search.search(query)
    }

    fun item(id: String): LibraryItem? = search.all.firstOrNull { it.id == id }

    /** Puts a check-in off for `days`; it comes back then. */
    fun later(c: CheckIn, days: Long = 3) {
        val st = ctx.settings.checkIns
        ctx.settings.checkIns = st.copy(snoozed = st.snoozed + (c.reminder.id to LocalDate.now().plusDays(days).toString()))
        checkInState = ctx.settings.checkIns
    }

    var calendarOn by mutableStateOf(ctx.settings.calendarSync)
        private set

    /** Fills the phone-only Grimoire calendar with check-ins (after permission was granted). */
    fun syncCalendar() {
        calendarOn = ctx.settings.calendarSync
        viewModelScope.launch {
            val n = withContext(Dispatchers.IO) { runCatching { PhoneCalendar(getApplication<Application>()).sync(ctx.records.value, ctx.settings) } }
            status = n.fold({ "$it check-ins in the Grimoire calendar" }, { "Calendar: ${it.message}" })
        }
    }

    fun removeCalendar() {
        calendarOn = false
        viewModelScope.launch(Dispatchers.IO) { runCatching { PhoneCalendar(getApplication<Application>()).remove() } }
    }

    /** Called after an outcome is sent, so Today drops the check-in it answered. */
    fun reloadCheckIns() {
        checkInState = ctx.settings.checkIns
    }
}
