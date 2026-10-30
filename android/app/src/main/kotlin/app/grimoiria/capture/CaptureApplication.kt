package app.grimoiria.capture

import android.app.Application
import android.content.Context
import android.content.res.AssetManager
import android.net.Uri
import app.grimoiria.capture.sync.LibraryReader
import app.grimoiria.core.CaptureStore
import app.grimoiria.core.CheckIns
import app.grimoiria.core.DefinitionLibrary
import app.grimoiria.core.DefinitionSource
import app.grimoiria.core.Library
import app.grimoiria.core.PhoneCheckInState
import app.grimoiria.core.ReadingParser
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.Json
import java.io.File
import java.time.LocalDate

class CaptureApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        app.grimoiria.capture.checkins.CheckInWorker.schedule(this)
    }

    val library: DefinitionLibrary by lazy { DefinitionLibrary.load(AssetDefinitionSource(assets)) }
    val parser: ReadingParser by lazy { ReadingParser(library) }
    val store: CaptureStore by lazy { CaptureStore(File(filesDir, "captures")) }
    val settings: Settings by lazy { Settings(this) }
    val libraryReader: LibraryReader by lazy { LibraryReader(this, File(filesDir, "library")) }

    private val _records by lazy { MutableStateFlow(libraryReader.load()) }
    /** The Mac's filed records as last synced (empty before the first sync). */
    val records: StateFlow<Library> get() = _records
    /** Why the last refresh found no new library, when it didn't. */
    @Volatile var libraryStatus: String? = null
        private set

    /**
     * Picks up a new library from the sync folder if the Mac wrote one. Call off the main thread.
     * Returns true when the library changed.
     */
    fun refreshLibrary(): Boolean {
        val result = runCatching { libraryReader.refresh(settings.inboxFolder?.let(Uri::parse)) }
            .getOrElse { LibraryReader.Refresh.NotThere(it.message ?: "The library could not be read") }
        libraryStatus = (result as? LibraryReader.Refresh.NotThere)?.reason
        val changed = result == LibraryReader.Refresh.Updated
        if (changed) {
            val lib = libraryReader.load()
            _records.value = lib
            settings.checkIns = CheckIns.prune(settings.checkIns, lib, LocalDate.now().toString())
        }
        return changed
    }
}

val Context.grimoire: CaptureApplication get() = applicationContext as CaptureApplication

/** Decks, spreads and Yi Jing from `assets/Definitions/` (the Swift package's resource folder). */
class AssetDefinitionSource(private val assets: AssetManager) : DefinitionSource {
    override fun list(dir: String): List<String> = assets.list("Definitions/$dir")?.toList() ?: emptyList()
    override fun read(path: String): String = assets.open("Definitions/$path").bufferedReader().use { it.readText() }
}

class Settings(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    /** Tree URI of the synced GrimoireInbox folder (the one that holds `incoming/`). */
    var inboxFolder: String?
        get() = prefs.getString("inboxFolder", null)
        set(v) = prefs.edit().putString("inboxFolder", v).apply()

    /** Sent as the sidecar's `device`; the Mac shows it as the capture's source. */
    var deviceName: String
        get() = prefs.getString("deviceName", null) ?: "pixel"
        set(v) = prefs.edit().putString("deviceName", v.trim().ifEmpty { "pixel" }).apply()

    var lastKind: String
        get() = prefs.getString("lastKind", null) ?: "draw"
        set(v) = prefs.edit().putString("lastKind", v).apply()

    var speechLanguage: String
        get() = prefs.getString("speechLanguage", null) ?: "en-US"
        set(v) = prefs.edit().putString("speechLanguage", v).apply()

    /** What the phone has answered or put off since the library was last written. */
    var checkIns: PhoneCheckInState
        get() = prefs.getString("checkIns", null)?.let { runCatching { json.decodeFromString(PhoneCheckInState.serializer(), it) }.getOrNull() }
            ?: PhoneCheckInState()
        set(v) = prefs.edit().putString("checkIns", json.encodeToString(PhoneCheckInState.serializer(), v)).apply()

    /** A notification each morning when check-ins are due. */
    var notifyCheckIns: Boolean
        get() = prefs.getBoolean("notifyCheckIns", true)
        set(v) = prefs.edit().putBoolean("notifyCheckIns", v).apply()

    /** Check-ins copied into a calendar kept only on this phone. */
    var calendarSync: Boolean
        get() = prefs.getBoolean("calendarSync", false)
        set(v) = prefs.edit().putBoolean("calendarSync", v).apply()

    /** Reminder ids already notified, so each check-in buzzes once. */
    var notified: Set<String>
        get() = prefs.getStringSet("notified", emptySet()).orEmpty()
        set(v) = prefs.edit().putStringSet("notified", v).apply()

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
    }
}
