package com.riskdetectedan.core.data.profile

import org.junit.Assert.assertEquals
import org.junit.Test

class UserProfileLocalizationTest {
    @Test
    fun `persisted onboarding safety profile drives analysis and report metadata`() {
        val profile = UserProfile(
            id = "user-1",
            tier = SubscriptionTier.Free,
            appLanguage = "en",
            preferredContentLocale = "en-GB",
            workJurisdictionCountry = "GB",
            safetyProfileId = "en-gb-generic-v1",
            safetyProfileVersion = 1,
            legalDocumentSetId = "en-global-v1",
        )

        val context = profile.resolvedLocalizationContext()

        assertEquals("en", context.appLanguage)
        assertEquals("en-GB", context.contentLocale)
        assertEquals("GB", context.workJurisdictionCountry)
        assertEquals("en-gb-generic-v1", context.safetyProfileId)
        assertEquals("matrix_5x5", context.defaultRiskMethod)
        assertEquals("en-global-v1", context.legalDocumentSetId)
    }

    @Test
    fun `profile preferred method wins over safety profile default`() {
        val profile = UserProfile(
            id = "user-2",
            tier = SubscriptionTier.Pro,
            preferredMethod = "fine_kinney",
            safetyProfileId = "en-us-generic-v1",
        )

        assertEquals("fine_kinney", profile.resolvedLocalizationContext().defaultRiskMethod)
    }
}
