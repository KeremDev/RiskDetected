package com.riskdetectedan.core.data.auth

import android.content.Intent
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.handleDeeplinks
import javax.inject.Inject
import javax.inject.Singleton

/** Keeps the app module independent from supabase-kt while still forwarding OAuth callbacks. */
@Singleton
class AuthDeepLinkHandler @Inject constructor(
    private val client: SupabaseClient,
) {
    fun handle(intent: Intent) {
        client.handleDeeplinks(intent)
    }
}
