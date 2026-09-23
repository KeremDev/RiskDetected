package com.riskdetectedan.core.data.notebook

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Server-owned, account-bound notebook rollout (`isg_notebook_rollout_v1`, iOS `NotebookUIRelease`).
 * An account the server enabled keeps the notebook for a week offline; the server stays the authority.
 */
@Singleton
class NotebookRollout @Inject constructor(
    @ApplicationContext context: Context,
    private val client: SupabaseClient,
) {
    private val preferences = context.getSharedPreferences("notebook.rollout", Context.MODE_PRIVATE)

    suspend fun enabled(): Boolean {
        val user = client.auth.currentUserOrNull()?.id ?: return false
        val cached = preferences.getLong(user, 0L).let { it > 0 && System.currentTimeMillis() - it < WEEK_MILLIS }
        return try {
            val body = Json.parseToJsonElement(client.postgrest.rpc("isg_notebook_rollout_v1").data).jsonObject
            if (client.auth.currentUserOrNull()?.id != user) return false
            val on = body["schema_version"]?.jsonPrimitive?.intOrNull == 1 && body["enabled"]?.jsonPrimitive?.booleanOrNull == true
            if (on) preferences.edit().putLong(user, System.currentTimeMillis()).apply() else preferences.edit().remove(user).apply()
            on
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            cached && client.auth.currentUserOrNull()?.id == user
        }
    }

    private companion object { const val WEEK_MILLIS = 7L * 86_400_000L }
}
