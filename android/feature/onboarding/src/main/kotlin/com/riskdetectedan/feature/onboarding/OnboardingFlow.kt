package com.riskdetectedan.feature.onboarding

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SentimentDissatisfied
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Port of OnboardingViewV2.swift's `currentScreen` switch — same 0-11 step sequence (Turkish
 * branch only, see OnboardingChoices.kt's doc comment on why English isn't ported). Auth is
 * step 8 here exactly like iOS: [AuthScreen] is called inline, not via a separate nav
 * destination — the coordinator IS the navigation for this whole flow, matching
 * OnboardingViewV2's own architecture (one view, one `switch state.step`) rather than
 * Navigation Compose's per-screen-route pattern used elsewhere in this app.
 *
 * [onSkip] mirrors iOS's `finishOnboarding()` reached via `OBSkipConfirmationView`'s confirm —
 * skip fires at step 0, always *before* the step-8 Auth screen ever runs, so the user is never
 * authenticated yet at this point; iOS's conditional (`auth.isAuthenticated ? .main : .auth`)
 * always resolves to `.auth` here in practice. Real bug fixed 2026-08-09 (owner-reported,
 * ios-parity check): this used to alias [onSkip] to [onFinished], routing "Atla" straight to
 * Home with no session at all — [RdNavHost] now sends skip to the real (previously wired but
 * unreachable) `Auth` destination instead.
 */
@Composable
fun OnboardingFlow(
    onFinished: () -> Unit,
    onSkip: () -> Unit,
    viewModel: OnboardingFlowViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    var showSkipConfirmation by rememberSaveable { mutableStateOf(false) }
    val primarySectorLabel = state.sectors.firstOrNull()?.let { onboardingSectorLabel(it) }
        ?: stringResource(RdR.string.rd_sector_construction)
    val hazardLabels = buildList {
        state.hazards.forEach { add(hazardLabel(it)) }
    }
    val hazardsLabel = if (hazardLabels.isEmpty()) {
        stringResource(RdR.string.rd_hazard_critical)
    } else {
        hazardLabels.joinToString(" · ")
    }
    val selectedCertificateLabel = state.certificate?.let { certificateLabel(it) }
        ?: stringResource(RdR.string.rd_cert_a)

    Box(modifier = Modifier.fillMaxSize()) {
        when (state.step) {
            0 -> OBSplashScreen(onNext = viewModel::next, onSkip = { showSkipConfirmation = true })
            1 -> OBPainPointScreen(onNext = viewModel::next)
            2 -> OBCertificateScreen(
                selected = state.certificate,
                onSelect = viewModel::setCertificate,
                onNext = viewModel::next,
                onBack = viewModel::back,
            )
            3 -> OBHazardClassScreen(
                selected = state.hazards,
                onToggle = viewModel::toggleHazard,
                onNext = viewModel::next,
                onBack = viewModel::back,
            )
            4 -> OBSectorScreen(
                selected = state.sectors,
                onToggle = viewModel::toggleSector,
                onNext = viewModel::next,
                onBack = viewModel::back,
            )
            5 -> OBFrequencyScreen(
                selected = state.frequency,
                onSelect = viewModel::setFrequency,
                onNext = viewModel::next,
                onBack = viewModel::back,
            )
            6 -> OBLoadingScreen(
                onFinished = viewModel::next,
                primarySectorLabel = primarySectorLabel,
                hazardsLabel = hazardsLabel,
                certificateLabel = selectedCertificateLabel,
            )
            7 -> OBPlanSummaryScreen(state = state, onNext = viewModel::next)
            8 -> AuthScreen(
                onAuthenticated = {
                    viewModel.submitAnswersAfterAuth { destination ->
                        when (destination) {
                            PostAuthDestination.Finish -> onFinished()
                            PostAuthDestination.TrialInvite -> viewModel.goTo(9)
                        }
                    }
                },
                onBack = viewModel::back,
                primarySectorLabel = state.sectors.firstOrNull()?.let { onboardingSectorLabel(it) },
                certificateLabel = state.certificate?.let { certificateLabel(it) },
            )
            9 -> OBTrialInviteScreen(onContinue = viewModel::next, onRestored = onFinished, onDismiss = onFinished)
            10 -> OBNotificationPermissionScreen(onContinue = viewModel::next)
            11 -> OBTimelinePaywallScreen(onDismiss = onFinished)
            else -> onFinished()
        }
    }

    if (showSkipConfirmation) {
        OBSkipConfirmationDialog(
            onCancel = { showSkipConfirmation = false },
            onConfirm = {
                showSkipConfirmation = false
                viewModel.clearPendingDraft()
                onSkip()
            },
        )
    }
}

@Composable
private fun OBSkipConfirmationDialog(onCancel: () -> Unit, onConfirm: () -> Unit) {
    val colors = RdTheme.colors
    Dialog(onDismissRequest = onCancel) {
        Surface(
            shape = RoundedCornerShape(22.dp),
            color = colors.white,
            tonalElevation = 0.dp,
            shadowElevation = 18.dp,
        ) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 22.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(RdSpacing.md),
            ) {
                Box(
                    modifier = Modifier.size(76.dp).background(colors.highBg, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.SentimentDissatisfied,
                        contentDescription = null,
                        tint = colors.high,
                        modifier = Modifier.size(42.dp),
                    )
                }
                Text(
                    stringResource(RdR.string.rd_skip_sonuc_baslik),
                    style = RdFontStyle.Title2.toTextStyle(),
                    color = colors.onyx,
                    textAlign = TextAlign.Center,
                )
                Text(
                    stringResource(RdR.string.rd_skip_sonuc_aciklama),
                    style = RdFontStyle.Footnote.toTextStyle(),
                    color = colors.slate,
                    textAlign = TextAlign.Center,
                )
                RdPrimaryButton(
                    text = stringResource(RdR.string.rd_cevaplamaya_devam_et),
                    onClick = onCancel,
                    showArrow = false,
                    style = RdButtonStyle.Onyx,
                )
                TextButton(onClick = onConfirm) {
                    Text(stringResource(RdR.string.rd_yine_de_atla), style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
                }
            }
        }
    }
}
