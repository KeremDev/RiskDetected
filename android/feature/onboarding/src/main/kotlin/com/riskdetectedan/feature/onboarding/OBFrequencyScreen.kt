package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.riskdetectedan.core.data.onboarding.OnboardingFrequency
import com.riskdetectedan.core.designsystem.RdHeroTint

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
        label = { frequencyLabel(it) },
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
    val (title, subtitle) = when (frequency) {
        OnboardingFrequency.One -> RdR.string.rd_frequency_one_title to RdR.string.rd_frequency_one_subtitle
        OnboardingFrequency.TwoToFive -> RdR.string.rd_frequency_standard_title to RdR.string.rd_frequency_standard_subtitle
        OnboardingFrequency.SixToFifteen -> RdR.string.rd_frequency_high_title to RdR.string.rd_frequency_high_subtitle
        OnboardingFrequency.FifteenPlus -> RdR.string.rd_frequency_intense_title to RdR.string.rd_frequency_intense_subtitle
    }
    return stringResource(RdR.string.rd_frequency_format, stringResource(title), stringResource(subtitle))
}
