package com.riskdetectedan.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Construction
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.FileCopy
import androidx.compose.material.icons.filled.FindInPage
import androidx.compose.material.icons.filled.GppMaybe
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.onboarding.OnboardingPersonalPlanContext
import com.riskdetectedan.core.data.onboarding.OnboardingPersonalPlanStep
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdFooter
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import kotlinx.coroutines.delay

/**
 * Port of OBPlanSummaryView.swift (2026-08-08 visual pass, Faz E). The segment-resolution model
 * (`OnboardingPersonalPlanContext.make`, `core:data`) is a real, faithful port of
 * `OnboardingPersonalPlan.swift` — same 5 segments, same headline/subtitle/step copy per segment,
 * not simplified. UI-layer simplifications, documented: the confetti burst (iOS's
 * `OBPersonalPlanConfettiView` — ~150 lines of `TimelineView`-driven particle physics) is NOT
 * ported, pure decoration; the top bar's real "HAZIR" done-state label is a small inline row here
 * rather than extending `RdTopBar` for a one-screen-only trailing-label variant. Timeline step
 * reveal-in-sequence IS ported (real `LaunchedEffect`+`delay` staged animation, same pattern as
 * PainPoint/Loading — not decorative, it paces the reader). iOS's real copy mentions "App Store"
 * for price verification — translated to "Google Play" per this repo's established platform-copy
 * convention (see DEC-10 / the trial-invite "App Store"->"Google Play" fix earlier this session).
 */
@Composable
fun OBPlanSummaryScreen(state: OnboardingUiState, onNext: () -> Unit) {
    val colors = RdTheme.colors
    val certificateLabel = state.certificate?.label ?: "A Sınıfı"
    val hazardsLabel = if (state.hazards.isEmpty()) "Çok Tehlikeli" else state.hazards.joinToString(" · ") { it.label }
    val primarySectorLabel = state.sectors.firstOrNull()?.label ?: "İnşaat"

    val context = remember(state.certificate, state.hazards, state.sectors, state.frequency) {
        OnboardingPersonalPlanContext.make(
            certificate = state.certificate,
            hazards = state.hazards,
            sectors = state.sectors,
            frequency = state.frequency,
            certificateLabel = certificateLabel,
            hazardsLabel = hazardsLabel,
            primarySectorLabel = primarySectorLabel,
        )
    }

    var revealedSteps by remember(context) { mutableStateOf(0) }
    LaunchedEffect(context) {
        revealedSteps = 0
        for (i in context.steps.indices) {
            delay(if (i == 0) 340L else 180L)
            revealedSteps = i + 1
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = RdSpacing.lg, vertical = RdSpacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(5.dp)
                    .clip(RoundedCornerShape(50))
                    .background(colors.green),
            )
            Spacer(Modifier.width(RdSpacing.sm))
            Text("HAZIR", style = RdFontStyle.Data.toTextStyle(), color = colors.greenDark)
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RdSpacing.xl),
        ) {
            PlanHeroCard(context = context)

            Spacer(Modifier.height(12.dp))
            TimelineCard(steps = context.steps, revealedCount = revealedSteps)

            Spacer(Modifier.height(12.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(colors.fog.copy(alpha = 0.62f))
                    .border(1.dp, colors.line, RoundedCornerShape(14.dp))
                    .padding(horizontal = 13.dp, vertical = 12.dp),
            ) {
                Icon(Icons.Filled.Lock, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(13.dp))
                Spacer(Modifier.width(9.dp))
                Text(
                    "Planını hesabına kaydedelim; fiyat ve uygun teklifleri Google Play'de doğrula.",
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                )
            }
            Spacer(Modifier.height(16.dp))
        }

        RdFooter {
            RdPrimaryButton(text = "Hesabımı Oluştur", onClick = onNext, style = RdButtonStyle.Onyx)
        }
    }
}

@Composable
private fun PlanHeroCard(context: OnboardingPersonalPlanContext) {
    val colors = RdTheme.colors
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(colors.white)
            .border(1.dp, colors.onyx.copy(alpha = 0.06f), RoundedCornerShape(18.dp))
            .padding(18.dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(colors.greenSoft.copy(alpha = 0.58f))
                    .border(1.dp, colors.green.copy(alpha = 0.16f), RoundedCornerShape(16.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(personalPlanIcon(context.heroIcon), contentDescription = null, tint = colors.onyx, modifier = Modifier.size(24.dp))
            }

            Spacer(Modifier.height(11.dp))
            Text(context.eyebrow, style = RdFontStyle.Footnote.toTextStyle(), color = colors.greenDark)
            Spacer(Modifier.height(3.dp))
            Text(context.headline, style = RdFontStyle.Title2.toTextStyle(), color = colors.onyx, textAlign = TextAlign.Center)
            Spacer(Modifier.height(3.dp))
            Text(context.subtitle, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)
        }

        Column(
            modifier = Modifier.align(Alignment.TopEnd),
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            context.chips.forEach { chip ->
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(topStart = 10.dp, bottomStart = 10.dp))
                        .background(androidx.compose.ui.graphics.Color(0xFFFFF6D8))
                        .border(1.dp, colors.onyx.copy(alpha = 0.08f), RoundedCornerShape(topStart = 10.dp, bottomStart = 10.dp))
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                ) {
                    Text(chip, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                }
            }
        }
    }
}

@Composable
private fun TimelineCard(steps: List<OnboardingPersonalPlanStep>, revealedCount: Int) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(colors.white)
            .border(1.dp, colors.onyx.copy(alpha = 0.06f), RoundedCornerShape(18.dp))
            .padding(horizontal = 13.dp, vertical = 12.dp),
    ) {
        steps.forEachIndexed { index, step ->
            if (index < revealedCount) {
                Row(verticalAlignment = Alignment.Top) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(
                            modifier = Modifier.size(30.dp).clip(CircleShape).background(colors.greenSoft.copy(alpha = 0.54f)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(personalPlanIcon(step.icon), contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(15.dp))
                        }
                        if (index != steps.lastIndex) {
                            Box(modifier = Modifier.width(2.dp).height(34.dp).background(colors.line))
                        }
                    }
                    Spacer(Modifier.width(11.dp))
                    Column(modifier = Modifier.padding(top = if (index == 0) 3.dp else 0.dp)) {
                        Text(step.title, style = RdFontStyle.Footnote.toTextStyle(), color = colors.onyx)
                        Text(step.subtitle, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                    }
                }
            }
        }
    }
}

/** SF Symbol -> closest Material Icons Extended equivalent, same mapping-not-literal-port policy
 * as [sectorIcon]/[hazardIcon]/[certificateIcon]. */
private fun personalPlanIcon(key: String): ImageVector = when (key) {
    "bolt.fill" -> Icons.Filled.Bolt
    "cross.case.fill" -> Icons.Filled.LocalHospital
    "hammer.fill" -> Icons.Filled.Construction
    "exclamationmark.shield.fill" -> Icons.Filled.GppMaybe
    "building.2.fill" -> Icons.Filled.Business
    "camera.viewfinder" -> Icons.Filled.CameraAlt
    "exclamationmark.triangle.fill" -> Icons.Filled.Warning
    "paperplane.fill" -> Icons.Filled.Send
    "person.2.fill" -> Icons.Filled.Groups
    "doc.richtext.fill" -> Icons.Filled.Description
    "square.and.arrow.up.fill" -> Icons.Filled.IosShare
    "shield.lefthalf.filled" -> Icons.Filled.Shield
    "doc.text.magnifyingglass" -> Icons.Filled.FindInPage
    "gauge" -> Icons.Filled.Speed
    "checklist" -> Icons.Filled.Checklist
    "doc.on.doc.fill" -> Icons.Filled.FileCopy
    "clock.fill" -> Icons.Filled.Schedule
    else -> Icons.Filled.Description
}
