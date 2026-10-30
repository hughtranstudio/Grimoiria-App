package app.grimoiria.capture.sync

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import app.grimoiria.core.Library
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * The Mac's read-only `library/` in the synced folder (docs/phone-library.md). Each refresh copies
 * it into the app's own storage when its manifest changed, so the library still opens when the
 * folder is unavailable, and is read from that copy.
 */
class LibraryReader(private val context: Context, private val cache: File) {
    sealed interface Refresh {
        data object Unchanged : Refresh
        data object Updated : Refresh
        data class NotThere(val reason: String) : Refresh
    }

    private val jsonl get() = File(cache, "grimoire.jsonl")
    private val manifest get() = File(cache, "manifest.json")

    /** The last copy, or an empty library before the first sync. */
    fun load(): Library {
        if (!jsonl.exists()) return Library.EMPTY
        val m = manifest.takeIf { it.exists() }?.readText()?.let(Library::parseManifest)
        return Library.parse(jsonl.readText(), m)
    }

    /** Copies `library/` from the synced folder when the Mac has written a new one. */
    fun refresh(tree: Uri?): Refresh {
        if (tree == null) return Refresh.NotThere("No sync folder chosen")
        val root = DocumentFile.fromTreeUri(context, tree) ?: return Refresh.NotThere("The sync folder is not available")
        val dir = root.findFile(FOLDER)?.takeIf { it.isDirectory }
            ?: return Refresh.NotThere("No library yet. Turn on “Share a read-only library with the phone” in the Mac app’s Settings > Inbox.")
        val remoteManifest = dir.findFile("manifest.json") ?: return Refresh.NotThere("The library is still arriving")
        val remoteJsonl = dir.findFile("grimoire.jsonl") ?: return Refresh.NotThere("The library is still arriving")
        val text = read(remoteManifest.uri)
        val remote = Library.parseManifest(text) ?: return Refresh.NotThere("The library manifest could not be read")
        if (remote.libraryVersion > Library.SUPPORTED_VERSION) return Refresh.NotThere("The Mac's library is newer than this app; update the app")
        val local = manifest.takeIf { it.exists() }?.readText()?.let(Library::parseManifest)
        if (local?.checksum == remote.checksum && jsonl.exists()) return Refresh.Unchanged
        cache.mkdirs()
        val tmp = File(cache, "grimoire.jsonl.part")
        context.contentResolver.openInputStream(remoteJsonl.uri)?.use { input -> tmp.outputStream().use { input.copyTo(it) } }
            ?: return Refresh.NotThere("The library could not be opened")
        // Syncthing can deliver the manifest before the records it describes; wait for the pair to match.
        if (Library.checksum(tmp.readBytes()) != remote.checksum) {
            tmp.delete()
            return Refresh.NotThere("The library is still arriving")
        }
        Files.move(tmp.toPath(), jsonl.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        manifest.writeText(text)
        return Refresh.Updated
    }

    private fun read(uri: Uri): String = context.contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() }.orEmpty()

    companion object {
        const val FOLDER = "library"
    }
}
