package com.riskdetectedan.core.data.profile

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.storage.storage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

/** Same two values as iOS's `RiskMethodWire` (App/Models/UserProfile.swift) — the risk-method
 * choice offered on the basic profile-edit form (Turkish default is fine_kinney). */
enum class RiskMethodWire(val wireValue: String) {
    FineKinney("fine_kinney"),
    Matrix5x5("matrix_5x5"),
}

/**
 * Mirrors AuthService.swift's `updateProfile(_:)` / `ProfileUpdatePayload` — same table
 * (`profiles`), same upsert-onConflict-id shape, same field-for-field column names. Only the
 * "basic edit form" subset from ProfileView.swift's `save()` is covered (fullName/title/
 * certificateNumber/companyName/phone/preferredMethod) — the wider `ProfileUpdateInput` also
 * carries appLanguage, preferredContentLocale, workJurisdiction country/region, safetyProfile
 * id/version, and legalDocumentSetID, all of which are set through onboarding/localization flows elsewhere,
 * not this edit screen, so they're intentionally left out of this payload (a real upsert would
 * otherwise null them out — see `nilIfBlank` fallback-to-existing pattern in the Swift source,
 * mirrored here by resolving unspecified fields from the already-fetched [current] profile
 * before sending, never sending a bare partial row). `companyLogoPath` — really the user's own
 * profile logo, stored under the confusingly-named `company_logo_url` column on `profiles`
 * itself (matches iOS's own naming exactly, not renamed here) — is covered via
 * [ProfileRepository.uploadProfileLogo] + the [updateProfile] `companyLogoUrl` param.
 */
@Serializable
private data class ProfileUpdatePayload(
    val id: String,
    val email: String?,
    @SerialName("full_name") val fullName: String?,
    val initials: String?,
    val title: String?,
    @SerialName("certificate_number") val certificateNumber: String?,
    @SerialName("company_name") val companyName: String?,
    @SerialName("company_logo_url") val companyLogoUrl: String?,
    val phone: String?,
    @SerialName("preferred_method") val preferredMethod: String?,
)

/**
 * `profiles` table access — backend is the single entitlement authority (invariant, master
 * §37): this repository only ever reads what the server already decided (tier, quotas,
 * safety_profile_id, etc.), never derives capability locally.
 */
@Singleton
class ProfileRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun fetchProfile(userId: String): RdResult<UserProfile> = try {
        val profile = client.postgrest.from("profiles")
            .select(Columns.ALL) {
                filter { eq("id", userId) }
            }
            .decodeSingle<UserProfile>()
        RdResult.Success(profile)
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "profile_fetch_failed",
            message = t.message ?: "profile_fetch_failed",
            cause = t,
        )
    }

    /** [current] supplies id/email (never edited here) and the pre-edit value for fields the
     * caller doesn't pass, matching AuthService.swift's `input.field ?? profile?.field` fallback
     * so this never nulls out a column the edit form doesn't surface. */
    suspend fun updateProfile(
        current: UserProfile,
        fullName: String,
        title: String,
        certificateNumber: String,
        companyName: String,
        phone: String,
        preferredMethod: RiskMethodWire?,
        companyLogoUrl: String? = current.companyLogoUrl,
    ): RdResult<Unit> = try {
        val trimmedName = fullName.trim()
        val initials = trimmedName
            .split(" ")
            .filter { it.isNotBlank() }
            .take(2)
            .mapNotNull { it.firstOrNull()?.uppercaseChar() }
            .joinToString("")
            .ifEmpty { null }

        client.postgrest.from("profiles").upsert(
            ProfileUpdatePayload(
                id = current.id,
                email = current.email,
                fullName = trimmedName.ifBlank { null },
                initials = initials,
                title = title.trim().ifBlank { null },
                certificateNumber = certificateNumber.trim().ifBlank { null },
                companyName = companyName.trim().ifBlank { null },
                companyLogoUrl = companyLogoUrl,
                phone = phone.trim().ifBlank { null },
                preferredMethod = (preferredMethod?.wireValue) ?: current.preferredMethod,
            ),
        ) {
            onConflict = "id"
        }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "profile_update_failed",
            message = t.message ?: "profile_update_failed",
            cause = t,
        )
    }

    /** Mirrors AuthService.swift's `uploadProfileLogo(_:)` — same bucket ("logos"), same
     * storage path (`{userId}/profile-logo.jpg`). Stays Context-free like every other upload
     * repository in this port; the caller supplies ready JPEG bytes. */
    suspend fun uploadProfileLogo(userId: String, jpegBytes: ByteArray): RdResult<String> = try {
        val path = "${userId.lowercase()}/profile-logo.jpg"
        client.storage.from(LOGO_BUCKET).upload(path, jpegBytes) {
            upsert = true
        }
        RdResult.Success(path)
    } catch (t: Throwable) {
        RdResult.Failure("profile_logo_upload_failed", "Logo yüklenemedi.", t)
    }

    /**
     * Real port of `saveProfileAvatar(_:)` — closes a previously undiscovered gap: `UserProfile`
     * already decoded `avatar_url` (unused by anything), but no upload path existed at all.
     * Genuinely distinct from [uploadProfileLogo]/`company_logo_url` (that one is the user's own
     * report-branding logo, confusingly named after "company" — see that function's doc comment)
     * — this is the personal profile photo shown in the app's UI (`HomeHeaderAvatar`, the
     * profile hero card), bucket `"avatars"`, path `{userId}/avatar.jpg`. Upload-then-patch in
     * one call, same sequencing as iOS (a failed upload never reaches the DB patch).
     */
    suspend fun uploadAvatar(userId: String, jpegBytes: ByteArray): RdResult<String> = try {
        val path = "${userId.lowercase()}/avatar.jpg"
        client.storage.from(AVATAR_BUCKET).upload(path, jpegBytes) {
            upsert = true
        }
        client.postgrest.from("profiles")
            .update(AvatarPatchPayload(avatarUrl = path)) {
                filter { eq("id", userId) }
            }
        RdResult.Success(path)
    } catch (t: Throwable) {
        RdResult.Failure("profile_avatar_upload_failed", "Profil fotoğrafı yüklenemedi.", t)
    }

    /** Mirrors `profileAvatarImage(path:)` — authenticated download from the private "avatars"
     * bucket, same pattern as every other private-bucket download in this port. */
    suspend fun downloadAvatar(path: String): RdResult<ByteArray> = try {
        RdResult.Success(client.storage.from(AVATAR_BUCKET).downloadAuthenticated(path))
    } catch (t: Throwable) {
        RdResult.Failure("profile_avatar_download_failed", t.message ?: "profile_avatar_download_failed", t)
    }

    private companion object {
        const val LOGO_BUCKET = "logos"
        const val AVATAR_BUCKET = "avatars"
    }
}

@Serializable
private data class AvatarPatchPayload(@SerialName("avatar_url") val avatarUrl: String)
