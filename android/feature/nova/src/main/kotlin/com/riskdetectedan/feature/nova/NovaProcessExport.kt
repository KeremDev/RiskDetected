package com.riskdetectedan.feature.nova

import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import com.riskdetectedan.core.data.nova.NovaProcessKind
import com.riskdetectedan.core.data.nova.NovaProcessRow
import com.riskdetectedan.core.data.nova.novaText
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

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

    /** A two-column workbook of inline text cells, so user text never becomes a formula. */
    fun xlsx(row: NovaProcessRow, kind: NovaProcessKind): ByteArray {
        fun xml(text: String) = text.filter { it == '\t' || it == '\n' || it == '\r' || it.code >= 32 }
            .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
        val rows = listOf("Belge" to (row.number ?: row.id), "Firma" to row.companyName, "Modül" to kind.title) + lines(row, kind)
        val sheetRows = rows.mapIndexed { index, (label, value) ->
            val r = index + 1
            "<row r=\"$r\"><c r=\"A$r\" t=\"inlineStr\"><is><t xml:space=\"preserve\">${xml(label)}</t></is></c>" +
                "<c r=\"B$r\" t=\"inlineStr\"><is><t xml:space=\"preserve\">${xml(value)}</t></is></c></row>"
        }.joinToString("")
        val entries = listOf(
            "[Content_Types].xml" to "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>",
            "_rels/.rels" to "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>",
            "xl/workbook.xml" to "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Kayıt\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>",
            "xl/_rels/workbook.xml.rels" to "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>",
            "xl/worksheets/sheet1.xml" to "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cols><col min=\"1\" max=\"1\" width=\"32\" customWidth=\"1\"/><col min=\"2\" max=\"2\" width=\"85\" customWidth=\"1\"/></cols><sheetData>$sheetRows</sheetData></worksheet>")
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            entries.forEach { (name, text) -> zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray(Charsets.UTF_8)); zip.closeEntry() }
        }
        return output.toByteArray()
    }

    /** An A4 record with the fields, children and signature lines (iOS `NovaProcessPDF`). */
    fun pdf(row: NovaProcessRow, kind: NovaProcessKind): ByteArray {
        val document = PdfDocument()
        val width = 595; val height = 842; val margin = 36f; val textWidth = 523
        var page: PdfDocument.Page? = null
        var pageNumber = 0
        var y = 44f
        val footer = Paint().apply { textSize = 8f; color = Color.DKGRAY }
        fun start() {
            page?.let(document::finishPage)
            pageNumber++
            page = document.startPage(PdfDocument.PageInfo.Builder(width, height, pageNumber).create())
            y = 44f
            page!!.canvas.drawText("İSGADA · ${row.number ?: row.id} · v${row.revision ?: 1} · Sayfa $pageNumber", margin, 820f, footer)
        }
        fun paragraph(text: String, size: Float = 11f, bold: Boolean = false) {
            val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = size; color = Color.BLACK; typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            }
            val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, textWidth).setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setLineSpacing(4f, 1f).build()
            var line = 0
            while (line < layout.lineCount) {
                if (y > 780f) start()
                val canvas = page!!.canvas
                var last = line
                while (last < layout.lineCount && y + (layout.getLineBottom(last) - layout.getLineTop(line)) <= 790f) last++
                if (last == line) { start(); continue }
                canvas.save()
                canvas.translate(margin, y - layout.getLineTop(line))
                canvas.clipRect(0f, layout.getLineTop(line).toFloat(), textWidth.toFloat(), layout.getLineBottom(last - 1).toFloat())
                layout.draw(canvas)
                canvas.restore()
                y += (layout.getLineBottom(last - 1) - layout.getLineTop(line)).toFloat()
                line = last
            }
            y += 12f
        }
        start()
        paragraph(kind.title.uppercase(java.util.Locale.forLanguageTag("tr-TR")), 19f, true)
        paragraph("Firma: ${row.companyName}")
        kind.fields.forEach { field ->
            val value = row.values[field.id]
            paragraph(field.title, 10f, true)
            paragraph(if (field.id == "workplace_id") row.workplaceName ?: "İşyeri" else field.choices[value.novaText()] ?: display(value))
        }
        val childCode = row.childKind
        if (childCode != null) {
            val child = NovaProcessKind.get(childCode)
            row.children.orEmpty().forEachIndexed { index, entry ->
                paragraph("${index + 1}. ${child.title}", 13f, true)
                child.fields.forEach { field ->
                    val value = entry.values[field.id]
                    paragraph("${field.title}: ${field.choices[value.novaText()] ?: display(value)}")
                }
            }
        }
        if (kind.code == "work_permit") paragraph("Bu form hazırlama aracıdır. Çalışmayı başlatma yetkisi veya saha onayı vermez.", 9f)
        if (kind.code == "katip_contract") paragraph("Uzman tarafından kaydedilen sözleşme bilgileridir. Resmî İSG-KATİP işlemi yapılmamıştır.", 9f)
        if (y > 650f) start()
        paragraph("Düzenleyen / İmza                         İlgili kişi / İmza", bold = true)
        page?.let(document::finishPage)
        val output = ByteArrayOutputStream()
        document.writeTo(output); document.close()
        return output.toByteArray()
    }
}
