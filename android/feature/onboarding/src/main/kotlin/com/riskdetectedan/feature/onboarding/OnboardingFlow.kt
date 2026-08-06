package com.riskdetectedan.feature.onboarding

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * Port of OnboardingViewV2.swift's `currentScreen` switch — same 0-11 step sequence (Turkish
 * branch only, see OnboardingChoices.kt's doc comment on why English isn't ported). Auth is
 * step 8 here exactly like iOS: [AuthScreen] is called inline, not via a separate nav
 * destination — the coordinator IS the navigation for this whole flow, matching
 * OnboardingViewV2's own architecture (one view, one `switch state.step`) rather than
 * Navigation Compose's per-screen-route pattern used elsewhere in this app.
 */
@Composable
fun OnboardingFlow(
    onFinished: () -> Unit,
    viewModel: OnboardingFlowViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()

    when (state.step) {
        0 -> OBSplashScreen(onNext = viewModel::next, onSkip = onFinished)
        1 -> OBPainPointScreen(onNext = viewModel::next)
        2 -> OBCertificateScreen(
            selected = state.certificate,
            onSelect = viewModel::setCertificate,
            onNext = viewModel::next,
        )
        3 -> OBHazardClassScreen(
            selected = state.hazards,
            onToggle = viewModel::toggleHazard,
            onNext = viewModel::next,
        )
        4 -> OBSectorScreen(
            selected = state.sectors,
            onToggle = viewModel::toggleSector,
            onNext = viewModel::next,
        )
        5 -> OBFrequencyScreen(
            selected = state.frequency,
            onSelect = viewModel::setFrequency,
            onNext = viewModel::next,
        )
        6 -> OBLoadingScreen(onFinished = viewModel::next)
        7 -> OBPlanSummaryScreen(state = state, onNext = viewModel::next)
        8 -> AuthScreen(
            onAuthenticated = {
                viewModel.submitAnswersAfterAuth()
                viewModel.next()
            },
        )
        9 -> OBTrialInviteScreen(onContinue = viewModel::next)
        10 -> OBNotificationPermissionScreen(onContinue = viewModel::next)
        11 -> OBTimelinePaywallScreen(onDismiss = onFinished)
        else -> onFinished()
    }
}
