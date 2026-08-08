package com.riskdetectedan.feature.onboarding

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.runtime.Composable
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
        title = "Ne sıklıkla saha denetimi yapıyorsun?",
        items = OnboardingFrequency.entries,
        isSelected = { it == selected },
        label = { "${it.title} — ${it.sub}" },
        onToggle = onSelect,
        canContinue = selected != null,
        onContinue = onNext,
        step = 4,
        onBack = onBack,
        heroTint = RdHeroTint.Cool,
        heroIcon = Icons.Filled.CalendarMonth,
    )
}
