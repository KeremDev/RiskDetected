package com.riskdetectedan.core.data.profile

import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
internal data class ProfileLocalizationRow(
    @SerialName("app_language") val appLanguage: String? = null,
    @SerialName("preferred_content_locale") val preferredContentLocale: String? = null,
    @SerialName("work_jurisdiction_country") val workJurisdictionCountry: String? = null,
    @SerialName("safety_profile_id") val safetyProfileId: String? = null,
    @SerialName("safety_profile_version") val safetyProfileVersion: Int? = null,
    @SerialName("legal_document_set") val legalDocumentSet: String? = null,
    @SerialName("client_platform") val clientPlatform: String? = null,
)

@Serializable
private data class ProfileLocalizationPatchPayload(
    @SerialName("app_language") val appLanguage: String,
    @SerialName("preferred_content_locale") val preferredContentLocale: String,
    @SerialName("work_jurisdiction_country") val workJurisdictionCountry: String,
    @SerialName("safety_profile_id") val safetyProfileId: String,
    @SerialName("safety_profile_version") val safetyProfileVersion: Int,
    @SerialName("legal_document_set") val legalDocumentSet: String,
    // `private.enforce_profile_localization_pair_v1` reads this column to pick the Turkish legal
    // document set (tr-android-v1 for Android, tr-current otherwise). Nothing on Android was
    // writing it, so every Android profile was being filed under the iOS document set.
    @SerialName("client_platform") val clientPlatform: String = "android",
)

/**
 * Guarantees the signed-in account carries the locale contract every server-side content path
 * resolves against.
 *
 * `send-push-notification` refuses to send a transactional notification whose recipient has no
 * `profiles.app_language` / `preferred_content_locale` (it records the event as `skipped` with
 * `NOTIFICATION_RECIPIENT_LOCALE_MISSING` rather than guessing a language), and the report
 * workers resolve their exact-locale templates the same way. On iOS these columns are written
 * during auth by `AuthService.swift`'s profile update; Android only ever wrote them from the
 * onboarding-answers upsert, so an account that signed in without completing that step — or that
 * predates the Turkish branch writing them at all — stayed locale-less and silently received no
 * "analiz hazır" / "rapor hazır" / account notifications.
 *
 * Repair-only by design: an existing value is never overwritten, so a user's real language choice
 * (including English) survives, and a fully-populated profile costs one cached-cheap read.
 */
@Singleton
class ProfileLocalizationRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    /** Returns true when a repair was actually written. Failures are returned, never thrown: this
     * runs beside sign-in and must not affect it. */
    suspend fun ensureLocalizationContext(userId: String): RdResult<Boolean> = try {
        val row = client.postgrest.from("profiles")
            .select(
                Columns.list(
                    "app_language",
                    "preferred_content_locale",
                    "work_jurisdiction_country",
                    "safety_profile_id",
                    "safety_profile_version",
                    "legal_document_set",
                    "client_platform",
                ),
            ) {
                filter { eq("id", userId) }
            }
            .decodeSingleOrNull<ProfileLocalizationRow>()

        when {
            row == null -> RdResult.Success(false)
            !row.appLanguage.isNullOrBlank() && !row.preferredContentLocale.isNullOrBlank() &&
                !row.clientPlatform.isNullOrBlank() -> RdResult.Success(false)
            else -> {
                val resolved = resolveContext(row)
                client.postgrest.from("profiles").update(
                    ProfileLocalizationPatchPayload(
                        appLanguage = row.appLanguage?.ifBlank { null } ?: resolved.appLanguage,
                        preferredContentLocale = row.preferredContentLocale?.ifBlank { null }
                            ?: resolved.contentLocale,
                        workJurisdictionCountry = row.workJurisdictionCountry?.ifBlank { null }
                            ?: resolved.workJurisdictionCountry,
                        safetyProfileId = row.safetyProfileId?.ifBlank { null } ?: resolved.safetyProfileId,
                        safetyProfileVersion = row.safetyProfileVersion ?: resolved.safetyProfileVersion,
                        legalDocumentSet = row.legalDocumentSet?.ifBlank { null } ?: resolved.legalDocumentSetId,
                    ),
                ) {
                    filter { eq("id", userId) }
                }
                RdResult.Success(true)
            }
        }
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "profile_localization_repair_failed",
            message = t.message ?: "profile_localization_repair_failed",
            cause = t,
        )
    }
}

/**
 * A profile that already names a safety profile keeps it — that row was written by a real
 * onboarding choice. Otherwise an account that only knows it is English gets the international
 * English contract, and everything else gets the device's own resolution (Turkish on this
 * Turkish-only build).
 */
internal fun resolveContext(row: ProfileLocalizationRow) =
    row.safetyProfileId?.ifBlank { null }?.let(RdClientMetadata::localizationForSafetyProfile)
        ?: if (row.appLanguage?.trim()?.lowercase() == "en") {
            RdClientMetadata.localizationForSafetyProfile("en-intl-generic-v1")
                ?: RdClientMetadata.localization()
        } else {
            RdClientMetadata.localization()
        }
