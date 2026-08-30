package com.riskdetectedan.feature.onboarding

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Engineering
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.SupervisorAccount
import androidx.compose.material.icons.filled.Work
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import com.riskdetectedan.core.data.onboarding.OnboardingProfessionalRole
import com.riskdetectedan.core.designsystem.R as RdR
import com.riskdetectedan.core.designsystem.RdHeroTint

/** iOS English onboarding step 2: role selection without credential verification. */
@Composable
fun OBProfessionalRoleScreen(
    selected: OnboardingProfessionalRole?,
    onSelect: (OnboardingProfessionalRole) -> Unit,
    onNext: () -> Unit,
    onBack: () -> Unit,
) {
    OnboardingChoiceScreen(
        title = stringResource(RdR.string.rd_role_question),
        subtitle = stringResource(RdR.string.rd_role_question_body),
        items = OnboardingProfessionalRole.entries,
        isSelected = { it == selected },
        label = { professionalRoleLabel(it) },
        itemSubtitle = { professionalRoleSubtitle(it) },
        itemIcon = { professionalRoleIcon(it) },
        onToggle = onSelect,
        canContinue = selected != null,
        onContinue = onNext,
        step = 2,
        totalSteps = 5,
        onBack = onBack,
        heroTint = RdHeroTint.Cool,
        heroIcon = Icons.Filled.Person,
    )
}

@Composable
internal fun professionalRoleLabel(role: OnboardingProfessionalRole): String = stringResource(
    when (role) {
        OnboardingProfessionalRole.SafetyProfessional -> RdR.string.rd_role_safety_professional
        OnboardingProfessionalRole.SafetyManager -> RdR.string.rd_role_safety_manager
        OnboardingProfessionalRole.SiteManager -> RdR.string.rd_role_site_manager
        OnboardingProfessionalRole.Engineer -> RdR.string.rd_role_engineer
        OnboardingProfessionalRole.Supervisor -> RdR.string.rd_role_supervisor
        OnboardingProfessionalRole.Consultant -> RdR.string.rd_role_consultant
        OnboardingProfessionalRole.EmployerOwner -> RdR.string.rd_role_employer_owner
        OnboardingProfessionalRole.Other -> RdR.string.rd_role_other
    },
)

@Composable
private fun professionalRoleSubtitle(role: OnboardingProfessionalRole): String = stringResource(
    when (role) {
        OnboardingProfessionalRole.SafetyProfessional -> RdR.string.rd_role_safety_professional_subtitle
        OnboardingProfessionalRole.SafetyManager -> RdR.string.rd_role_safety_manager_subtitle
        OnboardingProfessionalRole.SiteManager -> RdR.string.rd_role_site_manager_subtitle
        OnboardingProfessionalRole.Engineer -> RdR.string.rd_role_engineer_subtitle
        OnboardingProfessionalRole.Supervisor -> RdR.string.rd_role_supervisor_subtitle
        OnboardingProfessionalRole.Consultant -> RdR.string.rd_role_consultant_subtitle
        OnboardingProfessionalRole.EmployerOwner -> RdR.string.rd_role_employer_owner_subtitle
        OnboardingProfessionalRole.Other -> RdR.string.rd_role_other_subtitle
    },
)

private fun professionalRoleIcon(role: OnboardingProfessionalRole): ImageVector = when (role) {
    OnboardingProfessionalRole.SafetyProfessional -> Icons.Filled.Shield
    OnboardingProfessionalRole.SafetyManager -> Icons.Filled.Groups
    OnboardingProfessionalRole.SiteManager -> Icons.Filled.Business
    OnboardingProfessionalRole.Engineer -> Icons.Filled.Engineering
    OnboardingProfessionalRole.Supervisor -> Icons.Filled.SupervisorAccount
    OnboardingProfessionalRole.Consultant -> Icons.Filled.Person
    OnboardingProfessionalRole.EmployerOwner -> Icons.Filled.Work
    OnboardingProfessionalRole.Other -> Icons.Filled.MoreHoriz
}
