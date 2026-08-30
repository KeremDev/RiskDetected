package com.riskdetectedan.core.common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Locale

class RdClientMetadataTest {
    @Test
    fun `Turkish locale sends the Turkey safety context`() {
        assertEquals("android", RdClientMetadata.PLATFORM)
        assertEquals(3, RdClientMetadata.API_CONTRACT_VERSION)
        val context = RdClientMetadata.localization(Locale.forLanguageTag("tr-TR"))
        assertEquals("tr", context.appLanguage)
        assertEquals("tr-TR", context.contentLocale)
        assertEquals("TR", context.workJurisdictionCountry)
        assertEquals("tr-tr-current-v1", context.safetyProfileId)
        assertEquals(1, context.safetyProfileVersion)
        assertEquals("fine_kinney", context.defaultRiskMethod)
        assertEquals("tr-android-v1", context.legalDocumentSetId)
    }

    @Test
    fun `supported English regions use matching generic safety profiles`() {
        val expected = mapOf(
            "en-GB" to Triple("en-GB", "GB", "en-gb-generic-v1"),
            "en-US" to Triple("en-US", "US", "en-us-generic-v1"),
            "en-AU" to Triple("en-AU", "AU", "en-au-generic-v1"),
            "en-CA" to Triple("en-CA", "CA", "en-ca-generic-v1"),
            "en-NZ" to Triple("en-001", "INTL", "en-intl-generic-v1"),
        )
        expected.forEach { (tag, values) ->
            val context = RdClientMetadata.localization(Locale.forLanguageTag(tag))
            assertEquals("en", context.appLanguage)
            assertEquals(values.first, context.contentLocale)
            assertEquals(values.second, context.workJurisdictionCountry)
            assertEquals(values.third, context.safetyProfileId)
            assertEquals("matrix_5x5", context.defaultRiskMethod)
            assertEquals("en-global-v1", context.legalDocumentSetId)
        }
    }

    @Test
    fun `global localization capability is compiled in`() {
        assertTrue(RdClientMetadata.capabilities.getValue("global_localization_wave1"))
    }

    @Test
    fun `explicit onboarding safety profile overrides the device region deterministically`() {
        val context = RdClientMetadata.localizationForSafetyProfile("en-gb-generic-v1")

        requireNotNull(context)
        assertEquals("en", context.appLanguage)
        assertEquals("en-GB", context.contentLocale)
        assertEquals("GB", context.workJurisdictionCountry)
        assertEquals("matrix_5x5", context.defaultRiskMethod)
        assertEquals("en-global-v1", context.legalDocumentSetId)
        assertNull(RdClientMetadata.localizationForSafetyProfile("unsupported-profile"))
    }
}
