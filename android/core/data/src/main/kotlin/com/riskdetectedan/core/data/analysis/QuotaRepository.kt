package com.riskdetectedan.core.data.analysis

import com.riskdetectedan.core.common.RdResult
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Count
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import javax.inject.Inject
import javax.inject.Singleton

/** Mirrors AnalysisService.swift's `DailyQuotaUsage` — used/limit + the two derived computed
 * properties (remaining/isExhausted). */
data class DailyQuotaUsage(val used: Int, val limit: Int) {
    val remaining: Int get() = maxOf(limit - used, 0)
    val isExhausted: Boolean get() = remaining == 0
}

/**
 * Mirrors AnalysisService.swift's `dailyQuotaUsage()` — a real Postgrest exact-count query
 * against `usage_events`, read-only. Writes to that table (`reserved`/`completed` events) happen
 * server-side inside the shared `analyze` edge function, already exercised by both platforms
 * (confirmed — no client-side insert into `usage_events` exists anywhere in the iOS app either),
 * so this repository only needs the read side.
 *
 * `freeDailyLimit = 1` matches `AnalysisService.freeDailyLimit` exactly.
 *
 * iOS's `cachedQuotaUsageForCurrentUser`/`cacheQuotaUsage` UserDefaults fallback (`HomeView.swift`'s
 * `loadQuotaUsage()` falls back to a locally cached value on a failed network call, so a
 * transient failure doesn't hide a real quota-exhausted state) lives one layer up, in
 * [com.riskdetectedan.app.home.QuotaViewModel] — same place iOS's own version lives (a View's
 * `@State`, not the service), not duplicated here.
 */
@Singleton
class QuotaRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun dailyQuotaUsage(userId: String): RdResult<DailyQuotaUsage> = try {
        val result = client.postgrest.from("usage_events").select(columns = Columns.list("id")) {
            head = true
            count(Count.EXACT)
            filter {
                eq("user_id", userId)
                isIn("feature", listOf("analysis_standard", "analysis_detailed"))
                isIn("event_type", listOf("reserved", "completed"))
                gte("created_at", istanbulStartOfTodayIso())
            }
        }
        val used = (result.countOrNull() ?: 0L).toInt()
        RdResult.Success(DailyQuotaUsage(used = used, limit = FREE_DAILY_LIMIT))
    } catch (t: Throwable) {
        RdResult.Failure(
            code = "quota_fetch_failed",
            message = t.message ?: "quota_fetch_failed",
            cause = t,
        )
    }

    /** Same "Europe/Istanbul" business timezone as RDConfig.Quota.businessTimeZone, formatted as
     * the UTC instant Postgrest's timestamptz comparison expects — matches
     * AnalysisService.istanbulStartOfTodayISO()'s semantics exactly (calendar midnight computed
     * in Istanbul, serialized as an absolute point in time). */
    private fun istanbulStartOfTodayIso(): String {
        val zone = ZoneId.of("Europe/Istanbul")
        val startOfDay = LocalDate.now(zone).atStartOfDay(zone).toInstant()
        return DateTimeFormatter.ISO_INSTANT.format(startOfDay)
    }

    companion object {
        const val FREE_DAILY_LIMIT = 1
    }
}
