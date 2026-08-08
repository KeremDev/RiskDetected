package com.riskdetectedan.app.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import com.riskdetectedan.app.home.HomeScreen
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.feature.profile.ProfileScreen
import com.riskdetectedan.feature.reports.ReportsScreen

/**
 * Port of MainTabView.swift — persistent 4-tab shell (`switch app.activeTab { case .home: ... }`)
 * + floating [RdTabBar]. Tab switches are a plain `remember`ed state flip, not a nav-stack
 * operation — mirrors iOS exactly (tabs never show a back button; Capture/Analysis/Companies/
 * Support/NotificationSettings/DeleteAccount/Paywall stay genuine pushed/covering destinations on
 * the *outer* [navController], matching iOS's sheet/fullScreenCover semantics of covering the
 * whole tab shell including the tab bar).
 *
 * Faz M ships the shell + wires the two already-real tabs (Home, Analizler — the existing
 * `ReportsScreen`/`HistoryViewModel` reused as-is, it already mirrors iOS's real "Analizler" tab
 * content) and Profil. The "Raporlar" tab (iOS's separate generated-PDF/XLSX list, a different
 * table/repository than Analizler's `analyses` history) is a documented stub here — real content
 * lands in Faz R, not invented early.
 */
@Composable
fun MainShellScreen(navController: NavHostController) {
    val colors = RdTheme.colors
    // rememberSaveable (not remember) — MainShellScreen's composition is disposed while a
    // covering destination (Capture/Analysis/Companies/...) is on top of the outer NavHost's back
    // stack (default Navigation Compose behavior), so a plain `remember` reset the active tab back
    // to Home on every return trip — caught via on-device back-navigation testing. iOS doesn't
    // have this problem (`app.activeTab` lives in the `AppState` EnvironmentObject, untouched by
    // sheet/fullScreenCover presentation) — `rememberSaveable` is the Compose-Navigation-correct
    // fix, ties the value to the back stack entry's own SavedStateHandle instead of composition.
    var activeTab by rememberSaveable { mutableStateOf(RdTab.Home) }

    Box(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        when (activeTab) {
            RdTab.Home -> HomeScreen(
                onCapture = { navController.navigate(Capture) },
                onHistory = { activeTab = RdTab.Analyses },
                onProfile = { activeTab = RdTab.Profile },
                onUpgrade = { navController.navigate(Paywall) },
            )
            RdTab.Analyses -> ReportsScreen(onBack = null)
            RdTab.Reports -> GeneratedReportsStub()
            RdTab.Profile -> ProfileScreen(
                onBack = null,
                onManageCompanies = { navController.navigate(Companies) },
                onSupport = { navController.navigate(Support) },
                onNotificationSettings = { navController.navigate(NotificationSettings) },
                onDeleteAccount = { navController.navigate(DeleteAccount) },
                onPaywall = { navController.navigate(Paywall) },
            )
        }

        RdTabBar(
            active = activeTab,
            onTabSelected = { activeTab = it },
            onQuickScan = { navController.navigate(Capture) },
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}

/** Faz R stub — real "Raporlar" tab (generated `reports` table list, distinct from Analizler's
 * `analyses` history) lands separately; this is an honest placeholder, not a reuse of
 * [ReportsScreen]'s history content under a misleading label. */
@Composable
private fun GeneratedReportsStub() {
    Column(modifier = Modifier.fillMaxSize()) {
        RdScreenHeader(title = "Raporlar")
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            RdEmptyState(
                icon = Icons.Filled.Description,
                title = "Yakında",
                subtitle = "Oluşturduğun raporların listesi burada görünecek.",
            )
        }
    }
}
