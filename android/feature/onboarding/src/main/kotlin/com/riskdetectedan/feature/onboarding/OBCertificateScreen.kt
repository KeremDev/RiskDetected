package com.riskdetectedan.feature.onboarding

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.runtime.Composable
import com.riskdetectedan.core.data.onboarding.OnboardingCertificate
import com.riskdetectedan.core.designsystem.RdHeroTint

/** Port of OBCertificateView.swift (Turkish branch — see OnboardingChoices.kt doc comment). */
@Composable
fun OBCertificateScreen(
    selected: OnboardingCertificate?,
    onSelect: (OnboardingCertificate) -> Unit,
    onNext: () -> Unit,
    onBack: (() -> Unit)? = null,
) {
    OnboardingChoiceScreen(
        title = "Sertifika sınıfın nedir?",
        items = OnboardingCertificate.entries,
        isSelected = { it == selected },
        label = { it.label },
        onToggle = onSelect,
        canContinue = selected != null,
        onContinue = onNext,
        step = 1,
        onBack = onBack,
        heroTint = RdHeroTint.Warm,
        heroIcon = Icons.Filled.WorkspacePremium,
    )
}
