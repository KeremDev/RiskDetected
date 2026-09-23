package com.riskdetectedan.feature.nova

import com.riskdetectedan.core.data.nova.NovaProcessKind
import com.riskdetectedan.core.data.nova.NovaProcessRow
import com.riskdetectedan.core.data.nova.novaText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject

/** Process record exports (iOS `NovaProcessPDF` and `NovaProcessXLSX`). */
internal object NovaProcessExport {
    private fun display(value: JsonElement?): String = when (value) {
        null, is JsonNull -> "—"
        is JsonArray -> value.joinToString("\n") { display(it) }
        is JsonObject -> value["name"]?.novaText()?.takeIf { it.isNotEmpty() } ?: value.values.joinToString(" · ") { display(it) }
        else -> value.novaText()
    }

    private fun lines(row: NovaProcessRow, kind: NovaProcessKind): List<Pair<String, String>> {
        val result = mutableListOf<Pair<String, String>>()
        fun append(entry: NovaProcessRow, spec: NovaProcessKind) {
            spec.fields.forEach { field ->
                val value = entry.values[field.id]
                result += field.title to if (field.id == "workplace_id") entry.workplaceName.orEmpty() else field.choices[value.novaText()] ?: display(value)
            }
        }
        append(row, kind)
        row.children.orEmpty().forEach { child -> result += "" to ""; append(child, NovaProcessKind.get(row.childKind ?: kind.code)) }
        return result
    }

    fun fileName(row: NovaProcessRow, kind: NovaProcessKind, extension: String) = "${kind.code}-${row.id}-${row.expected.take(8)}.$extension"

    fun xlsx(row: NovaProcessRow, kind: NovaProcessKind): ByteArray {
        val rows = listOf("Belge" to (row.number ?: row.id), "Firma" to row.companyName, "Modül" to kind.title) + lines(row, kind)
        return NovaXlsx.workbook(listOf(NovaXlsx.Sheet("Kayıt", rows.map { listOf(it.first, it.second) }, listOf(32, 85))))
    }

    /** An A4 record with the fields, children and signature lines. */
    fun pdf(row: NovaProcessRow, kind: NovaProcessKind): ByteArray {
        val writer = NovaPdfWriter { page -> "İSGADA · ${row.number ?: row.id} · v${row.revision ?: 1} · Sayfa $page" }
        writer.paragraph(kind.title.uppercase(java.util.Locale.forLanguageTag("tr-TR")), 19f, true)
        writer.paragraph("Firma: ${row.companyName}")
        kind.fields.forEach { field ->
            val value = row.values[field.id]
            writer.paragraph(field.title, 10f, true)
            writer.paragraph(if (field.id == "workplace_id") row.workplaceName ?: "İşyeri" else field.choices[value.novaText()] ?: display(value))
        }
        row.childKind?.let { childCode ->
            val child = NovaProcessKind.get(childCode)
            row.children.orEmpty().forEachIndexed { index, entry ->
                writer.paragraph("${index + 1}. ${child.title}", 13f, true)
                child.fields.forEach { field ->
                    val value = entry.values[field.id]
                    writer.paragraph("${field.title}: ${field.choices[value.novaText()] ?: display(value)}")
                }
            }
        }
        if (kind.code == "work_permit") writer.paragraph("Bu form hazırlama aracıdır. Çalışmayı başlatma yetkisi veya saha onayı vermez.", 9f)
        if (kind.code == "katip_contract") writer.paragraph("Uzman tarafından kaydedilen sözleşme bilgileridir. Resmî İSG-KATİP işlemi yapılmamıştır.", 9f)
        writer.ensure(140f)
        writer.paragraph("Düzenleyen / İmza                         İlgili kişi / İmza", bold = true)
        return writer.finish()
    }
}
