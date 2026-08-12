package com.riskdetectedan.core.data.reports

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class PdfReportContractTest {

    @Test
    fun `standard report is cover then finding details`() {
        assertEquals(
            listOf(PdfReportSection.Cover, PdfReportSection.FindingDetails),
            pdfReportSectionOrder("standard"),
        )
    }

    @Test
    fun `risk analysis follows iOS reference then assessment table contract`() {
        val sections = pdfReportSectionOrder("risk_analysis")

        assertEquals(
            listOf(PdfReportSection.MethodReference, PdfReportSection.RiskAssessmentTable),
            sections,
        )
        assertFalse(sections.contains(PdfReportSection.Cover))
        assertFalse(sections.contains(PdfReportSection.FindingDetails))
    }
}
