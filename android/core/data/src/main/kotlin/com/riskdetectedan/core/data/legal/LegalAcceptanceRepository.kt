package com.riskdetectedan.core.data.legal

import android.content.Context
import android.util.Log
import com.riskdetectedan.core.common.RdEnvironmentConfig
import com.riskdetectedan.core.common.RdClientMetadata
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.release.AndroidLegalPolicy
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.encodeToJsonElement
import java.security.MessageDigest
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.min
import kotlin.math.pow

/** Android-specific Turkish versions. English reuses the approved `en-global-v1` versions. */
object LegalAndroidVersions {
    const val KVKK = "kvkk-android-2026-08-09"
    const val TERMS = "terms-android-2026-08-09"
    const val PRIVACY = "privacy-android-2026-08-09"
    const val CONSENT = "consent-android-2026-08-09"
}

private object LegalEnglishVersions {
    const val TERMS = "terms-en-2026-07-31.1"
    const val PRIVACY = "privacy-en-2026-07-31.1"
    const val CONSENT = "ai-data-en-2026-07-31.1"
}

/** Mirrors RDLegalSetAuditMetadata (LegalDocumentService.swift). */
data class LegalAcceptanceAudit(
    val documentSetID: String,
    val locale: String,
    val manifestChecksum: String,
)

/** Mirrors iOS's locale-specific legal-set audit: hash bundled bytes, canonicalize identities. */
object LegalDocumentSet {
    private data class Source(val kind: String, val version: String, val path: String)

    private fun documentSetId(): String = if (RdClientMetadata.APP_LANGUAGE == "en") {
        "en-global-v1"
    } else {
        "tr-android-v1"
    }

    fun locale(): String = if (RdClientMetadata.APP_LANGUAGE == "en") "en" else "tr"

    private fun sources(): List<Source> = if (RdClientMetadata.APP_LANGUAGE == "en") {
        listOf(
            Source("terms", LegalEnglishVersions.TERMS, "en/Terms-of-Use.md"),
            Source("privacy", LegalEnglishVersions.PRIVACY, "en/Privacy-Policy.md"),
            Source("consent", LegalEnglishVersions.CONSENT, "en/AI-and-Data-Processing-Notice.md"),
        )
    } else {
        listOf(
            Source("kvkk", LegalAndroidVersions.KVKK, "legal/KVKK-Aydinlatma-ve-Acik-Riza-Metni.md"),
            Source("terms", LegalAndroidVersions.TERMS, "legal/Kullanim-Kosullari.md"),
            Source("privacy", LegalAndroidVersions.PRIVACY, "legal/Gizlilik-Politikasi.md"),
            Source("consent", LegalAndroidVersions.CONSENT, "legal/Acik-Riza-Beyani.md"),
        )
    }

    /** Returns null if any bundled file is missing/unreadable — mirrors the Swift
     * `guard entries.count == sources.count` fail-closed behavior exactly (a partial audit
     * record is worse than none: it would silently under-represent what the user actually
     * agreed to). */
    fun acceptanceAuditMetadata(context: Context): LegalAcceptanceAudit? {
        val entries = sources().map { source ->
            val bytes = try {
                context.assets.open(source.path).use { it.readBytes() }
            } catch (t: Throwable) {
                return null
            }
            "${source.kind}|${source.version}|${sha256Hex(bytes)}"
        }
        val canonical = entries.sorted().joinToString("\n")
        return LegalAcceptanceAudit(
            documentSetID = documentSetId(),
            locale = locale(),
            manifestChecksum = sha256Hex(canonical.toByteArray(Charsets.UTF_8)),
        )
    }

    private fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
}

@Serializable
private data class ConsentAuditRow(
    @SerialName("user_id") val userId: String,
)

@Serializable
private data class ConsentAuditPayload(
    @SerialName("user_id") val userId: String,
    @SerialName("kvkk_version") val kvkkVersion: String,
    @SerialName("terms_version") val termsVersion: String,
    @SerialName("explicit_consent_version") val explicitConsentVersion: String,
    @SerialName("legal_document_set") val legalDocumentSet: String,
    @SerialName("legal_locale") val legalLocale: String,
    @SerialName("legal_set_manifest_checksum") val legalSetManifestChecksum: String,
    val source: String,
    @SerialName("app_version") val appVersion: String,
    @SerialName("device_id") val deviceId: String,
)

@Serializable
private data class LegalAcknowledgementRpcPayload(
    @SerialName("p_document_kind") val documentKind: String,
    @SerialName("p_version") val version: String,
    @SerialName("p_change_type") val changeType: String,
    @SerialName("p_document_set_id") val documentSetId: String,
    @SerialName("p_document_locale") val documentLocale: String,
    @SerialName("p_document_checksum") val documentChecksum: String,
    @SerialName("p_action") val action: String,
    @SerialName("p_source") val source: String,
    @SerialName("p_app_version") val appVersion: String,
    @SerialName("p_device_id") val deviceId: String,
)

/**
 * Mirrors LegalAcceptanceService.swift's `recordLoginNoticeAcceptanceIfNeeded` — a background,
 * non-blocking audit record written to `consents` on sign-in, not an interactive consent screen.
 * (There isn't one for Turkish on iOS either: `RDLegalReleaseGate.requireAuthAndPurchaseAccess`
 * short-circuits true for Turkish — DEC-10 changed the *text*, not this "continued use" model.)
 * Failures never block sign-in/analysis; retried with exponential backoff (capped 300s) on the
 * next call for the same user, same as iOS.
 */
@Singleton
class LegalAcceptanceRepository @Inject constructor(
    private val client: SupabaseClient,
    private val environmentConfig: RdEnvironmentConfig,
    @ApplicationContext private val context: Context,
) {
    private val prefs by lazy { context.getSharedPreferences("rd_device_identity", Context.MODE_PRIVATE) }
    private val recordedUsers = mutableSetOf<String>()
    private val recordingUsers = mutableSetOf<String>()
    private val failedAttempts = mutableMapOf<String, Int>()
    private val nextRetryAtMillis = mutableMapOf<String, Long>()

    /** Records a material Android legal update only after the server policy is proven to refer
     * to the exact document bytes bundled in this APK. This prevents a stale build from claiming
     * acceptance for text it could not have shown. The server-owned RPC repeats the document
     * registry/checksum validation and writes under auth.uid(), so neither the user id nor the
     * accepted document identity is trusted from a direct table insert. */
    suspend fun acknowledgeLegalUpdate(policy: AndroidLegalPolicy): RdResult<Unit> {
        val audit = LegalDocumentSet.acceptanceAuditMetadata(context)
            ?: return RdResult.Failure("legal_documents_unavailable", "legal_documents_unavailable")
        if (
            audit.documentSetID != policy.documentSetId ||
            audit.locale != LegalDocumentSet.locale() ||
            audit.manifestChecksum != policy.manifestChecksum
        ) {
            return RdResult.Failure("legal_documents_outdated", "legal_documents_outdated")
        }

        val localDocuments = LegalDocumentAssets.load(context).associateBy { it.kind }
        val policyMatchesBundle = policy.documents.size == localDocuments.size &&
            policy.documents.all { required ->
                localDocuments[required.kind]?.let { local ->
                    local.version == required.version && local.checksum == required.checksum
                } == true
            }
        if (!policyMatchesBundle) {
            return RdResult.Failure("legal_documents_outdated", "legal_documents_outdated")
        }

        val action = if (policy.requiresExplicitConsent) {
            "explicitly_accepted"
        } else {
            "continued_use_accepted"
        }
        return try {
            policy.documents.forEach { document ->
                val params = Json.encodeToJsonElement(
                    LegalAcknowledgementRpcPayload(
                        documentKind = document.kind,
                        version = document.version,
                        changeType = document.changeType,
                        documentSetId = policy.documentSetId,
                        documentLocale = audit.locale,
                        documentChecksum = document.checksum,
                        action = action,
                        source = "android_legal_update_notice",
                        appVersion = "${environmentConfig.appVersionName} (${environmentConfig.appVersionCode})",
                        deviceId = installationId(),
                    ),
                ) as JsonObject
                client.postgrest.rpc("acknowledge_legal_document_v1", params)
            }
            RdResult.Success(Unit)
        } catch (t: Throwable) {
            RdResult.Failure("legal_acknowledgement_failed", t.message ?: "legal_acknowledgement_failed", t)
        }
    }

    suspend fun recordLoginNoticeAcceptanceIfNeeded(userId: String) {
        // English consent is explicit and document-specific through acknowledgeLegalUpdate;
        // the legacy `consents` row below is the Turkish continued-use audit only.
        if (RdClientMetadata.APP_LANGUAGE == "en") return
        if (userId in recordedUsers || userId in recordingUsers) return
        val now = System.currentTimeMillis()
        nextRetryAtMillis[userId]?.let { if (it > now) return }

        val audit = LegalDocumentSet.acceptanceAuditMetadata(context)
        if (audit == null) {
            Log.e(TAG, "Consent audit record blocked: legal document-set metadata unavailable.")
            return
        }

        recordingUsers += userId
        try {
            val existing = client.postgrest.from("consents")
                .select {
                    filter {
                        eq("user_id", userId)
                        eq("kvkk_version", LegalAndroidVersions.KVKK)
                        eq("terms_version", LegalAndroidVersions.TERMS)
                        eq("explicit_consent_version", LegalAndroidVersions.CONSENT)
                        eq("legal_document_set", audit.documentSetID)
                        eq("legal_locale", audit.locale)
                        eq("legal_set_manifest_checksum", audit.manifestChecksum)
                    }
                    limit(1)
                }
                .decodeList<ConsentAuditRow>()

            if (existing.isNotEmpty()) {
                markRecorded(userId)
                return
            }

            client.postgrest.from("consents").insert(
                ConsentAuditPayload(
                    userId = userId,
                    kvkkVersion = LegalAndroidVersions.KVKK,
                    termsVersion = LegalAndroidVersions.TERMS,
                    explicitConsentVersion = LegalAndroidVersions.CONSENT,
                    legalDocumentSet = audit.documentSetID,
                    legalLocale = audit.locale,
                    legalSetManifestChecksum = audit.manifestChecksum,
                    source = "login_notice",
                    appVersion = "${environmentConfig.appVersionName} (${environmentConfig.appVersionCode})",
                    deviceId = installationId(),
                ),
            )
            markRecorded(userId)
        } catch (t: Throwable) {
            val attempts = (failedAttempts[userId] ?: 0) + 1
            failedAttempts[userId] = attempts
            val retryDelaySeconds = min(2.0.pow(attempts), 300.0)
            nextRetryAtMillis[userId] = now + (retryDelaySeconds * 1000).toLong()
            Log.e(
                TAG,
                "Consent audit record failed. attempt=$attempts retryDelay=${retryDelaySeconds}s " +
                    "errorClass=${t.javaClass.simpleName}",
            )
        } finally {
            recordingUsers -= userId
        }
    }

    private fun markRecorded(userId: String) {
        failedAttempts -= userId
        nextRetryAtMillis -= userId
        recordedUsers += userId
    }

    /** Same SharedPreferences file+key as DeviceTokenRepository's `installationId()` — both
     * repositories read/write the same persisted per-install id rather than minting a second,
     * competing one; whichever runs first generates it. */
    private fun installationId(): String {
        prefs.getString(KEY_INSTALLATION_ID, null)?.let { return it }
        val generated = UUID.randomUUID().toString()
        prefs.edit().putString(KEY_INSTALLATION_ID, generated).apply()
        return generated
    }

    private companion object {
        const val TAG = "LegalAcceptance"
        const val KEY_INSTALLATION_ID = "installation_id"
    }
}
