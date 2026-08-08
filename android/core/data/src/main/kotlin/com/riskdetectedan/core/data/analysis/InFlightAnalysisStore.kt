package com.riskdetectedan.core.data.analysis

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Real port of `InFlightAnalysis`/`InFlightAnalysisStore` — SharedPreferences instead of
 * UserDefaults (same `@ApplicationContext`-injection pattern as `DeviceTokenRepository`'s
 * `installation_id`/`QuotaViewModel`'s quota cache). Survives the app process being killed while
 * an analysis is mid-submit/mid-poll — without this, a killed process during that ~5-7 minute
 * window silently loses track of an analysis that's still genuinely running server-side (the
 * server keeps processing regardless; only the client's "we're watching it" UI state is lost).
 * Same 30-minute expiry as iOS (`isExpired`) — a record older than that is almost certainly stale
 * (server-side `waitForCompletedResult`'s own deadline tops out at 420s).
 */
@Serializable
data class InFlightAnalysis(
    val analysisId: String,
    val userId: String,
    val photoCount: Int,
    val startedAtMillis: Long,
    val title: String,
    val kind: String = "photo",
) {
    val isExpired: Boolean get() = System.currentTimeMillis() - startedAtMillis > 30 * 60 * 1000
}

@Singleton
class InFlightAnalysisStore @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val prefs by lazy { context.getSharedPreferences("rd_analysis_in_flight", Context.MODE_PRIVATE) }
    private val json = Json { ignoreUnknownKeys = true }

    fun save(analysis: InFlightAnalysis) {
        prefs.edit().putString(KEY, json.encodeToString(InFlightAnalysis.serializer(), analysis)).apply()
    }

    /** Mirrors `load()` — clears a corrupt or expired record as a side effect, same as iOS. */
    fun load(): InFlightAnalysis? {
        val analysis = loadWithoutExpiryCheck() ?: run {
            prefs.edit().remove(KEY).apply()
            return null
        }
        if (analysis.isExpired) {
            clear(analysis.analysisId)
            return null
        }
        return analysis
    }

    /** Mirrors `load(for:)` — a record belonging to a different user (e.g. after a sign-out/
     * sign-in-as-someone-else) is discarded, never resumed cross-account. */
    fun load(userId: String): InFlightAnalysis? {
        val analysis = load() ?: return null
        if (analysis.userId != userId) {
            clear(analysis.analysisId)
            return null
        }
        return analysis
    }

    fun clear(analysisId: String) {
        val current = loadWithoutExpiryCheck()
        if (current == null || current.analysisId == analysisId) {
            prefs.edit().remove(KEY).apply()
        }
    }

    private fun loadWithoutExpiryCheck(): InFlightAnalysis? {
        val raw = prefs.getString(KEY, null) ?: return null
        return runCatching { json.decodeFromString(InFlightAnalysis.serializer(), raw) }.getOrNull()
    }

    private companion object {
        const val KEY = "rd.analysis.inFlight.v1"
    }
}
