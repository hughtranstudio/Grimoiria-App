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
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import app.grimoiria.capture.CaptureViewModel
import app.grimoiria.capture.LibraryViewModel
import app.grimoiria.capture.Screen
import app.grimoiria.core.CheckIn

/** Outcome check-ins: due now (answer or put off), then what's coming up. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun TodayScreen(vm: CaptureViewModel, lib: LibraryViewModel, modifier: Modifier = Modifier) {
    var answering by remember { mutableStateOf<CheckIn?>(null) }
    val due = lib.due
    val upcoming = lib.upcoming.take(20)
    PullToRefreshBox(isRefreshing = lib.refreshing, onRefresh = lib::refresh, modifier = modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item { Text("Needs outcome", Modifier.padding(top = 16.dp), style = MaterialTheme.typography.titleLarge) }
            if (due.isEmpty()) item {
                Text(if (lib.library.isEmpty) "Check-ins come from the Mac’s library once it has synced." else "Nothing due. Readings ask again at 7, 30 and 90 days.",
                    style = MaterialTheme.typography.bodyMedium, fontStyle = FontStyle.Italic)
            }
            items(due, key = { it.reminder.id }) { c ->
                Column(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("DUE ${c.reminder.dueOn}" + (c.reminder.step?.let { " · $it DAYS" } ?: ""), style = MaterialTheme.typography.labelSmall,
                        color = LocalCodex.current.rubricText)
                    Text(c.title, Modifier.clickable { vm.go(Screen.Item(c.reminder.targetId)) }, style = MaterialTheme.typography.bodyLarge)
                    Text(c.prompt, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (c.inquiry != null) TextButton(onClick = { answering = c }) { Text("Add outcome") }
                        TextButton(onClick = { lib.later(c) }) { Text("In 3 days") }
                        TextButton(onClick = { vm.go(Screen.Item(c.reminder.targetId)) }) { Text("Open") }
                    }
                }
                HorizontalDivider(color = LocalCodex.current.rule)
            }
            if (upcoming.isNotEmpty()) {
                item { Text("Coming up", Modifier.padding(top = 16.dp), style = MaterialTheme.typography.titleLarge) }
                items(upcoming, key = { "u" + it.reminder.id }) { c ->
                    Row(Modifier.fillMaxWidth().clickable { vm.go(Screen.Item(c.reminder.targetId)) }.padding(vertical = 8.dp),
                        verticalAlignment = Alignment.Top) {
                        Text(c.reminder.dueOn.drop(5), Modifier.width(64.dp), style = MaterialTheme.typography.labelMedium)
                        Text(c.title, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }
    }
    answering?.let { c ->
        OutcomeDialog(c.title, onDismiss = { answering = null }) { text, fulfilled ->
            vm.sendOutcome(c.reminder.targetId, text, fulfilled)
            lib.reloadCheckIns()
            answering = null
        }
    }
}
