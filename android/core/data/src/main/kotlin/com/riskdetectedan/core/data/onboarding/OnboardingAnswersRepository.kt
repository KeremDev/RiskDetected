package com.riskdetectedan.core.data.onboarding

import android.content.Context
import com.riskdetectedan.core.common.RdResult
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.encodeToJsonElement
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors OnboardingAnswersService.swift's upsert() — same RPC name
 * (`upsert_onboarding_v2_answers`), same payload shape. Pending answers are persisted before
 * authentication and are removed only after the authenticated RPC succeeds. This mirrors the
 * iOS pending-draft contract and makes an interrupted/offline auth hand-off lossless.
 */
@Singleton
class OnboardingAnswersRepository @Inject constructor(
    @ApplicationContext context: Context,
    private val client: SupabaseClient,
) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun savePending(draft: OnboardingAnswersDraft) {
        preferences.edit().putString(PENDING_DRAFT_KEY, json.encodeToString(draft)).apply()
    }

    fun loadPending(): OnboardingAnswersDraft? = preferences.getString(PENDING_DRAFT_KEY, null)
        ?.let { encoded -> runCatching { json.decodeFromString<OnboardingAnswersDraft>(encoded) }.getOrNull() }

    fun clearPending() {
        preferences.edit().remove(PENDING_DRAFT_KEY).apply()
    }

    suspend fun upsert(draft: OnboardingAnswersDraft): RdResult<Unit> {
        if (!draft.hasProfileAnswers) {
            clearPending()
            return RdResult.Success(Unit)
        }
        return try {
            val params = Json.encodeToJsonElement(draft.toRpcPayload()) as JsonObject
            client.postgrest.rpc("upsert_onboarding_v2_answers", params)
            clearPending()
            RdResult.Success(Unit)
        } catch (t: Throwable) {
            RdResult.Failure(
                code = "onboarding_answers_upsert_failed",
                message = t.message ?: "onboarding_answers_upsert_failed",
                cause = t,
            )
        }
    }

    suspend fun syncPending(): RdResult<Unit> = loadPending()?.let { upsert(it) }
        ?: RdResult.Success(Unit)

    private companion object {
        const val PREFERENCES_NAME = "onboarding_answers"
        const val PENDING_DRAFT_KEY = "pending_v2_draft"
    }
}
