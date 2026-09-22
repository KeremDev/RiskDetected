package com.riskdetectedan.isg.designpreview

import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.feature.nova.NovaEquipmentClient
import com.riskdetectedan.feature.nova.NovaFileClient

/** Synthetic equipment inventory; nothing leaves the process. */
internal object PreviewEquipmentClient : NovaEquipmentClient {
    private fun item(id: String, type: String, serial: String, state: NovaEquipmentState, next: String?, months: Int?, last: String?,
                     result: String?, source: NovaEquipmentPeriodSource? = NovaEquipmentPeriodSource.regulationDefault) =
        NovaEquipmentItem(id, "c1", "Koza Altın A.Ş", "w1", type, serial, null, "Kırma Eleme", false, state, months, source,
            source?.needsReview, null, false, last, result, if (last != null) "Ahmet Yılmaz" else null, null, next,
            if (next != null) NovaEquipmentDueSource.period else null, false, null, false, null, null,
            if (last != null) listOf(NovaEquipmentInspection("i-$id", last, result ?: "pass", next, months, "Ahmet Yılmaz", "PK-2025-118",
                null, null, null, NovaEquipmentDueSource.period, false, null)) else emptyList())

    private val rows = listOf(
        item("e1", "forklift", "FL-0231", NovaEquipmentState.overdue, "2026-08-30", 12, "2025-08-30", "pass"),
        item("e2", "pressure_vessel", "BK-114", NovaEquipmentState.failed, null, 12, "2026-09-10", "fail"),
        item("e3", "fire_extinguisher", "YS-45", NovaEquipmentState.dueSoon, "2026-10-05", 12, "2025-10-05", "conditional"),
        item("e4", "crane", "VN-07", NovaEquipmentState.neverInspected, null, 12, null, null),
        item("e5", "earthing", "TP-01", NovaEquipmentState.valid, "2027-05-11", 12, "2026-05-11", "pass"))
    private val counts = rows.groupingBy { it.state }.eachCount()

    override val companies: suspend () -> List<NovaCompanyOption> = { listOf(NovaCompanyOption("c1", "Koza Altın A.Ş", "Maden · Çok tehlikeli", null)) }
    override val files: NovaFileClient get() = error("The design preview has no file library.")
    override suspend fun catalogue(company: String?) = NovaEquipmentCatalogue(
        listOf("forklift", "pressure_vessel", "fire_extinguisher", "crane", "earthing").map { NovaEquipmentSuggestion(it, 12, null) },
        listOf(NovaEquipmentRule("forklift", 12, NovaEquipmentPeriodSource.manufacturer, false, null)),
        listOf(NovaEquipmentWorkplace("w1", "Merkez Tesis"), NovaEquipmentWorkplace("w2", "Kırma Eleme")), 30)
    override suspend fun board(query: NovaEquipmentQuery): NovaEquipmentBoard {
        val group = NovaEquipmentGroup.ofWire(query.state)
        val shown = rows.filter { (group == null || it.group == group) && (query.equipmentType == null || it.equipmentType == query.equipmentType) && it.matches(query.query) }
        return NovaEquipmentBoard(counts, listOf(NovaEquipmentCompanySummary("c1", "Koza Altın A.Ş", rows.size, counts)),
            rows.groupBy { it.equipmentType }.mapValues { entry -> entry.value.groupingBy { it.state }.eachCount() }, shown, shown.size, false,
            query.limit, 0, "2026-09-23", 30)
    }
    override suspend fun detail(id: String) = rows.first { it.id == id }
    private fun refuse(): Nothing = throw NovaEquipmentException(NovaEquipmentFailure.moduleUnavailable)
    override suspend fun register(company: String, draft: NovaEquipmentDraft) = refuse()
    override suspend fun update(item: NovaEquipmentItem, draft: NovaEquipmentDraft) = refuse()
    override suspend fun archive(item: NovaEquipmentItem) = refuse()
    override suspend fun setRule(company: String, draft: NovaEquipmentRuleDraft) = refuse()
    override suspend fun recordInspection(item: NovaEquipmentItem, draft: NovaEquipmentInspectionDraft) = refuse()
    override suspend fun updateInspection(item: NovaEquipmentItem, inspection: NovaEquipmentInspection, draft: NovaEquipmentInspectionDraft) = refuse()
    override suspend fun filedReports(company: String) = emptyList<NovaFileEntry>()
}
