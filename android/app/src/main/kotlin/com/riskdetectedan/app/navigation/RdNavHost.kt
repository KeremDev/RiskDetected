package com.riskdetectedan.app.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
import com.riskdetectedan.feature.profile.ProfileScreen
import com.riskdetectedan.feature.profile.SupportScreen
import com.riskdetectedan.feature.reports.ReportsScreen

/**
 * Faz 1 skeleton graph — proves the 6 feature modules resolve through `:app`'s type-safe nav
 * host. Real root-state routing (`App/AppState.swift`/`App/RootView.swift`'s auth/onboarding/
 * legal/paywall gating on app relaunch) still isn't ported — this always starts at Onboarding.
 * Onboarding (0-11, matching OnboardingViewV2.swift's step switch — see OnboardingFlow) embeds
 * Auth as step 8 internally, same as iOS; the separate `Auth` destination below stays reachable
 * for a possible future direct-signin-reentry case (e.g. post sign-out), unused by this flow.
 */
@Composable
fun RdNavHost() {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = Onboarding) {
        composable<Onboarding> {
            OnboardingFlow(onFinished = { navController.navigate(Home) })
        }
        composable<Auth> {
            AuthScreen(onAuthenticated = { navController.navigate(Home) })
        }
        composable<Home> {
            HomeScreen(
                onCapture = { navController.navigate(Capture) },
                onHistory = { navController.navigate(Reports) },
                onProfile = { navController.navigate(Profile) },
            )
        }
        composable<Capture> {
            CaptureScreen(
                onPhotoCaptured = { file ->
                    navController.navigate(Analysis(photoPath = file.absolutePath))
                },
            )
        }
        composable<Analysis> { backStackEntry ->
            val args: Analysis = backStackEntry.toRoute()
            AnalysisScreen(photoPath = args.photoPath)
        }
        composable<Reports> { ReportsScreen() }
        composable<Profile> {
            ProfileScreen(
                onManageCompanies = { navController.navigate(Companies) },
                onSupport = { navController.navigate(Support) },
                onNotificationSettings = { navController.navigate(NotificationSettings) },
                onDeleteAccount = { navController.navigate(DeleteAccount) },
                onPaywall = { navController.navigate(Paywall) },
            )
        }
        composable<Companies> { CompanyListScreen() }
        composable<Support> { SupportScreen() }
        composable<NotificationSettings> { NotificationSettingsScreen() }
        composable<DeleteAccount> {
            AccountDeletionScreen(
                onDeleted = {
                    navController.navigate(Onboarding) {
                        popUpTo(0) { inclusive = true }
                    }
                },
            )
        }
        composable<Paywall> { PaywallScreen() }
    }
}

/**
 * Not a port of App/Views/Home/HomeView.swift's layout — a functional hub reaching the 3
 * screens actually built so far (Capture/History/Profile), standing in for
 * App/Views/Home/MainTabView.swift's 4-tab bar (home/analyses/reports/profile). The "reports"
 * tab (generated PDF/XLSX report list — distinct from the analyses/history list, which is what
 * this app's `Reports` nav route actually renders) isn't built.
 */
@Composable
private fun HomeScreen(
    onCapture: () -> Unit = {},
    onHistory: () -> Unit = {},
    onProfile: () -> Unit = {},
) {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        androidx.compose.foundation.layout.Column {
            Text("RiskDetected")
            androidx.compose.material3.Button(onClick = onCapture) {
                Text("Fotoğraf çek")
            }
            androidx.compose.material3.Button(onClick = onHistory) {
                Text("Geçmiş analizler")
            }
            androidx.compose.material3.Button(onClick = onProfile) {
                Text("Profil")
            }
        }
    }
}
