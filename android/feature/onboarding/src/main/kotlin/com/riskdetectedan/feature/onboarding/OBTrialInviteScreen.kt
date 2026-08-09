package com.riskdetectedan.feature.onboarding

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.platform.LocalContext
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
 * "Gizlilik Politikası"/"Şartlar" now open the real [RdLegalDocumentSheet]
 * (2026-08-09 gap sweep — were static, non-interactive text before). "Geri Yükle" stays
 * static/non-interactive — a real restore-purchases call already exists on the post-onboarding
 * Paywall screen (feature #20), wiring it here too is a separate, deliberate follow-up, not an
 * oversight of this pass.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OBTrialInviteScreen(onContinue: () -> Unit) {
    val colors = RdTheme.colors
    val context = LocalContext.current
    var legalDocumentKind by remember { mutableStateOf<String?>(null) }
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
                buildAnnotatedTitle(colors.onyx, colors.green),
                style = RdFontStyle.Title1.toTextStyle(),
                textAlign = TextAlign.Center,
            )
            Text("birlikte seçelim", style = RdFontStyle.Title1.toTextStyle(), color = colors.onyx, textAlign = TextAlign.Center)

            Spacer(Modifier.height(24.dp))
            PhoneDeck()

            Spacer(Modifier.height(28.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = colors.onyx, modifier = Modifier.size(15.dp))
                Spacer(Modifier.width(8.dp))
                Text(
                    "Fiyat ve uygun teklifler Google Play'de gösterilir",
                    style = RdFontStyle.Callout.toTextStyle(),
                    color = colors.onyx,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            Spacer(Modifier.height(14.dp))
            RdPrimaryButton(text = "Plan seçeneklerini gör", onClick = onContinue, style = RdButtonStyle.Onyx)

            Spacer(Modifier.height(10.dp))
            Text("Taahhüt yok, istediğin zaman iptal.", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)

            Spacer(Modifier.height(14.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text(
                    "Gizlilik Politikası",
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                    modifier = Modifier.clickable { legalDocumentKind = "privacy" },
                )
                Text("Geri Yükle", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                Text(
                    "Şartlar",
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
}

private fun buildAnnotatedTitle(onyx: Color, green: Color) = buildAnnotatedString {
    withStyle(SpanStyle(color = onyx)) { append("Sana uygun ") }
    withStyle(SpanStyle(color = green)) { append("planı") }
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
        for (cardIndex in 0 until 3) {
            val depthOrder = (cardIndex - frontIndex).mod(3)
            val depth = deckDepths[depthOrder]
            PhoneCard(depth)
        }
    }
}

@Composable
private fun PhoneCard(depth: DeckDepth) {
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
            Column(
                modifier = Modifier.fillMaxSize().padding(vertical = 24.dp, horizontal = 14.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(Icons.Filled.Shield, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
                Spacer(Modifier.weight(1f))
                MiniRiskRow(Color(0xFFB42318), "Yüksekte çalışma", "KRİTİK")
                Spacer(Modifier.height(8.dp))
                MiniRiskRow(Color(0xFFC76A00), "KKD eksikliği", "YÜKSEK")
                Spacer(Modifier.height(8.dp))
                MiniRiskRow(Color(0xFFD4A106), "Aydınlatma", "ORTA")
                Spacer(Modifier.weight(1f))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Verified, contentDescription = null, tint = Color(0xFF00B82E), modifier = Modifier.size(15.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Rapor hazır", style = RdFontStyle.Footnote.toTextStyle().copy(fontSize = 12.sp), color = Color(0xFF00B82E))
                }
            }
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

@Composable
private fun MiniRiskRow(dotColor: Color, label: String, badge: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Color.White.copy(alpha = 0.04f))
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(dotColor))
        Spacer(Modifier.width(10.dp))
        Text(label, style = RdFontStyle.Caption.toTextStyle(), color = Color.White, modifier = Modifier.weight(1f))
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                .background(dotColor.copy(alpha = 0.18f))
                .padding(horizontal = 6.dp, vertical = 2.dp),
        ) {
            Text(badge, style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 9.sp), color = dotColor, fontWeight = FontWeight.Bold)
        }
    }
}
