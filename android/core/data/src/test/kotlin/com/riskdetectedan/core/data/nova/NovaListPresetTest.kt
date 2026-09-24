package com.riskdetectedan.core.data.nova

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

/** A home card's list filter shows exactly what the card counted (iOS `NovaListPreset`, server `private_isg.home_feed`). */
class NovaListPresetTest {
    private val me = "20000000-0000-4000-8000-000000000001"
    private val other = "20000000-0000-4000-8000-000000000002"
    private val week = NovaListPreset("Son 7 günde 2 uygunsuzluk kaydettin", "recorded", "2026-09-18", "2026-09-24", null)

    private fun entry(state: String, createdAt: String? = null, by: String? = me, due: String? = null, kind: String? = null) =
        NovaNonconformityEntry(NovaNonconformityRow(id = "n", workplaceId = null, title = "Bulgu", severity = "high", state = state,
            version = 1, openedOn = "2026-09-01", dueOn = due, sourceKind = "manual", recordKind = kind, createdAt = createdAt,
            createdByUserId = by), "c", "Firma", null)

    @Test fun daysAreIstanbulDays() {
        // 21:30 UTC is already the next day in Istanbul (UTC+3).
        assertEquals("2026-09-18", NovaListPreset.istanbulDay(Instant.parse("2026-09-17T21:30:00Z")))
        assertTrue(week.includes(Instant.parse("2026-09-17T21:30:00Z")))
        assertFalse(week.includes(Instant.parse("2026-09-17T20:59:59Z")))
        assertTrue(week.isBefore(Instant.parse("2026-09-17T20:59:59Z")))
        assertFalse(week.isBefore(Instant.parse("2026-09-18T09:00:00Z")))
    }

    @Test fun readsServerTimestamps() {
        assertEquals(Instant.parse("2026-09-21T10:00:00.123456Z"), NovaListPreset.moment("2026-09-21T10:00:00.123456+00:00"))
        assertEquals(Instant.parse("2026-09-21T07:00:00Z"), NovaListPreset.moment("2026-09-21T10:00:00+03:00"))
        assertNull(NovaListPreset.moment("dün"))
    }

    @Test fun recordedCountsWhatWasWrittenInTheDays() {
        val today = "2026-09-24"
        assertTrue(entry("open", "2026-09-20T08:00:00+00:00").matches(week, today))
        assertFalse(entry("draft", "2026-09-20T08:00:00+00:00").matches(week, today))
        assertFalse(entry("cancelled", "2026-09-20T08:00:00+00:00").matches(week, today))
        assertFalse(entry("open", "2026-09-10T08:00:00+00:00").matches(week, today))
        assertFalse(entry("open", "2026-09-20T08:00:00+00:00", kind = "improvement").matches(week, today))
        assertFalse(entry("open", null).matches(week, today))
    }

    @Test fun mineNarrowsToTheMember() {
        val mine = week.copy(mine = me.uppercase())
        assertTrue(entry("open", "2026-09-20T08:00:00+00:00", by = me).matches(mine, "2026-09-24"))
        assertFalse(entry("open", "2026-09-20T08:00:00+00:00", by = other).matches(mine, "2026-09-24"))
        assertFalse(entry("open", "2026-09-20T08:00:00+00:00", by = null).matches(mine, "2026-09-24"))
    }

    @Test fun aDraftIsNeverOverdue() {
        val overdue = NovaListPreset("3 uygunsuzluğun termini geçti", "overdue", null, null, null)
        assertTrue(entry("open", due = "2026-09-20").matches(overdue, "2026-09-24"))
        assertFalse(entry("draft", due = "2026-09-20").isOverdue("2026-09-24"))
        assertFalse(entry("closed", due = "2026-09-20").matches(overdue, "2026-09-24"))
        assertFalse(entry("open", due = "2026-09-24").matches(overdue, "2026-09-24"))
    }

    @Test fun theBoardFilterCarriesThePreset() {
        val filter = NovaNonconformityFilter(preset = NovaListPreset("1 taslak uygunsuzluk", "draft", null, null, null))
        assertFalse(filter.isEmpty)
        assertTrue(entry("draft").matches(filter, "2026-09-24"))
        assertFalse(entry("open").matches(filter, "2026-09-24"))
    }
}
