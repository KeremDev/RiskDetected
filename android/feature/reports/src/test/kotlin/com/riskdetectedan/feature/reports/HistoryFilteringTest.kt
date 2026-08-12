package com.riskdetectedan.feature.reports

import com.riskdetectedan.core.data.analysis.HistoryItem
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HistoryFilteringTest {
    private val now = Instant.parse("2026-08-12T09:00:00Z")
    private val items = listOf(
        item("critical", "İskele Kontrolü", "Genel", "company-a", "2026-08-11T09:00:00Z", "critical"),
        item("ppe", "Baret kontrolü", "KKD", "company-b", "2026-08-01T09:00:00Z", "low"),
        item("future", "İleri tarih", "Genel", "company-a", "2026-08-13T09:00:00Z", "medium"),
    )

    @Test fun `week window includes boundary and rejects future timestamps`() {
        assertTrue(isWithinLastWeek("2026-08-05T09:00:00Z", now))
        assertTrue(isWithinLastWeek("2026-08-12T09:00:00Z", now))
        assertFalse(isWithinLastWeek("2026-08-05T08:59:59Z", now))
        assertFalse(isWithinLastWeek("2026-08-13T09:00:00Z", now))
        assertFalse(isWithinLastWeek("not-a-date", now))
    }

    @Test fun `search is Turkish case insensitive and combines with chip`() {
        assertEquals(
            listOf("critical"),
            filterHistoryItems(items, "İSKELE", HistoryFilterChip.Critical, now = now).map { it.id },
        )
        assertEquals(
            listOf("ppe"),
            filterHistoryItems(items, "kkd", HistoryFilterChip.Ppe, now = now).map { it.id },
        )
    }

    @Test fun `focused analysis and company filters compose without leaking other rows`() {
        assertEquals(
            listOf("critical"),
            filterHistoryItems(
                items = items,
                search = "",
                chip = HistoryFilterChip.All,
                focusedAnalysisId = "critical",
                selectedCompanyId = "company-a",
                now = now,
            ).map { it.id },
        )
        assertTrue(
            filterHistoryItems(
                items = items,
                search = "",
                chip = HistoryFilterChip.All,
                focusedAnalysisId = "ppe",
                selectedCompanyId = "company-a",
                now = now,
            ).isEmpty(),
        )
    }

    private fun item(
        id: String,
        title: String,
        kind: String,
        companyId: String,
        createdAt: String,
        risk: String,
    ) = HistoryItem(
        id = id,
        title = title,
        canvas = "general",
        status = "completed",
        kind = kind,
        findingCount = 1,
        highestBandFk = risk,
        companyId = companyId,
        createdAt = createdAt,
    )
}
