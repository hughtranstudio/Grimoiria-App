package app.grimoiria.capture.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import app.grimoiria.capture.LibraryViewModel
import app.grimoiria.capture.SessionViewModel
import app.grimoiria.capture.audio.Recorder
import app.grimoiria.core.CaptureKind
import app.grimoiria.core.SessionVocab
import app.grimoiria.core.StateCheck
import kotlinx.coroutines.delay

/**
 * Ritual, meditation or vision, phone-sized: set up, then a big Mark button for "something
 * happened here" without looking, phase buttons, and typed observations; ratings after.
 */
@Composable
fun SessionScreen(s: SessionViewModel, lib: LibraryViewModel, onStart: () -> Unit, onSaved: () -> Unit, modifier: Modifier = Modifier) {
    val d = s.draft
    Column(modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        when {
            d == null -> Setup(s, onStart)
            !s.closing -> Running(s, lib)
            else -> Closing(s, onSaved)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Setup(s: SessionViewModel, onStart: () -> Unit) {
    Text("Record a session", style = MaterialTheme.typography.headlineSmall)
    Text("The microphone runs the whole time. Tap Mark when something happens; the Mac transcribes the audio with times and builds the timeline in its Inbox.",
        style = MaterialTheme.typography.bodyMedium)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (k in CaptureKind.entries.filter { it.isSessionType }) {
            FilterChip(selected = s.type == k, onClick = { s.type = k }, label = { Text(k.label) })
        }
    }
    OutlinedTextField(s.intention, { s.intention = it }, Modifier.fillMaxWidth(), label = { Text("Intention") })
    OutlinedTextField(s.technique, { s.technique = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("Technique") },
        placeholder = { Text("stillness, inner flame, pathworking…") })
    OutlinedTextField(s.tags, { s.tags = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("Tags (optional)") })
    SectionTitle("Going in")
    Ratings(s.before) { s.before = it }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("Record audio", Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Switch(checked = s.withAudio, onCheckedChange = { s.withAudio = it })
    }
    Button(onClick = onStart, modifier = Modifier.fillMaxWidth().height(56.dp)) { Text("Begin", style = MaterialTheme.typography.titleMedium) }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Running(s: SessionViewModel, lib: LibraryViewModel) {
    val d = s.draft ?: return
    val rec by Recorder.state.collectAsState()
    val recording = (rec as? Recorder.State.Recording)?.takeIf { it.session }
    var now by remember { mutableStateOf(s.offset()) }
    LaunchedEffect(d.id) { while (true) { now = s.offset(); delay(500) } }
    var observing by remember { mutableStateOf(false) }

    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("${CaptureKind.fromHint(d.type).label.uppercase()} · ${d.phase ?: "—"}", style = MaterialTheme.typography.labelMedium,
                color = LocalCodex.current.rubricText)
            Text(clock(now), style = MaterialTheme.typography.displaySmall, fontFamily = FontFamily.Monospace)
            Text(if (recording != null) "Recording" else if (d.audioFile != null) "Microphone stopped" else "No audio",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    // The big target: usable with eyes half closed.
    Button(
        onClick = s::mark,
        modifier = Modifier.fillMaxWidth().height(160.dp),
        colors = ButtonDefaults.buttonColors(containerColor = LocalCodex.current.rubric, contentColor = MaterialTheme.colorScheme.onError),
    ) { Text("Mark", style = MaterialTheme.typography.displaySmall) }
    Text("${d.markerCount} mark${if (d.markerCount == 1) "" else "s"} · ${d.observations.size} observation${if (d.observations.size == 1) "" else "s"}",
        style = MaterialTheme.typography.bodySmall)

    SectionTitle("Phase")
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (p in SessionVocab.livePhases) FilterChip(selected = d.phase == p, onClick = { s.phase(p) }, label = { Text(p) })
    }
    OutlinedButton(onClick = { observing = true }, modifier = Modifier.fillMaxWidth()) { Text("Write an observation") }

    if (d.marks.isNotEmpty()) {
        SectionTitle("So far")
        d.marks.forEachIndexed { i, m ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(clock(m.offsetS), Modifier.width(60.dp), fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.labelMedium)
                Text(when {
                    m.phase != null -> "→ ${m.phase}"
                    m.kind != null -> "${m.kind}: ${m.text.orEmpty()}" + (m.tags?.takeIf { it.isNotEmpty() }?.joinToString(" ", "  ") ?: "")
                    else -> "mark"
                }, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                if (m.phase == null) IconButton(onClick = { s.removeMark(i) }) { Icon(Icons.Filled.Close, "Remove") }
            }
        }
    }
    HorizontalDivider(color = LocalCodex.current.rule)
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        var confirmDiscard by remember { mutableStateOf(false) }
        TextButton(onClick = { confirmDiscard = true }) { Text("Discard") }
        Box(Modifier.weight(1f))
        Button(onClick = s::end) { Text("End session") }
        if (confirmDiscard) {
            AlertDialog(onDismissRequest = { confirmDiscard = false },
                title = { Text("Discard this session?") }, text = { Text("The recording and marks are deleted from the phone.") },
                confirmButton = { TextButton(onClick = { confirmDiscard = false; s.discard() }) { Text("Discard") } },
                dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text("Keep") } })
        }
    }

    if (observing) ObservationDialog(lib.library.allTags, onDismiss = { observing = false }) { kind, text, tags ->
        s.observe(kind, text, tags)
        observing = false
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ObservationDialog(knownTags: List<String>, onDismiss: () -> Unit, onAdd: (String, String, String) -> Unit) {
    var kind by remember { mutableStateOf("imagery") }
    var text by remember { mutableStateOf("") }
    var tags by remember { mutableStateOf("") }
    val fragment = tags.split(',', ' ').lastOrNull()?.trim()?.trim('#').orEmpty()
    val suggestions = if (fragment.length < 2) emptyList() else knownTags.filter { it.contains(fragment, ignoreCase = true) }.take(6)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Observation") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (k in SessionVocab.observationKinds) FilterChip(selected = kind == k, onClick = { kind = k }, label = { Text(k) })
                }
                OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth(), minLines = 2, placeholder = { Text("What was seen, heard or felt") })
                OutlinedTextField(tags, { tags = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("Tags") },
                    placeholder = { Text("Leave empty: the Mac suggests them") })
                if (suggestions.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (t in suggestions) FilterChip(selected = false, label = { Text(t) }, onClick = {
                        tags = (tags.split(',').dropLast(1).map { it.trim() }.filter { it.isNotEmpty() } + t).joinToString(", ") + ", "
                    })
                }
            }
        },
        confirmButton = { TextButton(onClick = { onAdd(kind, text, tags) }, enabled = text.isNotBlank()) { Text("Add") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun Closing(s: SessionViewModel, onSaved: () -> Unit) {
    val d = s.draft ?: return
    Text("Coming out", style = MaterialTheme.typography.headlineSmall)
    Text("${CaptureKind.fromHint(d.type).label} · ${clock(s.offset(d.endedAt?.let { java.time.OffsetDateTime.parse(it) } ?: java.time.OffsetDateTime.now()))} · " +
        "${d.marks.count { it.phase == null }} marks and observations", style = MaterialTheme.typography.bodyMedium)
    Ratings(d.after ?: StateCheck()) { s.setAfter(it) }
    var outcome by remember(d.id) { mutableStateOf(d.outcome.orEmpty()) }
    OutlinedTextField(outcome, { outcome = it; s.setOutcome(it) }, Modifier.fillMaxWidth(), minLines = 3, label = { Text("Outcome") },
        placeholder = { Text("How it ended, and anything else you remember") })
    Button(onClick = { s.saveToInbox(onSaved) }, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("Save to Inbox") }
    TextButton(onClick = s::discard) { Text("Discard") }
}

/** Energy, calm and focus, 1 to 5; tap again to clear. */
@Composable
private fun Ratings(value: StateCheck, onChange: (StateCheck) -> Unit) {
    @Composable
    fun row(label: String, current: Int?, set: (Int?) -> StateCheck) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(label, Modifier.width(64.dp), style = MaterialTheme.typography.labelLarge)
            for (n in 1..5) FilterChip(selected = current == n, onClick = { onChange(set(if (current == n) null else n)) }, label = { Text("$n") })
        }
    }
    row("Energy", value.energy) { value.copy(energy = it) }
    row("Calm", value.calm) { value.copy(calm = it) }
    row("Focus", value.focus) { value.copy(focus = it) }
}
