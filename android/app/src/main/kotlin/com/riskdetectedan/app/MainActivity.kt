package com.riskdetectedan.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.riskdetectedan.app.navigation.RdNavHost
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            RiskDetectedTheme {
                RdNavHost()
            }
        }
    }
}
