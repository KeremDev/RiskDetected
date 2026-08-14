package com.riskdetectedan.core.data.notifications

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.encodeToJsonElement
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors NotificationService.swift's `NotificationPreferencesRow` — only the fields that
 * service actually exposes toggle UI for (master `enabled`, `app_reminders`, 3 progress
 * flags). `notification_preferences` has other columns (analysis_complete/report_ready/
 * account_updates/marketing/trial_reminder per send-push-notification's PreferenceRow) that
 * iOS's NotificationService doesn't surface either — not an Android gap, matches iOS's own
 * scope for this screen.
 */
@Serializable
data class NotificationPreferences(
    val enabled: Boolean = false,
    @SerialName("app_reminders") val appReminders: Boolean = false,
    @SerialName("progress_weekly_summary") val progressWeeklySummary: Boolean = false,
    @SerialName("progress_monthly_summary") val progressMonthlySummary: Boolean = false,
    @SerialName("progress_milestones") val progressMilestones: Boolean = false,
)

enum class ProgressPreference(val columnName: String) {
    WeeklySummary("progress_weekly_summary"),
    MonthlySummary("progress_monthly_summary"),
    Milestones("progress_milestones"),
}

@Serializable
private data class MasterPreferenceRpcPayload(@SerialName("p_enabled") val enabled: Boolean)

@Singleton
class NotificationPreferencesRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun fetch(userId: String): RdResult<NotificationPreferences> = try {
        val rows = client.postgrest.from("notification_preferences")
            .select {
                filter { eq("user_id", userId) }
                limit(1)
            }
            .decodeList<NotificationPreferences>()
        RdResult.Success(rows.firstOrNull() ?: NotificationPreferences())
    } catch (t: Throwable) {
        RdResult.Failure("notification_preferences_fetch_failed", t.message ?: "fetch_failed", t)
    }

    /** Mirrors setMasterPreference — same RPC (set_notification_master_preference_v1). */
    suspend fun setMasterPreference(enabled: Boolean): RdResult<Unit> = try {
        val params = Json.encodeToJsonElement(MasterPreferenceRpcPayload(enabled)) as JsonObject
        client.postgrest.rpc("set_notification_master_preference_v1", params)
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("notification_master_preference_failed", t.message ?: "failed", t)
    }

    suspend fun setProgressPreference(
        userId: String,
        preference: ProgressPreference,
        enabled: Boolean,
    ): RdResult<Unit> = try {
        client.postgrest.from("notification_preferences")
            .update(mapOf(preference.columnName to enabled)) {
                filter { eq("user_id", userId) }
            }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("progress_preference_failed", t.message ?: "Mesleki bildirim tercihi kaydedilemedi.", t)
    }

    suspend fun setAppRemindersPreference(userId: String, enabled: Boolean): RdResult<Unit> = try {
        client.postgrest.from("notification_preferences")
            .update(mapOf("app_reminders" to enabled)) {
                filter { eq("user_id", userId) }
            }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("app_reminders_preference_failed", t.message ?: "Uygulama bildirimi tercihi kaydedilemedi.", t)
    }
}
