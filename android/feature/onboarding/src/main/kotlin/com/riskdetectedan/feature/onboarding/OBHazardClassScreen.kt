package com.riskdetectedan.feature.onboarding

import androidx.compose.runtime.Composable
import com.riskdetectedan.core.data.onboarding.OnboardingHazardClass

/** Port of OBHazardClassView.swift (Turkish branch) — multi-select. */
@Composable
fun OBHazardClassScreen(
    selected: Set<OnboardingHazardClass>,
    onToggle: (OnboardingHazardClass) -> Unit,
    onNext: () -> Unit,
) {
    OnboardingChoiceScreen(
        title = "Hangi tehlike sınıfında çalışıyorsun?",
        subtitle = "Birden fazla seçebilirsin",
        items = OnboardingHazardClass.entries,
        isSelected = { selected.contains(it) },
        label = { it.label },
        onToggle = onToggle,
        canContinue = selected.isNotEmpty(),
        onContinue = onNext,
    )
}
