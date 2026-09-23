package com.riskdetectedan.feature.nova

import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** An A4 document of wrapped paragraphs that breaks across pages (iOS `UIGraphicsPDFRenderer` exports). */
internal class NovaPdfWriter(private val header: ((Int) -> String)? = null, private val footer: (Int) -> String) {
    private val document = PdfDocument()
    private var page: PdfDocument.Page? = null
    private var number = 0
    private val margin = 36f
    private val textWidth = 523
    var y = TOP; private set

    fun newPage() {
        page?.let(document::finishPage)
        number++
        page = document.startPage(PdfDocument.PageInfo.Builder(595, 842, number).create())
        y = TOP
        val small = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 8f; color = Color.DKGRAY }
        header?.let { page!!.canvas.drawText(it(number), margin, 28f, small) }
        page!!.canvas.drawText(footer(number), margin, 820f, small)
    }

    fun space(points: Float) { y += points }

    /** Starts a new page when fewer than [points] remain above the footer. */
    fun ensure(points: Float) { if (page == null || y > BOTTOM - points) newPage() }

    fun paragraph(text: String, size: Float = 11f, bold: Boolean = false, after: Float = 12f) {
        if (page == null) newPage()
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size; color = Color.BLACK; typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        }
        val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, textWidth).setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(4f, 1f).build()
        var line = 0
        while (line < layout.lineCount) {
            if (y > BOTTOM - 10f) newPage()
            var last = line
            while (last < layout.lineCount && y + (layout.getLineBottom(last) - layout.getLineTop(line)) <= BOTTOM) last++
            if (last == line) { newPage(); continue }
            val canvas = page!!.canvas
            canvas.save()
            canvas.translate(margin, y - layout.getLineTop(line))
            canvas.clipRect(0f, layout.getLineTop(line).toFloat(), textWidth.toFloat(), layout.getLineBottom(last - 1).toFloat())
            layout.draw(canvas)
            canvas.restore()
            y += (layout.getLineBottom(last - 1) - layout.getLineTop(line)).toFloat()
            line = last
        }
        y += after
    }

    fun finish(): ByteArray {
        page?.let(document::finishPage); page = null
        val output = ByteArrayOutputStream()
        document.writeTo(output); document.close()
        return output.toByteArray()
    }

    private companion object { const val TOP = 44f; const val BOTTOM = 790f }
}

/** A minimal OOXML workbook of inline text cells, so user text never becomes a formula. */
internal object NovaXlsx {
    data class Sheet(val name: String, val rows: List<List<String>>, val widths: List<Int>, val freeze: Boolean = false, val filter: Boolean = false)

    private fun xml(value: String) = value.filter { it == '\t' || it == '\n' || it == '\r' || it.code >= 32 }
        .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

    private fun column(index: Int): String {
        var value = index + 1; var answer = ""
        while (value > 0) { value -= 1; answer = ('A' + value % 26) + answer; value /= 26 }
        return answer
    }

    private fun sheetXml(sheet: Sheet): String {
        val rows = sheet.rows.mapIndexed { rowIndex, cells ->
            "<row r=\"${rowIndex + 1}\">" + cells.mapIndexed { columnIndex, value ->
                "<c r=\"${column(columnIndex)}${rowIndex + 1}\" t=\"inlineStr\"><is><t xml:space=\"preserve\">${xml(value)}</t></is></c>"
            }.joinToString("") + "</row>"
        }.joinToString("")
        val columns = sheet.widths.mapIndexed { index, width -> "<col min=\"${index + 1}\" max=\"${index + 1}\" width=\"$width\" customWidth=\"1\"/>" }.joinToString("")
        val views = if (sheet.freeze) "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>" else ""
        val filter = if (sheet.filter && sheet.rows.isNotEmpty()) "<autoFilter ref=\"A1:${column(maxOf((sheet.rows.first().size) - 1, 0))}${sheet.rows.size}\"/>" else ""
        return "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">$views<cols>$columns</cols><sheetData>$rows</sheetData>$filter</worksheet>"
    }

    fun workbook(sheets: List<Sheet>): ByteArray {
        val overrides = sheets.indices.joinToString("") {
            "<Override PartName=\"/xl/worksheets/sheet${it + 1}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        val sheetList = sheets.mapIndexed { index, sheet -> "<sheet name=\"${xml(sheet.name)}\" sheetId=\"${index + 1}\" r:id=\"rId${index + 1}\"/>" }.joinToString("")
        val relations = sheets.indices.joinToString("") {
            "<Relationship Id=\"rId${it + 1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet${it + 1}.xml\"/>"
        }
        val entries = listOf(
            "[Content_Types].xml" to "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>$overrides</Types>",
            "_rels/.rels" to "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>",
            "xl/workbook.xml" to "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>$sheetList</sheets></workbook>",
            "xl/_rels/workbook.xml.rels" to "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">$relations</Relationships>",
        ) + sheets.mapIndexed { index, sheet -> "xl/worksheets/sheet${index + 1}.xml" to sheetXml(sheet) }
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            entries.forEach { (name, text) -> zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray(Charsets.UTF_8)); zip.closeEntry() }
        }
        return output.toByteArray()
    }

    const val MIME = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
}
