package com.riskdetectedan.app.release

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.designsystem.RdSpacing

/**
 * Wraps the real app content, mirroring AppState.swift's release-policy gating: a hard-update
 * requirement replaces the whole screen with a non-dismissable prompt (no back button, no
 * skipping — the store listing is the only way out), a soft-update requirement layers a
 * dismissable dialog on top of the normal app, and a clear policy renders [content] untouched.
 */
@Composable
fun ReleaseGate(viewModel: ReleaseGateViewModel = hiltViewModel(), content: @Composable () -> Unit) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current

    when (val current = state) {
        is ReleaseGateState.Hard -> {
            Box(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg), contentAlignment = Alignment.Center) {
                Column {
                    Text("Güncelleme gerekli")
                    Text(current.policy.displayMessage)
                    Button(
                        onClick = {
                            val url = current.policy.playStoreUrl
                                ?: "https://play.google.com/store/apps/details?id=${context.packageName}"
                            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        },
                        modifier = Modifier.padding(top = RdSpacing.md),
                    ) { Text("Google Play'de aç") }
                }
            }
        }
        else -> {
            content()
            if (current is ReleaseGateState.Soft) {
                AlertDialog(
                    onDismissRequest = { viewModel.dismissSoft(current.policy) },
                    title = { Text("Yeni sürüm mevcut") },
                    text = { Text(current.policy.displayMessage) },
                    confirmButton = {
                        Button(
                            onClick = {
                                val url = current.policy.playStoreUrl
                                    ?: "https://play.google.com/store/apps/details?id=${context.packageName}"
                                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            },
                        ) { Text("Google Play'de aç") }
                    },
                    dismissButton = {
                        TextButton(onClick = { viewModel.dismissSoft(current.policy) }) { Text("Sonra") }
                    },
                )
            }
        }
    }
}
