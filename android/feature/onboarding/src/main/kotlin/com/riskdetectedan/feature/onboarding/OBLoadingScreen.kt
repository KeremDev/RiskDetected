package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.riskdetectedan.core.designsystem.RdSpacing
import kotlinx.coroutines.delay

/**
 * Port of OBLoadingView.swift — iOS shows a ~4s sequence of personalized status lines
 * (referencing the user's sector/certificate) before auto-advancing; simplified to a single
 * static line + a fixed 2s delay, same auto-advance behavior.
 */
@Composable
fun OBLoadingScreen(onFinished: () -> Unit) {
    LaunchedEffect(Unit) {
        delay(2_000)
        onFinished()
    }
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(modifier = Modifier.padding(RdSpacing.lg)) {
            CircularProgressIndicator()
            Text("Sana özel kurulum hazırlanıyor…")
        }
    }
}
