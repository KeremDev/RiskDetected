package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.riskdetectedan.core.designsystem.RdSpacing

/** Port of OBPainPointView.swift. */
@Composable
fun OBPainPointScreen(onNext: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Sahada gördüklerini akşam ofiste mi yazıyorsun?")
        Text("Tanıdık geliyor mu?")
        Button(onClick = onNext) { Text("Devam") }
    }
}
