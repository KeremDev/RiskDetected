package com.riskdetectedan.feature.onboarding

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import com.riskdetectedan.core.data.onboarding.OnboardingSafetyProfile
import com.riskdetectedan.core.designsystem.R as RdR
import com.riskdetectedan.core.designsystem.RdHeroTint

/** iOS English onboarding step 3: explicit terminology/jurisdiction profile selection. */
@Composable
fun OBSafetyProfileScreen(
    selected: OnboardingSafetyProfile?,
    onSelect: (OnboardingSafetyProfile) -> Unit,
    onNext: () -> Unit,
    onBack: () -> Unit,
) {
    OnboardingChoiceScreen(
        title = stringResource(RdR.string.rd_safety_profile_title),
        subtitle = stringResource(RdR.string.rd_safety_profile_body),
        items = OnboardingSafetyProfile.entries,
        isSelected = { it == selected },
        label = { safetyProfileLabel(it) },
        itemSubtitle = { safetyProfileSubtitle(it) },
        itemIcon = { safetyProfileIcon(it) },
        onToggle = onSelect,
        canContinue = selected != null,
        onContinue = onNext,
        step = 3,
        totalSteps = 5,
        onBack = onBack,
        heroTint = RdHeroTint.Cool,
        heroIcon = Icons.Filled.Language,
        footerNote = stringResource(RdR.string.rd_safety_profile_footer),
    )
}

@Composable
internal fun safetyProfileLabel(profile: OnboardingSafetyProfile): String = stringResource(
    when (profile) {
        OnboardingSafetyProfile.International -> RdR.string.rd_safety_profile_international
        OnboardingSafetyProfile.UnitedKingdom -> RdR.string.rd_safety_profile_gb
        OnboardingSafetyProfile.UnitedStates -> RdR.string.rd_safety_profile_us
        OnboardingSafetyProfile.Australia -> RdR.string.rd_safety_profile_au
        OnboardingSafetyProfile.Canada -> RdR.string.rd_safety_profile_ca
    },
)

@Composable
private fun safetyProfileSubtitle(profile: OnboardingSafetyProfile): String = stringResource(
    when (profile) {
        OnboardingSafetyProfile.International -> RdR.string.rd_safety_profile_international_subtitle
        OnboardingSafetyProfile.UnitedKingdom -> RdR.string.rd_safety_profile_gb_subtitle
        OnboardingSafetyProfile.UnitedStates -> RdR.string.rd_safety_profile_us_subtitle
        OnboardingSafetyProfile.Australia -> RdR.string.rd_safety_profile_au_subtitle
        OnboardingSafetyProfile.Canada -> RdR.string.rd_safety_profile_ca_subtitle
    },
)

private fun safetyProfileIcon(profile: OnboardingSafetyProfile): ImageVector = when (profile) {
    OnboardingSafetyProfile.International -> Icons.Filled.Public
    OnboardingSafetyProfile.UnitedKingdom -> Icons.Filled.AccountBalance
    OnboardingSafetyProfile.UnitedStates -> Icons.Filled.Flag
    OnboardingSafetyProfile.Australia -> Icons.Filled.WbSunny
    OnboardingSafetyProfile.Canada -> Icons.Filled.Public
}
