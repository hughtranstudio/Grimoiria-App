package app.grimoiria.capture.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import app.grimoiria.capture.CaptureViewModel
import app.grimoiria.capture.Screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GrimoireCaptureApp(vm: CaptureViewModel, onRecord: () -> Unit) {
    CaptureTheme {
        val snackbar = remember { SnackbarHostState() }
        LaunchedEffect(vm.message) {
            vm.message?.let { snackbar.showSnackbar(it); vm.message = null }
        }
        // Back from the check screen keeps the draft; it shows as "Unfinished" on Home.
        BackHandler(enabled = vm.screen != Screen.Home) { vm.go(Screen.Home) }
        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        Text(when (vm.screen) {
                            Screen.Home -> "Grimoire"
                            is Screen.Check -> "Check capture"
                            Screen.Outbox -> "Captures"
                            Screen.Settings -> "Settings"
                        })
                    },
                    navigationIcon = {
                        if (vm.screen != Screen.Home) {
                            IconButton(onClick = { vm.go(Screen.Home) }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                            }
                        }
                    },
                    actions = {
                        if (vm.screen == Screen.Home) {
                            TextButton(onClick = { vm.go(Screen.Outbox) }) {
                                BadgedBox(badge = { if (vm.pendingCount > 0) Badge { Text("${vm.pendingCount}") } }) {
                                    Text("Captures")
                                }
                            }
                            IconButton(onClick = { vm.go(Screen.Settings) }) {
                                Icon(Icons.Filled.Settings, contentDescription = "Settings")
                            }
                        }
                    },
                )
            },
            snackbarHost = { SnackbarHost(snackbar) },
        ) { padding ->
            val m = Modifier.padding(padding)
            when (vm.screen) {
                Screen.Home -> HomeScreen(vm, onRecord, m)
                is Screen.Check -> vm.check?.let { CheckScreen(vm, it, m) } ?: HomeScreen(vm, onRecord, m)
                Screen.Outbox -> OutboxScreen(vm, m)
                Screen.Settings -> SettingsScreen(vm, m)
            }
        }
    }
}
