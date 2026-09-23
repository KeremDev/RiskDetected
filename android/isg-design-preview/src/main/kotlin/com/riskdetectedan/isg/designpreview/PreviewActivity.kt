package com.riskdetectedan.isg.designpreview

import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.feature.nova.NovaActivityClient
import kotlinx.serialization.json.JsonPrimitive

/** Synthetic activity log; nothing leaves the process. */
internal object PreviewActivityClient : NovaActivityClient {
    private val items = listOf(NovaActivityItem(3, "training_session.create", "training_session", "s1", "c1", "Koza Altın A.Ş", "2026-09-22T14:10:00Z"),
        NovaActivityItem(2, "nonconformity.update", "nonconformity", "n1", "c1", "Koza Altın A.Ş", "2026-09-21T09:32:00Z"),
        NovaActivityItem(1, "visit.create", "visit", "v1", "c1", "Koza Altın A.Ş", "2026-09-18T08:05:00Z"))
    override suspend fun page(after: Long?, from: String?, action: String?, company: String?) = NovaActivityPage(1,
        NovaUsageSummary(2_700.0, 31_000.0, 118_000.0, 402_000.0, 0.0, 1_500.0, 42, "2026-09-23T06:40:00Z", "2026-09-23T07:55:00Z"),
        items.filter { action == null || it.action == action }, null, items.map { it.action }, listOf(NovaActivityPage.Company("c1", "Koza Altın A.Ş")))
    override suspend fun detail(event: Long) = NovaActivityDetail(event, items.first { it.id == event }.action, items.first { it.id == event }.entityType,
        "n1", "c1", items.first { it.id == event }.createdAt, listOf(NovaActivityDetail.Change("status", JsonPrimitive("open"), JsonPrimitive("closed")),
            NovaActivityDetail.Change("is_archived", JsonPrimitive(false), JsonPrimitive(true))), linkCompanyId = "c1")
}
