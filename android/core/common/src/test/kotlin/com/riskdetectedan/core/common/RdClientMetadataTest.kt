package com.riskdetectedan.core.common

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class RdClientMetadataTest {
    @Test
    fun `first Android release sends the frozen Turkish Turkey context`() {
        assertEquals("android", RdClientMetadata.PLATFORM)
        assertEquals(2, RdClientMetadata.API_CONTRACT_VERSION)
        assertEquals("tr", RdClientMetadata.APP_LANGUAGE)
        assertEquals("tr-TR", RdClientMetadata.CONTENT_LOCALE)
        assertEquals("TR", RdClientMetadata.WORK_JURISDICTION_COUNTRY)
        assertEquals("tr-tr-current-v1", RdClientMetadata.SAFETY_PROFILE_ID)
        assertEquals(1, RdClientMetadata.SAFETY_PROFILE_VERSION)
        assertEquals("fine_kinney", RdClientMetadata.DEFAULT_RISK_METHOD)
    }

    @Test
    fun `global localization remains fail closed while Turkish parity is implemented`() {
        assertFalse(RdClientMetadata.capabilities.getValue("global_localization_wave1"))
    }
}
