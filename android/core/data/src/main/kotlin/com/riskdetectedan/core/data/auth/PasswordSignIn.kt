package com.riskdetectedan.core.data.auth

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.exception.AuthErrorCode
import io.github.jan.supabase.auth.exception.AuthRestException
import io.github.jan.supabase.auth.providers.builtin.Email
import kotlinx.coroutines.CancellationException
import java.util.Locale

/** Existing-account login, NOT signup. Never apply the new-password strength policy here:
 * existing users may have an older valid password. Password bytes are sent unchanged.
 * Errors intentionally omit SDK bodies/causes, which may contain credentials or account hints.
 * The caller retains the existing release gate and post-auth/MFA/bootstrap coordinator.
 */
internal suspend fun passwordSignIn(client: SupabaseClient, email: String, password: String): RdResult<Unit> {
    val normalizedEmail = normalizedPasswordEmail(email) ?: return RdResult.Failure("password_email_invalid", "password_email_invalid")
    if (password.isEmpty()) return RdResult.Failure("password_required", "password_required")
    return try {
        client.auth.awaitInitialization()
        client.auth.signInWith(Email) {
            this.email = normalizedEmail
            this.password = password
        }
        RdResult.Success(Unit)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (error: AuthRestException) {
        // Only the code is kept: a wrong password (the server does not say whether the
        // address or the password was wrong), or a signup whose code was never entered.
        val code = when (error.errorCode) {
            AuthErrorCode.InvalidCredentials -> "password_invalid_credentials"
            AuthErrorCode.EmailNotConfirmed -> "password_email_not_confirmed"
            else -> "password_sign_in_failed"
        }
        RdResult.Failure(code, code)
    } catch (_: Exception) {
        RdResult.Failure("password_sign_in_failed", "password_sign_in_failed")
    }
}

internal fun normalizedPasswordEmail(email: String): String? = email.trim().lowercase(Locale.ROOT).takeIf {
    it.isNotEmpty() && it.count { c -> c == '@' } == 1 && !it.startsWith('@') && !it.endsWith('@') && !it.any(Char::isWhitespace)
}
