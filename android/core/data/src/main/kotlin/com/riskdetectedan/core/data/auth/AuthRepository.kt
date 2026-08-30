package com.riskdetectedan.core.data.auth

import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.data.notifications.DeviceTokenRepository
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.IDToken
import io.github.jan.supabase.auth.providers.builtin.OTP
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.Apple
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.encodeToJsonElement
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/** Decode target for [AuthRepository.backfillProviderIdentityIfNeeded]'s read-before-write —
 * the columns the backfill decision + [AuthRepository.recordFirstSeenDeviceRegionIfNeeded] need. */
@Serializable
private data class ProfileIdentityRow(
    val email: String? = null,
    @SerialName("full_name") val fullName: String? = null,
    val initials: String? = null,
    @SerialName("first_seen_device_region_code") val firstSeenDeviceRegionCode: String? = null,
)

@Serializable
private data class ProfileIdentityPatchPayload(
    val email: String?,
    @SerialName("full_name") val fullName: String?,
    val initials: String?,
)

@Serializable
private data class FirstSeenDeviceRegionParams(@SerialName("p_region_code") val regionCode: String)

/**
 * app_language/content_locale contract per contracts/mobile/api/otp-email-metadata.md (F6) —
 * keep in sync with App/Services/AuthService.swift's sendEmailOTP by hand until contracts/
 * becomes a generated source for both platforms.
 */
enum class RdAppLanguage(val code: String, val contentLocale: String) {
    Turkish("tr", "tr-TR"),
    English("en", "en-001"),
    ;

    companion object {
        fun current(): RdAppLanguage = if (RdClientMetadata.APP_LANGUAGE == "en") English else Turkish
    }
}

@Singleton
class AuthRepository @Inject constructor(
    private val client: SupabaseClient,
    private val deviceTokenRepository: DeviceTokenRepository,
) {
    /** Guards [recordFirstSeenDeviceRegionIfNeeded] against re-firing every sign-in within the
     * same process — a simpler single-slot version of iOS's `Set<UUID>` in-flight/completed
     * tracking (Android's auth flows are sequential per user action, no need for the
     * multi-callback concurrency iOS's reactive `authStateChanges` observer can see). */
    private var deviceRegionRecordedUserId: String? = null

    val sessionStatus: StateFlow<SessionStatus>
        get() = client.auth.sessionStatus

    /** [sessionStatus] narrowed to just the authenticated user id (or null) — lets consumers in
     * modules that don't otherwise depend on supabase-kt's auth types (e.g. `app`, which only
     * needs "who is signed in", not the full [SessionStatus] sealed hierarchy) react to sign-in/
     * sign-out without importing `io.github.jan.supabase.auth.status.SessionStatus` themselves. */
    val currentUserIdFlow: Flow<String?>
        get() = client.auth.sessionStatus.map { (it as? SessionStatus.Authenticated)?.session?.user?.id }

    val currentUserId: String?
        get() = client.auth.currentUserOrNull()?.id

    val currentUserEmail: String?
        get() = client.auth.currentUserOrNull()?.email

    /** Mirrors AuthService.swift's sendEmailOTP — same data contract, see F6. */
    suspend fun sendEmailOtp(email: String, language: RdAppLanguage): RdResult<Unit> = try {
        client.auth.signInWith(OTP) {
            this.email = email
            data = JsonObject(
                mapOf(
                    "app_language" to JsonPrimitive(language.code),
                    "content_locale" to JsonPrimitive(language.contentLocale),
                ),
            )
        }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(code = "otp_send_failed", message = t.message ?: "otp_send_failed", cause = t)
    }

    suspend fun verifyEmailOtp(email: String, token: String): RdResult<Unit> = try {
        client.auth.verifyEmailOtp(type = OtpType.Email.EMAIL, email = email, token = token)
        backfillProviderIdentityIfNeeded()
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(code = "otp_verify_failed", message = t.message ?: "otp_verify_failed", cause = t)
    }

    /**
     * Google Sign-In via Credential Manager -> ID token -> Supabase. Backend already has
     * `auth.external.google` configured (supabase/config.toml) with a real client_id — this
     * is the one auth path the review doc's F8 finding didn't even need to flag, since it was
     * already ready before Android work started.
     *
     * [emailFallback]/[fullNameFallback] — real port of `signInWithGoogle`'s
     * `emailFallback`/`fullNameFallback` params (from `GoogleSignInResult.email`/`.fullName`,
     * read straight off Google's own SDK profile object): passed through to
     * [backfillProviderIdentityIfNeeded] below.
     */
    suspend fun signInWithGoogleIdToken(
        idToken: String,
        rawNonce: String?,
        emailFallback: String? = null,
        fullNameFallback: String? = null,
    ): RdResult<Unit> = try {
        client.auth.signInWith(IDToken) {
            this.idToken = idToken
            provider = Google
            nonce = rawNonce
        }
        backfillProviderIdentityIfNeeded(emailFallback, fullNameFallback)
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(code = "google_sign_in_failed", message = t.message ?: "google_sign_in_failed", cause = t)
    }

    /** Starts Supabase Apple OAuth in a Custom Tab. PKCE completion is imported by
     * `SupabaseClient.handleDeeplinks` in MainActivity; sessionStatus is the completion signal. */
    suspend fun signInWithAppleOAuth(): RdResult<Unit> = try {
        client.auth.signInWith(Apple)
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(code = "apple_sign_in_failed", message = t.message ?: "apple_sign_in_failed", cause = t)
    }

    suspend fun awaitInitialization() {
        client.auth.awaitInitialization()
    }

    suspend fun clearLocalSession(): RdResult<Unit> = try {
        client.auth.clearSession()
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(code = "session_clear_failed", message = t.message ?: "session_clear_failed", cause = t)
    }

    /**
     * Real port of `ensureProfile`+`backfillProviderIdentityIfNeeded` — the DB's
     * `on_auth_user_created` trigger (`02_profiles.sql`) already creates the `profiles` row on
     * every sign-up with a single-key fallback (`raw_user_meta_data->>'full_name'`, else the
     * email local-part), which is NOT always the real provider-supplied name (Google's ID token
     * claims can land under `name`/`display_name`/`given_name`+`family_name` instead of
     * `full_name` depending on how GoTrue maps them) — without this correction, a real name could
     * get silently and *permanently* stuck as the email's local part forever, since nothing else
     * ever re-derives it. This was previously entirely missing on Android: nothing called
     * anything after a successful sign-in, the trigger's one-shot insert was the only thing that
     * ever ran. Best-effort/fire-and-forget by design (never surfaces a failure to the caller,
     * never blocks sign-in on a cosmetic identity correction) — matches iOS's own
     * `Self.logger.warning(...)`-only failure handling.
     */
    private suspend fun backfillProviderIdentityIfNeeded(
        emailFallback: String? = null,
        fullNameFallback: String? = null,
    ) {
        val user = client.auth.currentUserOrNull() ?: return
        val profile = try {
            client.postgrest.from("profiles")
                .select(Columns.list("email", "full_name", "initials", "first_seen_device_region_code")) {
                    filter { eq("id", user.id) }
                }
                .decodeSingleOrNull<ProfileIdentityRow>()
        } catch (t: Throwable) {
            null
        } ?: return

        recordFirstSeenDeviceRegionIfNeeded(user.id, profile)

        val metadata = user.userMetadata
        val resolvedEmail = user.email?.trim()?.ifEmpty { null }
            ?: emailFallback?.trim()?.ifEmpty { null }
            ?: metadataString(metadata, "email")
        val resolvedFullName = fullNameFallback?.trim()?.ifEmpty { null }
            ?: metadataString(metadata, "full_name")
            ?: metadataString(metadata, "name")
            ?: metadataString(metadata, "display_name")
            ?: listOfNotNull(metadataString(metadata, "given_name"), metadataString(metadata, "family_name"))
                .joinToString(" ").trim().ifEmpty { null }

        val shouldUpdateEmail = profile.email.isNullOrBlank() && resolvedEmail != null
        val shouldUpdateName = resolvedFullName != null &&
            shouldBackfillFullName(profile.fullName, resolvedEmail, resolvedFullName)
        if (!shouldUpdateEmail && !shouldUpdateName) return

        try {
            client.postgrest.from("profiles").update(
                ProfileIdentityPatchPayload(
                    email = if (shouldUpdateEmail) resolvedEmail else profile.email,
                    fullName = if (shouldUpdateName) resolvedFullName else profile.fullName,
                    initials = if (shouldUpdateName) computeInitials(resolvedFullName!!) else profile.initials,
                ),
            ) {
                filter { eq("id", user.id) }
            }
        } catch (t: Throwable) {
            // Best-effort — see doc comment.
        }
    }

    /**
     * Real port of `recordFirstSeenDeviceRegionIfNeeded(userID:)` — a genuinely missing gap, not
     * a deliberate simplification: `UserProfile.firstSeenDeviceRegionCode` decoded a real column
     * nothing ever wrote to on Android. Fires once per real sign-in (any provider), idempotent
     * both client-side (guarded here) and server-side (skipped entirely once
     * `profiles.first_seen_device_region_code` is already set). `Locale.getDefault().country`
     * is Android's direct equivalent of `Locale.current.region?.identifier` — both are JVM/OS
     * locale reads, no `Context` needed, keeping this repository Context-free like every other
     * one in this port. Best-effort/fire-and-forget — never surfaces a failure to the caller,
     * matches iOS's own log-only handling.
     */
    private suspend fun recordFirstSeenDeviceRegionIfNeeded(userId: String, profile: ProfileIdentityRow) {
        if (profile.firstSeenDeviceRegionCode != null) return
        if (deviceRegionRecordedUserId == userId) return
        val regionCode = normalizedDeviceRegionCode() ?: return
        try {
            val params = Json.encodeToJsonElement(FirstSeenDeviceRegionParams(regionCode)) as JsonObject
            client.postgrest.rpc("record_first_seen_device_region_v1", params)
            deviceRegionRecordedUserId = userId
        } catch (t: Throwable) {
            // Best-effort — see doc comment.
        }
    }

    private fun normalizedDeviceRegionCode(): String? {
        val candidate = Locale.getDefault().country.trim().uppercase()
        return candidate.takeIf { it.matches(Regex("^[A-Z]{2}$")) }
    }

    private fun shouldBackfillFullName(currentFullName: String?, email: String?, providerFullName: String): Boolean {
        val current = currentFullName?.trim()?.ifEmpty { null } ?: return true
        val emailLocalPart = email?.substringBefore("@")?.trim()?.lowercase()
        return current.lowercase() == emailLocalPart
    }

    private fun metadataString(metadata: JsonObject?, key: String): String? =
        (metadata?.get(key) as? JsonPrimitive)?.contentOrNull?.trim()?.ifEmpty { null }

    private fun computeInitials(name: String): String? = name.trim()
        .split(" ")
        .filter { it.isNotBlank() }
        .take(2)
        .mapNotNull { it.firstOrNull()?.uppercaseChar() }
        .joinToString("")
        .ifEmpty { null }

    suspend fun signOut(): RdResult<Unit> = try {
        // Best effort: logout must remain available offline, while an online logout removes this
        // installation's owner-scoped FCM token before the RLS-authenticated session disappears.
        client.auth.currentUserOrNull()?.id?.let { userId ->
            deviceTokenRepository.unregisterCurrentInstallation(userId)
        }
        client.auth.signOut()
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(code = "sign_out_failed", message = t.message ?: "sign_out_failed", cause = t)
    }
}
