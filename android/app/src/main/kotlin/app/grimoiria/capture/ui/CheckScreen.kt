package app.grimoiria.capture.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
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
import androidx.compose.ui.unit.dp
import app.grimoiria.capture.CaptureViewModel
import app.grimoiria.capture.CheckState
import app.grimoiria.core.CastMethod
import app.grimoiria.core.Confidence
import app.grimoiria.core.DeckDefinition
import app.grimoiria.core.DivinationSystem
import app.grimoiria.core.DraftDivination
import app.grimoiria.core.Orientation
import app.grimoiria.core.Tokenizer
import app.grimoiria.core.YiJing

/**
 * Confirm and correct on the phone: the words, then the reading parsed from them with every
 * field editable. Anything the parser was unsure of is outlined. Saving hands it to the Mac's
 * Inbox, where it is confirmed once more before it is filed.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CheckScreen(vm: CaptureViewModel, state: CheckState, modifier: Modifier = Modifier) {
    val c = state.capture
    val draft = c.draft
    val issues = draft?.let(vm.editor::issues).orEmpty()

    Column(modifier.fillMaxWidth()) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Picker("Kind", c.captureKind.label, app.grimoiria.core.CaptureKind.entries.filter { it.pickable }.map { it.label to it }) { vm.changeKind(it) }
                Text(c.capturedAt.take(16).replace('T', ' '), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            var tagText by remember(c.id) { mutableStateOf(c.tags.joinToString(", ")) }
            OutlinedTextField(tagText, { tagText = it; vm.changeTags(it) }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("Tags") })

            if (state.transcribing) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    CircularProgressIndicator(Modifier.width(24.dp))
                    Text("Transcribing on the phone…")
                }
            } else {
                OutlinedTextField(
                    value = state.words, onValueChange = vm::setWords, modifier = Modifier.fillMaxWidth(), minLines = 3,
                    label = { Text(if (c.audioFile != null) "Transcript" else "Text") },
                )
                c.transcriptionNote?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = vm::readAgain) { Text("Read again") }
                    if (c.audioFile != null) OutlinedButton(onClick = vm::retranscribe) { Text("Transcribe again") }
                    if (state.modelMissing) OutlinedButton(onClick = vm::downloadSpeechModel) { Text("Download speech model") }
                }
            }

            if (draft != null) {
                if (draft.unparsed.isNotEmpty()) {
                    Text("Not placed", style = MaterialTheme.typography.labelLarge)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        draft.unparsed.forEach { AssistChip(onClick = {}, label = { Text(it) }) }
                    }
                }
                issues.forEach { Notice(it) }
                OutlinedTextField(
                    value = draft.question.value.orEmpty(), onValueChange = { q -> vm.edit { vm.editor.setQuestion(it, q) } },
                    modifier = Modifier.fillMaxWidth(), label = { Text("Question") },
                )
                draft.divinations.forEachIndexed { i, d ->
                    when (d.system) {
                        DivinationSystem.YIJING -> YiJingCard(vm, i, d)
                        else -> CardsCard(vm, i, d)
                    }
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { vm.edit { vm.editor.addCards(it, null) } }) { Text("Add cards") }
                    OutlinedButton(onClick = { vm.edit { vm.editor.addYiJing(it) } }) { Text("Add Yi Jing") }
                }
            } else if (!state.transcribing) {
                TextButton(onClick = { vm.edit { it } }) { Text("This has a reading") }
            }
        }
        HorizontalDivider()
        Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.End)) {
            TextButton(onClick = vm::discard) { Text("Discard") }
            Button(onClick = vm::saveChecked, enabled = !state.transcribing) { Text("Save to Inbox") }
        }
    }
}

@Composable
private fun unsure(conf: Confidence) =
    if (conf < Confidence.HIGH) BorderStroke(2.dp, MaterialTheme.colorScheme.tertiary) else null

@Composable
private fun CardsCard(vm: CaptureViewModel, index: Int, d: DraftDivination) {
    val lib = vm.library
    val deck = lib.deck(d.deckId.value)
    val spread = lib.spread(d.spreadId.value) ?: lib.freeform
    var picking by remember { mutableStateOf<Int?>(null) }

    OutlinedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Cards", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                IconButton(onClick = { vm.edit { vm.editor.removeDivination(it, index) } }) {
                    Icon(Icons.Filled.Delete, contentDescription = "Remove these cards")
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Picker("Deck", deck?.name ?: "Pick a deck", lib.decks.map { it.name to it.id }, unsure(d.deckId.confidence)) { id ->
                    vm.edit { vm.editor.setDeck(it, index, id) }
                }
                Picker("Spread", spread.name, lib.spreads.filter { s -> deck == null || s.appliesTo(deck.id) }.map { it.name to it.id },
                    unsure(d.spreadId.confidence)) { id -> vm.edit { vm.editor.setSpread(it, index, id) } }
            }
            d.draws.forEachIndexed { j, draw ->
                val card = deck?.card(draw.cardId.value ?: "")
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(spread.label(draw.positionKey), Modifier.width(72.dp), style = MaterialTheme.typography.labelMedium)
                    OutlinedCard(
                        Modifier.weight(1f).clickable(enabled = deck?.isPlaceholder == false) { picking = j },
                        border = unsure(draw.cardId.confidence) ?: BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
                    ) {
                        Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                            Text(card?.name ?: "Pick a card", color = if (card == null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface)
                            draw.cardId.heard?.let {
                                Text("heard “$it”", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    if (deck?.reversalsAllowed != false) {
                        FilterChip(
                            selected = draw.orientation.value == Orientation.REVERSED,
                            onClick = {
                                val o = if (draw.orientation.value == Orientation.REVERSED) Orientation.UPRIGHT else Orientation.REVERSED
                                vm.edit { vm.editor.setOrientation(it, index, j, o) }
                            },
                            label = { Text("Rev") },
                            border = unsure(draw.orientation.confidence),
                        )
                    }
                    IconButton(onClick = { vm.edit { vm.editor.removeDraw(it, index, j) } }) {
                        Icon(Icons.Filled.Close, contentDescription = "Remove card")
                    }
                }
            }
            if (deck?.isPlaceholder == false) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { vm.edit { vm.editor.addDraw(it, index) } }) { Text("Add card") }
                    // Shuffles the deck on the phone and fills the empty positions.
                    TextButton(onClick = { vm.drawOnPhone(index) }) { Text("Draw on phone") }
                }
            }
        }
    }
    val pick = picking
    if (pick != null && deck != null) {
        CardPicker(deck, onDismiss = { picking = null }) { cardId ->
            vm.edit { vm.editor.setCard(it, index, pick, cardId) }
            picking = null
        }
    }
}

@Composable
private fun CardPicker(deck: DeckDefinition, onDismiss: () -> Unit, onPick: (String) -> Unit) {
    var query by remember { mutableStateOf("") }
    val key = Tokenizer.key(query)
    val cards = deck.cards.filter { c -> key.isEmpty() || (listOf(c.name) + c.aliases).any { Tokenizer.key(it).contains(key) } }
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
        title = { Text(deck.name) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(query, { query = it }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("tower, 3 cups, page wands…") })
                LazyColumn(Modifier.heightIn(max = 360.dp)) {
                    items(cards, key = { it.id }) { card ->
                        Text(card.name, Modifier.fillMaxWidth().clickable { onPick(card.id) }.padding(vertical = 10.dp))
                    }
                }
            }
        },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun YiJingCard(vm: CaptureViewModel, index: Int, d: DraftDivination) {
    val def = vm.library.yijing
    val cast = d.cast
    val lines = cast?.lines?.value.orEmpty()
    OutlinedCard(Modifier.fillMaxWidth(), border = unsure(cast?.lines?.confidence ?: Confidence.MISSING)
        ?: BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Yi Jing", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                IconButton(onClick = { vm.edit { vm.editor.removeDivination(it, index) } }) {
                    Icon(Icons.Filled.Delete, contentDescription = "Remove Yi Jing")
                }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (m in listOf(CastMethod.COINS, CastMethod.YARROW)) {
                    FilterChip(selected = cast?.method == m, onClick = { vm.edit { vm.editor.setMethod(it, index, m) } },
                        label = { Text(m.name.lowercase()) })
                }
            }
            TextButton(onClick = { vm.castOnPhone(index) }) { Text(if (lines.isEmpty()) "Cast on phone" else "Cast again on phone") }
            // Drawn top line first, as on paper; values are entered bottom to top.
            for (line in 5 downTo 0) {
                val v = lines.getOrNull(line)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("${line + 1}", Modifier.width(16.dp), style = MaterialTheme.typography.labelMedium)
                    Text(glyph(v), Modifier.width(96.dp), fontFamily = FontFamily.Monospace)
                    for (value in 6..9) {
                        FilterChip(selected = v == value, onClick = { vm.edit { vm.editor.setLine(it, index, line, value) } },
                            label = { Text("$value") })
                    }
                }
            }
            val primary = YiJing.primary(lines, def)
            if (primary != null) {
                Text("${primary.number}. ${primary.name} (${primary.pinyin})", style = MaterialTheme.typography.bodyLarge)
                val changing = YiJing.changingLines(lines)
                YiJing.resulting(lines, def)?.let {
                    Text("Changing ${changing.joinToString(", ")} → ${it.number}. ${it.name} (${it.pinyin})", style = MaterialTheme.typography.bodyMedium)
                } ?: Text("No changing lines", style = MaterialTheme.typography.bodySmall)
            }
            cast?.lines?.heard?.takeIf { it.isNotEmpty() }?.let {
                Text("heard “$it”", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

private fun glyph(v: Int?): String = when (v) {
    9 -> "━━━━━ ○"
    7 -> "━━━━━"
    8 -> "━━  ━━"
    6 -> "━━  ━━ ×"
    else -> "·  ·  ·"
}

@Composable
private fun <T> Picker(label: String, current: String, options: List<Pair<String, T>>, border: BorderStroke? = null, onPick: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(onClick = { open = true }, border = border ?: BorderStroke(1.dp, MaterialTheme.colorScheme.outline)) {
            Column {
                Text(label, style = MaterialTheme.typography.labelSmall)
                Text(current)
            }
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for ((name, value) in options) {
                DropdownMenuItem(text = { Text(name) }, onClick = { open = false; onPick(value) })
            }
        }
    }
}
