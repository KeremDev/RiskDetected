package com.riskdetectedan.isg.designpreview

import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.feature.nova.NovaDrillClient
import com.riskdetectedan.feature.nova.NovaEmergencyClient
import com.riskdetectedan.feature.nova.NovaFileClient
import com.riskdetectedan.feature.nova.NovaPersonOption

private val previewCompanies: suspend () -> List<NovaCompanyOption> = { listOf(NovaCompanyOption("c1", "Koza Altın A.Ş", "Maden · Çok tehlikeli", null)) }
private val previewTeam = listOf(NovaEmergencyMember("Ayşe Demir", NovaEmergencyRole.coordinator, "0532 000 00 00"),
    NovaEmergencyMember("Mehmet Kaya", NovaEmergencyRole.fire, null), NovaEmergencyMember("Elif Şahin", NovaEmergencyRole.firstAid, null))

/** Synthetic emergency plans; nothing leaves the process. */
internal object PreviewEmergencyClient : NovaEmergencyClient {
    private fun plan(id: String, workplace: String, state: NovaEmergencyState, until: String?, version: Int) = NovaEmergencyPlan(id, "c1", "Koza Altın A.Ş",
        "w-$id", workplace, version, version, "Acil Durum Planı", "2024-09-01", until, state, NovaEmergencyGroup.of(state), 30, false, null,
        previewTeam, previewTeam.size, null, null,
        (version downTo 1).map { NovaEmergencyVersion(it, if (it == version) "active" else "superseded", "Acil Durum Planı", "2024-09-01", until,
            it != version, null, previewTeam, null, null) })
    private val rows = listOf(plan("p1", "Merkez Tesis", NovaEmergencyState.expired, "2026-09-01", 2),
        plan("p2", "Kırma Eleme", NovaEmergencyState.dueSoon, "2026-10-10", 1), plan("p3", "Laboratuvar", NovaEmergencyState.valid, "2028-01-01", 1))
    override val companies = previewCompanies
    override val files: NovaFileClient get() = error("The design preview has no file library.")
    override suspend fun employees(company: String) = previewTeam.mapIndexed { index, member -> NovaPersonOption("e$index", member.fullName) } +
        NovaPersonOption("e9", "Can Yıldız")
    override suspend fun catalogue(company: String?) = NovaEmergencyCatalogue(listOf(NovaEmergencyCatalogue.Workplace("w1", "Merkez Tesis", false, "cok_tehlikeli", 2),
        NovaEmergencyCatalogue.Workplace("w2", "Kırma Eleme", false, "cok_tehlikeli", 2)), NovaEmergencyRole.entries, emptyList(), 30, false)
    override suspend fun board(query: NovaEmergencyQuery): NovaEmergencyBoard {
        val group = NovaEmergencyGroup.ofWire(query.state)
        val shown = rows.filter { group == null || it.group == group }
        return NovaEmergencyBoard(shown, rows.groupingBy { it.state.wire }.eachCount(), emptyList(), shown.size, false, 0, 30)
    }
    override suspend fun detail(id: String) = rows.first { it.id == id }
    override suspend fun publish(company: String, draft: NovaEmergencyPlanDraft): NovaEmergencyPlan? =
        throw NovaEmergencyException(NovaEmergencyFailure.moduleUnavailable)
}

/** Synthetic drills; nothing leaves the process. */
internal object PreviewDrillClient : NovaDrillClient {
    private fun drill(id: String, state: NovaDrillState, planned: String, performed: String?) = NovaDrill(id, "c1", "Koza Altın A.Ş", "w1", "Merkez Tesis",
        "p1", 2, "Acil Durum Planı", id == "d1", planned, performed, state, NovaDrillGroup.of(state), 30, performed != null,
        if (performed != null) "Toplanma alanına 6 dakikada ulaşıldı." else null, null, null,
        if (performed != null) listOf(NovaDrillParticipant("e1", "Ayşe Demir"), NovaDrillParticipant("e2", "Mehmet Kaya")) else emptyList(),
        if (performed != null) 2 else 0, performed != null)
    private val rows = listOf(drill("d1", NovaDrillState.overdue, "2026-09-10", null), drill("d2", NovaDrillState.scheduled, "2026-12-01", null),
        drill("d3", NovaDrillState.performed, "2026-03-01", "2026-03-02"))
    override val companies = previewCompanies
    override suspend fun catalogue(company: String?) = NovaDrillCatalogue(listOf(NovaDrillPlanOption("p1", 2, "Acil Durum Planı", "w1", "Merkez Tesis", "2028-01-01")),
        listOf(NovaDrillParticipant("e1", "Ayşe Demir"), NovaDrillParticipant("e2", "Mehmet Kaya")), 30, false)
    override suspend fun board(query: NovaDrillQuery): NovaDrillBoard {
        val group = NovaDrillGroup.ofWire(query.state)
        val shown = rows.filter { group == null || it.group == group }
        return NovaDrillBoard(shown, rows.groupingBy { it.state.wire }.eachCount(), emptyList(), shown.size, false, 0, 30)
    }
    override suspend fun detail(id: String) = rows.first { it.id == id }
    private fun refuse(): Nothing = throw NovaDrillException(NovaDrillFailure.moduleUnavailable)
    override suspend fun plan(company: String, draft: NovaDrillPlanDraft) = refuse()
    override suspend fun record(company: String, draft: NovaDrillResultDraft) = refuse()
    override suspend fun cancel(company: String, drill: String, reason: String) = refuse()
}
