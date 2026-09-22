package com.riskdetectedan.isg.designpreview

import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.feature.nova.NovaFileClient
import com.riskdetectedan.feature.nova.NovaRiskClient

/** Synthetic risk records; nothing leaves the process. */
internal object PreviewRiskClient : NovaRiskClient {
    private fun version(number: Int, kind: NovaRiskKind, state: String, on: String, until: String?) = NovaRiskVersion(number, kind,
        (number - 1).takeIf { it > 0 }, on, null, if (kind == NovaRiskKind.partial) listOf("Kırma Eleme") else emptyList(),
        if (kind == NovaRiskKind.full) null else "Yeni makine hattı eklendi.", state, null, 4, NovaRiskPeriodSource.hazardClass,
        false, false, until, false, null, null, emptyList(), emptyList())

    private fun row(id: String, workplace: String, state: NovaRiskState, until: String?, current: Int, draft: Boolean = false, drift: Boolean = false) =
        NovaRiskRow(id, "c1", "Koza Altın A.Ş", "w-$id", workplace, current, "2024-10-01", until, state, NovaRiskGroup.of(state), 60,
            if (current > 0) NovaRiskKind.full else null, if (current > 0) "2024-10-01" else null, null, null, if (current > 0) 2 else null,
            if (current > 0) NovaRiskPeriodSource.hazardClass else null, false, false, drift, null, "cok_tehlikeli", 2, draft,
            if (draft) current + 1 else null, if (draft) NovaRiskKind.partial else null, null, if (draft) "Yeni makine hattı eklendi." else null, 0,
            buildList {
                if (draft) add(version(current + 1, NovaRiskKind.partial, "draft", "2024-10-01", null))
                if (current > 0) add(version(current, NovaRiskKind.full, "final", "2024-10-01", until))
            })

    private val rows = listOf(
        row("r1", "Merkez Tesis", NovaRiskState.expired, "2026-09-01", 1),
        row("r2", "Kırma Eleme", NovaRiskState.dueSoon, "2026-10-20", 2, draft = true, drift = true),
        row("r3", "Laboratuvar", NovaRiskState.neverAssessed, null, 0),
        row("r4", "İdari Bina", NovaRiskState.valid, "2028-03-14", 1))

    override val companies: suspend () -> List<NovaCompanyOption> = { listOf(NovaCompanyOption("c1", "Koza Altın A.Ş", "Maden", null)) }
    override val files: NovaFileClient get() = error("The design preview has no file library.")
    override suspend fun catalogue(company: String?) = NovaRiskCatalogue(rows.map { NovaRiskCatalogue.Workplace(it.workplaceId!!, it.workplaceName!!, false, "cok_tehlikeli", 2) },
        emptyList(), 60, true)
    override suspend fun board(query: NovaRiskQuery): NovaRiskBoard {
        val group = NovaRiskGroup.ofWire(query.state)
        val shown = rows.filter { group == null || it.group == group }.filter { query.search.isBlank() || it.workplaceName!!.contains(query.search, true) }
        return NovaRiskBoard(shown, rows.groupingBy { it.state.wire }.eachCount(), emptyList(), shown.size, false, 0, 60)
    }
    override suspend fun detail(id: String) = rows.first { it.id == id }
    override suspend fun open(company: String, workplace: String) = rows.firstOrNull { it.workplaceId == workplace }
    override suspend fun draft(company: String, draft: NovaRiskVersionDraft): NovaRiskRow? = throw NovaRiskException(NovaRiskFailure.moduleUnavailable)
    override suspend fun finalize(company: String, draft: NovaRiskFinalizeDraft): NovaRiskRow? = throw NovaRiskException(NovaRiskFailure.moduleUnavailable)
    override suspend fun cancelDraft(company: String, row: NovaRiskRow, version: NovaRiskVersion, reason: String): NovaRiskRow? =
        throw NovaRiskException(NovaRiskFailure.moduleUnavailable)
}
