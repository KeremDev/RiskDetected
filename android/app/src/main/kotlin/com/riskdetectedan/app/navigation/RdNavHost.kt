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
import com.riskdetectedan.feature.analysis.AnalysisScreen
import com.riskdetectedan.feature.capture.CaptureScreen
import com.riskdetectedan.feature.onboarding.OnboardingScreen
import com.riskdetectedan.feature.paywall.PaywallScreen
import com.riskdetectedan.feature.profile.ProfileScreen
import com.riskdetectedan.feature.reports.ReportsScreen

/**
 * Faz 1 skeleton graph — proves the 6 feature modules resolve through `:app`'s type-safe nav
 * host. Faz 3 replaces the start destination with the real root-state routing that
 * `App/AppState.swift` / `App/RootView.swift` do on iOS (auth/onboarding/legal/paywall gating).
 */
@Composable
fun RdNavHost() {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = Onboarding) {
        composable<Onboarding> {
            OnboardingScreen(onFinished = { navController.navigate(Home) })
        }
        composable<Home> { HomeScreen() }
        composable<Capture> { CaptureScreen() }
        composable<Analysis> { AnalysisScreen() }
        composable<Reports> { ReportsScreen() }
        composable<Profile> { ProfileScreen() }
        composable<Paywall> { PaywallScreen() }
    }
}

@Composable
private fun HomeScreen() {
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text("Home — Faz 3 root-state routing")
    }
}
