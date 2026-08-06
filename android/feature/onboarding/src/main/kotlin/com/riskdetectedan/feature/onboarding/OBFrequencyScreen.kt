package com.riskdetectedan.feature.onboarding

import androidx.compose.runtime.Composable
import com.riskdetectedan.core.data.onboarding.OnboardingFrequency

/** Port of OBFrequencyView.swift — single-select. */
@Composable
fun OBFrequencyScreen(
    selected: OnboardingFrequency?,
    onSelect: (OnboardingFrequency) -> Unit,
    onNext: () -> Unit,
) {
    OnboardingChoiceScreen(
        title = "Ne sıklıkla saha denetimi yapıyorsun?",
        items = OnboardingFrequency.entries,
        isSelected = { it == selected },
        label = { "${it.title} — ${it.sub}" },
        onToggle = onSelect,
        canContinue = selected != null,
        onContinue = onNext,
    )
}
