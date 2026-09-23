package com.riskdetectedan.app.navigation

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.app.home.HomeScreen
import com.riskdetectedan.app.home.AppMainHeader
import com.riskdetectedan.app.home.HomeTierViewModel
import com.riskdetectedan.app.push.NotificationRouteTarget
import com.riskdetectedan.app.push.NotificationRouteViewModel
import com.riskdetectedan.app.reports.GeneratedReportsScreen
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.feature.profile.ProfileScreen
import com.riskdetectedan.feature.profile.ReferralRewardsViewModel
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
 * content) and Profil. Faz R (2026-08-08) replaces the "Raporlar" tab's stub with the real
 * [GeneratedReportsScreen] — iOS's separate generated-PDF/XLSX list, a genuinely different
 * table/repository than Analizler's `analyses` history.
 */
@Composable
fun MainShellScreen(
    navController: NavHostController,
    notificationRouteViewModel: NotificationRouteViewModel = hiltViewModel(),
    homeTierViewModel: HomeTierViewModel = hiltViewModel(),
    referralViewModel: ReferralRewardsViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    // rememberSaveable (not remember) — MainShellScreen's composition is disposed while a
    // covering destination (Capture/Analysis/Companies/...) is on top of the outer NavHost's back
    // stack (default Navigation Compose behavior), so a plain `remember` reset the active tab back
    // to Home on every return trip — caught via on-device back-navigation testing. iOS doesn't
    // have this problem (`app.activeTab` lives in the `AppState` EnvironmentObject, untouched by
    // sheet/fullScreenCover presentation) — `rememberSaveable` is the Compose-Navigation-correct
    // fix, ties the value to the back stack entry's own SavedStateHandle instead of composition.
    var activeTab by rememberSaveable { mutableStateOf(RdTab.Home) }
    var tabHistoryNames by rememberSaveable { mutableStateOf(emptyList<String>()) }
    var focusedAnalysisId by rememberSaveable { mutableStateOf<String?>(null) }
    var focusedReportId by rememberSaveable { mutableStateOf<String?>(null) }
    var quickScanRequestKey by rememberSaveable { mutableStateOf(0) }
    val pendingNotification by notificationRouteViewModel.pending.collectAsState()
    val headerProfile by homeTierViewModel.profile.collectAsState()

    LaunchedEffect(Unit) { homeTierViewModel.refresh() }

    fun selectTab(target: RdTab) {
        val snapshot = TabHistoryReducer.select(
            TabHistorySnapshot(
                active = activeTab,
                history = tabHistoryNames.mapNotNull { name ->
                    runCatching { RdTab.valueOf(name) }.getOrNull()
                },
            ),
            target,
        )
        activeTab = snapshot.active
        tabHistoryNames = snapshot.history.map(RdTab::name)
    }

    BackHandler(enabled = activeTab != RdTab.Home || tabHistoryNames.isNotEmpty()) {
        val previous = TabHistoryReducer.back(
            TabHistorySnapshot(
                active = activeTab,
                history = tabHistoryNames.mapNotNull { name ->
                    runCatching { RdTab.valueOf(name) }.getOrNull()
                },
            ),
        )
        activeTab = previous.active
        tabHistoryNames = previous.history.map(RdTab::name)
    }

    // An invite link opens Profil, where the profile screen shows the invite page.
    val referralRequested by referralViewModel.openRequested.collectAsState()
    LaunchedEffect(referralRequested) { if (referralRequested) selectTab(RdTab.Profile) }

    LaunchedEffect(pendingNotification) {
        val route = pendingNotification ?: return@LaunchedEffect
        when (route.target) {
            NotificationRouteTarget.Home -> selectTab(RdTab.Home)
            NotificationRouteTarget.Analyses -> {
                focusedAnalysisId = route.analysisId
                selectTab(RdTab.Analyses)
            }
            NotificationRouteTarget.Reports -> {
                focusedReportId = route.reportId
                selectTab(RdTab.Reports)
            }
            NotificationRouteTarget.Profile -> selectTab(RdTab.Profile)
            NotificationRouteTarget.NewAnalysis -> {
                selectTab(RdTab.Home)
                quickScanRequestKey += 1
            }
        }
        notificationRouteViewModel.consume()
    }

    Box(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        when (activeTab) {
            RdTab.Home -> HomeScreen(
                onNavigateToCamera = { navController.navigate(CaptureForTray) },
                onAnnotatePhotos = { paths ->
                    navController.navigate(Annotate(photoPath = paths.first(), queuedPaths = paths.drop(1)))
                },
                onStartAnalysis = { canvasIds, analysisMode, paths, sectorId ->
                    navController.navigate(
                        Analysis(photoPaths = paths, canvasIds = canvasIds, analysisMode = analysisMode, sectorId = sectorId),
                    )
                },
                onResumeAnalysis = { navController.navigate(Analysis(resume = true)) },
                onHistory = { selectTab(RdTab.Analyses) },
                onOpenAnalysis = { analysisId -> navController.navigate(AnalysisResult(analysisId)) },
                onReports = { selectTab(RdTab.Reports) },
                onProfile = { selectTab(RdTab.Profile) },
                onUpgrade = { entryPoint ->
                    navController.navigate(PaywallForTier(tier = "plus", entryPoint = entryPoint))
                },
                quickScanRequestKey = quickScanRequestKey,
                onQuickScanRequestConsumed = { consumedKey ->
                    if (quickScanRequestKey == consumedKey) quickScanRequestKey = 0
                },
            )
            RdTab.Analyses -> Column {
                AppMainHeader(
                    profile = headerProfile,
                    onLogo = { selectTab(RdTab.Home) },
                    onProfile = { selectTab(RdTab.Profile) },
                    onUpgradeTier = { tier ->
                        navController.navigate(PaywallForTier(tier.name.lowercase(), entryPoint = "analyses_header_upgrade"))
                    },
                )
                Box(Modifier.weight(1f)) {
                    ReportsScreen(
                        onBack = null,
                        embeddedInMainShell = true,
                        focusedAnalysisId = focusedAnalysisId,
                        onOpenAnalysis = { analysisId -> navController.navigate(AnalysisResult(analysisId)) },
                    )
                }
            }
            RdTab.Reports -> Column {
                AppMainHeader(
                    profile = headerProfile,
                    onLogo = { selectTab(RdTab.Home) },
                    onProfile = { selectTab(RdTab.Profile) },
                    onUpgradeTier = { tier ->
                        navController.navigate(PaywallForTier(tier.name.lowercase(), entryPoint = "reports_header_upgrade"))
                    },
                    bottomPadding = 10.dp,
                )
                Box(Modifier.weight(1f)) {
                    GeneratedReportsScreen(
                        focusedReportId = focusedReportId,
                        onUpgrade = { entryPoint ->
                            navController.navigate(PaywallForTier(tier = "plus", entryPoint = entryPoint))
                        },
                        embeddedInMainShell = true,
                    )
                }
            }
            RdTab.Profile -> ProfileScreen(
                onBack = null,
                onManageCompanies = { navController.navigate(Companies) },
                onOsgbWorkspace = { navController.navigate(OsgbWorkspace) },
                onAnalyses = { selectTab(RdTab.Analyses) },
                onReports = { selectTab(RdTab.Reports) },
                onSupport = { navController.navigate(Support) },
                onNotificationSettings = { navController.navigate(NotificationSettings) },
                onAppearanceSettings = { navController.navigate(AppearanceSettings) },
                onDataManagement = { navController.navigate(DataManagement) },
                onDeleteAccount = { navController.navigate(DeleteAccount) },
                onPaywall = {
                    navController.navigate(PaywallForTier(tier = "plus", entryPoint = "profile_upsell_card"))
                },
            )
        }

        RdTabBar(
            active = activeTab,
            onTabSelected = {
                selectTab(it)
                if (it != RdTab.Analyses) focusedAnalysisId = null
                if (it != RdTab.Reports) focusedReportId = null
            },
            onQuickScan = {
                // Live iOS handleQuickScanTap -> Home.handleQuickScanRequest: select Home first,
                // then let Home apply quota/existing-draft rules and open the camera/gallery
                // chooser. Direct camera navigation skipped that entire product sequence.
                selectTab(RdTab.Home)
                quickScanRequestKey += 1
            },
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}
