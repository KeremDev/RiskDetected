package com.riskdetectedan.app.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.riskdetectedan.app.annotate.AnnotateScreen
import com.riskdetectedan.app.bootstrap.AppBootstrapViewModel
import com.riskdetectedan.app.bootstrap.AppSplashScreen
import com.riskdetectedan.app.bootstrap.BootstrapState
import com.riskdetectedan.app.settings.AppearanceSettingsScreen
import com.riskdetectedan.app.home.PhotoTrayViewModel
import com.riskdetectedan.feature.analysis.AnalysisScreen
import com.riskdetectedan.feature.capture.CaptureScreen
import com.riskdetectedan.feature.onboarding.LoginScreen
import com.riskdetectedan.feature.onboarding.OnboardingFlow
import com.riskdetectedan.feature.onboarding.nova.NovaLoginScreen
import com.riskdetectedan.feature.onboarding.nova.NovaOnboardingFlow
import com.riskdetectedan.feature.paywall.PaywallScreen
import com.riskdetectedan.feature.paywall.PaywallPlan
import com.riskdetectedan.feature.profile.AccountDeletionScreen
import com.riskdetectedan.feature.profile.CompanyListScreen
import com.riskdetectedan.feature.profile.OsgbWorkspaceScreen
import com.riskdetectedan.feature.profile.ProfileScreen
import com.riskdetectedan.feature.nova.NovaPilotEntry
import com.riskdetectedan.feature.nova.LocalNovaOpenCompanies
import com.riskdetectedan.feature.nova.LocalNovaPilotNavigate
import com.riskdetectedan.core.designsystem.isg.NovaDestination
import com.riskdetectedan.feature.nova.NovaPilotSlots
import com.riskdetectedan.app.BuildConfig
import com.riskdetectedan.feature.profile.NotificationSettingsScreen
import com.riskdetectedan.feature.profile.DataManagementScreen
import com.riskdetectedan.feature.profile.SupportScreen
import com.riskdetectedan.feature.reports.ReportsScreen
import com.riskdetectedan.core.designsystem.RiskDetectedLightOnlyTheme
import kotlinx.serialization.ExperimentalSerializationApi

/**
 * Root routing mirrors AppState.bootstrap/finishOnboarding: Splash resolves persisted onboarding
 * and the Supabase session, and every root transition clears the complete navigation stack.
 * Onboarding (0-11, matching OnboardingViewV2.swift's step switch — see OnboardingFlow) embeds
 * Auth as step 8 internally, same as iOS. The separate `Auth` destination renders LoginScreen,
 * the iOS AuthView counterpart: skip and a returning signed-out user must never see onboarding's
 * plan recap / "Son adım" screen.
 *
 * `MainShell` (Faz M, 2026-08-08) replaces the old separate `Home`/`Reports`/`Profile` top-level
 * destinations — it's the persistent 4-tab shell (mirrors MainTabView.swift), Capture/Analysis/
 * Companies/Support/NotificationSettings/DeleteAccount/Paywall stay real pushed/covering outer
 * destinations (matching iOS's sheet/fullScreenCover semantics — they cover the whole tab shell,
 * including the tab bar).
 */
@Composable
@OptIn(ExperimentalSerializationApi::class)
fun RdNavHost(viewModel: AppBootstrapViewModel = hiltViewModel()) {
    val diagnostics: com.riskdetectedan.app.telemetry.FlowDiagnosticsViewModel = hiltViewModel()
    val navController = rememberNavController()
    val bootstrapState by viewModel.state.collectAsState()

    LaunchedEffect(bootstrapState) {
        when (bootstrapState) {
            BootstrapState.Splash -> Unit
            BootstrapState.Onboarding -> navController.navigate(Onboarding) {
                popUpTo(0) { inclusive = true }
                launchSingleTop = true
            }
            BootstrapState.Auth -> navController.navigate(Auth) {
                popUpTo(0) { inclusive = true }
                launchSingleTop = true
            }
            BootstrapState.Main -> {
                val destination = navController.currentDestination
                val currentRoute = destination?.route
                // Navigation Compose builds type-safe route names from the serializer descriptor.
                // Kotlin qualifiedName can be obfuscated in a minified release while the
                // descriptor remains stable, which made Splash look like a restored app route
                // and stranded release builds on the logo screen.
                val bootstrapRoutes = setOf(
                    Splash.serializer().descriptor.serialName,
                    Onboarding.serializer().descriptor.serialName,
                    Auth.serializer().descriptor.serialName,
                )
                val restoredAuthenticatedRoute = destination != null &&
                    currentRoute !in bootstrapRoutes
                // rememberNavController restores its complete back stack after activity/process
                // recreation. Do not replace that restored Analysis/Result/Profile/etc. route
                // with MainShell merely because bootstrap resolved the persisted session again.
                if (!restoredAuthenticatedRoute) navController.navigate(if (BuildConfig.NOVA_PILOT) NovaPilot else MainShell) {
                    popUpTo(0) { inclusive = true }
                    launchSingleTop = true
                }
            }
            // ReleaseGate and the legal service render these blocking layers above this graph.
            BootstrapState.UpdateBlocked, BootstrapState.LegalBlocked -> Unit
        }
    }

    NavHost(navController = navController, startDestination = Splash) {
        composable<Splash> { AppSplashScreen() }
        composable<Onboarding> {
            // Live iOS pins the complete V2 onboarding surface to light mode. Nesting the
            // design-system provider here preserves that behavior even when the device/app
            // appearance preference is dark, while the main application remains theme-aware.
            RiskDetectedLightOnlyTheme {
                // Pilot bundles run the Nova funnel (iOS NovaPilotEntryGate); production keeps V2.
                if (BuildConfig.NOVA_PILOT) {
                    NovaOnboardingFlow(onOpenLogin = viewModel::openLogin, onFinished = viewModel::finishNovaOnboarding)
                } else {
                    OnboardingFlow(
                        onFinished = viewModel::finishOnboarding,
                        onSkip = viewModel::finishOnboarding,
                    )
                }
            }
        }
        composable<Auth> {
            // AuthView.swift is also explicitly light-only on iOS.
            RiskDetectedLightOnlyTheme {
                // The session flow moves Auth to Main on its own; the Nova surface needs no callback.
                if (BuildConfig.NOVA_PILOT) NovaLoginScreen() else LoginScreen(onAuthenticated = viewModel::authenticated)
            }
        }
        composable<MainShell> { MainShellScreen(navController) }
        composable<NovaPilot> {
            NovaPilotEntry(NovaPilotSlots(
                profile = { _ ->
                    val openNovaCompanies = LocalNovaOpenCompanies.current
                    val pilotNavigate = LocalNovaPilotNavigate.current
                    ProfileScreen(
                        onBack = null,
                        pilot = true,
                        onAnalyses = { pilotNavigate?.invoke(NovaDestination.analyses) },
                        onReports = { pilotNavigate?.invoke(NovaDestination.reports) },
                        onActivity = pilotNavigate?.let { navigate -> { navigate(NovaDestination.activity) } },
                        onManageCompanies = openNovaCompanies ?: { navController.navigate(Companies) },
                        onOsgbWorkspace = { navController.navigate(OsgbWorkspace) },
                        onSupport = { navController.navigate(Support) },
                        onNotificationSettings = { navController.navigate(NotificationSettings) },
                        onAppearanceSettings = { navController.navigate(AppearanceSettings) },
                        onDataManagement = { navController.navigate(DataManagement) },
                        onDeleteAccount = { navController.navigate(DeleteAccount) },
                        onPaywall = { navController.navigate(PaywallForTier(tier = "plus", entryPoint = "nova_profile")) },
                    )
                },
                analysisReports = {
                    ReportsScreen(embeddedInMainShell = true, onOpenAnalysis = { analysisId -> navController.navigate(AnalysisResult(analysisId)) })
                },
            ))
        }
        composable<Capture> {
            // Retained as a typed direct-camera entry point. The center quick-scan action no
            // longer uses it: live iOS first returns to Home and opens the source chooser there.
            CaptureScreen(
                onDiagnostic = diagnostics::record,
                onPhotoCaptured = { file ->
                    navController.navigate(Analysis(photoPaths = listOf(file.absolutePath)))
                },
                onBack = { navController.popBackStack() },
            )
        }
        composable<CaptureForTray> {
            // Same CaptureScreen composable, different wiring — routes its photo through
            // [Annotate] (real port of `appendPickedPhotos(shouldAnnotate: true)`) instead of
            // adding it to the tray directly, matching iOS's real camera-then-markup-then-tray
            // flow. popUpTo(inclusive) replaces this destination with Annotate rather than
            // stacking on top of it, so Annotate's own popBackStack() (cancel/analyze) lands
            // straight back on MainShell's tray sheet, not back on the camera.
            CaptureScreen(
                onDiagnostic = diagnostics::record,
                onPhotoCaptured = { file ->
                    navController.navigate(Annotate(photoPath = file.absolutePath)) {
                        popUpTo<CaptureForTray> { inclusive = true }
                    }
                },
                onBack = { navController.popBackStack() },
            )
        }
        composable<Annotate> { backStackEntry ->
            // Scoped to MainShell's own back stack entry, same NavBackStackEntry-scoping
            // technique as CaptureForTray above — the photo this step produces (or the original,
            // on cancel) needs to land in the same PhotoTrayViewModel instance Home reads from.
            val args: Annotate = backStackEntry.toRoute()
            val parentEntry = remember(backStackEntry) { navController.getBackStackEntry(MainShell) }
            val photoTrayViewModel: PhotoTrayViewModel = hiltViewModel(parentEntry)

            fun advance() {
                val remaining = args.queuedPaths
                if (remaining.isEmpty()) {
                    navController.popBackStack()
                } else {
                    navController.navigate(Annotate(photoPath = remaining.first(), queuedPaths = remaining.drop(1))) {
                        popUpTo<Annotate> { inclusive = true }
                    }
                }
            }

            AnnotateScreen(
                photoPath = args.photoPath,
                onCancel = {
                    // Matches iOS's real onCancel — skipping markup keeps the original photo,
                    // it doesn't discard it.
                    photoTrayViewModel.addPhoto(args.photoPath)
                    advance()
                },
                onAnalyze = { annotatedPath ->
                    photoTrayViewModel.addPhoto(annotatedPath)
                    advance()
                },
            )
        }
        composable<Analysis> { backStackEntry ->
            val args: Analysis = backStackEntry.toRoute()
            AnalysisScreen(
                photoPaths = args.photoPaths,
                canvasIds = args.canvasIds,
                analysisMode = args.analysisMode,
                resume = args.resume,
                preSelectedSectorId = args.sectorId,
                onBack = { navController.popBackStack() },
                onOpenCompanies = { navController.navigate(Companies) },
                onPaywall = { request ->
                    navController.navigate(
                        PaywallForTier(
                            tier = request.targetTier.name.lowercase(),
                            resultAnalysisId = request.analysisId,
                            resultSection = request.resultSection?.wireValue,
                            resultFunnelSessionId = request.funnelSessionId,
                            entryPoint = request.entryPoint,
                            entryItemId = request.itemId,
                            entryKind = request.attributes["entry_kind"],
                            entryPlacement = request.attributes["placement"],
                            entryPromotionVariant = request.attributes["promotion_variant"],
                            entrySourceSection = request.attributes["source_section"],
                            entryCurrentTier = request.attributes["current_tier"],
                            entryPreviewNumber = request.attributes["preview_number"],
                        ),
                    )
                },
            )
        }
        composable<AnalysisReports> { backStackEntry ->
            val args: AnalysisReports = backStackEntry.toRoute()
            ReportsScreen(
                onBack = { navController.popBackStack() },
                focusedAnalysisId = args.analysisId,
                onOpenAnalysis = { analysisId -> navController.navigate(AnalysisResult(analysisId)) },
            )
        }
        composable<AnalysisResult> { backStackEntry ->
            val args: AnalysisResult = backStackEntry.toRoute()
            AnalysisScreen(
                completedAnalysisId = args.analysisId,
                onBack = { navController.popBackStack() },
                onOpenCompanies = { navController.navigate(Companies) },
                onPaywall = { request ->
                    navController.navigate(
                        PaywallForTier(
                            tier = request.targetTier.name.lowercase(),
                            resultAnalysisId = request.analysisId,
                            resultSection = request.resultSection?.wireValue,
                            resultFunnelSessionId = request.funnelSessionId,
                            entryPoint = request.entryPoint,
                            entryItemId = request.itemId,
                            entryKind = request.attributes["entry_kind"],
                            entryPlacement = request.attributes["placement"],
                            entryPromotionVariant = request.attributes["promotion_variant"],
                            entrySourceSection = request.attributes["source_section"],
                            entryCurrentTier = request.attributes["current_tier"],
                            entryPreviewNumber = request.attributes["preview_number"],
                        ),
                    )
                },
            )
        }
        composable<Companies> { CompanyListScreen(onBack = { navController.popBackStack() }) }
        composable<OsgbWorkspace> { OsgbWorkspaceScreen(onBack = { navController.popBackStack() }) }
        composable<Support> { SupportScreen(onBack = { navController.popBackStack() }) }
        composable<NotificationSettings> { NotificationSettingsScreen(onBack = { navController.popBackStack() }) }
        composable<AppearanceSettings> { AppearanceSettingsScreen(onBack = { navController.popBackStack() }) }
        composable<DataManagement> { DataManagementScreen(onBack = { navController.popBackStack() }) }
        composable<DeleteAccount> {
            AccountDeletionScreen(
                onDeleted = {
                    viewModel.accountDeleted()
                },
                onBack = { navController.popBackStack() },
            )
        }
        composable<PaywallForTier> { backStackEntry ->
            val args: PaywallForTier = backStackEntry.toRoute()
            RiskDetectedLightOnlyTheme {
                PaywallScreen(
                    onBack = { navController.popBackStack() },
                    initialPlan = if (args.tier == "pro") PaywallPlan.Pro else PaywallPlan.Plus,
                    resultAnalysisId = args.resultAnalysisId,
                    resultSection = args.resultSection,
                    resultFunnelSessionId = args.resultFunnelSessionId,
                    entryPoint = args.entryPoint,
                    entryTargetTier = args.tier,
                    entryItemId = args.entryItemId,
                    entryKind = args.entryKind,
                    entryPlacement = args.entryPlacement,
                    entryPromotionVariant = args.entryPromotionVariant,
                    entrySourceSection = args.entrySourceSection,
                    entryCurrentTier = args.entryCurrentTier,
                    entryPreviewNumber = args.entryPreviewNumber,
                )
            }
        }
    }
}

private val com.riskdetectedan.core.data.analysis.AnalysisResultSectionId.wireValue: String
    get() = when (this) {
        com.riskdetectedan.core.data.analysis.AnalysisResultSectionId.RiskAnalysis -> "risk_analysis"
        com.riskdetectedan.core.data.analysis.AnalysisResultSectionId.ExpertRecommendations -> "expert_recommendations"
        com.riskdetectedan.core.data.analysis.AnalysisResultSectionId.TrainingRecommendations -> "training_recommendations"
        com.riskdetectedan.core.data.analysis.AnalysisResultSectionId.ApprovedNotebook -> "approved_notebook"
    }
