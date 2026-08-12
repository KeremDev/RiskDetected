package com.riskdetectedan.core.data.reports

import kotlinx.serialization.json.Json
import com.riskdetectedan.core.data.profile.SubscriptionTier
import java.time.Instant
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

    @Test
    fun `free quota resets at Istanbul midnight rather than UTC midnight`() {
        val now = Instant.parse("2026-08-11T21:30:00Z") // 12 August 00:30 in Istanbul.
        assertEquals(
            Instant.parse("2026-08-11T21:00:00Z"),
            ReportQuotaWindow.periodStart(SubscriptionTier.Free, now),
        )
    }

    @Test
    fun `paid quota starts at first Istanbul day of month`() {
        val now = Instant.parse("2026-08-11T21:30:00Z")
        val expected = Instant.parse("2026-07-31T21:00:00Z")
        assertEquals(expected, ReportQuotaWindow.periodStart(SubscriptionTier.Plus, now))
        assertEquals(expected, ReportQuotaWindow.periodStart(SubscriptionTier.Pro, now))
    }
}
