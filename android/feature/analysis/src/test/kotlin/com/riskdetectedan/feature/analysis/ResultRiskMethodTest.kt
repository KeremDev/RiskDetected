package com.riskdetectedan.feature.analysis

import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.designsystem.RiskLevel
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ResultRiskMethodTest {
    private val finding = Finding(
        id = "finding-1",
        ordinal = 1,
        title = "Yüksekte çalışma",
        fkScore = 3600.0,
        fkBand = "critical",
        m5Score = 8,
        m5Band = "medium",
    )

    @Test fun `Fine Kinney view reads server FK score and band`() {
        assertEquals(3600.0, resultScore(finding, ResultRiskMethod.FineKinney), 0.0)
        assertEquals(RiskLevel.Critical, resultRiskLevel(finding, ResultRiskMethod.FineKinney))
    }

    @Test fun `five by five view reads server matrix score and band`() {
        assertEquals(8.0, resultScore(finding, ResultRiskMethod.Matrix5x5), 0.0)
        assertEquals(RiskLevel.Medium, resultRiskLevel(finding, ResultRiskMethod.Matrix5x5))
    }

    @Test fun `risk ordering remains critical high medium low unknown`() {
        assertEquals(
            listOf(RiskLevel.Critical, RiskLevel.High, RiskLevel.Medium, RiskLevel.Low, RiskLevel.Unknown),
            RiskLevel.entries.sortedByDescending(::riskRank),
        )
    }
}
