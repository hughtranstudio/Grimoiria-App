package app.grimoiria.capture

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import app.grimoiria.capture.ui.GrimoireCaptureApp

class MainActivity : ComponentActivity() {
    private val vm: CaptureViewModel by viewModels()
    private val lib: LibraryViewModel by viewModels()
    private val session: SessionViewModel by viewModels()

    /** Set when a shortcut or the Quick Settings tile asked to record before permission was granted. */
    private var recordAfterPermission = false

    private val micPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted && recordAfterPermission) vm.startRecording()
        if (!granted) vm.message = "Recording needs the microphone permission"
        recordAfterPermission = false
    }

    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    /** A session starts either way; without the microphone it records marks and observations only. */
    private val sessionMic = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        session.start(micAllowed = granted)
        if (!granted) session.message = "No microphone: marks and observations only"
    }

    private val calendarPermission = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        val ok = result.values.all { it }
        grimoire.settings.calendarSync = ok
        if (ok) lib.syncCalendar() else vm.message = "The calendar needs permission to add check-ins"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        setContent {
            GrimoireCaptureApp(vm, lib, session, onRecord = ::record, onStartSession = ::startSession, onCalendarToggle = ::setCalendar)
        }
        if (savedInstanceState == null) handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        vm.deliver()
        lib.refresh()
    }

    private fun handle(intent: Intent?) {
        when (intent?.action) {
            ACTION_RECORD -> { vm.go(Screen.Home); record() }
            ACTION_SESSION -> vm.go(Screen.Session)
            ACTION_TODAY -> vm.go(Screen.Today)
        }
    }

    private fun startSession() {
        if (!session.withAudio || checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            session.start(micAllowed = true)
        } else {
            sessionMic.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    private fun setCalendar(on: Boolean) {
        if (!on) {
            grimoire.settings.calendarSync = false
            lib.removeCalendar()
        } else {
            calendarPermission.launch(arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR))
        }
    }

    private fun record() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            vm.startRecording()
        } else {
            recordAfterPermission = true
            micPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    companion object {
        const val ACTION_RECORD = "app.grimoiria.capture.RECORD"
        const val ACTION_SESSION = "app.grimoiria.capture.SESSION"
        const val ACTION_TODAY = "app.grimoiria.capture.TODAY"
    }
}
