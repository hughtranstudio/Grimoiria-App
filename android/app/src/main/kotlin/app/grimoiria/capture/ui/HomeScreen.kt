package app.grimoiria.capture.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.grimoiria.capture.CaptureViewModel
import app.grimoiria.capture.Screen
import app.grimoiria.capture.audio.Recorder
import app.grimoiria.core.CaptureKind
import kotlinx.coroutines.delay

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun HomeScreen(vm: CaptureViewModel, onRecord: () -> Unit, modifier: Modifier = Modifier) {
    val rec by Recorder.state.collectAsState()
    val recording = (rec as? Recorder.State.Recording)?.takeIf { !it.session }

    Column(
        modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (vm.inboxLabel == null) {
            Notice("Choose the synced Inbox folder so captures can reach the Mac. They are kept on the phone until then.",
                action = "Choose" to { vm.go(Screen.Settings) })
        } else if (vm.pendingCount > 0) {
            Notice("${vm.pendingCount} waiting to go to ${vm.inboxLabel}", action = "Send now" to { vm.deliver() })
        }
        for (d in vm.drafts) {
            Notice("Unfinished ${CaptureKind.fromHint(d.capture.kind).label.lowercase()} from ${d.capture.capturedAt.take(16).replace('T', ' ')}",
                action = "Finish" to { vm.resume(d.capture.id) })
        }

        Text("What is this?", style = MaterialTheme.typography.titleMedium)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (k in CaptureKind.entries.filter { it.pickable }) {
                FilterChip(selected = vm.kind == k, onClick = { vm.selectKind(k) }, label = { Text(k.label) }, enabled = recording == null)
            }
        }
        OutlinedTextField(
            value = vm.tags, onValueChange = { vm.tags = it }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            label = { Text("Tags (optional)") }, placeholder = { Text("theme/threshold") },
        )

        Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(
                    onClick = { if (recording != null) vm.stopRecording() else onRecord() },
                    shape = CircleShape,
                    modifier = Modifier.size(140.dp),
                    colors = if (recording != null) ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                    else ButtonDefaults.buttonColors(),
                ) {
                    Text(if (recording != null) "Stop" else "Record", style = MaterialTheme.typography.titleLarge)
                }
                if (recording != null) {
                    Elapsed(recording.startedAt)
                    LinearProgressIndicator(progress = { recording.level * 4f }, modifier = Modifier.fillMaxWidth(0.6f))
                } else {
                    Text("Speak the question, deck, spread and cards, or Yi Jing lines bottom to top.",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        if (recording == null) {
            Text("No deck to hand?", style = MaterialTheme.typography.titleMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { vm.startPhoneReading(CaptureKind.DRAW) }) { Text("Draw cards") }
                OutlinedButton(onClick = { vm.startPhoneReading(CaptureKind.YIJING) }) { Text("Cast Yi Jing") }
            }

            Text("Or type", style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                value = vm.note, onValueChange = { vm.note = it }, modifier = Modifier.fillMaxWidth(), minLines = 3,
                placeholder = { Text("Deck RWS three card: 3 cups r, tower, page wands") },
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                OutlinedButton(onClick = vm::saveNote, enabled = vm.note.isNotBlank()) { Text("Save") }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun Elapsed(startedAt: Long) {
    val now = remember { mutableLongStateOf(android.os.SystemClock.elapsedRealtime()) }
    LaunchedEffect(startedAt) {
        while (true) { now.longValue = android.os.SystemClock.elapsedRealtime(); delay(250) }
    }
    val s = ((now.longValue - startedAt) / 1000).coerceAtLeast(0)
    Text("%d:%02d".format(s / 60, s % 60), style = MaterialTheme.typography.headlineSmall)
}

@Composable
fun Notice(text: String, action: Pair<String, () -> Unit>? = null) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)) {
        Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(text, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            action?.let { (label, onClick) -> TextButton(onClick = onClick) { Text(label) } }
        }
    }
}
