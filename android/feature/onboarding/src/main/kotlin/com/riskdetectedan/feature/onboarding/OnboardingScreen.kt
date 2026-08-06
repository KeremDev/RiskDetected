package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.riskdetectedan.core.designsystem.RdSpacing

/**
 * Placeholder — Faz 3 replaces this with the real onboarding step sequence (0-11), ported
 * screen-by-screen from `App/Views/Onboarding/V2/Screens/` per the master plan's iOS
 * source-mapping table (§8.2). Real work so far: the flow reaches [AuthScreen] and back, so
 * auth can actually be exercised end to end on-device before the rest of onboarding exists.
 */
@Composable
fun OnboardingScreen(onFinished: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(RdSpacing.lg),
        contentAlignment = Alignment.Center,
    ) {
        Column {
            Text("Onboarding — Faz 3 (steps 0-11 not ported yet)")
            Button(onClick = onFinished) {
                Text("Devam et")
            }
        }
    }
}
