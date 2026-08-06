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

/** Port of OBSplashView.swift — full marketing-carousel/phone-mockup animation not ported,
 * just the two headline strings + continue/skip actions. */
@Composable
fun OBSplashScreen(onNext: () -> Unit, onSkip: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Profesyonel İSG Asistanı")
        Text("Fotoğraf çek; yapay zekâ tehlikeleri otomatik tespit etsin, raporun anında oluşsun ve tek tıklama ile paylaş.")
        Button(onClick = onNext) { Text("Devam") }
        TextButton(onClick = onSkip) { Text("Atla") }
    }
}
