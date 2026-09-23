package com.riskdetectedan.isg.designpreview

import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.feature.nova.NovaStatisticsClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

/** Synthetic statistics; nothing leaves the process. */
internal object PreviewStatisticsClient : NovaStatisticsClient {
    private val months = listOf("2026-04-01" to (3 to 1), "2026-05-01" to (5 to 0), "2026-06-01" to (2 to 2), "2026-07-01" to (0 to 1),
        "2026-08-01" to (7 to 3), "2026-09-01" to (4 to 1))
    override val changes: Flow<Unit> = emptyFlow()
    override suspend fun load(company: String?, months: Int): NovaStatisticsSnapshot {
        val series = this.months.takeLast(months).map { (month, counts) -> NovaStatisticsSnapshot.Month(month, counts.first, counts.second) } +
            (0 until maxOf(0, months - this.months.size)).map { NovaStatisticsSnapshot.Month("2025-${String.format("%02d", 12 - it)}-01", 0, 0) }
        return NovaStatisticsSnapshot(1, "u1", company, months, "2026-04-01", "2026-09-23",
            listOf(NovaStatisticsSnapshot.Company("c1", "Koza Altın A.Ş", 42, 3), NovaStatisticsSnapshot.Company("c2", "Ege Lojistik", 18, 1)),
            2, 60, 4, series.sumOf { it.analyses }, series.sumOf { it.trainings }, 31, 44, series,
            NovaStatisticsSnapshot.Findings(9, 3, 2, 12, 7, mapOf("critical" to 1, "high" to 3, "medium" to 4, "low" to 1)),
            mapOf("valid" to 14, "due_soon" to 3, "expired" to 2, "missing" to 1))
    }
    override suspend fun visits(company: String?, from: String, to: String) = NovaVisitSummary(1, "u1", company, 6, 540, 5, "2026-09-18")
    override suspend fun followup(company: String?) = NovaFollowupPage(1, "u1", company, 14, 3, 2, 1, false, emptyList())
    override suspend fun tracking(company: String?) = NovaModuleTrackingSnapshot("2026-09-23", listOf(
        NovaModuleTrackingSnapshot.Row("c1", "Koza Altın A.Ş", "emergency_plan", true, 3, 0, 1, 1, 0, "2026-10-10"),
        NovaModuleTrackingSnapshot.Row("c1", "Koza Altın A.Ş", "drill", true, 2, 1, 0, 0, 0, null),
        NovaModuleTrackingSnapshot.Row("c1", "Koza Altın A.Ş", "site_visit", true, 6, 0, 0, 0, 1, null),
        NovaModuleTrackingSnapshot.Row("c1", "Koza Altın A.Ş", "checklist_run", true, 4, 0, 0, 0, 0, null),
        NovaModuleTrackingSnapshot.Row("c1", "Koza Altın A.Ş", "board", false),
    ))
}
