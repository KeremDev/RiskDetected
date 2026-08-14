package com.riskdetectedan.core.data.notifications

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidEngagementStatePayloadTest {
    @Test
    fun `RPC payload uses the backend parameter contract`() {
        val encoded = Json.encodeToString(
            AndroidEngagementStatePayload(
                timezone = "Europe/Istanbul",
                locale = "tr-TR",
                authorizationStatus = "authorized",
                appVersion = "1.5.1",
                appBuild = "3",
                applicationId = "com.riskdetectedan.app",
            ),
        )
        val json = Json.parseToJsonElement(encoded).jsonObject

        assertEquals("Europe/Istanbul", json.getValue("p_timezone").jsonPrimitive.content)
        assertEquals("tr-TR", json.getValue("p_locale").jsonPrimitive.content)
        assertEquals("authorized", json.getValue("p_authorization_status").jsonPrimitive.content)
        assertEquals("com.riskdetectedan.app", json.getValue("p_application_id").jsonPrimitive.content)
    }
}
