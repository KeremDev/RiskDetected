package com.riskdetectedan.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.riskdetectedan.app.navigation.RdNavHost
import com.riskdetectedan.app.push.PushTokenRegistrar
import com.riskdetectedan.app.release.ReleaseGate
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        requestNotificationPermissionIfNeeded()
        setContent {
            RiskDetectedTheme {
                // Mirrors AppState.swift: the release-policy gate wraps the whole app, checked
                // before anything else renders — a hard-update requirement replaces the nav
                // graph entirely, not just one screen inside it.
                ReleaseGate {
                    // No UI of its own — registers/refreshes the FCM token for an already
                    // signed-in session (see its own doc comment for what onNewToken alone
                    // doesn't cover).
                    PushTokenRegistrar()
                    RdNavHost()
                }
            }
        }
    }

    /** POST_NOTIFICATIONS is a runtime permission from API 33 (TIRAMISU) on — below that,
     * notification permission is granted at install time, no runtime prompt exists or is
     * needed. Requested unconditionally on launch rather than gated behind a specific user
     * action (matches iOS's own upfront `requestAuthorization` call in NotificationService.swift). */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
