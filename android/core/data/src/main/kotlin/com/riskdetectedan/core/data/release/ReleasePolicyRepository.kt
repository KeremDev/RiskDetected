package com.riskdetectedan.core.data.release

import android.content.Context
import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.legal.LegalDocumentSet
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.ktor.client.call.body
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
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
data class AndroidRuntimeGate(
    val enabled: Boolean = false,
    val reason: String = "unavailable",
)

enum class AndroidRuntimeGateName {
    Client,
    Auth,
    AnalysisSubmit,
    Payments,
    Notifications,
    PdfReports,
}

@Serializable
data class AndroidRuntimeGates(
    @SerialName("schema_version") val schemaVersion: Int = 1,
    @SerialName("evaluated_version_code") val evaluatedVersionCode: Int? = null,
    val client: AndroidRuntimeGate = AndroidRuntimeGate(),
    val auth: AndroidRuntimeGate = AndroidRuntimeGate(),
    @SerialName("analysis_submit") val analysisSubmit: AndroidRuntimeGate = AndroidRuntimeGate(),
    val payments: AndroidRuntimeGate = AndroidRuntimeGate(),
    val notifications: AndroidRuntimeGate = AndroidRuntimeGate(),
    @SerialName("pdf_reports") val pdfReports: AndroidRuntimeGate = AndroidRuntimeGate(),
) {
    fun decision(name: AndroidRuntimeGateName): AndroidRuntimeGate = when (name) {
        AndroidRuntimeGateName.Client -> client
        AndroidRuntimeGateName.Auth -> auth
        AndroidRuntimeGateName.AnalysisSubmit -> analysisSubmit
        AndroidRuntimeGateName.Payments -> payments
        AndroidRuntimeGateName.Notifications -> notifications
        AndroidRuntimeGateName.PdfReports -> pdfReports
    }

    companion object {
        val CLOSED = AndroidRuntimeGates(schemaVersion = 0)
    }
}

@Serializable
data class AndroidLegalDocumentPolicy(
    val kind: String,
    val version: String,
    val checksum: String,
    @SerialName("change_type") val changeType: String,
)

@Serializable
data class AndroidLegalPolicy(
    @SerialName("schema_version") val schemaVersion: Int = 1,
    val enabled: Boolean = false,
    val required: Boolean = false,
    val action: String = "none",
    val reason: String = "unavailable",
    @SerialName("document_set_id") val documentSetId: String = "",
    @SerialName("manifest_checksum") val manifestChecksum: String = "",
    @SerialName("policy_version") val policyVersion: String = "",
    @SerialName("message_tr") val messageTr: String = "",
    val documents: List<AndroidLegalDocumentPolicy> = emptyList(),
) {
    val requiresAcknowledgement: Boolean
        get() = enabled && required && action == "accept"

    val requiresAppUpdate: Boolean
        get() = enabled && required && action == "update_app"

    val requiresExplicitConsent: Boolean
        get() = documents.any { it.changeType == "explicit_consent" }

    val identity: String
        get() = listOf(policyVersion, documentSetId, manifestChecksum).joinToString("|")
}

data class ReleasePolicySnapshot(
    val releasePolicy: AppReleasePolicy,
    val androidLegalPolicy: AndroidLegalPolicy? = null,
)

@Serializable
private data class AppReleasePolicyResponse(
    val ok: Boolean? = null,
    val policy: AppReleasePolicy? = null,
    @SerialName("android_runtime_gates") val androidRuntimeGates: AndroidRuntimeGates? = null,
    @SerialName("android_legal_policy") val androidLegalPolicy: AndroidLegalPolicy? = null,
)

@Serializable
private data class AndroidLegalContextRequest(
    @SerialName("document_set_id") val documentSetId: String,
    @SerialName("manifest_checksum") val manifestChecksum: String,
    @SerialName("accepted_policy_version") val acceptedPolicyVersion: String,
)

@Serializable
private data class AppReleasePolicyRequest(
    @SerialName("client_platform") val clientPlatform: String,
    @SerialName("client_app_version") val clientAppVersion: String,
    @SerialName("client_app_build") val clientAppBuild: String,
    @SerialName("api_contract_version") val apiContractVersion: Int,
    @SerialName("client_capabilities") val clientCapabilities: Map<String, Boolean>,
    @SerialName("app_language") val appLanguage: String,
    @SerialName("content_locale") val contentLocale: String,
    @SerialName("work_jurisdiction_country") val workJurisdictionCountry: String,
    @SerialName("safety_profile_id") val safetyProfileId: String,
    @SerialName("safety_profile_version") val safetyProfileVersion: Int,
    @SerialName("android_legal_context") val androidLegalContext: AndroidLegalContextRequest?,
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
    private val _androidRuntimeGates = MutableStateFlow(AndroidRuntimeGates.CLOSED)
    val androidRuntimeGates: StateFlow<AndroidRuntimeGates> = _androidRuntimeGates.asStateFlow()

    suspend fun fetchReleasePolicy(userId: String? = null): RdResult<ReleasePolicySnapshot> = try {
        val legalAudit = LegalDocumentSet.acceptanceAuditMetadata(context)
        val response = client.functions.invoke(
            "app-release-policy",
            body = AppReleasePolicyRequest(
                clientPlatform = RdClientMetadata.PLATFORM,
                clientAppVersion = environmentConfig.appVersionName,
                clientAppBuild = environmentConfig.appVersionCode.toString(),
                apiContractVersion = RdClientMetadata.API_CONTRACT_VERSION,
                clientCapabilities = RdClientMetadata.capabilities,
                appLanguage = RdClientMetadata.APP_LANGUAGE,
                contentLocale = RdClientMetadata.CONTENT_LOCALE,
                workJurisdictionCountry = RdClientMetadata.WORK_JURISDICTION_COUNTRY,
                safetyProfileId = RdClientMetadata.SAFETY_PROFILE_ID,
                safetyProfileVersion = RdClientMetadata.SAFETY_PROFILE_VERSION,
                androidLegalContext = legalAudit?.let {
                    AndroidLegalContextRequest(
                        documentSetId = it.documentSetID,
                        manifestChecksum = it.manifestChecksum,
                        acceptedPolicyVersion = userId?.let(::acceptedLegalPolicyVersion).orEmpty(),
                    )
                },
            ),
        ).body<AppReleasePolicyResponse>()
        _androidRuntimeGates.value = response.androidRuntimeGates ?: AndroidRuntimeGates.CLOSED
        RdResult.Success(
            ReleasePolicySnapshot(
                releasePolicy = response.policy ?: AppReleasePolicy.FALLBACK,
                androidLegalPolicy = response.androidLegalPolicy,
            ),
        )
    } catch (t: Throwable) {
        _androidRuntimeGates.value = AndroidRuntimeGates.CLOSED
        RdResult.Failure("release_policy_fetch_failed", t.message ?: "release_policy_fetch_failed", t)
    }

    fun gate(name: AndroidRuntimeGateName): AndroidRuntimeGate =
        _androidRuntimeGates.value.decision(name)

    suspend fun resolveGate(name: AndroidRuntimeGateName): AndroidRuntimeGate {
        if (_androidRuntimeGates.value.schemaVersion == 0) fetchReleasePolicy()
        return gate(name)
    }

    fun acceptedLegalPolicyVersion(userId: String): String =
        prefs.getString(legalAcceptanceKey(userId), null).orEmpty()

    fun markLegalPolicyAccepted(userId: String, policy: AndroidLegalPolicy) {
        prefs.edit().putString(legalAcceptanceKey(userId), policy.policyVersion).apply()
    }

    private fun legalAcceptanceKey(userId: String): String =
        "$KEY_ACCEPTED_LEGAL_POLICY_PREFIX${userId.lowercase()}"

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
        const val KEY_ACCEPTED_LEGAL_POLICY_PREFIX = "accepted_legal_policy."
    }
}
