package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.riskdetectedan.core.designsystem.RdSpacing

/**
 * Port of OBTimelinePaywallView.swift's *slot* in the onboarding flow (step 11) — an
 * onboarding-specific paywall step, deliberately a local composable here rather than reusing
 * `feature:paywall`'s PaywallScreen: iOS keeps OBTimelinePaywallView embedded in the onboarding
 * coordinator too, distinct from wherever a general post-onboarding upsell paywall lives.
 * `feature:paywall` isn't a dependency of `feature:onboarding` (module boundary, review §8) and
 * shouldn't become one just for this. No RevenueCat packages/pricing wired — no RevenueCat
 * Android project/key exists yet (same gap as OBTrialInviteScreen). "Devam et" just finishes
 * onboarding without a purchase, which is a real, valid path even on iOS (skip/dismiss).
 */
@Composable
fun OBTimelinePaywallScreen(onDismiss: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Planını seç")
        Text("Satın alma RevenueCat Android kurulmadan çalışmaz — iskelet ekran.")
        Button(onClick = onDismiss) { Text("Devam et") }
        TextButton(onClick = onDismiss) { Text("Şimdi değil") }
    }
}
