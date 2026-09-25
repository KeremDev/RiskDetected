package com.riskdetectedan.core.data.onboarding

import android.content.Context
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.common.RdClientMetadata
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
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
            // The notification/report workers resolve exact-locale content from profiles. This
            // write must happen for Turkish as well as English: Turkish onboarding used to only
            // persist user_onboarding_answers, leaving freshly-created accounts without a locale
            // until a later heartbeat happened (and report_ready was then recorded as
            // LOCALIZATION_BLOCKED). Keep the selected safety profile when it is valid, while
            // falling back to the current Android contract for older/incomplete drafts.
            val profileId = if (draft.appLanguage == "en") {
                draft.safetyProfileId ?: RdClientMetadata.SAFETY_PROFILE_ID
            } else {
                // Turkish is the safe base contract; never let a stale English profile id in a
                // pending draft change the language selected for the current onboarding run.
                "tr-tr-current-v1"
            }
            val localization = RdClientMetadata.localizationForSafetyProfile(profileId)
                ?: RdClientMetadata.localization()
            val userId = client.auth.currentUserOrNull()?.id
                ?: return RdResult.Failure("auth_required", "auth_required")
            draft.nova?.name?.let { adoptOnboardingName(userId, it) }
            client.postgrest.from("profiles").update(
                OnboardingLocalizationPayload(
                    appLanguage = localization.appLanguage,
                    preferredContentLocale = localization.contentLocale,
                    workJurisdictionCountry = localization.workJurisdictionCountry,
                    safetyProfileId = localization.safetyProfileId,
                    safetyProfileVersion = localization.safetyProfileVersion,
                    legalDocumentSet = localization.legalDocumentSetId,
                    title = draft.professionalRole?.label,
                ),
            ) {
                filter { eq("id", userId) }
            }
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

    /** The name typed in the Nova funnel ("Sana nasıl hitap edelim?") becomes the profile name while
     * the profile still has none, or only the default the signup trigger takes from the address. A
     * name from Apple or Google, or one set on the profile, stays (iOS `adoptOnboardingName`). Never
     * fails the answer sync. */
    private suspend fun adoptOnboardingName(userId: String, typed: String) {
        val name = typed.trim()
        if (name.isEmpty()) return
        try {
            val profile = client.postgrest.from("profiles").select(Columns.list("email", "full_name")) {
                filter { eq("id", userId) }
            }.decodeSingle<ProfileName>()
            val current = profile.fullName?.trim().orEmpty()
            val fromAddress = profile.email?.substringBefore('@').orEmpty()
            if ((current.isEmpty() || current == fromAddress) && current != name) {
                client.postgrest.from("profiles").update(NameUpdate(name)) { filter { eq("id", userId) } }
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Throwable) {
        }
    }

    private companion object {
        const val PREFERENCES_NAME = "onboarding_answers"
        const val PENDING_DRAFT_KEY = "pending_v2_draft"
    }
}

@Serializable
private data class ProfileName(val email: String? = null, @SerialName("full_name") val fullName: String? = null)

@Serializable
private data class NameUpdate(@SerialName("full_name") val fullName: String)

@Serializable
private data class OnboardingLocalizationPayload(
    @SerialName("app_language") val appLanguage: String,
    @SerialName("preferred_content_locale") val preferredContentLocale: String,
    @SerialName("work_jurisdiction_country") val workJurisdictionCountry: String,
    @SerialName("safety_profile_id") val safetyProfileId: String,
    @SerialName("safety_profile_version") val safetyProfileVersion: Int,
    @SerialName("legal_document_set") val legalDocumentSet: String,
    val title: String?,
)
