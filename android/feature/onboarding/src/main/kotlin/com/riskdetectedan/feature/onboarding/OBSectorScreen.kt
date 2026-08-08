package com.riskdetectedan.feature.onboarding

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocationCity
import androidx.compose.runtime.Composable
import com.riskdetectedan.core.data.onboarding.OnboardingSector
import com.riskdetectedan.core.designsystem.RdHeroTint

/** Port of OBSectorView.swift — multi-select, the one screen iOS gives a bespoke 2-column grid
 * picker instead of the shared list-row card (see OnboardingChoiceList.kt's doc comment). */
@Composable
fun OBSectorScreen(
    selected: List<OnboardingSector>,
    onToggle: (OnboardingSector) -> Unit,
    onNext: () -> Unit,
    onBack: (() -> Unit)? = null,
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
        multi = true,
        layout = RdPickerLayout.Grid,
        step = 3,
        onBack = onBack,
        heroTint = RdHeroTint.Cool,
        heroIcon = Icons.Filled.LocationCity,
        selectionCounterSuffix = "sektör seçildi",
    )
}
