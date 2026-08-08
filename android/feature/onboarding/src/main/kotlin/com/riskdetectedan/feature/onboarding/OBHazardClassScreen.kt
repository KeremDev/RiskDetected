package com.riskdetectedan.feature.onboarding

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.riskdetectedan.core.data.onboarding.OnboardingHazardClass
import com.riskdetectedan.core.designsystem.RdColors
import com.riskdetectedan.core.designsystem.RdHeroTint
import com.riskdetectedan.core.designsystem.RdTheme

/** Port of OBHazardClassView.swift (Turkish branch) — multi-select. Per-item icon/subtitle/tint
 * mirror the screen's local `items` tuple array and `hazardIcon()` helper exactly: unlike every
 * other picker, the icon box stays severity-tinted (rdCritical/rdHigh/rdLow + their Bg variants)
 * regardless of selection state — that's what [OnboardingChoiceScreen]'s `itemIconTint`/
 * `itemIconBackground` overrides exist for. */
@Composable
fun OBHazardClassScreen(
    selected: Set<OnboardingHazardClass>,
    onToggle: (OnboardingHazardClass) -> Unit,
    onNext: () -> Unit,
    onBack: (() -> Unit)? = null,
) {
    val colors = RdTheme.colors
    OnboardingChoiceScreen(
        title = "Hangi tehlike sınıfında çalışıyorsun?",
        subtitle = "Birden fazla seçebilirsin",
        items = OnboardingHazardClass.entries,
        isSelected = { selected.contains(it) },
        label = { it.label },
        onToggle = onToggle,
        canContinue = selected.isNotEmpty(),
        onContinue = onNext,
        multi = true,
        step = 2,
        onBack = onBack,
        heroTint = RdHeroTint.Warm,
        heroIcon = Icons.Filled.Warning,
        selectionCounterSuffix = "tehlike sınıfı seçildi",
        itemIcon = { hazardIcon(it) },
        itemSubtitle = { hazardSubtitle(it) },
        itemIconTint = { hazardTint(it, colors) },
        itemIconBackground = { hazardBackground(it, colors) },
    )
}

/** Mirrors the screen's local `items` array: `exclamationmark.triangle.fill`->Warning (exact
 * shape match), `exclamationmark.circle.fill`->Error (filled circle-exclamation),
 * `info.circle.fill`->Info. */
private fun hazardIcon(hazard: OnboardingHazardClass): ImageVector = when (hazard) {
    OnboardingHazardClass.Critical -> Icons.Filled.Warning
    OnboardingHazardClass.High -> Icons.Filled.Error
    OnboardingHazardClass.Low -> Icons.Filled.Info
}

/** Mirrors the screen's local `items` array sub text verbatim. */
private fun hazardSubtitle(hazard: OnboardingHazardClass): String = when (hazard) {
    OnboardingHazardClass.Critical -> "Petrokimya, maden, inşaat, fabrika vb."
    OnboardingHazardClass.High -> "İmalat, gıda, sağlık vb."
    OnboardingHazardClass.Low -> "Ofis, perakende, hizmet vb."
}

/** Mirrors OBHazardClass.color (rdCritical/rdHigh/rdLow). */
private fun hazardTint(hazard: OnboardingHazardClass, colors: RdColors): Color =
    when (hazard) {
        OnboardingHazardClass.Critical -> colors.critical
        OnboardingHazardClass.High -> colors.high
        OnboardingHazardClass.Low -> colors.low
    }

/** Mirrors OBHazardClass.bgColor (rdCriticalBg/rdHighBg/rdLowBg). */
private fun hazardBackground(hazard: OnboardingHazardClass, colors: RdColors): Color =
    when (hazard) {
        OnboardingHazardClass.Critical -> colors.criticalBg
        OnboardingHazardClass.High -> colors.highBg
        OnboardingHazardClass.Low -> colors.lowBg
    }
