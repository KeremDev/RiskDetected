package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.riskdetectedan.core.data.onboarding.OnboardingCertificate
import com.riskdetectedan.core.designsystem.RdHeroTint

/** Port of OBCertificateView.swift (Turkish branch — see OnboardingChoices.kt doc comment).
 * iOS's real leading view (`helmetItems`) is a bespoke Canvas-drawn hard-hat-with-letter badge
 * per class, not an SF Symbol — substituted with a Material icon per this pass's documented
 * simplification policy. A/B/C reuse iOS's real `hatColor` values (amber/blue/green) as the icon
 * tint — a real, cheap detail to keep even without the full badge illustration. iOS's screen
 * itself only offers A/B/C (`helmetItems` has 3 entries). Android intentionally presents that
 * same specialist-only set while keeping legacy enum values readable for existing profiles. */
@Composable
fun OBCertificateScreen(
    selected: OnboardingCertificate?,
    onSelect: (OnboardingCertificate) -> Unit,
    onNext: () -> Unit,
    onBack: (() -> Unit)? = null,
) {
    OnboardingChoiceScreen(
        title = stringResource(RdR.string.rd_sertifika_sinifi_soru),
        items = specialistCertificates,
        isSelected = { it == selected },
        label = { certificateLabel(it) },
        onToggle = onSelect,
        canContinue = selected != null,
        onContinue = onNext,
        step = 1,
        onBack = onBack,
        heroTint = RdHeroTint.Warm,
        heroIcon = Icons.Filled.WorkspacePremium,
        itemIcon = { certificateIcon(it) },
        itemIconTint = { certificateTint(it) },
    )
}

internal val specialistCertificates = listOf(
    OnboardingCertificate.A,
    OnboardingCertificate.B,
    OnboardingCertificate.C,
)

@Composable
internal fun certificateLabel(certificate: OnboardingCertificate): String = stringResource(
    when (certificate) {
        OnboardingCertificate.A -> RdR.string.rd_cert_a
        OnboardingCertificate.B -> RdR.string.rd_cert_b
        OnboardingCertificate.C -> RdR.string.rd_cert_c
        OnboardingCertificate.Doctor -> RdR.string.rd_cert_doctor
        OnboardingCertificate.OtherHealth -> RdR.string.rd_cert_health
    },
)

private fun certificateIcon(certificate: OnboardingCertificate): ImageVector = when (certificate) {
    OnboardingCertificate.A -> Icons.Filled.WorkspacePremium
    OnboardingCertificate.B -> Icons.Filled.Shield
    OnboardingCertificate.C -> Icons.Filled.Shield
    OnboardingCertificate.Doctor, OnboardingCertificate.OtherHealth -> Icons.Filled.Shield
}

/** A/B/C reuse OBCertificateView.swift's real `hatColor` values verbatim (#FFB300/#4F86E0/
 * #00B82E). Doctor/OtherHealth have no iOS source — left null (falls back to RdCard's default
 * selection-dependent onyx/fog coloring). */
private fun certificateTint(certificate: OnboardingCertificate): Color? = when (certificate) {
    OnboardingCertificate.A -> Color(0xFFFFB300)
    OnboardingCertificate.B -> Color(0xFF4F86E0)
    OnboardingCertificate.C -> Color(0xFF00B82E)
    OnboardingCertificate.Doctor, OnboardingCertificate.OtherHealth -> null
}
