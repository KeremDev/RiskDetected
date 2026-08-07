package com.riskdetectedan.core.data.auth

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.IDToken
import io.github.jan.supabase.auth.providers.builtin.OTP
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import javax.inject.Inject
import javax.inject.Singleton

/**
 * app_language/content_locale contract per contracts/mobile/api/otp-email-metadata.md (F6) —
 * keep in sync with App/Services/AuthService.swift's sendEmailOTP by hand until contracts/
 * becomes a generated source for both platforms.
 */
enum class RdAppLanguage(val code: String, val contentLocale: String) {
    Turkish("tr", "tr-TR"),
    English("en", "en-001"),
}

@Singleton
class AuthRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    val sessionStatus: StateFlow<SessionStatus>
        get() = client.auth.sessionStatus

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
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(code = "otp_verify_failed", message = t.message ?: "otp_verify_failed", cause = t)
    }

    /**
     * Google Sign-In via Credential Manager -> ID token -> Supabase. Backend already has
     * `auth.external.google` configured (supabase/config.toml) with a real client_id — this
     * is the one auth path the review doc's F8 finding didn't even need to flag, since it was
     * already ready before Android work started.
     */
    suspend fun signInWithGoogleIdToken(idToken: String, rawNonce: String?): RdResult<Unit> = try {
        client.auth.signInWith(IDToken) {
            this.idToken = idToken
            provider = Google
            nonce = rawNonce
        }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(code = "google_sign_in_failed", message = t.message ?: "google_sign_in_failed", cause = t)
    }

    suspend fun signOut(): RdResult<Unit> = try {
        client.auth.signOut()
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure(code = "sign_out_failed", message = t.message ?: "sign_out_failed", cause = t)
    }
}
