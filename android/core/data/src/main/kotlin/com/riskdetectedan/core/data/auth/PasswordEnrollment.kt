package com.riskdetectedan.core.data.auth

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Success only means submission accepted, never proof of a new account or saved password.
 * UI rollout is closed until confirmation/Unicode policy/provider/MFA gates pass. */
internal suspend fun passwordSignUp(client: SupabaseClient, email: String, password: String, language: RdAppLanguage): RdResult<Unit> {
    val address = normalizedPasswordEmail(email) ?: return RdResult.Failure("password_email_invalid", "password_email_invalid")
    if (!IsgPasswordRules.evaluate(password).valid) return RdResult.Failure("password_policy_invalid", "password_policy_invalid")
    return safePasswordRequest("password_signup_failed") {
        client.auth.awaitInitialization()
        if (client.auth.currentSessionOrNull() != null) return@safePasswordRequest RdResult.Failure("password_signup_requires_signed_out", "password_signup_requires_signed_out")
        val response = client.auth.signUpWith(Email) {
            this.email = address; this.password = password
            data = buildJsonObject { put("app_language", language.code); put("content_locale", language.contentLocale) }
        }
        // SDK 3.7 imports an auto-confirm session AND can return non-null UserInfo.
        // This is only a configuration-error signal, not a session-isolation
        // boundary: auth-state listeners may already have run. Keep UI gated.
        if (response == null || client.auth.currentSessionOrNull() != null) RdResult.Failure("password_confirmation_required", "password_confirmation_required")
        else RdResult.Success(Unit)
    }
}

internal suspend fun passwordRecoveryRequest(client: SupabaseClient, email: String): RdResult<Unit> {
    val address = normalizedPasswordEmail(email) ?: return RdResult.Failure("password_email_invalid", "password_email_invalid")
    return safePasswordRequest("password_recovery_failed") {
        client.auth.awaitInitialization()
        client.auth.resetPasswordForEmail(address)
        RdResult.Success(Unit)
    }
}

private suspend fun safePasswordRequest(code: String, action: suspend () -> RdResult<Unit>): RdResult<Unit> = try {
    action()
} catch (cancelled: CancellationException) {
    throw cancelled
} catch (_: Exception) {
    RdResult.Failure(code, code)
}
