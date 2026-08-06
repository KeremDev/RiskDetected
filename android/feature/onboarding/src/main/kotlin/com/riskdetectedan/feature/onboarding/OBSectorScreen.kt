package com.riskdetectedan.feature.onboarding

import androidx.compose.runtime.Composable
import com.riskdetectedan.core.data.onboarding.OnboardingSector

/** Port of OBSectorView.swift — multi-select. */
@Composable
fun OBSectorScreen(
    selected: List<OnboardingSector>,
    onToggle: (OnboardingSector) -> Unit,
    onNext: () -> Unit,
) {
    OnboardingChoiceScreen(
        title = "Hangi sektörde çalışıyorsun?",
        subtitle = "Birden fazla seçebilirsin",
        items = OnboardingSector.entries,
        isSelected = { selected.contains(it) },
        label = { it.label },
        onToggle = onToggle,
        canContinue = selected.isNotEmpty(),
        onContinue = onNext,
    )
}
