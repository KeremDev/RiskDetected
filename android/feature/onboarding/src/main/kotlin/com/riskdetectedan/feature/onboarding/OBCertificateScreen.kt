package com.riskdetectedan.feature.onboarding

import androidx.compose.runtime.Composable
import com.riskdetectedan.core.data.onboarding.OnboardingCertificate

/** Port of OBCertificateView.swift (Turkish branch — see OnboardingChoices.kt doc comment). */
@Composable
fun OBCertificateScreen(
    selected: OnboardingCertificate?,
    onSelect: (OnboardingCertificate) -> Unit,
    onNext: () -> Unit,
) {
    OnboardingChoiceScreen(
        title = "Sertifika sınıfın nedir?",
        items = OnboardingCertificate.entries,
        isSelected = { it == selected },
        label = { it.label },
        onToggle = onSelect,
        canContinue = selected != null,
        onContinue = onNext,
    )
}
