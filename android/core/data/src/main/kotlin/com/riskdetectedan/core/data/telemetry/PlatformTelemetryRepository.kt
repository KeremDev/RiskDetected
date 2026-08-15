package com.riskdetectedan.core.data.telemetry

import com.riskdetectedan.core.common.RdEnvironmentConfig
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

@Serializable
internal data class PlatformTelemetryParams(
    @SerialName("p_platform") val platform: String,
    @SerialName("p_app_version") val appVersion: String,
    @SerialName("p_app_build") val appBuild: String,
)

@Serializable
data class PlatformTelemetryResponse(
    val recorded: Boolean,
    @SerialName("activity_day") val activityDay: String? = null,
)

/**
 * Best-effort analytics transport. This repository is deliberately not part of auth/profile/
 * quota success: callers may retry or ignore failures without changing any user-facing flow.
 */
@Singleton
class PlatformTelemetryRepository @Inject constructor(
    private val client: SupabaseClient,
    private val environmentConfig: RdEnvironmentConfig,
) {
    suspend fun recordCurrentPlatform(): RdResult<PlatformTelemetryResponse> = try {
        val params = Json.encodeToJsonElement(
            PlatformTelemetryParams(
                platform = environmentConfig.clientPlatform,
                appVersion = environmentConfig.appVersionName.substringBefore('-'),
                appBuild = environmentConfig.appVersionCode.toString(),
            ),
        ) as JsonObject
        val response = client.postgrest
            .rpc("record_client_platform_v1", params)
            .decodeAs<PlatformTelemetryResponse>()
        RdResult.Success(response)
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "platform_telemetry_failed",
            message = t.message ?: "platform_telemetry_failed",
            cause = t,
        )
    }
}
