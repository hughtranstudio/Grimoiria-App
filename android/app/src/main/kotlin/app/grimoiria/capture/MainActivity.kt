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

    /** Set when a shortcut or the Quick Settings tile asked to record before permission was granted. */
    private var recordAfterPermission = false

    private val micPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted && recordAfterPermission) vm.startRecording()
        if (!granted) vm.message = "Recording needs the microphone permission"
        recordAfterPermission = false
    }

    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        setContent { GrimoireCaptureApp(vm, onRecord = ::record) }
        if (savedInstanceState == null) handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        vm.deliver()
    }

    private fun handle(intent: Intent?) {
        if (intent?.action == ACTION_RECORD) {
            vm.go(Screen.Home)
            record()
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
    }
}
