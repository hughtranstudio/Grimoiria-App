package app.grimoiria.capture.sync

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import app.grimoiria.core.InboxDestination
import java.io.File
import java.io.IOException

/**
 * The synced Inbox folder picked by the user through the system folder picker (Storage Access
 * Framework). With Syncthing it is a plain folder on the phone such as `GrimoireInbox/`;
 * Syncthing carries whatever lands in `incoming/` to the Mac.
 */
class SafDestination(private val context: Context, private val tree: Uri) : InboxDestination {

    private fun incoming(): DocumentFile {
        val root = DocumentFile.fromTreeUri(context, tree) ?: throw IOException("The Inbox folder is not available")
        if (!root.exists()) throw IOException("The Inbox folder no longer exists; choose it again in Settings")
        if (!root.canWrite()) throw IOException("No permission to write to the Inbox folder; choose it again in Settings")
        root.findFile(INCOMING)?.let { if (it.isDirectory) return it }
        return root.createDirectory(INCOMING) ?: throw IOException("Could not create incoming/ in the Inbox folder")
    }

    override fun write(name: String, source: File) {
        val dir = incoming()
        val partName = ".$name.part"
        dir.findFile(partName)?.delete()
        val part = dir.createFile(BINARY, partName) ?: throw IOException("Could not create $partName")
        copy(source, part)
        dir.findFile(name)?.delete()
        if (part.renameTo(name) && part.name == name) return
        // Some providers can't rename; fall back to writing the final name directly.
        part.delete()
        val direct = dir.createFile(BINARY, name) ?: throw IOException("Could not create $name")
        copy(source, direct)
    }

    private fun copy(source: File, target: DocumentFile) {
        val out = context.contentResolver.openOutputStream(target.uri, "wt") ?: throw IOException("Could not open ${target.name}")
        out.use { o -> source.inputStream().use { it.copyTo(o) } }
    }

    companion object {
        const val INCOMING = "incoming"
        private const val BINARY = "application/octet-stream"

        /** A readable label for a tree URI, e.g. `primary:GrimoireInbox` → `GrimoireInbox`. */
        fun label(uri: Uri): String {
            val last = uri.lastPathSegment ?: return uri.toString()
            return last.substringAfter(':').ifEmpty { last }
        }
    }
}
