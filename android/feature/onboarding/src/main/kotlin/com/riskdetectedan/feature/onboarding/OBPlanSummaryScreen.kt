package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.riskdetectedan.core.designsystem.RdSpacing

/** Port of OBPlanSummaryView.swift — shows what was collected before moving to auth. */
@Composable
fun OBPlanSummaryScreen(state: OnboardingUiState, onNext: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Planın hazır")
        Text("Sertifika: ${state.certificate?.label ?: "—"}")
        Text("Tehlike sınıfı: ${state.hazards.joinToString(" · ") { it.label }.ifEmpty { "—" }}")
        Text("Sektör: ${state.sectors.joinToString(" · ") { it.label }.ifEmpty { "—" }}")
        Text("Sıklık: ${state.frequency?.title ?: "—"}")
        Button(onClick = onNext) { Text("Devam") }
    }
}
