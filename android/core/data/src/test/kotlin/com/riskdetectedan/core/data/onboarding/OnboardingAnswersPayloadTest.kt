package com.riskdetectedan.core.data.onboarding

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/** The JSON `OnboardingAnswersRepository.upsert` sends to upsert_onboarding_v2_answers. */
class OnboardingAnswersPayloadTest {
    private val nova = OnboardingNovaAnswers(
        flow = "nova-v1", name = "Kerem", certificate = null, work = OnboardingAnswerChoice("osgb", "OSGB"),
        role = null, experience = null, sectors = emptyList(), trainings = emptyList(), approach = emptyList(),
        inspections = 0, growth = emptyList(), assist = listOf(OnboardingAnswerChoice("risk", "Risk Analizi")),
        skipped = listOf("cert"), marketingEmailOptIn = null,
    )

    private fun rpcJson(draft: OnboardingAnswersDraft) = Json.encodeToJsonElement(draft.toRpcPayload()) as JsonObject

    @Test fun novaAnswersTravelWholeInRawAnswers() {
        val payload = rpcJson(OnboardingAnswersDraft(safetyProfileId = null, nova = nova))
        assertEquals("v2", payload.getValue("p_onboarding_version").jsonPrimitive.content)
        val sent = payload.getValue("p_raw_answers").jsonObject.getValue("nova").jsonObject
        assertEquals("nova-v1", sent.getValue("flow").jsonPrimitive.content)
        assertEquals("Kerem", sent.getValue("name").jsonPrimitive.content)
        assertEquals("risk", sent.getValue("assist").let { it as kotlinx.serialization.json.JsonArray }[0].jsonObject.getValue("value").jsonPrimitive.content)
        assertEquals(JsonNull, sent.getValue("marketing_email_opt_in"))
    }

    @Test fun otherDraftsNeverSendANovaKey() {
        // raw_answers is merged on the server: a null here would wipe a stored Nova profile.
        val payload = rpcJson(OnboardingAnswersDraft(sectors = listOf(OnboardingAnswerChoice("construction", "İnşaat"))))
        assertFalse(payload.getValue("p_raw_answers").jsonObject.containsKey("nova"))
    }

    @Test fun draftsSavedBeforeNovaStillLoad() {
        val stored = Json { ignoreUnknownKeys = true; encodeDefaults = true }
        val old = """{"onboardingVersion":"v2","certificateClass":null,"hazardClasses":[],"professionalRole":null,""" +
            """"safetyProfileId":null,"appLanguage":"tr","sectors":[],"auditFrequency":{"value":"1","label":"1"},""" +
            """"selectedPlan":null,"capturedAt":"2026-09-01T00:00:00Z"}"""
        assertNull(stored.decodeFromString(OnboardingAnswersDraft.serializer(), old).nova)
        val withNova = OnboardingAnswersDraft(safetyProfileId = null, nova = nova)
        assertEquals(withNova, stored.decodeFromString(OnboardingAnswersDraft.serializer(), stored.encodeToString(OnboardingAnswersDraft.serializer(), withNova)))
    }
}
