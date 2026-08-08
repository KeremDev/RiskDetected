package com.riskdetectedan.feature.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSectionCard
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/** Port of SupportService.swift's send() contract (2026-08-08 visual pass, Faz K of the
 * core-flow redesign) — App/Views/Profile/SupportContactSheet.swift's layout wasn't read;
 * attachments not ported (see SupportRepository's doc comment). Repository/ViewModel logic
 * unchanged. */
@Composable
fun SupportScreen(onBack: (() -> Unit)? = null, viewModel: SupportViewModel = hiltViewModel()) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    var subject by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = "Destek", onBack = onBack)

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.lg)) {
            RdSectionCard {
                Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                    OutlinedTextField(
                        value = subject,
                        onValueChange = { subject = it },
                        label = { Text("Konu") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = message,
                        onValueChange = { message = it },
                        label = { Text("Mesaj") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    RdPrimaryButton(
                        text = "Gönder",
                        onClick = { viewModel.send(subject, message) },
                        enabled = subject.isNotBlank() && message.isNotBlank() && state !is SupportUiState.Sending,
                        style = RdButtonStyle.Onyx,
                        showArrow = false,
                    )
                }
            }

            Spacer(Modifier.height(RdSpacing.md))
            when (val current = state) {
                is SupportUiState.Idle -> Unit
                is SupportUiState.Sending -> Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.onyx)
                }
                is SupportUiState.Sent -> Text(
                    "Gönderildi. Destek kodu: ${current.supportId ?: "—"}",
                    style = RdFontStyle.Footnote.toTextStyle(),
                    color = colors.greenDark,
                )
                is SupportUiState.Failed -> Text(current.error.message, style = RdFontStyle.Footnote.toTextStyle(), color = colors.critical)
            }
        }
    }
}
