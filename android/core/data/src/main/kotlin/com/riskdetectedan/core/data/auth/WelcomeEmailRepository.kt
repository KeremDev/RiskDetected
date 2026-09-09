package com.riskdetectedan.core.data.auth

import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors WelcomeEmailService.swift's `sendIfNeeded()` — calls the `send-welcome-email` edge
 * function every authenticated session with the resolved client locale; delivery is deduped server-side
 * (the function itself decides whether a welcome email is actually needed), the client never
 * tracks "have I already sent this" locally. Same fire-and-forget, non-blocking contract as
 * AppState.swift's `sendWelcomeEmailIfPossible()` — a failure here must never block sign-in.
 */
@Serializable
private data class WelcomeEmailRequest(
    @SerialName("app_language") val appLanguage: String = RdClientMetadata.APP_LANGUAGE,
    @SerialName("preferred_content_locale") val preferredContentLocale: String = RdClientMetadata.CONTENT_LOCALE,
)

@Singleton
class WelcomeEmailRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun sendIfNeeded(): RdResult<Unit> = try {
        // Android can reach the sender before profile localization sync completes. Sending the
        // resolved client contract lets the edge function render the correct language and repair
        // only missing profile fields without using client data for authorization.
        client.functions.invoke(
            "send-welcome-email",
            body = WelcomeEmailRequest(),
        )
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("welcome_email_send_failed", t.message ?: "failed", t)
    }
}
