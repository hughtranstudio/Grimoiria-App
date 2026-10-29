package app.grimoiria.capture.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Switch
import androidx.compose.ui.Alignment
import app.grimoiria.capture.CaptureViewModel
import app.grimoiria.capture.LibraryViewModel
import app.grimoiria.capture.grimoire

@Composable
fun SettingsScreen(vm: CaptureViewModel, lib: LibraryViewModel, onCalendarToggle: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val pickFolder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        uri?.let(vm::setInboxFolder)
    }
    var device by remember { mutableStateOf(vm.deviceName) }

    Column(
        modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Sync folder", style = MaterialTheme.typography.titleMedium)
        Text(
            "Pick the GrimoireInbox folder that Syncthing shares with the Mac. Captures go into its incoming/ folder; " +
                "the Mac app watches the same folder and puts each one in its Inbox for you to confirm.",
            style = MaterialTheme.typography.bodyMedium,
        )
        Text(vm.inboxLabel ?: "Not chosen", style = MaterialTheme.typography.bodyLarge)
        OutlinedButton(onClick = { pickFolder.launch(null) }) { Text(if (vm.inboxLabel == null) "Choose folder" else "Change folder") }

        HorizontalDivider()
        Text("Library from the Mac", style = MaterialTheme.typography.titleMedium)
        Text(
            "The Mac writes a read-only copy of everything filed into library/ in the same folder. The phone keeps its own copy, " +
                "so the library opens even when the folder is not there.",
            style = MaterialTheme.typography.bodyMedium,
        )
        val m = lib.library.manifest
        Text(
            if (m == null) "Not synced yet" else "${m.entries} entries, ${m.inquiries} readings, ${m.reminders} check-ins · written ${m.exportedAt.take(16).replace('T', ' ')}",
            style = MaterialTheme.typography.bodyLarge,
        )
        lib.status?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        if (lib.library.skipped > 0) {
            Text("${lib.library.skipped} records were written by a newer Mac app and are not shown; update this app.",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
        OutlinedButton(onClick = lib::refresh, enabled = !lib.refreshing) { Text("Look for a new library") }

        HorizontalDivider()
        Text("Check-ins", style = MaterialTheme.typography.titleMedium)
        val settings = androidx.compose.ui.platform.LocalContext.current.grimoire.settings
        var notify by remember { mutableStateOf(settings.notifyCheckIns) }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Notify me each morning when an outcome is due", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            Switch(checked = notify, onCheckedChange = { notify = it; settings.notifyCheckIns = it })
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Put check-ins in a Grimoire calendar on this phone", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            Switch(checked = lib.calendarOn, onCheckedChange = onCalendarToggle)
        }
        Text("The calendar is a local one: Google Calendar on the phone shows it, but it never syncs to your Google account.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

        HorizontalDivider()
        Text("This phone", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(device, { device = it; vm.setDevice(it) }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            label = { Text("Device name sent to the Mac") })

        HorizontalDivider()
        Text("Speech", style = MaterialTheme.typography.titleMedium)
        Text(
            "Transcription runs on the phone with Android's offline speech model; nothing is sent to a server. " +
                "If it can't run, the audio still goes to the Mac and Whisper transcribes it there.",
            style = MaterialTheme.typography.bodyMedium,
        )
        OutlinedButton(onClick = vm::downloadSpeechModel) { Text("Download speech model") }
    }
}
