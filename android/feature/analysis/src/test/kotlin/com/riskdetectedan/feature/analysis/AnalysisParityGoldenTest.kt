package com.riskdetectedan.feature.analysis

import android.app.Application
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import com.github.takahirom.roborazzi.RoborazziOptions
import com.github.takahirom.roborazzi.captureRoboImage
import com.riskdetectedan.core.data.analysis.AnalysisResultSummary
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FindingMeasure
import com.riskdetectedan.core.data.analysis.PlanCapabilities
import com.riskdetectedan.core.data.profile.SubscriptionTier
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
    qualifiers = "w393dp-h852dp-xxhdpi",
)
class AnalysisParityGoldenTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val exactPixelOptions = RoborazziOptions(
        compareOptions = RoborazziOptions.CompareOptions(changeThreshold = 0f),
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
    fun pro_pdf_generation_overlay_light() {
        composeRule.mainClock.autoAdvance = false
        setResultContent(
            capabilities = proCapabilities(),
            reportState = ResultReportUiState.Generating(ResultReportFormat.Pdf, .68f),
        )

        composeRule.onRoot().captureRoboImage(roborazziOptions = exactPixelOptions)
    }

    private fun setResultContent(
        capabilities: PlanCapabilities,
        reportState: ResultReportUiState,
    ) {
        composeRule.setContent {
            RiskDetectedTheme(darkTheme = false) {
                IosParityResultView(
                    analysisId = "analysis-1",
                    findings = findings,
                    summary = summary,
                    photoBytes = emptyList(),
                    capabilities = capabilities,
                    reportState = reportState,
                    onGenerateReport = { _, _, _, _ -> },
                    onReportFileConsumed = {},
                    onReportErrorDismiss = {},
                    onBack = {},
                    onDelete = {},
                    onUpdate = { _, _ -> },
                    onOpenCompanies = {},
                    onUpgradeTier = {},
                )
            }
        }
    }

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
        primaryMethod = "fine_kinney",
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
