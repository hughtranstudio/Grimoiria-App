package app.grimoiria.capture.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.grimoiria.capture.CaptureViewModel
import app.grimoiria.capture.LibraryViewModel
import app.grimoiria.capture.Screen
import app.grimoiria.core.LibraryItem
import app.grimoiria.core.YiJing

/** Everything filed on the Mac, newest first, with search and filters. Read-only. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(vm: CaptureViewModel, lib: LibraryViewModel, modifier: Modifier = Modifier) {
    val q = lib.query
    Column(modifier.fillMaxSize()) {
        OutlinedTextField(
            value = q.text, onValueChange = lib::setText, singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            trailingIcon = { if (q.text.isNotEmpty()) IconButton(onClick = { lib.setText("") }) { Icon(Icons.Filled.Close, "Clear search") } },
            placeholder = { Text("Words, cards, #tags…") },
        )
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            item { FilterChip(selected = q.group == null, onClick = { lib.setGroup(null) }, label = { Text("All") }) }
            items(lib.search.groups) { g ->
                FilterChip(selected = q.group == g, onClick = { lib.setGroup(if (q.group == g) null else g) }, label = { Text(groupLabel(g)) })
            }
        }
        // Card and hexagram filters come from tapping them in a reading; show them so they can be cleared.
        val pinned = q.card?.let { c -> lib.search.cardName(c.substringBefore('/'), c.substringAfter('/')) }
            ?: q.hexagram?.let { n -> lib.definitions.yijing.hexagram(n)?.let { "$n. ${it.name}" } ?: "Hexagram $n" }
        if (pinned != null) {
            Row(Modifier.padding(horizontal = 16.dp)) {
                InputChip(selected = true, onClick = lib::clear, label = { Text(pinned) },
                    trailingIcon = { Icon(Icons.Filled.Close, "Clear", Modifier.padding(0.dp)) })
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(countLine(lib), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = { vm.go(Screen.Decks) }) { Text("Decks") }
        }
        HorizontalDivider(color = LocalCodex.current.rule)
        PullToRefreshBox(isRefreshing = lib.refreshing, onRefresh = lib::refresh, modifier = Modifier.weight(1f)) {
            if (lib.library.isEmpty) {
                Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Nothing here yet", style = MaterialTheme.typography.titleMedium)
                    Text(lib.status ?: "Pull down to look for the Mac’s library in the sync folder.", style = MaterialTheme.typography.bodyMedium)
                }
            } else {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(lib.results, key = { it.id }) { item ->
                        LibraryRow(lib, item) { vm.go(Screen.Item(item.id)) }
                        HorizontalDivider(color = LocalCodex.current.rule)
                    }
                }
            }
        }
    }
}

private fun countLine(lib: LibraryViewModel): String {
    val n = lib.results.size
    val synced = lib.library.manifest?.exportedAt?.take(16)?.replace('T', ' ')
    return "$n record${if (n == 1) "" else "s"}" + (synced?.let { " · from the Mac $it" } ?: "")
}

fun groupLabel(g: String) = if (g == "reading") "Readings" else g.replaceFirstChar { it.uppercase() }

@Composable
private fun LibraryRow(lib: LibraryViewModel, item: LibraryItem, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("${groupLabel(item.group).removeSuffix("s").uppercase()} · ${item.day}", style = MaterialTheme.typography.labelSmall,
            color = LocalCodex.current.rubricText)
        Text(item.title, style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
        summary(lib, item)?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2,
                overflow = TextOverflow.Ellipsis)
        }
    }
}

/** One line under the title: the cards and hexagrams of a reading, or the start of an entry. */
private fun summary(lib: LibraryViewModel, item: LibraryItem): String? = when (item) {
    is LibraryItem.Reading -> item.inquiry.divinations.joinToString(" · ") { d ->
        d.cast?.lines?.let { lines ->
            val p = YiJing.primary(lines, lib.definitions.yijing)
            val r = YiJing.resulting(lines, lib.definitions.yijing)
            listOfNotNull(p?.let { "${it.number} ${it.name}" }, r?.let { "→ ${it.number} ${it.name}" }).joinToString(" ")
        } ?: d.draws.joinToString(", ") { lib.search.cardName(d.deckId, it.cardId) + if (it.orientation.name == "REVERSED") " (r)" else "" }
    }.ifBlank { null }?.let { s -> if (item.inquiry.outcomes.isNotEmpty()) "$s · outcome" else s }
    is LibraryItem.Record -> item.entry.session?.let { s -> "${s.observations.size} observations" + (s.durationSeconds?.let { " · ${it / 60} min" } ?: "") }
        ?: item.entry.body.lineSequence().drop(if (item.entry.title.isNullOrBlank()) 1 else 0).joinToString(" ").trim().ifBlank { null }
}
