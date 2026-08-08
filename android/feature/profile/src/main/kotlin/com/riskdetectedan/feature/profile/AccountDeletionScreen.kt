package com.riskdetectedan.feature.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Port of the account-deletion request flow (2026-08-08 visual pass, Faz K of the core-flow
 * redesign — AnalysisService.swift's requestAccountDeletion, called from ProfileView.swift's
 * delete-account UI, that specific confirmation dialog layout wasn't read, this uses a standard
 * AlertDialog instead). Requires explicit confirmation before calling — destructive, irreversible
 * action. ViewModel logic unchanged. The delete CTA uses a one-off critical-red button (not
 * [com.riskdetectedan.core.designsystem.RdPrimaryButton], which only offers onyx/green styles) —
 * a real destructive-action color, not worth extending the shared button for a single screen.
 */
@Composable
fun AccountDeletionScreen(onDeleted: () -> Unit, onBack: (() -> Unit)? = null, viewModel: AccountDeletionViewModel = hiltViewModel()) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    var showConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(state) {
        if (state is AccountDeletionUiState.Completed) onDeleted()
    }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = "Hesabı Sil", onBack = onBack)

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.lg)) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(RdRadius.lg))
                    .background(colors.criticalBg.copy(alpha = 0.70f))
                    .border(1.dp, colors.critical.copy(alpha = 0.22f), RoundedCornerShape(RdRadius.lg))
                    .padding(RdSpacing.md),
            ) {
                Text("Hesabını silmek üzeresin", style = RdFontStyle.Callout.toTextStyle(), color = colors.criticalText)
                Spacer(Modifier.height(RdSpacing.xxs))
                Text(
                    "Bu işlem geri alınamaz. Tüm analizlerin, fotoğrafların ve raporların kalıcı olarak silinir.",
                    style = RdFontStyle.Footnote.toTextStyle(),
                    color = colors.criticalText,
                )
            }

            Spacer(Modifier.height(RdSpacing.md))
            when (val current = state) {
                is AccountDeletionUiState.Idle -> DestructiveButton(text = "Hesabımı sil", onClick = { showConfirm = true })
                is AccountDeletionUiState.Requesting -> Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.critical)
                }
                is AccountDeletionUiState.Completed -> Text("Hesap silindi.", style = RdFontStyle.Callout.toTextStyle(), color = colors.slate)
                is AccountDeletionUiState.Failed -> Column {
                    Text(current.error.message, style = RdFontStyle.Footnote.toTextStyle(), color = colors.critical)
                    Spacer(Modifier.height(RdSpacing.sm))
                    DestructiveButton(text = "Tekrar dene", onClick = { showConfirm = true })
                }
            }
        }
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text("Emin misin?") },
            text = { Text("Hesabın ve tüm verilerin kalıcı olarak silinecek. Bu işlem geri alınamaz.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showConfirm = false
                        viewModel.confirmDeletion()
                    },
                ) { Text("Evet, sil") }
            },
            dismissButton = {
                TextButton(onClick = { showConfirm = false }) { Text("Vazgeç") }
            },
        )
    }
}

@Composable
private fun DestructiveButton(text: String, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(colors.critical)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = RdFontStyle.Callout.toTextStyle(), color = colors.white, textAlign = TextAlign.Center)
    }
}
