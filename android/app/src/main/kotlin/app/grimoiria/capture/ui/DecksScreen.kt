package app.grimoiria.capture.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import app.grimoiria.capture.CaptureViewModel
import app.grimoiria.capture.LibraryViewModel
import app.grimoiria.capture.Screen
import app.grimoiria.core.LibraryQuery
import app.grimoiria.core.Tokenizer
import kotlinx.serialization.json.JsonPrimitive

/** The decks and Yi Jing the phone shares with the Mac (the same definition files). */
@Composable
fun DecksScreen(vm: CaptureViewModel, lib: LibraryViewModel, modifier: Modifier = Modifier) {
    val defs = lib.definitions
    LazyColumn(modifier.fillMaxSize()) {
        items(defs.decks.filter { !it.isPlaceholder }, key = { it.id }) { d ->
            Row(Modifier.fillMaxWidth().clickable { vm.go(Screen.Deck(d.id)) }.padding(16.dp)) {
                Column(Modifier.weight(1f)) {
                    Text(d.name, style = MaterialTheme.typography.titleMedium)
                    Text("${d.cards.size} cards" + if (d.cards.any { it.significations.isNotEmpty() }) " · with meanings" else "",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            HorizontalDivider(color = LocalCodex.current.rule)
        }
        item {
            Row(Modifier.fillMaxWidth().clickable { vm.go(Screen.Hexagram(1)) }.padding(16.dp)) {
                Column(Modifier.weight(1f)) {
                    Text("Yi Jing", style = MaterialTheme.typography.titleMedium)
                    Text("64 hexagrams", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            HorizontalDivider(color = LocalCodex.current.rule)
        }
        defs.decks.filter { it.isPlaceholder && it.id != "custom-template" }.takeIf { it.isNotEmpty() }?.let { waiting ->
            item {
                Text("Waiting for card lists: ${waiting.joinToString { it.name }}", Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
fun DeckScreen(vm: CaptureViewModel, lib: LibraryViewModel, deckId: String, modifier: Modifier = Modifier) {
    val deck = lib.definitions.deck(deckId) ?: return Text("Unknown deck", modifier.padding(16.dp))
    var query by remember { mutableStateOf("") }
    val key = Tokenizer.key(query)
    val cards = deck.cards.filter { c -> key.isEmpty() || (listOf(c.name) + c.aliases).any { Tokenizer.key(it).contains(key) } }
    Column(modifier.fillMaxSize()) {
        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(16.dp), singleLine = true, placeholder = { Text("Find a card") })
        LazyColumn {
            items(cards, key = { it.id }) { c ->
                Column(Modifier.fillMaxWidth().clickable { vm.go(Screen.Card(deck.id, c.id)) }.padding(horizontal = 16.dp, vertical = 10.dp)) {
                    Text(c.name, style = MaterialTheme.typography.bodyLarge)
                    c.significations.values.firstOrNull()?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                    }
                }
                HorizontalDivider(color = LocalCodex.current.rule)
            }
        }
    }
}

@Composable
fun CardScreen(vm: CaptureViewModel, lib: LibraryViewModel, deckId: String, cardId: String, modifier: Modifier = Modifier) {
    val deck = lib.definitions.deck(deckId)
    val card = deck?.card(cardId) ?: return Text("Unknown card", modifier.padding(16.dp))
    val readings = lib.search.search(LibraryQuery(card = "$deckId/$cardId")).size
    Column(modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(deck.name.uppercase(), style = MaterialTheme.typography.labelMedium, color = LocalCodex.current.rubricText)
        Text(card.name, style = MaterialTheme.typography.headlineSmall)
        val attrs = card.attributes.mapNotNull { (k, v) -> (v as? JsonPrimitive)?.content?.let { k to it } }
            .filter { (k, _) -> k !in setOf("order") }
        if (attrs.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                for ((k, v) in attrs) Row {
                    Text(k, Modifier.width(110.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(v, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        if (card.significations.isEmpty()) {
            Text("No meanings for this deck yet.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        for ((kind, text) in card.significations) {
            SectionTitle(kind)
            Text(text, style = MaterialTheme.typography.bodyMedium)
        }
        OutlinedButton(onClick = { lib.showCard(deckId, cardId); vm.go(Screen.Library) }, enabled = readings > 0) {
            Text(if (readings == 0) "Not in any reading yet" else "In $readings reading${if (readings == 1) "" else "s"}")
        }
    }
}

@Composable
fun HexagramScreen(vm: CaptureViewModel, lib: LibraryViewModel, number: Int, modifier: Modifier = Modifier) {
    val yj = lib.definitions.yijing
    val h = yj.hexagram(number) ?: return Text("Unknown hexagram", modifier.padding(16.dp))
    val readings = lib.search.search(LibraryQuery(hexagram = number)).size
    Column(modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("HEXAGRAM $number", style = MaterialTheme.typography.labelMedium, color = LocalCodex.current.rubricText)
        Text("${h.name}", style = MaterialTheme.typography.headlineSmall)
        Text(h.pinyin, style = MaterialTheme.typography.bodyLarge)
        Column { for (i in 5 downTo 0) Text(lineGlyph(if (h.lines.getOrNull(i) == 1) 7 else 8), fontFamily = FontFamily.Monospace) }
        OutlinedButton(onClick = { lib.showHexagram(number); vm.go(Screen.Library) }, enabled = readings > 0) {
            Text(if (readings == 0) "Not in any reading yet" else "In $readings reading${if (readings == 1) "" else "s"}")
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (number > 1) OutlinedButton(onClick = { vm.replaceTop(Screen.Hexagram(number - 1)) }) { Text("← ${number - 1}") }
            if (number < 64) OutlinedButton(onClick = { vm.replaceTop(Screen.Hexagram(number + 1)) }) { Text("${number + 1} →") }
        }
    }
}
