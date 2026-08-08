package com.riskdetectedan.feature.onboarding

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.runtime.Composable
import com.riskdetectedan.core.data.onboarding.OnboardingHazardClass
import com.riskdetectedan.core.designsystem.RdHeroTint

/** Port of OBHazardClassView.swift (Turkish branch) — multi-select. */
@Composable
fun OBHazardClassScreen(
    selected: Set<OnboardingHazardClass>,
    onToggle: (OnboardingHazardClass) -> Unit,
    onNext: () -> Unit,
    onBack: (() -> Unit)? = null,
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
        multi = true,
        step = 2,
        onBack = onBack,
        heroTint = RdHeroTint.Warm,
        heroIcon = Icons.Filled.Warning,
        selectionCounterSuffix = "tehlike sınıfı seçildi",
    )
}
