package com.riskdetectedan.core.data.notifications

import android.content.Context
import android.os.Build
import com.riskdetectedan.core.common.RdEnvironment
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors NotificationService.swift's `saveDeviceToken(_:)` — same `push_device_tokens` table,
 * same `upsert(onConflict: "user_id,token")`. `provider`/`provider_environment`/
 * `application_id`/`installation_id`/`client_build` are the Android/FCM-only columns F1/F2
 * added this session (`20260806220000_android_push_device_tokens.sql`) — iOS rows never set
 * these (provider defaults to `"apns"` there), Android rows always do. `environment` reuses the
 * exact same "sandbox in debug, production in release" split as iOS's `PushEnvironment.current`
 * — mapped from [RdEnvironmentConfig.environment] instead of a `#if DEBUG`, since that's the
 * Android equivalent of the same debug/release distinction (master §9.1: debug/qa -> staging
 * backend, which is the same build-type boundary APNs sandbox/production tracks on iOS).
 */
@Serializable
private data class PushDeviceTokenPayload(
    @SerialName("user_id") val userId: String,
    val token: String,
    val platform: String = "android",
    val environment: String,
    @SerialName("app_version") val appVersion: String?,
    @SerialName("device_model") val deviceModel: String?,
    @SerialName("notifications_enabled") val notificationsEnabled: Boolean,
    @SerialName("last_registered_at") val lastRegisteredAt: String,
    val provider: String = "fcm",
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
                environment = environment,
                appVersion = environmentConfig.appVersionName,
                deviceModel = Build.MODEL,
                notificationsEnabled = notificationsEnabled,
                lastRegisteredAt = Instant.now().toString(),
                providerEnvironment = environmentConfig.firebaseProjectId,
                applicationId = environmentConfig.applicationId,
                installationId = installationId(),
                clientBuild = environmentConfig.appVersionCode.toString(),
            ),
        ) {
            onConflict = "user_id,token"
        }
        RdResult.Success(Unit)
    } catch (t: Throwable) {
        RdResult.Failure("device_token_register_failed", t.message ?: "device_token_register_failed", t)
    }

    private companion object {
        const val KEY_INSTALLATION_ID = "installation_id"
    }
}
