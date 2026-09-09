package com.riskdetectedan.core.data.progress

import java.util.Locale
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class ProfessionalProgressBadgeLocalizationTest {
    private lateinit var originalLocale: Locale

    @Before
    fun rememberLocale() {
        originalLocale = Locale.getDefault()
    }

    @After
    fun restoreLocale() {
        Locale.setDefault(originalLocale)
    }

    @Test
    fun `legacy server badge copy is localized for English sessions`() {
        Locale.setDefault(Locale.US)
        val badge = badge(
            key = "reports:10",
            title = "Kararlı Başlangıç",
            subtitle = "10 rapora ulaştın.",
        )

        assertEquals("Steady Start", badge.localizedTitle)
        assertEquals(
            "You reached 10 reports. Your reporting discipline is getting stronger.",
            badge.localizedSubtitle,
        )
    }

    @Test
    fun `Turkish sessions keep authoritative server badge copy`() {
        Locale.setDefault(Locale.forLanguageTag("tr-TR"))
        val badge = badge(
            key = "reports:10",
            title = "Kararlı Başlangıç",
            subtitle = "10 rapora ulaştın.",
        )

        assertEquals("Kararlı Başlangıç", badge.localizedTitle)
        assertEquals("10 rapora ulaştın.", badge.localizedSubtitle)
    }

    @Test
    fun `future unknown badge falls back to server copy`() {
        Locale.setDefault(Locale.US)
        val badge = badge(
            key = "future:badge",
            title = "Future Badge",
            subtitle = "Future badge details",
        )

        assertEquals("Future Badge", badge.localizedTitle)
        assertEquals("Future badge details", badge.localizedSubtitle)
    }

    private fun badge(key: String, title: String, subtitle: String) = ProfessionalProgressBadge(
        id = "badge-id",
        badgeKey = key,
        badgeType = "report_count",
        title = title,
        subtitle = subtitle,
        iconName = "medal.fill",
    )
}
