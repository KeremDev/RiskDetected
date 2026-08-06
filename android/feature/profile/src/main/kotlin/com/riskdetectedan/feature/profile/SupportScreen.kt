package com.riskdetectedan.feature.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.designsystem.RdSpacing

/** Port of SupportService.swift's send() contract — App/Views/Profile/SupportContactSheet.swift's
 * layout wasn't read; attachments not ported (see SupportRepository's doc comment). */
@Composable
fun SupportScreen(viewModel: SupportViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    var subject by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }

    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Destek")
        OutlinedTextField(
            value = subject,
            onValueChange = { subject = it },
            label = { Text("Konu") },
            modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.sm),
        )
        OutlinedTextField(
            value = message,
            onValueChange = { message = it },
            label = { Text("Mesaj") },
            modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.sm),
        )
        Button(
            onClick = { viewModel.send(subject, message) },
            enabled = subject.isNotBlank() && message.isNotBlank() && state !is SupportUiState.Sending,
            modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.sm),
        ) {
            Text("Gönder")
        }

        when (val current = state) {
            is SupportUiState.Idle -> Unit
            is SupportUiState.Sending -> CircularProgressIndicator()
            is SupportUiState.Sent -> Text("Gönderildi. Destek kodu: ${current.supportId ?: "—"}")
            is SupportUiState.Failed -> Text(current.message)
        }
    }
}
