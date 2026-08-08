package com.riskdetectedan.app.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.riskdetectedan.feature.analysis.AnalysisScreen
import com.riskdetectedan.feature.capture.CaptureScreen
import com.riskdetectedan.feature.onboarding.AuthScreen
import com.riskdetectedan.feature.onboarding.OnboardingFlow
import com.riskdetectedan.feature.paywall.PaywallScreen
import com.riskdetectedan.feature.profile.AccountDeletionScreen
import com.riskdetectedan.feature.profile.CompanyListScreen
import com.riskdetectedan.feature.profile.NotificationSettingsScreen
import com.riskdetectedan.feature.profile.SupportScreen

/**
 * Real root-state routing (`App/AppState.swift`/`App/RootView.swift`'s auth/onboarding/legal/
 * paywall gating on app relaunch) still isn't ported — this always starts at Onboarding.
 * Onboarding (0-11, matching OnboardingViewV2.swift's step switch — see OnboardingFlow) embeds
 * Auth as step 8 internally, same as iOS; the separate `Auth` destination below stays reachable
 * for a possible future direct-signin-reentry case (e.g. post sign-out), unused by this flow.
 *
 * `MainShell` (Faz M, 2026-08-08) replaces the old separate `Home`/`Reports`/`Profile` top-level
 * destinations — it's the persistent 4-tab shell (mirrors MainTabView.swift), Capture/Analysis/
 * Companies/Support/NotificationSettings/DeleteAccount/Paywall stay real pushed/covering outer
 * destinations (matching iOS's sheet/fullScreenCover semantics — they cover the whole tab shell,
 * including the tab bar).
 */
@Composable
fun RdNavHost() {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = Onboarding) {
        composable<Onboarding> {
            OnboardingFlow(onFinished = { navController.navigate(MainShell) })
        }
        composable<Auth> {
            AuthScreen(onAuthenticated = { navController.navigate(MainShell) })
        }
        composable<MainShell> { MainShellScreen(navController) }
        composable<Capture> {
            CaptureScreen(
                onPhotoCaptured = { file ->
                    navController.navigate(Analysis(photoPath = file.absolutePath))
                },
                onBack = { navController.popBackStack() },
            )
        }
        composable<Analysis> { backStackEntry ->
            val args: Analysis = backStackEntry.toRoute()
            AnalysisScreen(photoPath = args.photoPath, onBack = { navController.popBackStack() })
        }
        composable<Companies> { CompanyListScreen(onBack = { navController.popBackStack() }) }
        composable<Support> { SupportScreen(onBack = { navController.popBackStack() }) }
        composable<NotificationSettings> { NotificationSettingsScreen(onBack = { navController.popBackStack() }) }
        composable<DeleteAccount> {
            AccountDeletionScreen(
                onDeleted = {
                    navController.navigate(Onboarding) {
                        popUpTo(0) { inclusive = true }
                    }
                },
                onBack = { navController.popBackStack() },
            )
        }
        composable<Paywall> { PaywallScreen(onBack = { navController.popBackStack() }) }
    }
}
