package com.riskdetectedan.feature.onboarding

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.billing.BillingPackage
import com.riskdetectedan.core.data.legal.LegalDocumentAssets
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdLegalDocument
import com.riskdetectedan.core.designsystem.RdLegalDocumentSheet
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

private enum class TimelinePlan { Yearly, Monthly }

private data class TimelineFeature(val title: String, val badge: String? = null)

private val plusFeatures = listOf(
    TimelineFeature("Detaylı Analiz"),
    TimelineFeature("Risk Analizi (Fine-Kinney ve 5*5)"),
    TimelineFeature("PDF/Excel Rapor"),
    TimelineFeature("Firma Yönetimi"),
    TimelineFeature("Çoklu Fotoğraf Analizi", badge = "Yeni"),
    TimelineFeature("Sektör Bazlı Analiz"),
)

/**
 * Port of OBTimelinePaywallView.swift's *slot* in the onboarding flow (step 11) — real visual
 * structure (plan toggle, timeline card with per-step icon/accent/day/detail + the yearly plan's
 * feature checklist, bottom CTA bar, dismiss button), same real Turkish copy per step. Stays a
 * local composable rather than reusing `feature:paywall`'s PaywallScreen, same module-boundary
 * reasoning as before this pass (`feature:onboarding` doesn't depend on `feature:paywall`).
 *
 * Real RevenueCat purchase now, via [OBTimelinePaywallViewModel]/[com.riskdetectedan.core.data.billing.BillingRepository]
 * (previously the real gap this doc comment used to justify away: this screen never fetched live
 * offerings, so "Devam et" always just skipped past a fake plans page). While packages are
 * loading or unavailable the price line/CTA fall back to the pre-existing static Google Play
 * copy — same honest degrade `feature:paywall`'s empty-packages state uses, not a soft-lock.
 * "Devam et" now attempts a real purchase for the selected plan and only continues onboarding on
 * success (or on the free "Şimdilik ücretsiz devam et" tap, which still always continues).
 * Not ported: the processing overlay's own visual chrome (borrowed as a disabled/"İşleniyor..."
 * button state instead). The timeline connector's flowing-gradient animation now IS real
 * (2026-08-09 animation pass — was a static translucent line before): a brighter highlight band
 * travels down each connector on its own `infiniteTransition`, clipped to the connector's own
 * rounded shape so it reads as light flowing through the line, not a separate overlay.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OBTimelinePaywallScreen(onDismiss: () -> Unit, viewModel: OBTimelinePaywallViewModel = hiltViewModel()) {
    val colors = RdTheme.colors
    var selectedPlan by remember { mutableStateOf(TimelinePlan.Yearly) }
    var legalDocumentKind by remember { mutableStateOf<String?>(null) }
    val state by viewModel.state.collectAsState()
    val isPurchasing by viewModel.isPurchasing.collectAsState()
    val purchaseError by viewModel.purchaseError.collectAsState()
    val activity = LocalContext.current.findActivity()

    val loaded = state as? OBTimelinePaywallUiState.Loaded
    val selectedPackage = loaded?.packages?.let {
        if (selectedPlan == TimelinePlan.Yearly) it.yearly else it.monthly
    }

    Box(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RdSpacing.lg),
        ) {
            Spacer(Modifier.height(48.dp))
            Text(
                if (selectedPlan == TimelinePlan.Yearly) "Yıllık Plan Nasıl Çalışır" else "Plus Aboneliğin Gücünü Hemen Kullanın",
                style = RdFontStyle.Title1.toTextStyle(),
                color = colors.black,
                modifier = Modifier.padding(end = 52.dp),
            )

            Spacer(Modifier.height(18.dp))
            PlanToggle(selectedPlan = selectedPlan, onSelect = { selectedPlan = it })

            Spacer(Modifier.height(15.dp))
            TimelineCard(selectedPlan)

            Spacer(Modifier.height(160.dp))
        }

        IconButton(
            onClick = onDismiss,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 52.dp, end = 18.dp)
                .size(38.dp)
                .clip(CircleShape)
                .background(colors.white.copy(alpha = 0.94f))
                .border(1.dp, colors.line, CircleShape),
        ) {
            Icon(Icons.Filled.Close, contentDescription = "Kapat", tint = colors.black, modifier = Modifier.size(15.dp))
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(colors.paper)
                .padding(horizontal = RdSpacing.lg)
                .padding(top = 12.dp, bottom = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            RdPrimaryButton(
                text = if (selectedPlan == TimelinePlan.Yearly) "Devam et" else "Aboneliği başlat",
                onClick = {
                    val activityRef = activity
                    if (selectedPackage != null && activityRef != null) {
                        viewModel.purchase(activityRef, selectedPackage, onPurchased = onDismiss)
                    } else {
                        // Unavailable/loading fallback — no real package to purchase yet,
                        // matches this screen's pre-existing behavior.
                        onDismiss()
                    }
                },
                enabled = !isPurchasing,
                loading = isPurchasing,
                loadingLabel = "İşleniyor...",
                style = RdButtonStyle.Onyx,
            )

            Spacer(Modifier.height(8.dp))
            TextButton(onClick = onDismiss, enabled = !isPurchasing) {
                Text("Şimdilik ücretsiz devam et", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }

            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Geri yükle", style = RdFontStyle.Caption.toTextStyle(), color = colors.black)
                Box(modifier = Modifier.size(3.dp).clip(CircleShape).background(colors.slate.copy(alpha = 0.35f)))
                Text(
                    "Kullanım Şartları",
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                    modifier = Modifier.clickable { legalDocumentKind = "terms" },
                )
                Box(modifier = Modifier.size(3.dp).clip(CircleShape).background(colors.slate.copy(alpha = 0.35f)))
                Text(
                    "Gizlilik Politikası",
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                    modifier = Modifier.clickable { legalDocumentKind = "privacy" },
                )
            }

            Spacer(Modifier.height(6.dp))
            Text(
                priceLine(selectedPlan, selectedPackage),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(6.dp))
        }
    }

    purchaseError?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearPurchaseError,
            title = { Text(error.title) },
            text = {
                Column {
                    Text(error.message)
                    if (error.action.isNotEmpty()) Text(error.action)
                    Text(error.supportID)
                }
            },
            confirmButton = {
                TextButton(onClick = viewModel::clearPurchaseError) { Text("Tamam") }
            },
        )
    }

    if (legalDocumentKind != null) {
        val legalContext = LocalContext.current
        var legalDocuments by remember { mutableStateOf<List<RdLegalDocument>>(emptyList()) }
        LaunchedEffect(Unit) {
            legalDocuments = LegalDocumentAssets.load(legalContext)
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

/** Real price when the package loaded, otherwise the pre-existing static Google Play copy
 * (loading, signed-out, offerings-fetch-failed, or no Plus package configured on this offering
 * yet — all fold into the same honest fallback). */
private fun priceLine(plan: TimelinePlan, billingPackage: BillingPackage?): String = when {
    plan == TimelinePlan.Yearly && billingPackage != null ->
        "Yıllık plan · ${billingPackage.formattedPrice}/yıl"
    plan == TimelinePlan.Yearly ->
        "Yıllık plan · fiyat ve varsa uygun teklif Google Play'de gösterilir"
    billingPackage != null ->
        "Aylık plan · istediğin zaman iptal · ${billingPackage.formattedPrice}/ay"
    else ->
        "Aylık plan · istediğin zaman iptal · fiyat Google Play'de gösterilir"
}

/** RevenueCat's `PurchaseParams.Builder` needs an Activity (to launch Google Play's billing
 * sheet) — `LocalContext.current` in a Composable is often an Activity already but isn't
 * guaranteed to be one (can be wrapped), so unwrap defensively rather than force-casting. Same
 * pattern as `feature:paywall`'s `PaywallScreen.findActivity`; kept local rather than shared
 * since neither module depends on the other. */
private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

@Composable
private fun PlanToggle(selectedPlan: TimelinePlan, onSelect: (TimelinePlan) -> Unit) {
    val colors = RdTheme.colors
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .width(210.dp)
                .clip(CircleShape)
                .background(colors.fog)
                .border(1.dp, colors.line, CircleShape)
                .padding(4.dp),
        ) {
            PlanPill("Yıllık", selected = selectedPlan == TimelinePlan.Yearly, onClick = { onSelect(TimelinePlan.Yearly) }, modifier = Modifier.weight(1f))
            PlanPill("Aylık", selected = selectedPlan == TimelinePlan.Monthly, onClick = { onSelect(TimelinePlan.Monthly) }, modifier = Modifier.weight(1f))
        }
        if (selectedPlan == TimelinePlan.Yearly) {
            Spacer(Modifier.height(7.dp))
            Text("%17 İndirim", style = RdFontStyle.Caption.toTextStyle(), color = colors.green)
        }
    }
}

@Composable
private fun PlanPill(label: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    Box(
        modifier = modifier
            .height(25.dp)
            .clip(CircleShape)
            .background(if (selected) colors.white else Color.Transparent)
            .border(1.dp, if (selected) colors.black.copy(alpha = 0.12f) else Color.Transparent, CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = RdFontStyle.Caption.toTextStyle(), color = if (selected) colors.black else colors.slate)
    }
}

@Composable
private fun TimelineCard(plan: TimelinePlan) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(24.dp))
            .padding(14.dp),
    ) {
        if (plan == TimelinePlan.Yearly) {
            TimelineStep(Icons.Filled.Lock, colors.green, "Bugün", "Yıllık Plus özelliklerini ve Google Play fiyatını incele.", plusFeatures, isLast = false)
            TimelineStep(Icons.Filled.Notifications, Color(0xFFF0A400), "5 gün", "Denemen bitmeden sana hatırlatma göndeririz.", emptyList(), isLast = false)
            TimelineStep(Icons.Filled.WorkspacePremium, Color(0xFFF0A400), "7 gün · Yenileme", "Devam edersen yıllık plan başlar; istediğin zaman iptal edebilirsin.", emptyList(), isLast = true)
        } else {
            TimelineStep(Icons.Filled.Lock, Color(0xFFF0A400), "Bugün", "Tüm özellikler hemen aktif olur, ödeme başlar.", plusFeatures, isLast = false)
            TimelineStep(Icons.Filled.CalendarMonth, colors.green, "Her ay", "Aylık plan otomatik yenilenir. İstediğin zaman iptal edebilirsin.", emptyList(), isLast = true)
        }
    }
}

/** Real port of the timeline connector's flowing-gradient — base translucent line + a brighter
 * band that travels top-to-bottom on a loop, clipped to the same rounded shape as the line so it
 * reads as light moving through the connector, not a separate floating overlay. */
@Composable
private fun FlowingConnector(accent: Color, height: Dp) {
    BoxWithConstraints(
        modifier = Modifier
            .width(4.dp)
            .height(height)
            .clip(RoundedCornerShape(50))
            .background(accent.copy(alpha = 0.18f)),
    ) {
        val heightPx = constraints.maxHeight.toFloat()
        val infiniteTransition = rememberInfiniteTransition(label = "connector-flow")
        val flow by infiniteTransition.animateFloat(
            initialValue = -0.4f,
            targetValue = 1.4f,
            animationSpec = infiniteRepeatable(tween(1600, easing = LinearEasing), repeatMode = RepeatMode.Restart),
            label = "connector-flow-offset",
        )
        Box(
            modifier = Modifier
                .width(4.dp)
                .height(28.dp)
                .graphicsLayer { translationY = heightPx * flow }
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, accent.copy(alpha = 0.9f), Color.Transparent),
                    ),
                ),
        )
    }
}

@Composable
private fun TimelineStep(
    icon: ImageVector,
    accent: Color,
    day: String,
    detail: String,
    features: List<TimelineFeature>,
    isLast: Boolean,
) {
    val colors = RdTheme.colors
    Row(verticalAlignment = Alignment.Top) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(accent.copy(alpha = 0.12f))
                    .border(1.6.dp, accent, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(16.dp))
            }
            if (!isLast) {
                FlowingConnector(
                    accent = accent,
                    height = if (features.isNotEmpty()) (102 + maxOf(0, features.size - 3) * 19).dp else 50.dp,
                )
            }
        }
        Spacer(Modifier.width(13.dp))
        Column(modifier = Modifier.padding(top = 4.dp, bottom = if (isLast) 0.dp else 10.dp)) {
            Text(day, style = RdFontStyle.Callout.toTextStyle(), color = colors.onyx)
            if (detail.isNotEmpty()) {
                Spacer(Modifier.height(2.dp))
                Text(detail, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }
            if (features.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Column {
                    features.forEach { feature ->
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 2.dp)) {
                            Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = colors.green, modifier = Modifier.size(13.dp))
                            Spacer(Modifier.width(6.dp))
                            Text(feature.title, style = RdFontStyle.Caption.toTextStyle(), color = colors.black)
                            if (feature.badge != null) {
                                Spacer(Modifier.width(5.dp))
                                Box(
                                    modifier = Modifier
                                        .clip(CircleShape)
                                        .background(colors.green.copy(alpha = 0.10f))
                                        .border(0.8.dp, colors.green.copy(alpha = 0.20f), CircleShape)
                                        .wrapContentWidth()
                                        .padding(horizontal = 5.dp, vertical = 1.5.dp),
                                ) {
                                    Text(feature.badge, style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 8.sp), color = colors.green)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

