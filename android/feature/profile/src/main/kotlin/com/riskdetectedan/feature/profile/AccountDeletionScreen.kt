package com.riskdetectedan.feature.profile

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
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
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.designsystem.RdSpacing

/**
 * Port of the account-deletion request flow (AnalysisService.swift's
 * requestAccountDeletion, called from ProfileView.swift's delete-account UI — that specific
 * confirmation dialog layout wasn't read, this uses a standard AlertDialog instead). Requires
 * explicit confirmation before calling — destructive, irreversible action.
 */
@Composable
fun AccountDeletionScreen(onDeleted: () -> Unit, viewModel: AccountDeletionViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    var showConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(state) {
        if (state is AccountDeletionUiState.Completed) onDeleted()
    }

    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Hesabı sil")
        Text("Bu işlem geri alınamaz. Tüm analizlerin, fotoğrafların ve raporların kalıcı olarak silinir.")

        when (val current = state) {
            is AccountDeletionUiState.Idle -> Button(onClick = { showConfirm = true }) {
                Text("Hesabımı sil")
            }
            is AccountDeletionUiState.Requesting -> CircularProgressIndicator()
            is AccountDeletionUiState.Completed -> Text("Hesap silindi.")
            is AccountDeletionUiState.Failed -> {
                Text(current.message)
                Button(onClick = { showConfirm = true }) { Text("Tekrar dene") }
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
