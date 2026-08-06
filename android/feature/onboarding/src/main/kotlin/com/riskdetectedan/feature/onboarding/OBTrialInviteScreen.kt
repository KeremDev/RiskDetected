package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.riskdetectedan.core.designsystem.RdSpacing

/**
 * Port of OBTrialInviteView.swift — real RevenueCat pricing/restore not wired (no RevenueCat
 * Android project/key yet, same gap noted for the paywall step). Headline + continue only.
 */
@Composable
fun OBTrialInviteScreen(onContinue: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("7 gün ücretsiz dene")
        Text("Fiyat Google Play üzerinden yüklenecek.") // iOS says "App Store" — platform-correct here, not a typo
        Button(onClick = onContinue) { Text("Devam") }
    }
}
