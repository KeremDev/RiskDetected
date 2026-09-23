package com.riskdetectedan.isg.designpreview

import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.feature.nova.NovaReportClient
import kotlinx.serialization.json.JsonPrimitive

/** Synthetic report sources; nothing leaves the process. */
internal object PreviewReportClient : NovaReportClient {
    override val owner = "preview"
    override val companies: suspend () -> List<NovaCompanyOption> = { listOf(NovaCompanyOption("c1", "Koza Altın A.Ş", "Maden · Çok tehlikeli", null)) }
    override suspend fun trainings() = PreviewTrainingClient.page(null).rows
    override suspend fun visits(company: String?, offset: Int) = NovaProcessPage(listOf(
        NovaProcessRow("v1", "c1", "Koza Altın A.Ş", "Saha ziyareti", "2026-09-18T09:00:00Z", "e1",
            mapOf("duration_minutes" to JsonPrimitive(90), "responsible_contact" to JsonPrimitive("Ayşe Demir"),
                "expert_note" to JsonPrimitive("Kırma eleme korkulukları kontrol edildi.")), workplaceName = "Merkez Tesis")))
    override suspend fun tracking(company: String?) = PreviewStatisticsClient.tracking(company)
    override suspend fun documents(offset: Int) = listOf(NovaProcessDocument("d1", 2, "YCP-2026-004", "Koza Altın A.Ş", "annual_work_plan"),
        NovaProcessDocument("d2", 1, "UYG-2026-011", "Koza Altın A.Ş", "nonconformity_report"))
    override suspend fun document(id: String, version: Int) = visits(null, 0).rows.first()
}
