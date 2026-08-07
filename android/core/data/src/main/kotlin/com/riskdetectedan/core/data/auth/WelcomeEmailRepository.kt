package com.riskdetectedan.core.data.auth

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors WelcomeEmailService.swift's `sendIfNeeded()` — calls the `send-welcome-email` edge
 * function with an empty body every authenticated session; delivery is deduped server-side
 * (the function itself decides whether a welcome email is actually needed), the client never
 * tracks "have I already sent this" locally. Same fire-and-forget, non-blocking contract as
 * AppState.swift's `sendWelcomeEmailIfPossible()` — a failure here must never block sign-in.
 */
@Singleton
class WelcomeEmailRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun sendIfNeeded(): RdResult<Unit> = try {
        client.functions.invoke("send-welcome-email")
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("welcome_email_send_failed", t.message ?: "failed", t)
    }
}
