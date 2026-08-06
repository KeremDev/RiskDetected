package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.riskdetectedan.core.designsystem.RdSpacing

/**
 * Placeholder — Faz 3 replaces this with the real onboarding flow, ported screen-by-screen
 * from `App/Views/Onboarding/V2/Screens/` per the master plan's iOS source-mapping table (§8.2).
 */
@Composable
fun OnboardingScreen(onFinished: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(RdSpacing.lg),
        contentAlignment = Alignment.Center,
    ) {
        Text("Onboarding — Faz 3")
    }
}
