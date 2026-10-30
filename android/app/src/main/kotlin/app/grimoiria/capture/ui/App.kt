package app.grimoiria.capture.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Create
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.layout.Column
import app.grimoiria.capture.CaptureViewModel
import app.grimoiria.capture.LibraryViewModel
import app.grimoiria.capture.Screen
import app.grimoiria.capture.SessionViewModel
import app.grimoiria.capture.Tab

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GrimoireCaptureApp(
    vm: CaptureViewModel,
    lib: LibraryViewModel,
    session: SessionViewModel,
    onRecord: () -> Unit,
    onStartSession: () -> Unit,
    onCalendarToggle: (Boolean) -> Unit,
) {
    CaptureTheme {
        val snackbar = remember { SnackbarHostState() }
        LaunchedEffect(vm.message) {
            vm.message?.let { snackbar.showSnackbar(it); vm.message = null }
        }
        LaunchedEffect(session.message) {
            session.message?.let { snackbar.showSnackbar(it); session.message = null }
        }
        // Back from the check screen keeps the draft; it shows as "Unfinished" on Capture.
        BackHandler(enabled = vm.canGoBack) { vm.back() }
        val screen = vm.screen
        Scaffold(
            topBar = {
                Column {
                    TopAppBar(
                        colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
                        title = { Text(title(vm, lib, screen).uppercase(), style = MaterialTheme.typography.titleLarge) },
                        navigationIcon = {
                            if (Tab.of(screen) == null) {
                                IconButton(onClick = vm::back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                            }
                        },
                        actions = {
                            if (screen == Screen.Home) {
                                TextButton(onClick = { vm.go(Screen.Outbox) }) {
                                    BadgedBox(badge = { if (vm.pendingCount > 0) Badge { Text("${vm.pendingCount}") } }) { Text("Sent") }
                                }
                            }
                            if (Tab.of(screen) != null) {
                                IconButton(onClick = { vm.go(Screen.Settings) }) { Icon(Icons.Filled.Settings, contentDescription = "Settings") }
                            }
                        },
                    )
                    HorizontalDivider(color = LocalCodex.current.rule)
                }
            },
            bottomBar = {
                if (screen !is Screen.Check) {
                    NavigationBar(containerColor = MaterialTheme.colorScheme.background) {
                        for (t in Tab.entries) {
                            NavigationBarItem(
                                selected = vm.tab == t,
                                onClick = { vm.go(t.root) },
                                icon = {
                                    BadgedBox(badge = { if (t == Tab.TODAY && lib.due.isNotEmpty()) Badge { Text("${lib.due.size}") } }) {
                                        Icon(icon(t), contentDescription = null)
                                    }
                                },
                                label = { Text(t.label) },
                                colors = NavigationBarItemDefaults.colors(indicatorColor = MaterialTheme.colorScheme.secondaryContainer),
                            )
                        }
                    }
                }
            },
            snackbarHost = { SnackbarHost(snackbar) },
        ) { padding ->
            val m = Modifier.padding(padding)
            when (screen) {
                Screen.Home -> HomeScreen(vm, onRecord, m)
                is Screen.Check -> vm.check?.let { CheckScreen(vm, it, m) } ?: HomeScreen(vm, onRecord, m)
                Screen.Outbox -> OutboxScreen(vm, m)
                Screen.Settings -> SettingsScreen(vm, lib, onCalendarToggle, m)
                Screen.Library -> LibraryScreen(vm, lib, m)
                is Screen.Item -> ItemScreen(vm, lib, screen.id, m)
                Screen.Decks -> DecksScreen(vm, lib, m)
                is Screen.Deck -> DeckScreen(vm, lib, screen.id, m)
                is Screen.Card -> CardScreen(vm, lib, screen.deckId, screen.cardId, m)
                is Screen.Hexagram -> HexagramScreen(vm, lib, screen.number, m)
                Screen.Session -> SessionScreen(session, lib, onStartSession, onSaved = vm::deliver, modifier = m)
                Screen.Today -> TodayScreen(vm, lib, m)
            }
        }
    }
}

private fun icon(t: Tab): ImageVector = when (t) {
    Tab.CAPTURE -> Icons.Filled.Create
    Tab.LIBRARY -> Icons.Filled.Menu
    Tab.SESSION -> Icons.Filled.PlayArrow
    Tab.TODAY -> Icons.Filled.DateRange
}

private fun title(vm: CaptureViewModel, lib: LibraryViewModel, s: Screen): String = when (s) {
    Screen.Home -> "Grimoire"
    is Screen.Check -> "Check capture"
    Screen.Outbox -> "Sent to the Mac"
    Screen.Settings -> "Settings"
    Screen.Library -> "Library"
    is Screen.Item -> if (lib.item(s.id) is app.grimoiria.core.LibraryItem.Reading) "Reading" else "Entry"
    Screen.Decks -> "Decks"
    is Screen.Deck -> lib.definitions.deck(s.id)?.name ?: "Deck"
    is Screen.Card -> "Card"
    is Screen.Hexagram -> "Yi Jing"
    Screen.Session -> "Session"
    Screen.Today -> "Today"
}
