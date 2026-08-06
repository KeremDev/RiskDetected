package com.riskdetectedan.core.data.onboarding

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.encodeToJsonElement
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors OnboardingAnswersService.swift's upsert() — same RPC name
 * (`upsert_onboarding_v2_answers`), same payload shape. Deliberately simplified: no local
 * pending-draft persistence/retry-on-reconnect (iOS caches an unsynced draft in UserDefaults
 * and replays it once a session exists — real offline-resilience behavior, not decoration;
 * tracked as follow-up, not silently dropped). This calls the RPC directly and requires an
 * authenticated session already.
 */
@Singleton
class OnboardingAnswersRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun upsert(draft: OnboardingAnswersDraft): RdResult<Unit> {
        if (!draft.hasProfileAnswers) return RdResult.Success(Unit)
        return try {
            val params = Json.encodeToJsonElement(draft.toRpcPayload()) as JsonObject
            client.postgrest.rpc("upsert_onboarding_v2_answers", params)
            RdResult.Success(Unit)
        } catch (t: Throwable) {
            RdResult.Failure(
                code = "onboarding_answers_upsert_failed",
                message = t.message ?: "onboarding_answers_upsert_failed",
                cause = t,
            )
        }
    }
}
