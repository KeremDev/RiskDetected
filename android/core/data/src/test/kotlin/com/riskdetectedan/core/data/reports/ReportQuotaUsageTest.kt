package com.riskdetectedan.core.data.reports

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReportQuotaUsageTest {
    @Test
    fun `report archive contract decodes company snapshot relation`() {
        val report = Json.decodeFromString<Report>(
            """{"id":"report-1","storage_path":"u/a/report.pdf","company_id":"company-1"}""",
        )

        assertEquals("company-1", report.companyId)
    }

    @Test
    fun `standard quota is exhausted at the backend limit`() {
        assertTrue(ReportQuotaUsage(standardUsed = 1, standardLimit = 1, riskTrialUsed = false).isStandardQuotaExhausted)
        assertTrue(ReportQuotaUsage(standardUsed = 151, standardLimit = 150, riskTrialUsed = true).isStandardQuotaExhausted)
    }

    @Test
    fun `remaining standard quota is not exhausted independently of risk trial`() {
        assertFalse(ReportQuotaUsage(standardUsed = 149, standardLimit = 150, riskTrialUsed = true).isStandardQuotaExhausted)
        assertFalse(ReportQuotaUsage(standardUsed = 0, standardLimit = 1, riskTrialUsed = false).isStandardQuotaExhausted)
    }
}
