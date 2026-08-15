package com.riskdetectedan.core.data.telemetry

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlatformTelemetryContractTest {
    @Test
    fun payloadUsesTheFrozenRpcKeys() {
        val encoded = Json.encodeToString(
            PlatformTelemetryParams("android", "1.5.3", "5"),
        )
        assertTrue(encoded.contains("\"p_platform\":\"android\""))
        assertTrue(encoded.contains("\"p_app_version\":\"1.5.3\""))
        assertTrue(encoded.contains("\"p_app_build\":\"5\""))
    }

    @Test
    fun responseAllowsProfileNotReadyWithoutAUserFacingFailure() {
        val decoded = Json.decodeFromString<PlatformTelemetryResponse>(
            """{"recorded":false}""",
        )
        assertEquals(false, decoded.recorded)
        assertEquals(null, decoded.activityDay)
    }
}
