package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import com.riskdetectedan.core.data.legal.LegalDocumentAssets
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdLegalDocument
import com.riskdetectedan.core.designsystem.RdLegalDocumentSheet
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel

/**
 * Port of OBTrialInviteView.swift (2026-08-08 visual pass, Faz E). Real RevenueCat pricing not
 * shown on this invitation step; the following timeline paywall fetches the real store price.
 * A single realistically proportioned Samsung-style device stays centered while three preview
 * screens slide and cross-fade inside it every 2.8 seconds. Keeping the hardware frame fixed
 * avoids the distorted stacked-phone effect while still revealing successive product screens.
 * Footer links:
 * "Gizlilik Politikası"/"Şartlar" open the real [RdLegalDocumentSheet]. "Geri Yükle" uses
 * the same RevenueCat owner checks and backend-authoritative entitlement flow as the final
 * onboarding paywall; an active subscription completes onboarding exactly like iOS.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OBTrialInviteScreen(
    onContinue: () -> Unit,
    onRestored: () -> Unit,
    onDismiss: () -> Unit,
    viewModel: OBTimelinePaywallViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    var legalDocumentKind by remember { mutableStateOf<String?>(null) }
    val isRestoring by viewModel.isPurchasing.collectAsState()
    val restoreError by viewModel.purchaseError.collectAsState()
    OBTrialInviteContent(
        isRestoring = isRestoring,
        onContinue = onContinue,
        onDismiss = onDismiss,
        onRestore = { viewModel.restorePurchases(onRestored) },
        onOpenLegal = { legalDocumentKind = it },
    )

    if (legalDocumentKind != null) {
        var legalDocuments by remember { mutableStateOf<List<RdLegalDocument>>(emptyList()) }
        LaunchedEffect(Unit) {
            legalDocuments = LegalDocumentAssets.load(context)
                .map { RdLegalDocument(kind = it.kind, title = it.title, text = it.text) }
        }
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(onDismissRequest = { legalDocumentKind = null }, sheetState = sheetState) {
            RdLegalDocumentSheet(
                documents = legalDocuments,
                initialKind = legalDocumentKind,
                onClose = { legalDocumentKind = null },
            )
        }
    }

    restoreError?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearPurchaseError,
            title = { Text(error.title) },
            text = { Text(error.message) },
            confirmButton = { TextButton(onClick = viewModel::clearPurchaseError) { Text(stringResource(RdR.string.rd_tamam)) } },
        )
    }
}

@Composable
fun OBTrialInvitePreviewSurface() {
    OBTrialInviteContent(false, {}, {}, {}, {})
}

@Composable
private fun OBTrialInviteContent(
    isRestoring: Boolean,
    onContinue: () -> Unit,
    onDismiss: () -> Unit,
    onRestore: () -> Unit,
    onOpenLegal: (String) -> Unit,
) {
    val colors = RdTheme.colors
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.radialGradient(
                    colors = listOf(colors.green.copy(alpha = 0.10f), colors.paper),
                    center = Offset(0.5f, 0f),
                    radius = 900f,
                ),
            ),
    ) {
        Column(
            modifier = Modifier.fillMaxSize().navigationBarsPadding().padding(horizontal = RdSpacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(28.dp))

            Text(
                stringResource(RdR.string.rd_trial_free_title),
                style = RdFontStyle.Title1.toTextStyle(),
                textAlign = TextAlign.Center,
                color = colors.onyx,
            )

            Spacer(Modifier.height(8.dp))
            Box(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                PhoneDeck()
            }
            Spacer(Modifier.height(6.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = colors.onyx, modifier = Modifier.size(15.dp))
                Spacer(Modifier.width(8.dp))
                Text(
                    stringResource(RdR.string.rd_bu_asamada_odeme_alinmaz),
                    style = RdFontStyle.Callout.toTextStyle(),
                    color = colors.onyx,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            Spacer(Modifier.height(14.dp))
            RdPrimaryButton(text = stringResource(RdR.string.rd_sifir_tl_dene), onClick = onContinue, style = RdButtonStyle.Onyx)

            Spacer(Modifier.height(10.dp))
            Text(stringResource(RdR.string.rd_taahhut_yok_istedigin_zaman_iptal), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)

            Spacer(Modifier.height(14.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(
                    stringResource(RdR.string.rd_gizlilik_politikasi),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                    modifier = Modifier.clickable { onOpenLegal("privacy") },
                )
                Text(
                    if (isRestoring) stringResource(RdR.string.rd_geri_yukleniyor) else stringResource(RdR.string.rd_geri_yukle),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                    modifier = Modifier.clickable(enabled = !isRestoring) {
                        onRestore()
                    },
                )
                Text(
                    stringResource(RdR.string.rd_sartlar),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                    modifier = Modifier.clickable { onOpenLegal("terms") },
                )
            }
            Spacer(Modifier.height(10.dp))
        }

        IconButton(
            onClick = onDismiss,
            modifier = Modifier.align(Alignment.TopEnd).padding(top = 18.dp, end = 14.dp).size(38.dp),
        ) {
            Icon(
                Icons.Filled.Close,
                contentDescription = stringResource(RdR.string.rd_kapat),
                tint = colors.slate.copy(alpha = 0.62f),
                modifier = Modifier.size(18.dp),
            )
        }
    }

}

@Composable
private fun PhoneDeck() {
    var previewIndex by remember { mutableIntStateOf(0) }
    val previewResources = listOf(
        R.drawable.ob_trial_preview_a,
        R.drawable.ob_trial_preview_b,
        R.drawable.ob_trial_preview_c,
    )
    LaunchedEffect(Unit) {
        while (true) {
            delay(2_800L)
            previewIndex = (previewIndex + 1) % previewResources.size
        }
    }
    SamsungPhone(previewResources, previewIndex)
}

@Composable
private fun SamsungPhone(previewResources: List<Int>, previewIndex: Int) {
    Box(
        modifier = Modifier
            .width(218.dp)
            .height(457.dp)
            .clip(RoundedCornerShape(21.dp))
            .background(Color(0xFF17191A)),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .width(210.dp)
                .height(449.dp)
                .clip(RoundedCornerShape(17.dp))
                .background(Color(0xFF0B0D0E)),
        ) {
            AnimatedContent(
                targetState = previewIndex,
                transitionSpec = {
                    (fadeIn(tween(900)) + slideInVertically(tween(1_250, easing = FastOutSlowInEasing)) { it / 14 })
                        .togetherWith(fadeOut(tween(700)) + slideOutVertically(tween(1_050, easing = FastOutSlowInEasing)) { -it / 14 })
                },
                label = "samsung-preview",
            ) { index ->
                Image(
                    painter = painterResource(previewResources[index]),
                    contentDescription = stringResource(RdR.string.rd_riskdetected_uygulama_onizlemesi),
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        Box(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 8.dp)
                .size(7.dp)
                .clip(CircleShape)
                .background(Color.Black),
        )
        Box(
            modifier = Modifier.align(Alignment.CenterEnd).padding(top = 64.dp).size(width = 2.dp, height = 48.dp)
                .clip(RoundedCornerShape(1.dp)).background(Color(0xFF383B3D)),
        )
        Box(
            modifier = Modifier.align(Alignment.CenterEnd).padding(bottom = 62.dp).size(width = 2.dp, height = 34.dp)
                .clip(RoundedCornerShape(1.dp)).background(Color(0xFF383B3D)),
        )
    }
}
