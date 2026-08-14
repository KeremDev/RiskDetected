package com.riskdetectedan.app.visual

import android.app.Application
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import com.github.takahirom.roborazzi.captureRoboImage
import com.github.takahirom.roborazzi.RoborazziOptions
import com.riskdetectedan.core.data.onboarding.OnboardingCertificate
import com.riskdetectedan.core.data.onboarding.OnboardingFrequency
import com.riskdetectedan.core.data.onboarding.OnboardingHazardClass
import com.riskdetectedan.core.data.onboarding.OnboardingSector
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisSectorBadge
import com.riskdetectedan.core.data.analysis.AnalysisSectorPickerItem
import com.riskdetectedan.core.data.profile.ProfileStats
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import com.riskdetectedan.core.designsystem.RiskDetectedLightOnlyTheme
import com.riskdetectedan.core.designsystem.LocalRdConfettiSnapshotElapsedMillis
import com.riskdetectedan.app.home.SectorPickerSheet
import com.riskdetectedan.app.home.PhotoTraySheet
import com.riskdetectedan.app.reports.ExcelGenerationOverlayParityPreviewSurface
import com.riskdetectedan.app.reports.GeneratedReportsParityPreviewSurface
import com.riskdetectedan.app.reports.ReportSourceSheetParityPreviewSurface
import com.riskdetectedan.app.navigation.RdTab
import com.riskdetectedan.app.navigation.RdTabBar
import com.riskdetectedan.feature.onboarding.OBCertificateScreen
import com.riskdetectedan.feature.onboarding.OBFrequencyScreen
import com.riskdetectedan.feature.onboarding.OBHazardClassScreen
import com.riskdetectedan.feature.onboarding.OBLoadingScreen
import com.riskdetectedan.feature.onboarding.OBNotificationPermissionScreen
import com.riskdetectedan.feature.onboarding.OBPlanSummaryScreen
import com.riskdetectedan.feature.onboarding.OBTrialInvitePreviewSurface
import com.riskdetectedan.feature.onboarding.OBTimelinePaywallPreviewSurface
import com.riskdetectedan.feature.onboarding.AuthOnboardingPreviewSurface
import com.riskdetectedan.feature.onboarding.OnboardingUiState
import com.riskdetectedan.feature.onboarding.OBPainPointScreen
import com.riskdetectedan.feature.onboarding.OBSectorScreen
import com.riskdetectedan.feature.onboarding.OBSplashScreen
import com.riskdetectedan.feature.onboarding.LoginScreenContent
import com.riskdetectedan.feature.onboarding.EmailPhase
import com.riskdetectedan.feature.paywall.PaywallBilling
import com.riskdetectedan.feature.paywall.PaywallParityPreviewSurface
import com.riskdetectedan.feature.paywall.PaywallPlan
import com.riskdetectedan.feature.profile.AccountDeletionParityPreviewSurface
import com.riskdetectedan.feature.profile.CompanyListParityPreviewSurface
import com.riskdetectedan.feature.profile.ProfileParityPreviewSurface
import com.riskdetectedan.feature.profile.ProfileLoadedSurface
import com.riskdetectedan.feature.reports.ReportsParityPreviewSurface
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(
    application = Application::class,
    sdk = [35],
    qualifiers = "w393dp-h852dp-xxhdpi",
)
class OnboardingGoldenTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val exactPixelOptions = RoborazziOptions(
        compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0f),
    )

    @Test
    fun splash_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                OBSplashScreen(onNext = {}, onSkip = {})
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pain_point_checks_completed_light() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                OBPainPointScreen(onNext = {})
            }
        }
        composeRule.mainClock.advanceTimeBy(2_100L)

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun certificate_empty_light() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                OBCertificateScreen(
                    selected = null,
                    onSelect = {},
                    onNext = {},
                    onBack = {},
                )
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
        assertEquals(0, composeRule.onAllNodesWithText("İşyeri Hekimi").fetchSemanticsNodes().size)
        assertEquals(0, composeRule.onAllNodesWithText("Sağlık personeli").fetchSemanticsNodes().size)
    }

    @Test
    fun hazard_multi_selected_light() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                OBHazardClassScreen(
                    selected = setOf(OnboardingHazardClass.Critical, OnboardingHazardClass.High),
                    onToggle = {},
                    onNext = {},
                    onBack = {},
                )
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun sector_grid_selected_light() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                OBSectorScreen(
                    selected = listOf(OnboardingSector.Construction, OnboardingSector.Manufacturing),
                    onToggle = {},
                    onNext = {},
                    onBack = {},
                )
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun frequency_selected_system_dark_stays_light() {
        composeRule.setContent {
            // Mirrors the app route: the outer app theme may be dark, but live iOS pins the
            // onboarding/auth/paywall product surfaces to light mode.
            RiskDetectedTheme(darkTheme = true) {
                RiskDetectedLightOnlyTheme {
                    OBFrequencyScreen(
                        selected = OnboardingFrequency.TwoToFive,
                        onSelect = {},
                        onNext = {},
                        onBack = {},
                    )
                }
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun loading_second_step_light() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                OBLoadingScreen(
                    onFinished = {},
                    primarySectorLabel = "İnşaat",
                    hazardsLabel = "Çok Tehlikeli · Tehlikeli",
                    certificateLabel = "A Sınıfı",
                )
            }
        }
        composeRule.mainClock.advanceTimeBy(1_850L)

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun notification_permission_light() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                OBNotificationPermissionScreen(onContinue = {})
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun plan_summary_confetti_light() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            CompositionLocalProvider(LocalRdConfettiSnapshotElapsedMillis provides 1_200L) {
                RiskDetectedLightOnlyTheme {
                    OBPlanSummaryScreen(
                        state = OnboardingUiState(
                            certificate = OnboardingCertificate.A,
                            hazards = setOf(OnboardingHazardClass.Critical, OnboardingHazardClass.High),
                            sectors = listOf(OnboardingSector.Construction),
                            frequency = OnboardingFrequency.TwoToFive,
                        ),
                        onNext = {},
                    )
                }
            }
        }
        composeRule.mainClock.advanceTimeBy(1_400L)
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun onboarding_auth_provider_buttons_light() {
        composeRule.setContent { RiskDetectedLightOnlyTheme { AuthOnboardingPreviewSurface() } }
        composeRule.onNodeWithText("Google ile devam et").assertIsDisplayed()
        composeRule.onNodeWithText("E-posta ile devam et").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun trial_invite_light() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent { RiskDetectedLightOnlyTheme { OBTrialInvitePreviewSurface() } }
        composeRule.mainClock.advanceTimeBy(900L)
        composeRule.onNodeWithText("0,00 TL'ye dene").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun onboarding_timeline_yearly_store_loaded_light() {
        composeRule.setContent { RiskDetectedLightOnlyTheme { OBTimelinePaywallPreviewSurface() } }
        composeRule.onNodeWithText("7 Gün Ücretsiz Dene").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun standalone_login_options_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                LoginScreenContent()
            }
        }

        composeRule.onNodeWithText("E-posta ile giriş yap").assertIsDisplayed()
        composeRule.onNodeWithText("Google ile devam et").assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodesWithText("Son adım.").fetchSemanticsNodes().size)
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun standalone_login_email_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                LoginScreenContent(
                    phase = EmailPhase.Email,
                    email = "uzman@riskdetected.com",
                )
            }
        }

        composeRule.onNodeWithText("E-posta adresinizi giriniz").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun standalone_login_otp_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                LoginScreenContent(
                    phase = EmailPhase.Otp,
                    sentTo = "uzman@riskdetected.com",
                    otp = "184",
                )
            }
        }

        composeRule.onNodeWithText("Doğrula ve devam et").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun standalone_login_error_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                LoginScreenContent(error = "Kodun süresi doldu. Yeni bir kod iste.")
            }
        }

        composeRule.onNodeWithText("Kodun süresi doldu. Yeni bir kod iste.").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun photo_tray_free_locked_slots_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                PhotoTraySheet(
                    photoPaths = emptyList(),
                    maxPhotoCount = 1,
                    visibleSlotCount = 3,
                    onCamera = {},
                    onGallery = {},
                    onRemove = {},
                    onMove = { _, _ -> },
                    onLockedSlot = {},
                    onStartAnalysis = {},
                    onClose = {},
                )
            }
        }

        composeRule.onNodeWithText("Fotoğraf ekle").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun paywall_plus_yearly_gold_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                PaywallParityPreviewSurface(
                    plan = PaywallPlan.Plus,
                    billing = PaywallBilling.Yearly,
                    formattedPrice = "₺1.499,99",
                )
            }
        }

        composeRule.onNodeWithText("PLUS").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun paywall_pro_monthly_green_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                PaywallParityPreviewSurface(
                    plan = PaywallPlan.Pro,
                    billing = PaywallBilling.Monthly,
                    formattedPrice = "₺2.499,99",
                )
            }
        }

        composeRule.onNodeWithText("PRO").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun analysis_history_loaded_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                ReportsParityPreviewSurface()
            }
        }

        composeRule.onNodeWithText("İskele çalışma alanı").assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodesWithText("Excel oluştur").fetchSemanticsNodes().size)
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun report_archive_pdf_xlsx_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                GeneratedReportsParityPreviewSurface()
            }
        }

        composeRule.onNodeWithText("İskele Risk Analizi").assertIsDisplayed()
        composeRule.onNodeWithText("Üretim Hattı Bulguları").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun report_archive_pdf_xlsx_dark() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = true) {
                GeneratedReportsParityPreviewSurface()
            }
        }

        composeRule.onNodeWithText("İskele Risk Analizi").assertIsDisplayed()
        composeRule.onNodeWithText("Üretim Hattı Bulguları").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun report_source_preview_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                ReportSourceSheetParityPreviewSurface()
            }
        }

        composeRule.onNodeWithText("RAPOR ÖNİZLEMESİ").assertIsDisplayed()
        composeRule.onNodeWithText("Platform kenarında düşmeye karşı koruma yok").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun report_source_sheet_free_trial_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                ReportSourceSheetParityPreviewSurface()
            }
        }

        composeRule.onNodeWithTag("report-source-primary").performClick()
        composeRule.onNodeWithText("Standart Rapor").assertIsDisplayed()
        composeRule.onNodeWithText("Risk Analizi Tablosu").assertIsDisplayed()
        composeRule.onNodeWithText("Hoş geldin, 1 risk analizi oluşturma hakkını hemen kullan!").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun report_source_sheet_free_trial_used_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                ReportSourceSheetParityPreviewSurface(freeRiskTrialAvailable = false)
            }
        }

        composeRule.onNodeWithTag("report-source-primary").performClick()
        composeRule.onNodeWithText("Bir kez tanımlanan hakkını kullandın. Risk analizi tabloları Plus ile devam eder.").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun report_source_sheet_plus_risk_settings_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                ReportSourceSheetParityPreviewSurface(tier = SubscriptionTier.Plus, freeRiskTrialAvailable = false)
            }
        }

        composeRule.onNodeWithTag("report-source-primary").performClick()
        composeRule.onNodeWithText("Risk Analizi Tablosu").performClick()
        composeRule.onNodeWithText("Rapor firması").assertIsDisplayed()
        composeRule.onNodeWithText("Risk yöntemi").assertIsDisplayed()
        composeRule.onNodeWithTag("report-settings-list").performScrollToIndex(5)
        composeRule.onNodeWithText("HAZIRLAYAN BİLGİLERİ").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun excel_generation_overlay_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                ExcelGenerationOverlayParityPreviewSurface()
            }
        }

        composeRule.onNodeWithText("Excel hazırlanıyor").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun account_deletion_idle_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                AccountDeletionParityPreviewSurface()
            }
        }

        composeRule.onNodeWithText("Hesabımı sil").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun company_management_plus_limit_light() {
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                CompanyListParityPreviewSurface()
            }
        }

        composeRule.onNodeWithText("RiskDetected İnşaat").assertIsDisplayed()
        composeRule.onNodeWithText("2 / 5 firma").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun analysis_sector_picker_three_column_light() {
        var selectedResult: AnalysisSector? = null
        val items = AnalysisSector.entries.map { sector ->
            AnalysisSectorPickerItem(
                sector = sector,
                badges = when (sector) {
                    AnalysisSector.Construction -> setOf(AnalysisSectorBadge.Recommended)
                    AnalysisSector.Manufacturing -> setOf(AnalysisSectorBadge.LastUsed)
                    else -> emptySet()
                },
            )
        }
        composeRule.setContent {
            RiskDetectedLightOnlyTheme {
                SectorPickerSheet(items = items, onSelect = { selectedResult = it })
            }
        }

        composeRule.onNodeWithText("İnşaat").assertIsDisplayed()
        composeRule.onNodeWithText("İmalat / Fabrika").assertIsDisplayed()
        composeRule.onNodeWithText("İnşaat").performClick()
        composeRule.onNodeWithText("İnşaat").assertIsSelected()
        assertEquals(null, selectedResult)
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
        composeRule.onNodeWithText("Devam et").performClick()
        assertEquals(AnalysisSector.Construction, selectedResult)
    }

    @Test
    fun profile_ios_parity_light() {
        var analysesOpened = 0
        var titlesOpened = 0
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                Box(Modifier.fillMaxSize()) {
                    ProfileParityPreviewSurface(onAnalyses = { analysesOpened += 1 }, onShowTitles = { titlesOpened += 1 })
                    RdTabBar(active = RdTab.Profile, onTabSelected = {}, onQuickScan = {}, modifier = Modifier.align(Alignment.BottomCenter))
                }
            }
        }

        composeRule.onNodeWithText("Kerem Kayalar").assertIsDisplayed()
        composeRule.onNodeWithText("Yetkinlik Haritası").assertIsDisplayed()
        composeRule.onAllNodesWithText("12")[0].performClick()
        assertEquals(1, analysesOpened)
        composeRule.onAllNodesWithText("Aday Uzman")[0].performClick()
        assertEquals(1, titlesOpened)
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    @Config(application = Application::class, sdk = [35], qualifiers = "w320dp-h640dp-xhdpi")
    fun profile_small_font_scale_1_3_light() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 1.3f)) {
                    Box(Modifier.fillMaxSize()) {
                        ProfileParityPreviewSurface()
                        RdTabBar(active = RdTab.Profile, onTabSelected = {}, onQuickScan = {}, modifier = Modifier.align(Alignment.BottomCenter))
                    }
                }
            }
        }

        composeRule.onNodeWithText("Kerem Kayalar").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun profile_ios_parity_dark() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = true) {
                Box(Modifier.fillMaxSize()) {
                    ProfileParityPreviewSurface()
                    RdTabBar(active = RdTab.Profile, onTabSelected = {}, onQuickScan = {}, modifier = Modifier.align(Alignment.BottomCenter))
                }
            }
        }

        composeRule.onNodeWithText("Kerem Kayalar").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun profile_live_stats_survive_progress_unavailability() {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                ProfileLoadedSurface(
                    profile = UserProfile(
                        id = "stats-contract",
                        fullName = "Test Uzmanı",
                        tier = SubscriptionTier.Free,
                    ),
                    stats = ProfileStats(analysisCount = 17, reportCount = 6, weeklyAnalysisCount = 4),
                    progress = null,
                )
            }
        }

        composeRule.onAllNodesWithText("17")[0].assertIsDisplayed()
        composeRule.onAllNodesWithText("6")[0].assertIsDisplayed()
        composeRule.onAllNodesWithText("4")[0].assertIsDisplayed()
    }
}
