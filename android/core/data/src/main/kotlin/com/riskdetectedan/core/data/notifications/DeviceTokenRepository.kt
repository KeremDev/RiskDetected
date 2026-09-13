package com.riskdetectedan.core.data.notifications

import android.content.Context
import android.os.Build
import com.riskdetectedan.core.common.RdEnvironment
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors NotificationService.swift's `saveDeviceToken(_:)` — same `push_device_tokens` table,
 * Android registrations are upserted by their stable installation identity so an FCM token
 * rotation replaces the old token instead of leaving a second active row. `provider`/
 * `provider_environment`/
 * `application_id`/`installation_id`/`client_build` are the Android/FCM-only columns F1/F2
 * added this session (`20260806220000_android_push_device_tokens.sql`) — iOS rows never set
 * these (provider defaults to `"apns"` there), Android rows always do. `environment` reuses the
 * exact same "sandbox in debug, production in release" split as iOS's `PushEnvironment.current`
 * — mapped from [RdEnvironmentConfig.environment] instead of a `#if DEBUG`, since that's the
 * Android equivalent of the same debug/release distinction (master §9.1: debug/qa -> staging
 * backend, which is the same build-type boundary APNs sandbox/production tracks on iOS).
 */
@Serializable
internal data class PushDeviceTokenPayload(
    @SerialName("user_id") val userId: String,
    val token: String,
    // Do not give these two fields Kotlin defaults. Supabase's serializer omits default-valued
    // properties when encodeDefaults=false; the database would then apply its legacy iOS/APNs
    // defaults and make a valid Android token invisible to the FCM dispatcher.
    val platform: String,
    val environment: String,
    @SerialName("app_version") val appVersion: String?,
    @SerialName("device_model") val deviceModel: String?,
    @SerialName("notifications_enabled") val notificationsEnabled: Boolean,
    @SerialName("last_registered_at") val lastRegisteredAt: String,
    val provider: String,
    @SerialName("provider_environment") val providerEnvironment: String,
    @SerialName("application_id") val applicationId: String,
    @SerialName("installation_id") val installationId: String,
    @SerialName("client_build") val clientBuild: String,
)

@Singleton
class DeviceTokenRepository @Inject constructor(
    private val client: SupabaseClient,
    private val environmentConfig: RdEnvironmentConfig,
    @ApplicationContext private val context: Context,
) {
    private val prefs by lazy { context.getSharedPreferences("rd_device_identity", Context.MODE_PRIVATE) }

    /** Stable per-install random id, generated once and persisted — Android has no first-party
     * "installation id" API as portable as iOS's `identifierForVendor`, so this mints its own,
     * matching what the `installation_id` column is for (per-install FCM registration tracking,
     * not per-user — a fresh install/reinstall gets a new one, same as a fresh iOS install
     * getting a new identifierForVendor). */
    private fun installationId(): String {
        prefs.getString(KEY_INSTALLATION_ID, null)?.let { return it }
        val generated = UUID.randomUUID().toString()
        prefs.edit().putString(KEY_INSTALLATION_ID, generated).apply()
        return generated
    }

    suspend fun registerToken(
        userId: String,
        token: String,
        notificationsEnabled: Boolean,
    ): RdResult<Unit> = try {
        val environment = if (environmentConfig.environment == RdEnvironment.Production) {
            "production"
        } else {
            "sandbox"
        }
        client.postgrest.from("push_device_tokens").upsert(
            PushDeviceTokenPayload(
                userId = userId,
                token = token,
                platform = "android",
                environment = environment,
                appVersion = environmentConfig.appVersionName,
                deviceModel = Build.MODEL,
                notificationsEnabled = notificationsEnabled,
                lastRegisteredAt = Instant.now().toString(),
                provider = "fcm",
                providerEnvironment = environmentConfig.firebaseProjectId,
                applicationId = environmentConfig.applicationId,
                installationId = installationId(),
                clientBuild = environmentConfig.appVersionCode.toString(),
            ),
        ) {
            onConflict = "user_id,provider,application_id,installation_id"
        }
        // The optional P12 RPC may not exist on an older server. Its failure
        // must not turn a successful legacy FCM registration into a failure.
        try {
            client.postgrest.rpc("isg_notification_device_permission_v1",
                Json.encodeToJsonElement(DevicePermissionPayload(token, "fcm", environmentConfig.appVersionCode, notificationsEnabled)).jsonObject)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            // No token, owner, or raw backend error in telemetry.
        }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("device_token_register_failed", t.message ?: "device_token_register_failed", t)
    }

    /**
     * Removes only this installation's FCM registration for the authenticated owner. This must
     * run before Supabase sign-out because the table's delete policy is owner-scoped. Filtering
     * by installation and application prevents a sign-out on one device/build from disabling
     * notifications on the user's other devices.
     */
    suspend fun unregisterCurrentInstallation(userId: String): RdResult<Unit> = try {
        client.postgrest.from("push_device_tokens").delete {
            filter {
                eq("user_id", userId)
                eq("provider", "fcm")
                eq("application_id", environmentConfig.applicationId)
                eq("installation_id", installationId())
            }
        }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("device_token_unregister_failed", "device_token_unregister_failed", t)
    }

    private companion object {
        const val KEY_INSTALLATION_ID = "installation_id"
    }
}

@Serializable
internal data class DevicePermissionPayload(
    @SerialName("p_token") val token: String,
    @SerialName("p_provider") val provider: String,
    @SerialName("p_build") val build: Int,
    @SerialName("p_authorized") val authorized: Boolean,
)
