package com.riskdetectedan.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.riskdetectedan.app.navigation.RdNavHost
import com.riskdetectedan.app.release.ReleaseGate
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            RiskDetectedTheme {
                // Mirrors AppState.swift: the release-policy gate wraps the whole app, checked
                // before anything else renders — a hard-update requirement replaces the nav
                // graph entirely, not just one screen inside it.
                ReleaseGate {
                    RdNavHost()
                }
            }
        }
    }
}
