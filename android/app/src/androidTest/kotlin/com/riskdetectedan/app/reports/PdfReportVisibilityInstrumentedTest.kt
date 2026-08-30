package com.riskdetectedan.app.reports

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.reports.PdfReportGenerator
import com.riskdetectedan.core.data.reports.PdfReportInput
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class PdfReportVisibilityInstrumentedTest {
    @Test
    fun standardAndRiskAnalysisPdfsRenderWithoutConfidenceCopy() {
        val context: Context = InstrumentationRegistry.getInstrumentation().targetContext
        val generator = PdfReportGenerator(context)
        val finding = Finding(
            id = "finding-1",
            ordinal = 1,
            title = "Koruyucusuz makine parçası",
            category = "Makine güvenliği",
            description = "Dönen parçaya erişimi engelleyen fiziksel koruyucu bulunmuyor.",
            recommendedAction = "Uygun sabit koruyucu monte edilmeli.",
            confidence = 0.97,
            sourcePhotoIndices = listOf(1),
            fkProbability = 6.0,
            fkFrequency = 3.0,
            fkSeverity = 15.0,
            fkScore = 270.0,
            fkBand = "high",
            m5Probability = 4,
            m5Severity = 5,
            m5Score = 20,
            m5Band = "critical",
        )
        val outputDir = File(context.filesDir, "pdf-qa").apply { mkdirs() }

        listOf("standard", "risk_analysis").forEach { kind ->
            val generated = generator.generate(
                PdfReportInput(
                    kind = kind,
                    method = "fine_kinney",
                    title = "QA Raporu",
                    canvasLabel = "Makine",
                    createdAt = "2026-08-14T12:00:00Z",
                    findings = listOf(finding),
                    companyName = "RiskDetected QA",
                    companyAddress = "İstanbul",
                    companyLogoBytes = null,
                    preparedByName = "QA Uzmanı",
                    preparedByTitle = "İSG Uzmanı",
                    certificateNumber = "QA-001",
                    coverPhotoBytes = null,
                ),
            )
            assertTrue(generated.bytes.isNotEmpty())
            assertTrue(generated.pageCount >= 2)
            File(outputDir, "$kind.pdf").writeBytes(generated.bytes)
        }
    }
}
