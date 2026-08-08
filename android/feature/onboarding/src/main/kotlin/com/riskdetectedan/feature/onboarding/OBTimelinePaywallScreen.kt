package com.riskdetectedan.feature.onboarding

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
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
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
 * No live RevenueCat packages/pricing here — deliberate, not a leftover gap: this onboarding
 * screen never fetched live offerings even before this visual pass, and the *real* post-onboarding
 * Paywall screen (feature #20, `feature:paywall`) already owns the live package-fetch+purchase
 * flow with its own loading/error states. Gating this screen's CTA on a price load that never
 * happens would just soft-lock it forever, so the price line and CTA are static Google Play
 * copy instead of iOS's dynamic `priceLine`/`primaryButtonTitle` (which react to a real
 * `SubscriptionOfferingsLoadState`). "Devam et"/"Şimdilik ücretsiz devam et" both end onboarding —
 * there's no purchase outcome to branch on here, matching this screen's pre-existing behavior.
 * Not ported: the processing overlay (App Store purchase-in-flight modal — no purchase flow to
 * show it for) and the timeline connector's flowing-gradient animation (decorative, static
 * connector line kept instead).
 */
@Composable
fun OBTimelinePaywallScreen(onDismiss: () -> Unit) {
    val colors = RdTheme.colors
    var selectedPlan by remember { mutableStateOf(TimelinePlan.Yearly) }

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
                onClick = onDismiss,
                style = RdButtonStyle.Onyx,
            )

            Spacer(Modifier.height(8.dp))
            TextButton(onClick = onDismiss) {
                Text("Şimdilik ücretsiz devam et", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }

            Spacer(Modifier.height(6.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Geri yükle", style = RdFontStyle.Caption.toTextStyle(), color = colors.black)
                Box(modifier = Modifier.size(3.dp).clip(CircleShape).background(colors.slate.copy(alpha = 0.35f)))
                Text("Kullanım Şartları", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                Box(modifier = Modifier.size(3.dp).clip(CircleShape).background(colors.slate.copy(alpha = 0.35f)))
                Text("Gizlilik Politikası", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }

            Spacer(Modifier.height(6.dp))
            Text(
                if (selectedPlan == TimelinePlan.Yearly) {
                    "Yıllık plan · fiyat ve varsa uygun teklif Google Play'de gösterilir"
                } else {
                    "Aylık plan · istediğin zaman iptal · fiyat Google Play'de gösterilir"
                },
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(6.dp))
        }
    }
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
                Box(
                    modifier = Modifier
                        .width(4.dp)
                        .height(if (features.isNotEmpty()) (102 + maxOf(0, features.size - 3) * 19).dp else 50.dp)
                        .clip(RoundedCornerShape(50))
                        .background(accent.copy(alpha = 0.18f)),
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

