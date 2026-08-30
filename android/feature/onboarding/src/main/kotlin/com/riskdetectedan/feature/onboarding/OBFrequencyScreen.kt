package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CenterFocusStrong
import androidx.compose.material.icons.filled.Domain
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Speed
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.graphics.vector.ImageVector
import com.riskdetectedan.core.data.onboarding.OnboardingFrequency
import com.riskdetectedan.core.designsystem.RdHeroTint
import com.riskdetectedan.core.designsystem.RdFontStyle

/** Port of OBFrequencyView.swift — single-select. */
@Composable
fun OBFrequencyScreen(
    selected: OnboardingFrequency?,
    onSelect: (OnboardingFrequency) -> Unit,
    onNext: () -> Unit,
    onBack: (() -> Unit)? = null,
) {
    OnboardingChoiceScreen(
        title = stringResource(RdR.string.rd_denetime_siklik_soru),
        items = OnboardingFrequency.entries,
        isSelected = { it == selected },
        label = { frequencyTitle(it) },
        itemSubtitle = { frequencySubtitle(it) },
        itemIcon = { frequencyIcon(it) },
        itemTitleStyle = RdFontStyle.Body,
        onToggle = onSelect,
        canContinue = selected != null,
        onContinue = onNext,
        step = 4,
        onBack = onBack,
        heroTint = RdHeroTint.Cool,
        heroIcon = Icons.Filled.CalendarMonth,
    )
}

@Composable
internal fun frequencyLabel(frequency: OnboardingFrequency): String {
    return "${frequencyTitle(frequency)}\n${frequencySubtitle(frequency)}"
}

@Composable
internal fun frequencyTitle(frequency: OnboardingFrequency): String = stringResource(
    when (frequency) {
        OnboardingFrequency.One -> RdR.string.rd_frequency_one_title
        OnboardingFrequency.TwoToFive -> RdR.string.rd_frequency_standard_title
        OnboardingFrequency.SixToFifteen -> RdR.string.rd_frequency_high_title
        OnboardingFrequency.FifteenPlus -> RdR.string.rd_frequency_intense_title
    },
)

@Composable
private fun frequencySubtitle(frequency: OnboardingFrequency): String = "— ${stringResource(
    when (frequency) {
        OnboardingFrequency.One -> RdR.string.rd_frequency_one_subtitle
        OnboardingFrequency.TwoToFive -> RdR.string.rd_frequency_standard_subtitle
        OnboardingFrequency.SixToFifteen -> RdR.string.rd_frequency_high_subtitle
        OnboardingFrequency.FifteenPlus -> RdR.string.rd_frequency_intense_subtitle
    },
)}"

private fun frequencyIcon(frequency: OnboardingFrequency): ImageVector = when (frequency) {
    OnboardingFrequency.One -> Icons.Filled.CenterFocusStrong
    OnboardingFrequency.TwoToFive -> Icons.Filled.Domain
    OnboardingFrequency.SixToFifteen -> Icons.Filled.Route
    OnboardingFrequency.FifteenPlus -> Icons.Filled.Speed
}
