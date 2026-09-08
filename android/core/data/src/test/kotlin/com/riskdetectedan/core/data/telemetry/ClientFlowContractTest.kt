package com.riskdetectedan.core.data.telemetry

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.*
import org.junit.Test

class ClientFlowContractTest {
    @Test fun `payload has only frozen operational fields and retry keeps identity`() {
        val event = FlowEvent(user_id = "owner", session_id = "session", app_version = "2.0.1", app_build = "13",
            stage = "analysis_upload", outcome = "failed", reason = "network", photo_count = 1)
        val json = Json { encodeDefaults = true }
        val encoded = json.encodeToString(event)
        assertEquals(setOf("client_event_id", "user_id", "session_id", "platform", "app_version", "app_build", "stage", "outcome", "reason", "photo_count", "client_occurred_at"), json.parseToJsonElement(encoded).jsonObject.keys)
        assertEquals(event, json.decodeFromString<FlowEvent>(encoded))
        assertFalse(ClientFlowEvents.reasons.contains("raw exception with private data"))
        assertFalse(ClientFlowEvents.stages.contains("photo_path"))
    }
}
