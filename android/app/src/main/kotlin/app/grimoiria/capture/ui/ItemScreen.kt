package app.grimoiria.capture.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import app.grimoiria.capture.CaptureViewModel
import app.grimoiria.capture.LibraryViewModel
import app.grimoiria.capture.Screen
import app.grimoiria.core.DivinationSystem
import app.grimoiria.core.Fulfilled
import app.grimoiria.core.LibEntry
import app.grimoiria.core.LibInquiry
import app.grimoiria.core.LibraryItem
import app.grimoiria.core.Orientation
import app.grimoiria.core.YiJing
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive

/** One reading or entry from the library, read-only, with Add Outcome for readings. */
@Composable
fun ItemScreen(vm: CaptureViewModel, lib: LibraryViewModel, id: String, modifier: Modifier = Modifier) {
    val item = lib.item(id)
    Column(modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        when (item) {
            null -> Text("This record is no longer in the library.")
            is LibraryItem.Reading -> ReadingView(vm, lib, item.inquiry)
            is LibraryItem.Record -> EntryView(vm, lib, item.entry)
        }
    }
}

@Composable
fun SectionTitle(text: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(text.uppercase(), style = MaterialTheme.typography.titleSmall)
        HorizontalDivider(color = LocalCodex.current.rule)
    }
}

@Composable
private fun Meta(text: String) =
    Text(text, style = MaterialTheme.typography.labelMedium, color = LocalCodex.current.rubricText)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Tags(vm: CaptureViewModel, lib: LibraryViewModel, tags: List<String>) {
    if (tags.isEmpty()) return
    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        tags.distinct().forEach { t -> AssistChip(onClick = { lib.showTag(t); vm.go(Screen.Library) }, label = { Text(t) }) }
    }
}

private fun timingLine(timing: kotlinx.serialization.json.JsonObject?): String? {
    timing ?: return null
    fun s(k: String) = (timing[k] as? JsonPrimitive)?.content
    val parts = listOfNotNull(
        s("moonPhase")?.replace('-', ' ')?.let { "Moon $it" + (s("moonSign")?.let { sign -> " in ${sign.replaceFirstChar(Char::uppercase)}" } ?: "") },
        s("planetaryDay")?.let { "${it.replaceFirstChar(Char::uppercase)} day" },
        s("planetaryHour")?.let { "${it.replaceFirstChar(Char::uppercase)} hour" },
    )
    return parts.joinToString(" · ").ifBlank { null }
}

@Composable
private fun ReadingView(vm: CaptureViewModel, lib: LibraryViewModel, inq: LibInquiry) {
    val defs = lib.definitions
    var addingOutcome by remember { mutableStateOf(false) }
    Meta("READING · ${inq.askedAt.dateTime.toLocalDateTime().toString().take(16).replace('T', ' ')} · ${inq.status}")
    Text(inq.question, style = MaterialTheme.typography.headlineSmall)
    timingLine(inq.timing)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    if (inq.context.isNotBlank()) Text(inq.context, style = MaterialTheme.typography.bodyMedium)
    Tags(vm, lib, inq.tags)

    for (d in inq.divinations.sortedBy { it.order }) {
        when (d.system) {
            DivinationSystem.YIJING -> {
                SectionTitle("Yi Jing" + (d.cast?.method?.let { " · $it" } ?: ""))
                val lines = d.cast?.lines.orEmpty()
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column { for (i in 5 downTo 0) Text(lineGlyph(lines.getOrNull(i)), fontFamily = FontFamily.Monospace) }
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        YiJing.primary(lines, defs.yijing)?.let { h ->
                            Text("${h.number}. ${h.name} (${h.pinyin})", Modifier.clickable { vm.go(Screen.Hexagram(h.number)) },
                                style = MaterialTheme.typography.bodyLarge)
                        }
                        val changing = YiJing.changingLines(lines)
                        if (changing.isNotEmpty()) Text("Changing ${changing.joinToString(", ")}", style = MaterialTheme.typography.bodySmall)
                        YiJing.resulting(lines, defs.yijing)?.let { h ->
                            Text("→ ${h.number}. ${h.name} (${h.pinyin})", Modifier.clickable { vm.go(Screen.Hexagram(h.number)) },
                                style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
            }
            else -> {
                val deck = defs.deck(d.deckId)
                val spread = defs.spread(d.spreadId) ?: defs.freeform
                SectionTitle(listOfNotNull(deck?.name ?: d.deckId, spread.name.takeIf { spread.id != "freeform" }).joinToString(" · "))
                for (w in d.draws) {
                    val card = deck?.card(w.cardId)
                    Row(Modifier.fillMaxWidth().clickable { d.deckId?.let { vm.go(Screen.Card(it, w.cardId)) } }.padding(vertical = 4.dp),
                        verticalAlignment = Alignment.Top) {
                        Text(spread.label(w.positionKey), Modifier.width(96.dp), style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Column(Modifier.weight(1f)) {
                            Text((card?.name ?: w.cardId) + if (w.orientation == Orientation.REVERSED) ", reversed" else "",
                                style = MaterialTheme.typography.bodyLarge)
                            card?.significations?.values?.firstOrNull()?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                            }
                            w.notes?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                        }
                    }
                }
            }
        }
        d.notes?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
    }

    inq.synthesis?.let { s ->
        SectionTitle("Synthesis" + (s.confidence?.let { " · confidence $it/5" } ?: ""))
        Text(s.body, style = MaterialTheme.typography.bodyMedium)
    }

    SectionTitle("Outcomes")
    if (inq.outcomes.isEmpty()) Text("None yet.", style = MaterialTheme.typography.bodyMedium, fontStyle = FontStyle.Italic)
    for (o in inq.outcomes) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Meta("${o.recordedAt.day} · ${o.fulfilled.wire}")
            Text(o.body, style = MaterialTheme.typography.bodyMedium)
        }
    }
    lib.checkInState.answered[inq.id]?.let {
        Text("Outcome sent from the phone on $it; it shows here once confirmed on the Mac.", style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    Button(onClick = { addingOutcome = true }) { Text("Add outcome") }

    if (addingOutcome) {
        OutcomeDialog(inq.question, onDismiss = { addingOutcome = false }) { text, fulfilled ->
            vm.sendOutcome(inq.id, text, fulfilled)
            lib.reloadCheckIns()
            addingOutcome = false
        }
    }
}

/** Typed or dictated (the keyboard's microphone) outcome for a reading. Goes to the Mac's Inbox. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun OutcomeDialog(question: String, onDismiss: () -> Unit, onSend: (String, Fulfilled) -> Unit) {
    var text by remember { mutableStateOf("") }
    var fulfilled by remember { mutableStateOf(Fulfilled.UNCLEAR) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Outcome") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(question, style = MaterialTheme.typography.bodyMedium, fontStyle = FontStyle.Italic)
                OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth(), minLines = 3, placeholder = { Text("What actually happened?") })
                Text("Did it come true?", style = MaterialTheme.typography.labelLarge)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (f in Fulfilled.entries) FilterChip(selected = fulfilled == f, onClick = { fulfilled = f }, label = { Text(f.wire) })
                }
            }
        },
        confirmButton = { TextButton(onClick = { onSend(text, fulfilled) }, enabled = text.isNotBlank()) { Text("Send to Inbox") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun EntryView(vm: CaptureViewModel, lib: LibraryViewModel, e: LibEntry) {
    Meta("${e.type.uppercase()} · ${e.occurredAt.dateTime.toLocalDateTime().toString().take(16).replace('T', ' ')}")
    Text(e.displayTitle, style = MaterialTheme.typography.headlineSmall)
    timingLine(e.timing)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    Tags(vm, lib, e.tags)
    if (e.body.isNotBlank()) Text(e.body, style = MaterialTheme.typography.bodyMedium)

    // Type fields (intention, technique, being…), as plain label: value lines.
    val fields = e.fields.mapNotNull { (k, v) ->
        val value = when (v) {
            is JsonPrimitive -> v.content
            is JsonArray -> v.joinToString(", ") { (it as? JsonPrimitive)?.content ?: it.toString() }
            else -> null
        }
        value?.takeIf { it.isNotBlank() }?.let { k to it }
    }
    if (fields.isNotEmpty()) {
        SectionTitle("Details")
        for ((k, v) in fields) {
            Row {
                Text(fieldLabel(k), Modifier.width(120.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(v, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }

    e.session?.let { s ->
        SectionTitle("Session" + (s.durationSeconds?.let { " · ${it / 60} min" } ?: ""))
        fun rating(label: String, c: app.grimoiria.core.StateCheck?) = c?.takeIf { !it.isEmpty }?.let {
            "$label: energy ${it.energy ?: "–"}, calm ${it.calm ?: "–"}, focus ${it.focus ?: "–"}"
        }
        listOfNotNull(rating("Before", s.before), rating("After", s.after)).forEach { Text(it, style = MaterialTheme.typography.bodySmall) }
        for (o in s.observations) {
            Row(Modifier.padding(vertical = 2.dp)) {
                Text(clock(o.offset), Modifier.width(56.dp), style = MaterialTheme.typography.labelMedium, fontFamily = FontFamily.Monospace)
                Column(Modifier.weight(1f)) {
                    Text("${o.kind}${o.phase?.let { " · $it" } ?: ""}", style = MaterialTheme.typography.labelSmall, color = LocalCodex.current.rubricText)
                    Text(o.text.ifBlank { "(marker)" }, style = MaterialTheme.typography.bodyMedium)
                    if (o.tags.isNotEmpty()) Text(o.tags.joinToString("  "), style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        s.outcome?.let { Text("Outcome: $it", style = MaterialTheme.typography.bodyMedium, fontStyle = FontStyle.Italic) }
    }
    e.extraNotes?.takeIf { it.isNotBlank() }?.let { SectionTitle("Notes"); Text(it, style = MaterialTheme.typography.bodyMedium) }
    if (e.attachments.isNotEmpty()) {
        Text("${e.attachments.size} attachment${if (e.attachments.size == 1) "" else "s"} on the Mac (audio and photos stay there).",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    e.inquiryId?.let { id ->
        if (lib.item(id) != null) OutlinedButton(onClick = { vm.go(Screen.Item(id)) }) { Text("Open the reading") }
    }
}

fun clock(seconds: Double): String {
    val s = seconds.toLong()
    return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
}

private fun fieldLabel(k: String) = k.replace(Regex("([A-Z])"), " $1").lowercase().replaceFirstChar { it.uppercase() }

fun lineGlyph(v: Int?): String = when (v) {
    9 -> "━━━━━ ○"
    7 -> "━━━━━  "
    8 -> "━━  ━━  "
    6 -> "━━  ━━ ×"
    else -> "·  ·  ·  "
}
