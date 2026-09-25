package com.riskdetectedan.app.release

import android.content.Intent
import android.net.Uri
import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.legal.LegalDocumentAssets
import com.riskdetectedan.core.designsystem.RdLegalDocument
import com.riskdetectedan.core.designsystem.RdLegalDocumentSheet
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.app.BuildConfig
import androidx.compose.ui.graphics.Color

/**
 * Wraps the real app content, mirroring AppState.swift's release-policy gating: a hard-update
 * requirement replaces the whole screen with a non-dismissable prompt (no back button, no
 * skipping — the store listing is the only way out), a soft-update requirement layers a
 * dismissable dialog on top of the normal app, and a clear policy renders [content] untouched.
 */
@Composable
fun ReleaseGate(
    viewModel: ReleaseGateViewModel = hiltViewModel(),
    onRequestUpdate: ((immediate: Boolean, storeUrl: String) -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val colors = RdTheme.colors

    when (val current = state) {
        ReleaseGateState.Checking -> {
            // The pilot opens on the white Nova splash (İSGADA): a plain white wait keeps the
            // launch one continuous white screen instead of a grey spinner in between.
            if (BuildConfig.NOVA_PILOT) {
                Box(modifier = Modifier.fillMaxSize().background(Color.White))
            } else {
                Box(modifier = Modifier.fillMaxSize().background(colors.cloud), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
        }
        is ReleaseGateState.ClientBlocked -> {
            Box(modifier = Modifier.fillMaxSize().background(colors.cloud).padding(RdSpacing.lg), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(stringResource(RdR.string.rd_android_erisim_hazir_degil), color = colors.black)
                    Text(
                        stringResource(RdR.string.rd_android_erisim_gecici_kapali),
                        modifier = Modifier.padding(top = RdSpacing.sm),
                        color = colors.black,
                    )
                    Button(
                        onClick = { viewModel.refresh() },
                        modifier = Modifier.padding(top = RdSpacing.md),
                    ) { Text(stringResource(RdR.string.rd_tekrar_dene)) }
                }
            }
        }
        is ReleaseGateState.Hard -> {
            Box(modifier = Modifier.fillMaxSize().background(colors.cloud).padding(RdSpacing.lg), contentAlignment = Alignment.Center) {
                Column {
                    Text(stringResource(RdR.string.rd_guncelleme_gerekli), color = colors.black)
                    Text(current.policy.displayMessage, color = colors.black)
                    Button(
                        onClick = {
                            val url = current.policy.playStoreUrl
                                ?: "https://play.google.com/store/apps/details?id=${context.packageName}"
                            if (onRequestUpdate != null) onRequestUpdate(true, url)
                            else context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        },
                        modifier = Modifier.padding(top = RdSpacing.md),
                    ) { Text(stringResource(RdR.string.rd_google_play_de_ac)) }
                }
            }
        }
        is ReleaseGateState.LegalDocumentsOutdated -> {
            Box(modifier = Modifier.fillMaxSize().background(colors.cloud).padding(RdSpacing.lg), contentAlignment = Alignment.Center) {
                Column {
                    Text(stringResource(RdR.string.rd_hukuki_metinler_guncellendi), color = colors.black)
                    Text(stringResource(RdR.string.rd_hukuk_metinleri_guncel_degil), color = colors.black)
                    Button(
                        onClick = {
                            val url = "https://play.google.com/store/apps/details?id=${context.packageName}"
                            if (onRequestUpdate != null) onRequestUpdate(true, url)
                            else context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        },
                        modifier = Modifier.padding(top = RdSpacing.md),
                    ) { Text(stringResource(RdR.string.rd_google_play_de_ac)) }
                }
            }
        }
        else -> {
            content()
            if (current is ReleaseGateState.Soft) {
                AlertDialog(
                    onDismissRequest = { viewModel.dismissSoft(current.policy) },
                    title = { Text(stringResource(RdR.string.rd_yeni_surum_mevcut)) },
                    text = { Text(current.policy.displayMessage) },
                    confirmButton = {
                        Button(
                            onClick = {
                                val url = current.policy.playStoreUrl
                                    ?: "https://play.google.com/store/apps/details?id=${context.packageName}"
                                if (onRequestUpdate != null) onRequestUpdate(false, url)
                                else context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            },
                        ) { Text(stringResource(RdR.string.rd_google_play_de_ac)) }
                    },
                    dismissButton = {
                        TextButton(onClick = { viewModel.dismissSoft(current.policy) }) { Text(stringResource(RdR.string.rd_sonra)) }
                    },
                )
            }
            if (current is ReleaseGateState.Legal) {
                LegalUpdateDialog(current = current, viewModel = viewModel)
            }
        }
    }
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun LegalUpdateDialog(
    current: ReleaseGateState.Legal,
    viewModel: ReleaseGateViewModel,
) {
    val context = LocalContext.current
    var showDocuments by remember { mutableStateOf(false) }
    var documents by remember { mutableStateOf<List<RdLegalDocument>>(emptyList()) }

    LaunchedEffect(showDocuments) {
        if (showDocuments && documents.isEmpty()) {
            documents = LegalDocumentAssets.load(context)
                .map { RdLegalDocument(kind = it.kind, title = it.title, text = it.text) }
        }
    }

    AlertDialog(
        onDismissRequest = {
            if (current.policy.requiresExplicitConsent) {
                viewModel.dismissExplicitLegal(current.policy)
            }
        },
        title = { Text(stringResource(RdR.string.rd_hukuki_metinler_guncellendi)) },
        text = {
            Column {
                Text(current.policy.localizedMessage)
                TextButton(onClick = { showDocuments = true }) {
                    Text(stringResource(RdR.string.rd_guncel_metinleri_incele))
                }
                if (current.errorCode != null) {
                    Text(stringResource(RdR.string.rd_hukuk_kabul_hatasi))
                }
            }
        },
        confirmButton = {
            Button(
                onClick = { viewModel.acknowledgeLegal(current.policy) },
                enabled = !current.isSubmitting,
            ) {
                if (current.isSubmitting) {
                    CircularProgressIndicator()
                } else {
                    Text(
                        stringResource(
                            if (current.policy.requiresExplicitConsent) {
                                RdR.string.rd_kabul_ediyorum
                            } else {
                                RdR.string.rd_devam_et
                            },
                        ),
                    )
                }
            }
        },
        dismissButton = if (current.policy.requiresExplicitConsent) {
            {
                TextButton(onClick = { viewModel.dismissExplicitLegal(current.policy) }) {
                    Text(stringResource(RdR.string.rd_simdilik_kapat))
                }
            }
        } else {
            null
        },
    )

    if (showDocuments) {
        ModalBottomSheet(onDismissRequest = { showDocuments = false }) {
            RdLegalDocumentSheet(
                documents = documents,
                initialKind = null,
                onClose = { showDocuments = false },
            )
        }
    }
}
