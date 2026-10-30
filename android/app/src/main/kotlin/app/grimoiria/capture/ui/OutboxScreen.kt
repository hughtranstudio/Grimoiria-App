package app.grimoiria.capture.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.grimoiria.capture.CaptureViewModel
import app.grimoiria.core.CaptureStore

/** Everything captured on this phone: still being checked, waiting to sync, or sent. */
@Composable
fun OutboxScreen(vm: CaptureViewModel, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                vm.inboxLabel?.let { "Sync folder: $it" } ?: "No sync folder chosen",
                Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium,
            )
            OutlinedButton(onClick = vm::deliver, enabled = !vm.syncing && vm.pendingCount > 0) { Text("Send now") }
        }
        if (vm.captures.isEmpty()) {
            Text("Nothing captured yet.", Modifier.padding(16.dp))
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            items(vm.captures, key = { it.capture.id + it.state }) { s ->
                val c = s.capture
                val words = (c.transcript ?: c.text).orEmpty().ifEmpty { if (c.audioFile != null) "Audio, transcribed on the Mac" else "" }
                ListItem(
                    overlineContent = { Text("${c.captureKind.label} · ${c.capturedAt.take(16).replace('T', ' ')}") },
                    headlineContent = { Text(words, maxLines = 2) },
                    supportingContent = {
                        Text(when (s.state) {
                            CaptureStore.State.DRAFT -> "Not saved yet"
                            CaptureStore.State.PENDING -> c.lastError?.let { "Waiting: $it" } ?: "Waiting to sync"
                            CaptureStore.State.SENT -> "In the sync folder"
                        }, color = if (s.state == CaptureStore.State.PENDING && c.lastError != null) MaterialTheme.colorScheme.error
                        else MaterialTheme.colorScheme.onSurfaceVariant)
                    },
                    trailingContent = {
                        when (s.state) {
                            CaptureStore.State.DRAFT -> TextButton(onClick = { vm.resume(c.id) }) { Text("Finish") }
                            CaptureStore.State.SENT -> IconButton(onClick = { vm.deleteSent(c.id) }) {
                                Icon(Icons.Filled.Delete, contentDescription = "Remove from this phone")
                            }
                            CaptureStore.State.PENDING -> Unit
                        }
                    },
                )
            }
        }
    }
}
