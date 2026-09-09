package com.riskdetectedan.core.data.profile

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import java.util.Locale

/**
 * The repair may never invent a language for an account that already declared one — a wrong guess
 * here reaches the user as notifications and reports in the wrong language, which is worse than
 * the missing-locale gap it exists to close.
 */
class ProfileLocalizationResolutionTest {

    private lateinit var originalLocale: Locale

    @Before
    fun captureLocale() {
        originalLocale = Locale.getDefault()
        Locale.setDefault(Locale.forLanguageTag("tr-TR"))
    }

    @After
    fun restoreLocale() {
        Locale.setDefault(originalLocale)
    }

    @Test
    fun `a profile with nothing recorded takes the device contract`() {
        val resolved = resolveContext(ProfileLocalizationRow())

        assertEquals("tr", resolved.appLanguage)
        assertEquals("tr-TR", resolved.contentLocale)
        assertEquals("TR", resolved.workJurisdictionCountry)
        assertEquals("tr-android-v1", resolved.legalDocumentSetId)
    }

    @Test
    fun `an english account keeps english even on a turkish device`() {
        val resolved = resolveContext(ProfileLocalizationRow(appLanguage = "EN"))

        assertEquals("en", resolved.appLanguage)
        assertEquals("en-001", resolved.contentLocale)
        assertEquals("en-global-v1", resolved.legalDocumentSetId)
    }

    @Test
    fun `an existing safety profile decides the contract, not the device`() {
        val resolved = resolveContext(
            ProfileLocalizationRow(safetyProfileId = "en-gb-generic-v1"),
        )

        assertEquals("en", resolved.appLanguage)
        assertEquals("en-GB", resolved.contentLocale)
        assertEquals("GB", resolved.workJurisdictionCountry)
    }

    @Test
    fun `an unrecognised safety profile does not block the repair`() {
        val resolved = resolveContext(
            ProfileLocalizationRow(safetyProfileId = "retired-profile-v0"),
        )

        assertEquals("tr", resolved.appLanguage)
        assertEquals("tr-TR", resolved.contentLocale)
    }
}
