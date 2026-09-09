package com.riskdetectedan.core.data.reports

import org.junit.Assert.assertEquals
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
    fun `risk analysis matches iOS reference then assessment table contract`() {
        val sections = pdfReportSectionOrder("risk_analysis")

        assertEquals(listOf(PdfReportSection.MethodReference, PdfReportSection.RiskAssessmentTable), sections)
    }
}
