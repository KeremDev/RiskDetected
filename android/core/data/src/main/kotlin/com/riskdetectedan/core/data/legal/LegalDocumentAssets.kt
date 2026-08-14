package com.riskdetectedan.core.data.legal

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Real gap sweep finding (2026-08-09): Android had a bundled, counsel-reviewed legal document
 * set (`android/app/src/main/assets/legal`'s `.md` files + `manifest.json`, DEC-10) used only to compute
 * [LegalAndroidVersions]' acceptance-audit checksums — nothing ever actually displayed this text
 * to a user. Every "Kullanım Koşulları"/"Gizlilik Politikası" label across onboarding/auth was
 * static, non-clickable text (5 real trigger points exist on iOS for `LegalInfoSheet`: RootView,
 * AuthView, ProfileView, InAppPaywallView, OnboardingViewV2 — Android had zero). This is the
 * reader half of that gap: loads the same bundled documents [LegalAcceptanceRepository] already
 * trusts for its checksum, for a real on-screen [com.riskdetectedan.core.designsystem.RdLegalDocumentSheet].
 */
data class LegalDocument(
    val kind: String,
    val title: String,
    val version: String,
    val checksum: String,
    val text: String,
)

@Serializable
private data class LegalManifest(val documents: List<LegalManifestEntry>)

@Serializable
private data class LegalManifestEntry(
    val kind: String,
    val title: String,
    val version: String,
    val path: String,
    @SerialName("hash") val checksum: String,
)

object LegalDocumentAssets {
    private const val MANIFEST_PATH = "legal/manifest.json"
    private const val DOCUMENTS_DIR = "legal"

    /** Reads [MANIFEST_PATH] and every document it lists, in manifest order. Returns an empty
     * list on any read/parse failure — same "honest empty state, no crash" reasoning as
     * [com.riskdetectedan.feature.paywall.PaywallScreen]'s no-packages case; the caller shows
     * that as a real (if unlikely, since these are bundled app assets) error state, not a stale
     * placeholder. */
    suspend fun load(context: Context): List<LegalDocument> = withContext(Dispatchers.IO) {
        try {
            val manifestJson = context.assets.open(MANIFEST_PATH).use { it.readBytes() }
                .decodeToString()
            val manifest = Json { ignoreUnknownKeys = true }
                .decodeFromString(LegalManifest.serializer(), manifestJson)
            manifest.documents.mapNotNull { entry ->
                val text = try {
                    context.assets.open("$DOCUMENTS_DIR/${entry.path}").use { it.readBytes() }
                        .decodeToString()
                } catch (t: Throwable) {
                    return@mapNotNull null
                }
                LegalDocument(
                    kind = entry.kind,
                    title = entry.title,
                    version = entry.version,
                    checksum = entry.checksum,
                    text = text,
                )
            }
        } catch (t: Throwable) {
            emptyList()
        }
    }
}
