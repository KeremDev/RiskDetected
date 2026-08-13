package com.riskdetectedan.core.data.notifications

import android.app.NotificationManager
import android.content.Context
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.encodeToJsonElement
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Serializable
internal data class AndroidEngagementStatePayload(
    @SerialName("p_timezone") val timezone: String,
    @SerialName("p_locale") val locale: String,
    @SerialName("p_authorization_status") val authorizationStatus: String,
    @SerialName("p_app_version") val appVersion: String,
    @SerialName("p_app_build") val appBuild: String,
    @SerialName("p_application_id") val applicationId: String,
)

@Serializable
private data class NotificationOpenPayload(
    @SerialName("p_notification_event_id") val notificationEventId: String,
)

/** Android counterpart of iOS NotificationService.syncEngagementStateIfNeeded(). */
@Singleton
class NotificationEngagementRepository @Inject constructor(
    private val client: SupabaseClient,
    private val environmentConfig: RdEnvironmentConfig,
    @ApplicationContext private val context: Context,
) {
    private val prefs by lazy {
        context.getSharedPreferences("rd_notification_engagement", Context.MODE_PRIVATE)
    }

    suspend fun sync(userId: String, force: Boolean = false): RdResult<Unit> {
        return try {
            val manager = context.getSystemService(NotificationManager::class.java)
            val authorizationStatus = if (manager.areNotificationsEnabled()) "authorized" else "denied"
            val timezone = TimeZone.getDefault().id
            val signature = "$timezone|$authorizationStatus"
            val timestampKey = "last_sync.$userId"
            val signatureKey = "signature.$userId"
            val lastSyncMillis = prefs.getLong(timestampKey, 0L)
            val fresh = lastSyncMillis > 0L &&
                Instant.ofEpochMilli(lastSyncMillis).isAfter(Instant.now().minus(6, ChronoUnit.HOURS))

            if (!force && fresh && prefs.getString(signatureKey, null) == signature) {
                RdResult.Success(Unit)
            } else {
                val params = Json.encodeToJsonElement(
                    AndroidEngagementStatePayload(
                        timezone = timezone,
                        locale = Locale.getDefault().toLanguageTag(),
                        authorizationStatus = authorizationStatus,
                        appVersion = environmentConfig.appVersionName,
                        appBuild = environmentConfig.appVersionCode.toString(),
                        applicationId = environmentConfig.applicationId,
                    ),
                ) as JsonObject
                client.postgrest.rpc("record_android_user_engagement_state_v1", params)
                prefs.edit()
                    .putLong(timestampKey, System.currentTimeMillis())
                    .putString(signatureKey, signature)
                    .apply()
                RdResult.Success(Unit)
            }
        } catch (t: Throwable) {
            RdResult.Failure("notification_engagement_sync_failed", t.message ?: "sync_failed", t)
        }
    }

    suspend fun recordOpen(eventId: String?): RdResult<Unit> {
        if (eventId == null || runCatching { UUID.fromString(eventId) }.isFailure) {
            return RdResult.Success(Unit)
        }
        return try {
            val params = Json.encodeToJsonElement(NotificationOpenPayload(eventId)) as JsonObject
            client.postgrest.rpc("record_notification_open_v1", params)
            RdResult.Success(Unit)
        } catch (t: Throwable) {
            RdResult.Failure("notification_open_record_failed", t.message ?: "record_failed", t)
        }
    }
}
