package app.grimoiria.capture

import android.app.Application
import android.content.Context
import android.content.res.AssetManager
import app.grimoiria.core.CaptureStore
import app.grimoiria.core.DefinitionLibrary
import app.grimoiria.core.DefinitionSource
import app.grimoiria.core.ReadingParser
import java.io.File

class CaptureApplication : Application() {
    val library: DefinitionLibrary by lazy { DefinitionLibrary.load(AssetDefinitionSource(assets)) }
    val parser: ReadingParser by lazy { ReadingParser(library) }
    val store: CaptureStore by lazy { CaptureStore(File(filesDir, "captures")) }
    val settings: Settings by lazy { Settings(this) }
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
}
