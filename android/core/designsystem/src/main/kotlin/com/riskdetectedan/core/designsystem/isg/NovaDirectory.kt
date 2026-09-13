package com.riskdetectedan.core.designsystem.isg

import java.util.UUID

enum class NovaDirectoryKind(val title: String) {
    workplaces("İşyerleri"), departments("Departmanlar"), jobs("Görev ve Unvanlar"), contractors("Dış Firmalar"),
    engagements("İşyeri İlişkileri"), contexts("İşyeri Bağlam Geçmişi"), assignments("Görevlendirme Geçmişi"), employers("Personelin İşvereni");
    val isCatalog get() = this in setOf(workplaces, departments, jobs, contractors)
}
sealed interface NovaDirectoryValue {
    data class Text(val value: String): NovaDirectoryValue
    data class Number(val value: Long): NovaDirectoryValue
    data class Flag(val value: Boolean): NovaDirectoryValue
    data object Null: NovaDirectoryValue
}
data class NovaDirectoryRow(val id: UUID, val fields: Map<String, NovaDirectoryValue>) {
    fun text(key: String) = (fields[key] as? NovaDirectoryValue.Text)?.value
    val title get() = text("name") ?: text("title") ?: text("job_title_snapshot") ?: text("jurisdiction") ?: text("description") ?: "Kayıt"
    val version get() = (fields["version"] as? NovaDirectoryValue.Number)?.value ?: 0L
    val archived get() = (fields["is_archived"] as? NovaDirectoryValue.Flag)?.value == true
}
data class NovaDirectoryPage(val rows: List<NovaDirectoryRow>, val next: UUID?, val parentVersion: Long?)
data class NovaDirectoryIntent(val scope: NovaPersonnelScope, val kind: NovaDirectoryKind, val operationID: UUID, val mutationID: UUID, val entityID: UUID?, val expectedVersion: Long, val body: Map<String, NovaDirectoryValue>)
data class NovaDirectoryCommit(val operationID: UUID, val entityID: UUID, val version: Long)
data class NovaDirectoryClient(
    val read: suspend (NovaPersonnelScope, NovaDirectoryKind, UUID?, UUID?, Boolean) -> NovaDirectoryPage,
    val save: suspend (NovaDirectoryIntent) -> NovaDirectoryCommit,
    val pending: suspend (NovaPersonnelScope) -> NovaDirectoryIntent?,
)
