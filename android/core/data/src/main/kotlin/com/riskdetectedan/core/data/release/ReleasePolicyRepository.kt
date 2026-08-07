package com.riskdetectedan.core.data.release

import android.content.Context
import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.ktor.client.call.body
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Mirrors AppState.swift's `AppReleasePolicy` field-for-field — same `app-release-policy`
 * edge function, same request/response shape. The backend already branches on `client_platform`
 * (F9/ADR-005, deployed this session) so this call gets Android's own policy row, never iOS's.
 */
@Serializable
data class AppReleasePolicy(
    @SerialName("minimum_supported_build") val minimumSupportedBuild: Int? = null,
    @SerialName("latest_build") val latestBuild: Int? = null,
    @SerialName("hard_update_enabled") val hardUpdateEnabled: Boolean? = null,
    @SerialName("soft_update_enabled") val softUpdateEnabled: Boolean? = null,
    @SerialName("app_store_url") val playStoreUrl: String? = null,
    @SerialName("message_tr") val messageTr: String? = null,
    @SerialName("message_en") val messageEn: String? = null,
    @SerialName("policy_version") val policyVersion: String? = null,
) {
    /** Turkish-only client (see every other Turkish-only note this session) — always
     * [messageTr], matching iOS's `RDLanguage.current == .english ? messageEN : messageTR`
     * collapsed to its always-Turkish branch here. */
    val displayMessage: String
        get() = messageTr?.trim()?.takeIf { it.isNotEmpty() }
            ?: "Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin."

    /** Used to remember "user already dismissed *this* soft-update policy" — a new
     * [policyVersion]/build pair is a different identity, so a fresh soft prompt fires again. */
    val identity: String
        get() = listOfNotNull(policyVersion, minimumSupportedBuild, latestBuild).joinToString("|")

    fun requiresHardUpdate(currentBuild: Int?): Boolean {
        if (hardUpdateEnabled != true || currentBuild == null || minimumSupportedBuild == null) return false
        return currentBuild < minimumSupportedBuild
    }

    fun offersSoftUpdate(currentBuild: Int?): Boolean {
        if (softUpdateEnabled != true || currentBuild == null || latestBuild == null) return false
        return currentBuild < latestBuild
    }

    companion object {
        /** Same conservative fallback as iOS's `AppReleasePolicy.fallback` — both update flags
         * off, so a network failure with no cached hard policy never accidentally blocks the app. */
        val FALLBACK = AppReleasePolicy(
            minimumSupportedBuild = null,
            latestBuild = null,
            hardUpdateEnabled = false,
            softUpdateEnabled = false,
            policyVersion = "fallback",
        )
    }
}

@Serializable
private data class AppReleasePolicyResponse(val ok: Boolean? = null, val policy: AppReleasePolicy? = null)

@Serializable
private data class AppReleasePolicyRequest(
    @SerialName("client_platform") val clientPlatform: String,
    @SerialName("client_app_version") val clientAppVersion: String,
    @SerialName("client_app_build") val clientAppBuild: String,
    @SerialName("api_contract_version") val apiContractVersion: Int,
)

/**
 * Mirrors AppState.swift's cached-hard-policy behavior: a hard-update requirement is persisted
 * so it survives a killed process with no network — matching the invariant that a hard-blocked
 * build can never slip past the gate just because the refresh call didn't complete in time.
 * Soft-update dismissal is remembered per [AppReleasePolicy.identity], same as iOS.
 */
@Singleton
class ReleasePolicyRepository @Inject constructor(
    private val client: SupabaseClient,
    private val environmentConfig: RdEnvironmentConfig,
    @ApplicationContext private val context: Context,
) {
    private val prefs by lazy { context.getSharedPreferences("rd_release_policy", Context.MODE_PRIVATE) }

    suspend fun fetchReleasePolicy(): RdResult<AppReleasePolicy> = try {
        val response = client.functions.invoke(
            "app-release-policy",
            body = AppReleasePolicyRequest(
                clientPlatform = RdClientMetadata.PLATFORM,
                clientAppVersion = environmentConfig.appVersionName,
                clientAppBuild = environmentConfig.appVersionCode.toString(),
                apiContractVersion = RdClientMetadata.API_CONTRACT_VERSION,
            ),
        ).body<AppReleasePolicyResponse>()
        RdResult.Success(response.policy ?: AppReleasePolicy.FALLBACK)
    } catch (t: Throwable) {
        RdResult.Failure("release_policy_fetch_failed", t.message ?: "release_policy_fetch_failed", t)
    }

    fun cachedHardPolicy(): AppReleasePolicy? {
        val json = prefs.getString(KEY_CACHED_HARD_POLICY, null) ?: return null
        return try {
            Json.decodeFromString<AppReleasePolicy>(json)
        } catch (t: Throwable) {
            null
        }
    }

    fun cacheHardPolicy(policy: AppReleasePolicy) {
        prefs.edit().putString(KEY_CACHED_HARD_POLICY, Json.encodeToString(policy)).apply()
    }

    fun clearCachedHardPolicy() {
        prefs.edit().remove(KEY_CACHED_HARD_POLICY).apply()
    }

    fun dismissedSoftPolicyIdentity(): String? = prefs.getString(KEY_DISMISSED_SOFT_IDENTITY, null)

    fun dismissSoftPolicy(identity: String) {
        prefs.edit().putString(KEY_DISMISSED_SOFT_IDENTITY, identity).apply()
    }

    private companion object {
        const val KEY_CACHED_HARD_POLICY = "cached_hard_policy"
        const val KEY_DISMISSED_SOFT_IDENTITY = "dismissed_soft_identity"
    }
}
