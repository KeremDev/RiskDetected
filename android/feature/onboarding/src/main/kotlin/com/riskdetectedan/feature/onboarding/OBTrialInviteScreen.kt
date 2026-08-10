package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
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
 * shown here either way (matches this screen's pre-existing scope note — same gap as the paywall
 * step). The 3-phone auto-swapping deck now really swaps (2026-08-09 animation pass — was one
 * static phone bezel before): 3 stacked [PhoneCard]s cycle which one is in front every 2.4s
 * (`LaunchedEffect` index loop, same staged-timer pattern as every other real animation this
 * pass), each card's scale/rotation/offset/alpha animating smoothly between front/mid/back depth
 * via `animate*AsState` rather than iOS's continuous loop — a discrete cycle reads the same to a
 * user glancing at an onboarding screen for a few seconds, cheaper than perpetually-running
 * per-frame math for 3 stacked cards. All 3 share the same real preview content (mini risk rows +
 * "Rapor hazır") — the deck is a depth/ordering animation, not 3 different screens. Footer links:
 * "Gizlilik Politikası"/"Şartlar" open the real [RdLegalDocumentSheet]. "Geri Yükle" uses
 * the same RevenueCat owner checks and backend-authoritative entitlement flow as the final
 * onboarding paywall; an active subscription completes onboarding exactly like iOS.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OBTrialInviteScreen(
    onContinue: () -> Unit,
    onRestored: () -> Unit,
    viewModel: OBTimelinePaywallViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val context = LocalContext.current
    var legalDocumentKind by remember { mutableStateOf<String?>(null) }
    val isRestoring by viewModel.isPurchasing.collectAsState()
    val restoreError by viewModel.purchaseError.collectAsState()
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
            modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.xl),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(32.dp))

            Text(
                buildAnnotatedTitle(
                    colors.onyx,
                    colors.green,
                    stringResource(RdR.string.rd_trial_title_prefix),
                    stringResource(RdR.string.rd_trial_title_emphasis),
                ),
                style = RdFontStyle.Title1.toTextStyle(),
                textAlign = TextAlign.Center,
            )
            Text(stringResource(RdR.string.rd_birlikte_secelim), style = RdFontStyle.Title1.toTextStyle(), color = colors.onyx, textAlign = TextAlign.Center)

            Spacer(Modifier.height(24.dp))
            PhoneDeck()

            Spacer(Modifier.height(28.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = colors.onyx, modifier = Modifier.size(15.dp))
                Spacer(Modifier.width(8.dp))
                Text(
                    stringResource(RdR.string.rd_fiyat_google_play),
                    style = RdFontStyle.Callout.toTextStyle(),
                    color = colors.onyx,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            Spacer(Modifier.height(14.dp))
            RdPrimaryButton(text = stringResource(RdR.string.rd_plan_seceneklerini_gor), onClick = onContinue, style = RdButtonStyle.Onyx)

            Spacer(Modifier.height(10.dp))
            Text(stringResource(RdR.string.rd_taahhut_yok_istedigin_zaman_iptal), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)

            Spacer(Modifier.height(14.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(
                    stringResource(RdR.string.rd_gizlilik_politikasi),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                    modifier = Modifier.clickable { legalDocumentKind = "privacy" },
                )
                Text(
                    if (isRestoring) stringResource(RdR.string.rd_geri_yukleniyor) else stringResource(RdR.string.rd_geri_yukle),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                    modifier = Modifier.clickable(enabled = !isRestoring) {
                        viewModel.restorePurchases(onRestored)
                    },
                )
                Text(
                    stringResource(RdR.string.rd_sartlar),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                    modifier = Modifier.clickable { legalDocumentKind = "terms" },
                )
            }
            Spacer(Modifier.height(24.dp))
        }
    }

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

private fun buildAnnotatedTitle(onyx: Color, green: Color, prefix: String, emphasis: String) = buildAnnotatedString {
    withStyle(SpanStyle(color = onyx)) { append(prefix) }
    withStyle(SpanStyle(color = green)) { append(emphasis) }
}

/** Depth-ordered target values for the deck effect — index 0 is front (full size, no tilt), 2 is
 * furthest back (smallest, most tilted, dimmest). */
private data class DeckDepth(val scale: Float, val rotation: Float, val offsetY: Dp, val alpha: Float, val z: Float)

private val deckDepths = listOf(
    DeckDepth(scale = 1f, rotation = 0f, offsetY = 0.dp, alpha = 1f, z = 3f),
    DeckDepth(scale = 0.94f, rotation = -6f, offsetY = 14.dp, alpha = 0.85f, z = 2f),
    DeckDepth(scale = 0.88f, rotation = 6f, offsetY = 26.dp, alpha = 0.6f, z = 1f),
)

@Composable
private fun PhoneDeck() {
    var frontIndex by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(2400L)
            frontIndex = (frontIndex + 1) % 3
        }
    }

    Box(modifier = Modifier.width(210.dp).height(446.dp), contentAlignment = Alignment.TopCenter) {
        val previewResources = listOf(
            R.drawable.ob_trial_preview_a,
            R.drawable.ob_trial_preview_b,
            R.drawable.ob_trial_preview_c,
        )
        for (cardIndex in 0 until 3) {
            val depthOrder = (cardIndex - frontIndex).mod(3)
            val depth = deckDepths[depthOrder]
            PhoneCard(depth, previewResources[cardIndex])
        }
    }
}

@Composable
private fun PhoneCard(depth: DeckDepth, previewResource: Int) {
    val scale by animateFloatAsState(depth.scale, animationSpec = tween(700), label = "deck-scale")
    val rotation by animateFloatAsState(depth.rotation, animationSpec = tween(700), label = "deck-rotation")
    val offsetY by animateDpAsState(depth.offsetY, animationSpec = tween(700), label = "deck-offset")
    val alpha by animateFloatAsState(depth.alpha, animationSpec = tween(700), label = "deck-alpha")

    Box(
        modifier = Modifier
            .zIndex(depth.z)
            .offset(y = offsetY)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                rotationZ = rotation
                this.alpha = alpha
            }
            .width(210.dp)
            .height(420.dp)
            .clip(RoundedCornerShape(38.dp))
            .background(Color(0xFF16191A)),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .width(190.dp)
                .height(400.dp)
                .clip(RoundedCornerShape(30.dp))
                .background(Color(0xFF0B0D0E)),
        ) {
            Image(
                painter = painterResource(previewResource),
                contentDescription = stringResource(RdR.string.rd_riskdetected_uygulama_onizlemesi),
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        Box(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 10.dp)
                .size(width = 76.dp, height = 20.dp)
                .clip(RoundedCornerShape(50))
                .background(Color.Black),
        )
    }
}
