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

/** UI feedback, not authority: the RPC checks scope, full history and concurrent edits. */
object NovaDirectoryFormRules {
    fun isDate(value: String): Boolean {
        if (!Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}").matches(value)) return false
        val year = value.take(4).toInt(); val month = value.substring(5, 7).toInt(); val day = value.takeLast(2).toInt()
        if (year == 0 || month !in 1..12) return false
        val leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
        val days = listOf(31, if (leap) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
        return day in 1..days[month - 1]
    }
    fun allowedOptions(rows: List<NovaDirectoryRow>, field: String, workplace: String?, originalID: UUID?): List<NovaDirectoryRow> {
        val blocked = mutableSetOf<UUID>()
        if (field == "parent_id" && originalID != null) {
            blocked += originalID
            // Only loaded ancestors are known; the server still checks the complete tree.
            var changed = true
            while (changed) {
                changed = false
                rows.forEach { row ->
                    val parent = row.text("parent_id")?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                    if (parent in blocked && blocked.add(row.id)) changed = true
                }
            }
        }
        return rows.filter { row ->
            !row.archived && (field !in setOf("parent_id", "department_id") ||
                (row.id !in blocked && row.text("workplace_id")?.lowercase() == workplace?.lowercase()))
        }
    }
    fun selecting(field: String, value: String, fields: Map<String, String>): Map<String, String> =
        fields + (if (field == "workplace_id" && fields[field] != value) mapOf("parent_id" to "", "department_id" to "") else emptyMap()) + (field to value)

    fun validation(kind: NovaDirectoryKind, fields: Map<String, String>, options: Map<String, List<NovaDirectoryRow>>, originalID: UUID?): String? {
        val values = fields.mapValues { it.value.trim() }
        if (kind in setOf(NovaDirectoryKind.engagements, NovaDirectoryKind.contexts, NovaDirectoryKind.assignments)) {
            val start = values["starts_on"].orEmpty(); val end = values["ends_before"].orEmpty()
            if (!isDate(start)) return "Başlangıç tarihini YYYY-AA-GG biçiminde geçerli bir tarih olarak girin."
            if (kind == NovaDirectoryKind.engagements && end.isNotEmpty()) {
                if (!isDate(end)) return "Bitiş tarihini YYYY-AA-GG biçiminde geçerli bir tarih olarak girin."
                if (end <= start) return "Bitiş (hariç), başlangıç tarihinden sonra olmalı."
            }
            val previous = values["previous_id"].orEmpty()
            if (previous.isNotEmpty()) {
                val row = options["previous_id"]?.firstOrNull { it.id.toString().equals(previous, ignoreCase = true) }
                val priorStart = row?.text("starts_on")
                if (priorStart == null || !isDate(priorStart)) return "Önceki dönemi listeden yeniden seçin; gerekirse diğer kayıtları yükleyin."
                if (start <= priorStart || row.text("ends_before")?.let { start >= it } == true)
                    return "Yeni başlangıç, önceki dönemin başlangıcından sonra ve varsa bitişinden önce olmalı."
            }
        }
        for (key in listOf("parent_id", "department_id")) {
            val selected = values[key].orEmpty()
            if (selected.isNotEmpty() && allowedOptions(options[key].orEmpty(), key, values["workplace_id"], originalID).none { it.id.toString().equals(selected, ignoreCase = true) })
                return "Departmanı seçili işyerinin geçerli listesinden seçin; kendi alt departmanınızı üst departman yapamazsınız."
        }
        return null
    }
}
