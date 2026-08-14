package com.riskdetectedan.app.home

import com.riskdetectedan.core.data.analysis.AnalysisCanvas
import org.junit.Assert.assertEquals
import org.junit.Test

class CanvasSelectionTest {
    @Test
    fun `specific focus replaces default general focus for paid user`() {
        assertEquals(
            setOf(AnalysisCanvas.sector),
            nextCanvasSelection(
                selected = setOf(AnalysisCanvas.general),
                tapped = AnalysisCanvas.sector,
                isPaidTier = true,
            ),
        )
    }

    @Test
    fun `general focus replaces all specific focuses`() {
        assertEquals(
            setOf(AnalysisCanvas.general),
            nextCanvasSelection(
                selected = setOf(AnalysisCanvas.sector, AnalysisCanvas.explosion),
                tapped = AnalysisCanvas.general,
                isPaidTier = true,
            ),
        )
    }

    @Test
    fun `paid user can still combine specific focuses`() {
        assertEquals(
            setOf(AnalysisCanvas.sector, AnalysisCanvas.explosion),
            nextCanvasSelection(
                selected = setOf(AnalysisCanvas.sector),
                tapped = AnalysisCanvas.explosion,
                isPaidTier = true,
            ),
        )
    }
}
