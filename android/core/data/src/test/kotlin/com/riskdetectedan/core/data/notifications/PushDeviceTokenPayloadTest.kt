package com.riskdetectedan.core.data.notifications

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

class PushDeviceTokenPayloadTest {
    @Test
    fun `android transport fields survive encodeDefaults false`() {
        val encoded = Json { encodeDefaults = false }.encodeToString(
            PushDeviceTokenPayload(
                userId = "00000000-0000-0000-0000-000000000001",
                token = "test-token",
                platform = "android",
                environment = "sandbox",
                appVersion = "1.5.0-debug",
                deviceModel = "emulator",
                notificationsEnabled = true,
                lastRegisteredAt = "2026-08-10T00:00:00Z",
                provider = "fcm",
                providerEnvironment = "riskdetected-android-staging",
                applicationId = "com.riskdetectedan.app.debug",
                installationId = "00000000-0000-0000-0000-000000000002",
                clientBuild = "1",
            ),
        )
        val json = Json.parseToJsonElement(encoded).jsonObject

        assertEquals("android", json.getValue("platform").jsonPrimitive.content)
        assertEquals("fcm", json.getValue("provider").jsonPrimitive.content)
    }
}
