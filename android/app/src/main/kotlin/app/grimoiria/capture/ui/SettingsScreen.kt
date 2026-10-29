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
import app.grimoiria.capture.CaptureViewModel

@Composable
fun SettingsScreen(vm: CaptureViewModel, modifier: Modifier = Modifier) {
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
