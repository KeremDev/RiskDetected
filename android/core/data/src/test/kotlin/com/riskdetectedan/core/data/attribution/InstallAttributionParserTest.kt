package com.riskdetectedan.core.data.attribution

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class InstallAttributionParserTest {
    @Test
    fun `keeps only bounded allow-listed UTM values`() {
        val parsed = parseInstallReferrer(
            "utm_source=google&utm_medium=cpc&utm_campaign=android%20launch&gclid=secret-id",
        )

        assertEquals("google", parsed["utm_source"])
        assertEquals("cpc", parsed["utm_medium"])
        assertEquals("android launch", parsed["utm_campaign"])
        assertFalse(parsed.containsKey("gclid"))
    }

    @Test
    fun `sanitizes control and markup characters`() {
        val parsed = parseInstallReferrer("utm_campaign=%3Cscript%3E%0Alaunch%3C%2Fscript%3E")
        assertEquals("scriptlaunch/script", parsed["utm_campaign"])
    }

    @Test
    fun `empty referrer produces no attribution`() {
        assertEquals(emptyMap<String, String>(), parseInstallReferrer(null))
    }
}
