package com.riskdetectedan.feature.analysis

import android.app.Application
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import com.riskdetectedan.core.data.analysis.AnalysisResultSummary
import com.riskdetectedan.core.data.analysis.AnalysisResultAccess
import com.riskdetectedan.core.data.analysis.AnalysisResultDisclaimers
import com.riskdetectedan.core.data.analysis.AnalysisResultHubItem
import com.riskdetectedan.core.data.analysis.AnalysisResultHubResponse
import com.riskdetectedan.core.data.analysis.AnalysisResultSection
import com.riskdetectedan.core.data.analysis.AnalysisResultSectionId
import com.riskdetectedan.core.data.analysis.AnalysisItemReaction
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FindingMeasure
import com.riskdetectedan.core.data.analysis.PlanCapabilities
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.data.reports.ReportQuotaUsage
import com.riskdetectedan.core.designsystem.RiskDetectedTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(
    application = Application::class,
    sdk = [35],
    qualifiers = "tr-rTR-w393dp-h852dp-xxhdpi",
)
class AnalysisParityGoldenTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val exactPixelOptions = RoborazziOptions(
        compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0f),
    )

    // Native Skia rounds the multi-stop gradients in this sheet by 1-2 channel values between
    // macOS and Linux. Keep the allowance below any visible/layout delta and scoped to this one
    // cross-platform capture; every other release golden remains exact-pixel.
    private val crossPlatformGradientOptions = RoborazziOptions(
        compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0.000003f),
    )

    @Test
    fun analysis_waiting_polling_light() {
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                IosParityAnalyzingView(
                    state = CreateAnalysisUiState.Polling("analysis-1"),
                    previewPhotoPath = null,
                    previewPhotoBytes = null,
                    photoCount = 3,
                )
            }
        }

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun free_result_plus_pro_ctas_light() {
        setResultContent(
            capabilities = PlanCapabilities.forTier(SubscriptionTier.Free),
            reportState = ResultReportUiState.Idle,
        )
        composeRule.onNode(hasScrollAction()).performScrollToNode(hasText("Gizli uygunsuzluk"))

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pro_finding_detail_light() {
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Idle,
        )
        composeRule.onNodeWithText("Koruyucusuz hareketli makine parçası").performClick()

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pro_finding_detail_actions_dark() {
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Idle,
            darkTheme = true,
        )
        composeRule.onNodeWithText("Koruyucusuz hareketli makine parçası").performClick()

        composeRule.onNode(hasContentDescription("Düzenle")).assertIsDisplayed()
        composeRule.onNodeWithText("Raporu İndir").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pro_finding_detail_root_cause_dark() {
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Idle,
            darkTheme = true,
        )
        composeRule.onNodeWithText("Koruyucusuz hareketli makine parçası").performClick()
        composeRule.onAllNodes(hasScrollAction())[1]
            .performScrollToNode(hasText("KÖK NEDEN", substring = true))

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun free_finding_detail_uses_ios_membership_promotion_light() {
        setResultContent(
            capabilities = PlanCapabilities.forTier(SubscriptionTier.Free),
            reportState = ResultReportUiState.Idle,
        )
        composeRule.onNodeWithText("Koruyucusuz hareketli makine parçası").performClick()
        composeRule.onAllNodes(hasScrollAction())[1]
            .performScrollToNode(hasText("Analizini PLUS ve PRO ile güçlendir"))
        composeRule.onNodeWithText("Planları incele").assertIsDisplayed()

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pro_result_dark() {
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Idle,
            darkTheme = true,
        )

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pro_result_hub_risk_analysis_light() {
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Idle,
            resultHub = resultHub,
        )

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pro_result_hub_risk_analysis_dark() {
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Idle,
            darkTheme = true,
            resultHub = resultHub,
        )

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pro_result_hub_like_selected_light() {
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Idle,
            resultHub = resultHub,
            reduceFeedbackLocally = true,
        )

        composeRule.onNode(hasContentDescription("Beğen")).performClick()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pro_result_hub_training_recommendations_light() {
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Idle,
            resultHub = resultHub,
        )
        composeRule.onNodeWithText("Eğitim Önerileri").performClick()
        composeRule.onNodeWithText("İş ekipmanlarının güvenli kullanımı").assertIsDisplayed()

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun free_result_hub_uses_ios_premium_teasers_for_all_locked_sections() {
        val teaserHub = resultHub.copy(
            tier = "free",
            sections = resultHub.sections.map { section ->
                if (section.id == AnalysisResultSectionId.RiskAnalysis) section
                else section.copy(access = AnalysisResultAccess.Teaser, canEdit = false, canReport = false)
            },
        )
        setResultContent(
            capabilities = PlanCapabilities.forTier(SubscriptionTier.Free),
            reportState = ResultReportUiState.Idle,
            resultHub = teaserHub,
        )

        composeRule.onNodeWithText("Uzman Görüşü").performClick()
        composeRule.onNodeWithText("Koruyucu uygunluğunu…").assertIsDisplayed()
        composeRule.onAllNodesWithText("Koruyucu uygunluğunu sahada teyit edin").assertCountEquals(0)
        composeRule.onNodeWithText("Bu özellikler premium özelliktir.").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)

        composeRule.onNodeWithText("Eğitim Önerileri").performClick()
        composeRule.onNodeWithText("İş ekipmanlarının…").assertIsDisplayed()
        composeRule.onAllNodesWithText("İş ekipmanlarının güvenli kullanımı").assertCountEquals(0)

        composeRule.onNodeWithText("Onaylı Defter").performClick()
        composeRule.onNodeWithText("Koruyucusuz ekipman…").assertIsDisplayed()
        composeRule.onAllNodesWithText("Koruyucusuz ekipman gözlenmiştir. Uygun koruyucu takılmalıdır.").assertCountEquals(0)
    }

    @Test
    fun risk_report_sheet_requires_an_explicit_report_type_selection() {
        setResultContent(proCapabilities(), ResultReportUiState.Idle, reportSetup)
        composeRule.onNodeWithText("Rapor Oluştur").performClick()

        composeRule.onNodeWithText("Rapor türü seçin").assertIsDisplayed().assertIsNotEnabled()
        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
        composeRule.onNodeWithText("Standart Rapor").performClick()
        composeRule.onAllNodesWithText("Rapor Oluştur")[1].assertIsDisplayed().assertIsEnabled()
    }

    @Test
    fun report_kind_wire_value_follows_the_selected_card_not_the_active_section() {
        org.junit.Assert.assertEquals("standard", ParityReportKind.Standard.wireValue())
        org.junit.Assert.assertEquals("risk_analysis", ParityReportKind.RiskAnalysis.wireValue())
    }

    @Test
    fun free_risk_report_sheet_dark_has_legible_trial_and_themed_cta() {
        setResultContent(
            capabilities = PlanCapabilities.forTier(SubscriptionTier.Free),
            reportState = ResultReportUiState.Idle,
            reportSetup = ResultReportSetup(
                quotaUsage = ReportQuotaUsage(standardUsed = 0, standardLimit = 1, riskTrialUsed = false),
            ),
            darkTheme = true,
            resultHub = resultHub.copy(tier = "free"),
        )
        composeRule.onNodeWithText("Rapor Oluştur").performClick()

        composeRule.onNodeWithText("Hoş geldin, 1 risk analizi oluşturma hakkını hemen kullan!").assertIsDisplayed()
        composeRule.onNodeWithText("Analizlerini Fine-Kinney veya 5×5 Matris ile hesapla, PDF ya da Excel olarak rapor oluştur ve paylaş.").assertIsDisplayed()
        composeRule.onNodeWithText("Rapor türü seçin").assertIsDisplayed().assertIsNotEnabled()
        composeRule.onNodeWithText("Standart Rapor").performClick()
        composeRule.onAllNodesWithText("Rapor Oluştur")[1].assertIsDisplayed().assertIsEnabled()
        composeRule.onRoot().captureRoboImage(roborazziOptions = crossPlatformGradientOptions)
    }

    @Test
    fun used_free_risk_report_gift_hides_ribbon_and_locks_the_table() {
        setResultContent(
            capabilities = PlanCapabilities.forTier(SubscriptionTier.Free),
            reportState = ResultReportUiState.Idle,
            reportSetup = ResultReportSetup(
                quotaUsage = ReportQuotaUsage(standardUsed = 0, standardLimit = 1, riskTrialUsed = true),
            ),
            resultHub = resultHub.copy(tier = "free"),
        )
        composeRule.onNodeWithText("Rapor Oluştur").performClick()

        composeRule.onAllNodesWithText("Hoş geldin, 1 risk analizi oluşturma hakkını hemen kullan!").assertCountEquals(0)
        composeRule.onNodeWithText("Bir kez tanımlanan hakkını kullandın. Risk analizi tabloları Plus ile devam eder.").assertIsDisplayed()
        composeRule.onNodeWithText("PLUS/PRO").assertIsDisplayed()
        composeRule.onRoot().captureRoboImage(roborazziOptions = crossPlatformGradientOptions)
        composeRule.onNodeWithText("Standart Rapor").performClick()
        composeRule.onAllNodesWithText("Rapor Oluştur")[1].assertIsDisplayed().assertIsEnabled()
    }

    @Test
    fun result_hub_dislike_offers_custom_feedback_composer_action() {
        // The focused Material text field has a perpetual cursor blink. Keep the test clock
        // explicit so Robolectric does not wait for that visual-only animation to become idle.
        composeRule.mainClock.autoAdvance = false
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Idle,
            resultHub = resultHub,
        )
        composeRule.onNode(hasContentDescription("Beğenme")).performClick()
        composeRule.mainClock.advanceTimeBy(1_000)
        // Finding and clicking this action proves the dislike reason dialog is available. Do
        // not query semantics after the focused field opens: Robolectric treats Material's
        // perpetual cursor as a non-idle UI, while device QA covers the rendered composer.
        composeRule.onNodeWithText("Nedenini yazmak istiyorum").performClick()
    }

    @Test
    fun pro_finding_editor_matches_ios_sheet_light() {
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Idle,
        )
        composeRule.onNode(hasScrollAction()).performScrollToNode(hasText("Koruyucusuz hareketli makine parçası"))
        composeRule.onAllNodes(hasContentDescription("Bulguyu düzenle"))[0].performClick()
        composeRule.onNodeWithText("Düzeltici faaliyet").assertIsDisplayed()
        composeRule.onNodeWithText("Önleyici kontrol").assertIsDisplayed()

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pro_pdf_generation_overlay_light() {
        composeRule.mainClock.autoAdvance = false
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Generating(ResultReportFormat.Pdf, .68f),
        )

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun pro_risk_report_company_settings_light() {
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Idle,
            reportSetup = reportSetup,
        )
        composeRule.onNodeWithText("Rapor Oluştur").performClick()
        composeRule.onNodeWithText("Risk Analizi Tablosu").performClick()
        composeRule.onAllNodes(hasScrollAction())[1].performScrollToNode(hasText("RAPOR FİRMASI"))

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    @Test
    fun report_company_picker_can_continue_without_company() {
        setResultContent(proCapabilities(), ResultReportUiState.Idle, reportSetup)
        composeRule.onNodeWithText("Rapor Oluştur").performClick()
        composeRule.onNodeWithText("Risk Analizi Tablosu").performClick()
        composeRule.onAllNodes(hasScrollAction())[1].performScrollToNode(hasText("RAPOR FİRMASI"))
        composeRule.onNodeWithText("Değiştir").performClick()
        composeRule.onNodeWithText("Firma seçmeden devam et").performClick()
        composeRule.onNodeWithText("Firma seçmeden devam et").assertIsDisplayed()
    }

    private fun setResultContent(
        capabilities: PlanCapabilities,
        reportState: ResultReportUiState,
        reportSetup: ResultReportSetup = ResultReportSetup(),
        darkTheme: Boolean = false,
        resultHub: AnalysisResultHubResponse? = null,
        reduceFeedbackLocally: Boolean = false,
    ) {
        composeRule.setContent {
            var displayedHub by remember(resultHub, reduceFeedbackLocally) { mutableStateOf(resultHub) }
            RiskDetectedTheme(darkTheme = darkTheme) {
                IosParityResultView(
                    analysisId = "analysis-1",
                    findings = findings,
                    summary = summary,
                    photoBytes = emptyList(),
                    resultHub = displayedHub,
                    capabilities = capabilities,
                    reportState = reportState,
                    reportSetup = reportSetup,
                    onGenerateReport = { _, _, _, _ -> },
                    onReportFileConsumed = {},
                    onReportErrorDismiss = {},
                    onBack = {},
                    onDelete = {},
                    onUpdate = { _, _ -> },
                    onOpenCompanies = {},
                    onUpgradeTier = {},
                    onFeedback = { sectionId, item, reaction, _, _ ->
                        if (reduceFeedbackLocally) {
                            displayedHub = displayedHub?.copy(
                                sections = displayedHub.orEmptySections().map { section ->
                                    if (section.id == sectionId) {
                                        section.copy(
                                            items = section.items.map { candidate ->
                                                if (candidate.id == item.id) candidate.copy(userReaction = reaction) else candidate
                                            },
                                        )
                                    } else {
                                        section
                                    }
                                },
                            )
                        }
                    },
                )
            }
        }
    }

    private fun AnalysisResultHubResponse?.orEmptySections(): List<AnalysisResultSection> = this?.sections.orEmpty()

    private fun proCapabilities(): PlanCapabilities = PlanCapabilities.forTier(SubscriptionTier.Pro).copy(
        maxPhotosPerAnalysis = 3,
        visiblePhotoSlotsInUI = 3,
        maxFindingsPerAnalysis = 39,
        canUseMultiPhotoAnalysis = true,
        canEditAIFindings = true,
    )

    private val summary = AnalysisResultSummary(
        id = "analysis-1",
        title = "Üretim Hattı Risk Analizi",
        canvas = "general",
        createdAt = "2026-08-09T10:30:00+03:00",
        analysisSector = "manufacturing",
        companyId = "company-1",
        primaryMethod = "fine_kinney",
    )

    private val reportSetup = ResultReportSetup(
        profile = UserProfile(
            id = "user-1",
            email = "uzman@example.com",
            fullName = "Ayşe Yılmaz",
            title = "A Sınıfı İSG Uzmanı",
            certificateNumber = "A-12345",
            companyName = "RiskDetected Saha",
            tier = SubscriptionTier.Pro,
        ),
        companies = listOf(
            Company(
                id = "company-1",
                userId = "user-1",
                name = "Örnek Üretim A.Ş.",
                hazardClassId = "high",
                address = "İstanbul Fabrikası",
                contactPerson = "Saha Sorumlusu",
            ),
        ),
    )

    private val resultHub = AnalysisResultHubResponse(
        enabled = true,
        uiVersion = "analysis-result-hub-v2",
        analysisId = "analysis-1",
        analysisEditVersion = 4,
        tier = "pro",
        language = "tr",
        disclaimers = AnalysisResultDisclaimers(
            expert = "Uzman önerilerini işyerinize uygunluk açısından kontrol edin.",
            notebook = "Onaylı Defter taslakları uzman değerlendirmesi gerektirir.",
        ),
        sections = listOf(
            AnalysisResultSection(
                id = AnalysisResultSectionId.RiskAnalysis,
                access = AnalysisResultAccess.Full,
                count = 1,
                canEdit = true,
                canReport = true,
                items = listOf(
                    AnalysisResultHubItem(
                        id = "risk-1",
                        title = "Koruyucusuz hareketli makine parçası",
                        description = "Dönen ekipmana erişim fiziksel bir koruyucu ile sınırlandırılmamış.",
                        recommendedAction = "Sabit koruyucu takılmalı ve enerji kesme prosedürü uygulanmalıdır.",
                        recommendedMeasures = listOf(
                            FindingMeasure(kind = "corrective", text = "Sabit koruyucu takılmalı ve enerji kesme prosedürü uygulanmalıdır."),
                            FindingMeasure(kind = "preventive", text = "Periyodik koruyucu kontrol listesi uygulanmalıdır."),
                        ),
                        rootCauseText = "Koruyucu bakım kontrolü uygulanmamış.",
                        referencesText = "İş Ekipmanlarının Kullanımında Sağlık ve Güvenlik Şartları Yönetmeliği",
                        fkScore = 540.0,
                        fkBand = "critical",
                        m5Score = 20,
                        m5Band = "critical",
                    ),
                ),
            ),
            AnalysisResultSection(
                id = AnalysisResultSectionId.ExpertRecommendations,
                access = AnalysisResultAccess.Full,
                count = 1,
                canReport = true,
                items = listOf(AnalysisResultHubItem(id = "expert-1", title = "Koruyucu uygunluğunu sahada teyit edin", description = "Koruyucu açıklıkları ve kilitleme düzenini kontrol edin.")),
            ),
            AnalysisResultSection(
                id = AnalysisResultSectionId.TrainingRecommendations,
                access = AnalysisResultAccess.Full,
                count = 1,
                canReport = false,
                items = listOf(
                    AnalysisResultHubItem(
                        id = "training-1",
                        catalogCode = "tr-work-equipment-01",
                        title = "İş ekipmanlarının güvenli kullanımı",
                        categoryLabel = "İş Ekipmanı",
                        audienceLabel = "Ekipmanı kullanan çalışanlar",
                        text = "Koruyucular, güvenli kullanım ve enerji kesme adımları birlikte ele alınmalıdır.",
                        durationLabel = "Tehlike sınıfına göre",
                        durationValue = "8 / 12 / 16 saat",
                        durationNote = "İşyerinin tehlike sınıfına göre planlanır.",
                    ),
                ),
            ),
            AnalysisResultSection(
                id = AnalysisResultSectionId.ApprovedNotebook,
                access = AnalysisResultAccess.Full,
                count = 1,
                canEdit = true,
                canReport = true,
                observationBasis = "direct_site_observation",
                items = listOf(AnalysisResultHubItem(id = "book-1", findingText = "Koruyucusuz ekipman gözlenmiştir.", recommendationText = "Uygun koruyucu takılmalıdır.")),
            ),
        ),
    )

    private val findings = listOf(
        Finding(
            id = "finding-1",
            ordinal = 1,
            title = "Koruyucusuz hareketli makine parçası",
            category = "Makine Güvenliği",
            description = "Dönen ekipmana erişim fiziksel bir koruyucu ile sınırlandırılmamış.",
            recommendedAction = "Sabit koruyucu takılmalı ve enerji kesme prosedürü uygulanmalı.",
            recommendedMeasures = listOf(
                FindingMeasure("corrective", "Düzeltici", "Sabit koruyucu ve emniyet kilidi monte edin."),
                FindingMeasure("preventive", "Önleyici", "Periyodik koruyucu kontrolünü bakım planına ekleyin."),
            ),
            confidence = .94,
            needsFieldVerification = true,
            sourcePhotoIndices = listOf(1),
            fkProbability = 6.0,
            fkFrequency = 6.0,
            fkSeverity = 15.0,
            fkScore = 540.0,
            fkBand = "critical",
            m5Probability = 4,
            m5Severity = 5,
            m5Score = 20,
            m5Band = "critical",
            referencesText = "6331 sayılı Kanun ve İş Ekipmanları Yönetmeliği",
            rootCauseText = "Makine koruyucu kabul kontrolünün tamamlanmaması",
        ),
        Finding(
            id = "finding-2",
            ordinal = 2,
            title = "Yaya yolu ile forklift rotası kesişiyor",
            category = "Trafik Düzeni",
            description = "Yaya ve araç yolları fiziksel bariyerle ayrılmamış.",
            recommendedAction = "Yaya yolunu bariyer ve zemin işaretleriyle ayırın.",
            confidence = .88,
            sourcePhotoIndices = listOf(2, 3),
            fkProbability = 3.0,
            fkFrequency = 6.0,
            fkSeverity = 15.0,
            fkScore = 270.0,
            fkBand = "high",
            m5Probability = 3,
            m5Severity = 4,
            m5Score = 12,
            m5Band = "high",
        ),
    )
}
