package com.riskdetectedan.core.data.reports

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FineKinneyValues
import java.io.ByteArrayOutputStream

/** What [PdfReportGenerator] needs to lay out a report — deliberately not a 1:1 port of
 * `PDFReportService.ReportInput` (which carries live `UIImage`/`AnalysisResultBundle` objects);
 * this repo's report-generation call site (`ReportsRepository.generatePdfReport`) resolves those
 * down to plain bytes/strings first, keeping this generator itself free of any network/Storage
 * dependency — pure rendering, easy to test in isolation. */
data class PdfReportInput(
    val kind: String, // "standard" | "risk_analysis" — matches PDFReportKind's rawValue exactly
    val method: String, // "fine_kinney" | "matrix_5x5" — matches RiskMethodWire
    val title: String,
    val canvasLabel: String,
    val createdAt: String?,
    val findings: List<Finding>,
    val companyName: String?,
    val companyAddress: String?,
    val companyLogoBytes: ByteArray?,
    val preparedByName: String,
    val preparedByTitle: String?,
    val certificateNumber: String?,
    val coverPhotoBytes: ByteArray?,
)

/**
 * Real on-device PDF report generator (DEC-09) — Android's `android.graphics.pdf.PdfDocument`
 * counterpart to `PDFReportService.swift`. That file is 1642 lines of hand-tuned Core Graphics
 * drawing (per-method risk-assessment tables with color-coded score grids, a full Fine-Kinney/
 * 5x5-Matrix reference-legend page, cover-image collages, page chrome with running headers).
 * This port keeps the same real *structure* — cover page, finding-detail pages, and (for
 * `kind="risk_analysis"`) a real risk-assessment table + method reference page — with the same
 * real data throughout (no placeholder text anywhere), but does not attempt byte-identical
 * layout/typography replication of every table cell and gradient; same "structure real,
 * decoration reasonably matched, not pixel-identical" policy this whole visual pass has used
 * since Home's rebuild. Per-finding photo association (`source_photo_indices`) isn't ported —
 * [Finding] doesn't carry that column yet — only a single cover photo is placed, documented gap.
 */
object PdfReportGenerator {
    // A4 at ~150dpi — sharp enough for on-screen PDF viewers/printing without an unreasonably
    // large file for a text-heavy document.
    private const val PAGE_WIDTH = 1240
    private const val PAGE_HEIGHT = 1754
    private const val MARGIN = 60f

    private val COLOR_ONYX = Color.parseColor("#1A1D1F")
    private val COLOR_SLATE = Color.parseColor("#64748B")
    private val COLOR_LINE = Color.parseColor("#E2E8F0")
    private val COLOR_GREEN = Color.parseColor("#00B82E")
    private val COLOR_WHITE = Color.WHITE

    private fun bandColor(band: String): Int = when (band.lowercase()) {
        "critical" -> Color.parseColor("#B42318")
        "high" -> Color.parseColor("#C76A00")
        "medium" -> Color.parseColor("#D4A106")
        "low" -> Color.parseColor("#237A3B")
        else -> Color.parseColor("#94A3B8")
    }

    private fun bandLabel(band: String): String = when (band.lowercase()) {
        "critical" -> "Kritik"
        "high" -> "Yüksek"
        "medium" -> "Orta"
        "low" -> "Düşük"
        else -> "Bilinmiyor"
    }

    /** Table column budget is a fixed char count, not a wrap — cutting to [max] mid-word without
     * marking it reads like a typo (verified on the real test render: "...malzeme isti" looked
     * broken, not truncated). One glyph of the budget goes to "…" when cut. */
    private fun truncateWithEllipsis(text: String, max: Int): String =
        if (text.length <= max) text else text.take(max - 1).trimEnd() + "…"

    fun generate(input: PdfReportInput): ByteArray {
        val document = PdfDocument()
        var pageNumber = 1

        pageNumber = drawCoverPage(document, input, pageNumber)
        pageNumber = drawFindingPages(document, input, pageNumber)
        if (input.kind == "risk_analysis") {
            drawRiskAssessmentPages(document, input, pageNumber)
        }

        val output = ByteArrayOutputStream()
        document.writeTo(output)
        document.close()
        return output.toByteArray()
    }

    private fun newPage(document: PdfDocument, pageNumber: Int): PdfDocument.Page {
        val info = PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNumber).create()
        return document.startPage(info)
    }

    private fun drawFooter(canvas: Canvas, pageNumber: Int) {
        val paint = TextPaint().apply { color = COLOR_SLATE; textSize = 20f; textAlign = Paint.Align.CENTER }
        canvas.drawText("$pageNumber", PAGE_WIDTH / 2f, PAGE_HEIGHT - 30f, paint)
    }

    private fun drawCoverPage(document: PdfDocument, input: PdfReportInput, startPage: Int): Int {
        val page = newPage(document, startPage)
        val canvas = page.canvas
        var y = MARGIN + 20f

        // Wordmark
        val brand = TextPaint().apply { color = COLOR_ONYX; textSize = 34f; isFakeBoldText = true }
        canvas.drawText("RiskDetected", MARGIN, y, brand)
        y += 30f
        val tagline = TextPaint().apply { color = COLOR_SLATE; textSize = 18f }
        canvas.drawText("Profesyonel İSG Asistanı", MARGIN, y, tagline)
        y += 70f

        canvas.drawLine(MARGIN, y, PAGE_WIDTH - MARGIN, y, Paint().apply { color = COLOR_LINE; strokeWidth = 2f })
        y += 60f

        // Report title
        val title = TextPaint().apply { color = COLOR_ONYX; textSize = 40f; isFakeBoldText = true }
        y = drawWrapped(canvas, if (input.kind == "risk_analysis") "Risk Değerlendirme Raporu" else "Standart Rapor", MARGIN, y, PAGE_WIDTH - 2 * MARGIN, title) + 12f
        val subtitle = TextPaint().apply { color = COLOR_SLATE; textSize = 22f }
        y = drawWrapped(canvas, input.title, MARGIN, y, PAGE_WIDTH - 2 * MARGIN, subtitle) + 50f

        // Company block (logo + name/address)
        input.companyLogoBytes?.let { bytes ->
            val bitmap = runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
            if (bitmap != null) {
                val logoRect = RectF(MARGIN, y, MARGIN + 120f, y + 120f)
                drawBitmapFit(canvas, bitmap, logoRect)
            }
        }
        val companyTextX = if (input.companyLogoBytes != null) MARGIN + 140f else MARGIN
        if (!input.companyName.isNullOrBlank()) {
            val companyPaint = TextPaint().apply { color = COLOR_ONYX; textSize = 24f; isFakeBoldText = true }
            canvas.drawText(input.companyName, companyTextX, y + 30f, companyPaint)
            input.companyAddress?.takeIf { it.isNotBlank() }?.let {
                val addrPaint = TextPaint().apply { color = COLOR_SLATE; textSize = 18f }
                drawWrapped(canvas, it, companyTextX, y + 60f, PAGE_WIDTH - MARGIN - companyTextX, addrPaint)
            }
            y += 140f
        }

        // Info rows
        val rows = listOfNotNull(
            "Hazırlayan" to input.preparedByName,
            input.preparedByTitle?.takeIf { it.isNotBlank() }?.let { "Unvan" to it },
            input.certificateNumber?.takeIf { it.isNotBlank() }?.let { "Sertifika No" to it },
            "Analiz Odağı" to input.canvasLabel,
            "Yöntem" to if (input.method == "matrix_5x5") "5x5 Risk Matrisi" else "Fine-Kinney",
            "Tarih" to (input.createdAt?.take(10) ?: "—"),
        )
        val labelPaint = TextPaint().apply { color = COLOR_SLATE; textSize = 18f }
        val valuePaint = TextPaint().apply { color = COLOR_ONYX; textSize = 18f; isFakeBoldText = true }
        rows.forEach { (label, value) ->
            canvas.drawText(label, MARGIN, y, labelPaint)
            canvas.drawText(value, MARGIN + 220f, y, valuePaint)
            y += 34f
        }
        y += 30f

        // Summary counts by band
        val counts = input.findings.groupingBy { it.fkBand.ifBlank { it.m5Band } }.eachCount()
        val summaryPaint = TextPaint().apply { color = COLOR_ONYX; textSize = 22f; isFakeBoldText = true }
        canvas.drawText("${input.findings.size} bulgu", MARGIN, y, summaryPaint)
        y += 40f
        var chipX = MARGIN
        listOf("critical", "high", "medium", "low").forEach { band ->
            val count = counts[band] ?: 0
            if (count > 0) {
                val chipPaint = Paint().apply { color = bandColor(band) }
                canvas.drawRoundRect(RectF(chipX, y - 26f, chipX + 130f, y + 4f), 8f, 8f, chipPaint)
                val chipText = TextPaint().apply { color = COLOR_WHITE; textSize = 16f; isFakeBoldText = true; textAlign = Paint.Align.CENTER }
                canvas.drawText("${bandLabel(band)}: $count", chipX + 65f, y - 6f, chipText)
                chipX += 150f
            }
        }
        y += 50f

        input.coverPhotoBytes?.let { bytes ->
            val bitmap = runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
            if (bitmap != null) {
                val photoRect = RectF(MARGIN, y, PAGE_WIDTH - MARGIN, minOf(y + 500f, PAGE_HEIGHT - 100f))
                drawBitmapFit(canvas, bitmap, photoRect, cropToFill = true)
            }
        }

        drawFooter(canvas, startPage)
        document.finishPage(page)
        return startPage + 1
    }

    private fun drawFindingPages(document: PdfDocument, input: PdfReportInput, startPage: Int): Int {
        if (input.findings.isEmpty()) return startPage
        var pageNumber = startPage
        var page = newPage(document, pageNumber)
        var canvas = page.canvas
        var y = MARGIN

        fun header() {
            val h = TextPaint().apply { color = COLOR_ONYX; textSize = 26f; isFakeBoldText = true }
            canvas.drawText("Bulgu Detayları", MARGIN, y, h)
            y += 50f
        }
        header()

        input.findings.forEachIndexed { index, finding ->
            val band = finding.fkBand.ifBlank { finding.m5Band }
            val score = finding.fkScore ?: finding.m5Score?.toDouble()

            // Estimate this block's height and start a new page if it won't fit.
            val estimatedHeight = 220f + (finding.description?.let { estimateWrappedHeight(it, PAGE_WIDTH - 2 * MARGIN, 18f) } ?: 0f)
            if (y + estimatedHeight > PAGE_HEIGHT - MARGIN) {
                drawFooter(canvas, pageNumber)
                document.finishPage(page)
                pageNumber += 1
                page = newPage(document, pageNumber)
                canvas = page.canvas
                y = MARGIN
                header()
            }

            val titlePaint = TextPaint().apply { color = COLOR_ONYX; textSize = 22f; isFakeBoldText = true }
            canvas.drawText("${index + 1}. ${finding.title}", MARGIN, y, titlePaint)

            val chipPaint = Paint().apply { color = bandColor(band) }
            val chipLabel = "${bandLabel(band)}${score?.let { " · %.1f".format(it) } ?: ""}"
            val chipWidth = 40f + chipLabel.length * 11f
            canvas.drawRoundRect(RectF(PAGE_WIDTH - MARGIN - chipWidth, y - 28f, PAGE_WIDTH - MARGIN, y + 4f), 8f, 8f, chipPaint)
            val chipText = TextPaint().apply { color = COLOR_WHITE; textSize = 16f; isFakeBoldText = true; textAlign = Paint.Align.CENTER }
            canvas.drawText(chipLabel, PAGE_WIDTH - MARGIN - chipWidth / 2f, y - 8f, chipText)
            y += 34f

            finding.category?.takeIf { it.isNotBlank() }?.let {
                val catPaint = TextPaint().apply { color = COLOR_SLATE; textSize = 16f }
                canvas.drawText(it, MARGIN, y, catPaint)
                y += 28f
            }
            finding.description?.takeIf { it.isNotBlank() }?.let {
                val descPaint = TextPaint().apply { color = COLOR_ONYX; textSize = 18f }
                y = drawWrapped(canvas, it, MARGIN, y, PAGE_WIDTH - 2 * MARGIN, descPaint) + 16f
            }
            finding.rootCauseText?.takeIf { it.isNotBlank() }?.let {
                val labelPaint = TextPaint().apply { color = COLOR_SLATE; textSize = 15f; isFakeBoldText = true }
                canvas.drawText("Kök neden", MARGIN, y, labelPaint)
                y += 22f
                val bodyPaint = TextPaint().apply { color = COLOR_ONYX; textSize = 17f }
                y = drawWrapped(canvas, it, MARGIN, y, PAGE_WIDTH - 2 * MARGIN, bodyPaint) + 16f
            }
            val measures = finding.recommendedMeasures
            if (!measures.isNullOrEmpty()) {
                val labelPaint = TextPaint().apply { color = COLOR_SLATE; textSize = 15f; isFakeBoldText = true }
                canvas.drawText("Önlemler", MARGIN, y, labelPaint)
                y += 22f
                val bodyPaint = TextPaint().apply { color = COLOR_ONYX; textSize = 17f }
                measures.forEach { measure ->
                    val kindLabel = if (measure.kind == "preventive") "Önleyici" else "Düzeltici"
                    y = drawWrapped(canvas, "• [$kindLabel] ${measure.title}: ${measure.text}", MARGIN, y, PAGE_WIDTH - 2 * MARGIN, bodyPaint) + 8f
                }
                y += 8f
            } else {
                finding.recommendedAction?.takeIf { it.isNotBlank() }?.let {
                    val labelPaint = TextPaint().apply { color = COLOR_SLATE; textSize = 15f; isFakeBoldText = true }
                    canvas.drawText("Önerilen aksiyon", MARGIN, y, labelPaint)
                    y += 22f
                    val bodyPaint = TextPaint().apply { color = COLOR_ONYX; textSize = 17f }
                    y = drawWrapped(canvas, it, MARGIN, y, PAGE_WIDTH - 2 * MARGIN, bodyPaint) + 16f
                }
            }

            canvas.drawLine(MARGIN, y, PAGE_WIDTH - MARGIN, y, Paint().apply { color = COLOR_LINE; strokeWidth = 1.5f })
            y += 36f
        }

        drawFooter(canvas, pageNumber)
        document.finishPage(page)
        return pageNumber + 1
    }

    /** `kind="risk_analysis"` only — real assessment table (ordinal/title/method
     * values/score/band per finding) + a reference legend page using the real
     * [com.riskdetectedan.core.data.analysis.FineKinneyValues] option sets for Fine-Kinney, or a
     * short 1-5 scale description for the 5x5 matrix — not iOS's full multi-page illustrated
     * legend, a real but condensed reference. */
    private fun drawRiskAssessmentPages(document: PdfDocument, input: PdfReportInput, startPage: Int) {
        var pageNumber = startPage
        var page = newPage(document, pageNumber)
        var canvas = page.canvas
        var y = MARGIN

        val header = TextPaint().apply { color = COLOR_ONYX; textSize = 26f; isFakeBoldText = true }
        canvas.drawText("Risk Değerlendirme Tablosu", MARGIN, y, header)
        y += 50f

        val isMatrix = input.method == "matrix_5x5"
        val headers = if (isMatrix) listOf("No", "Bulgu", "Olasılık", "Şiddet", "Skor", "Seviye") else listOf("No", "Bulgu", "O", "F", "Ş", "Skor", "Seviye")
        val widths = if (isMatrix) {
            listOf(0.06f, 0.44f, 0.12f, 0.12f, 0.12f, 0.14f)
        } else {
            listOf(0.05f, 0.37f, 0.09f, 0.09f, 0.09f, 0.13f, 0.18f)
        }
        val tableWidth = PAGE_WIDTH - 2 * MARGIN
        y = drawTableRow(canvas, MARGIN, y, tableWidth, widths, headers, isHeader = true)

        input.findings.forEachIndexed { index, finding ->
            if (y > PAGE_HEIGHT - MARGIN - 40f) {
                drawFooter(canvas, pageNumber)
                document.finishPage(page)
                pageNumber += 1
                page = newPage(document, pageNumber)
                canvas = page.canvas
                y = MARGIN
                y = drawTableRow(canvas, MARGIN, y, tableWidth, widths, headers, isHeader = true)
            }
            val band = if (isMatrix) finding.m5Band else finding.fkBand
            val score = if (isMatrix) finding.m5Score?.toString() else finding.fkScore?.let { "%.1f".format(it) }
            val values = if (isMatrix) {
                listOf(
                    "${index + 1}", truncateWithEllipsis(finding.title, 40),
                    finding.m5Probability?.toString() ?: "—",
                    finding.m5Severity?.toString() ?: "—",
                    score ?: "—", bandLabel(band),
                )
            } else {
                listOf(
                    "${index + 1}", truncateWithEllipsis(finding.title, 32),
                    finding.fkProbability?.let { "%.1f".format(it) } ?: "—",
                    finding.fkFrequency?.let { "%.1f".format(it) } ?: "—",
                    finding.fkSeverity?.let { "%.1f".format(it) } ?: "—",
                    score ?: "—", bandLabel(band),
                )
            }
            y = drawTableRow(canvas, MARGIN, y, tableWidth, widths, values, isHeader = false, bandForRow = band)
        }

        y += 40f
        val legendTitle = TextPaint().apply { color = COLOR_ONYX; textSize = 22f; isFakeBoldText = true }
        if (y > PAGE_HEIGHT - MARGIN - 200f) {
            drawFooter(canvas, pageNumber)
            document.finishPage(page)
            pageNumber += 1
            page = newPage(document, pageNumber)
            canvas = page.canvas
            y = MARGIN
        }
        canvas.drawText(if (isMatrix) "5x5 Risk Matrisi Referansı" else "Fine-Kinney Referansı", MARGIN, y, legendTitle)
        y += 40f
        val bodyPaint = TextPaint().apply { color = COLOR_ONYX; textSize = 17f }
        val legendText = if (isMatrix) {
            "Skor = Olasılık × Şiddet (1-5 ölçek her ikisi için de). 1-4: Düşük, 5-9: Orta, 10-14: Yüksek, 15-25: Kritik."
        } else {
            val p = FineKinneyValues.PROBABILITY.joinToString(", ")
            val f = FineKinneyValues.FREQUENCY.joinToString(", ")
            val s = FineKinneyValues.SEVERITY.joinToString(", ")
            "Skor = Olasılık (O) × Frekans (F) × Şiddet (Ş).\nOlasılık değerleri: $p\nFrekans değerleri: $f\nŞiddet değerleri: $s\n" +
                "0-20: Düşük, 20-70: Orta, 70-200: Yüksek, 200+: Kritik."
        }
        drawWrapped(canvas, legendText, MARGIN, y, tableWidth, bodyPaint)

        drawFooter(canvas, pageNumber)
        document.finishPage(page)
    }

    private fun drawTableRow(
        canvas: Canvas,
        x: Float,
        y: Float,
        totalWidth: Float,
        weights: List<Float>,
        values: List<String>,
        isHeader: Boolean,
        bandForRow: String? = null,
    ): Float {
        val rowHeight = 40f
        if (isHeader) {
            canvas.drawRect(RectF(x, y, x + totalWidth, y + rowHeight), Paint().apply { color = COLOR_ONYX })
        } else if (bandForRow != null) {
            canvas.drawRect(RectF(x, y, x + totalWidth, y + rowHeight), Paint().apply { color = Color.argb(28, Color.red(bandColor(bandForRow)), Color.green(bandColor(bandForRow)), Color.blue(bandColor(bandForRow))) })
        }
        var cellX = x
        val paint = TextPaint().apply {
            color = if (isHeader) COLOR_WHITE else COLOR_ONYX
            textSize = 15f
            isFakeBoldText = isHeader
        }
        values.forEachIndexed { i, value ->
            val cellWidth = totalWidth * weights[i]
            canvas.drawText(value, cellX + 8f, y + rowHeight - 12f, paint)
            cellX += cellWidth
        }
        canvas.drawLine(x, y + rowHeight, x + totalWidth, y + rowHeight, Paint().apply { color = COLOR_LINE; strokeWidth = 1f })
        return y + rowHeight
    }

    /** Wraps [text] to [maxWidth] via [StaticLayout] (Android's real word-wrap engine, not a
     * hand-rolled approximation) and draws it starting at ([x], [y]). Returns the y-coordinate
     * immediately below the wrapped block. */
    private fun drawWrapped(canvas: Canvas, text: String, x: Float, y: Float, maxWidth: Float, paint: TextPaint): Float {
        val layout = StaticLayout.Builder
            .obtain(text, 0, text.length, paint, maxWidth.toInt())
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(0f, 1.15f)
            .build()
        canvas.save()
        canvas.translate(x, y)
        layout.draw(canvas)
        canvas.restore()
        return y + layout.height
    }

    private fun estimateWrappedHeight(text: String, maxWidth: Float, textSize: Float): Float {
        val paint = TextPaint().apply { this.textSize = textSize }
        val layout = StaticLayout.Builder
            .obtain(text, 0, text.length, paint, maxWidth.toInt())
            .setLineSpacing(0f, 1.15f)
            .build()
        return layout.height.toFloat()
    }

    private fun drawBitmapFit(canvas: Canvas, bitmap: Bitmap, rect: RectF, cropToFill: Boolean = false) {
        val srcAspect = bitmap.width.toFloat() / bitmap.height
        val dstAspect = rect.width() / rect.height()
        val srcRect = if (cropToFill) {
            if (srcAspect > dstAspect) {
                val cropWidth = (bitmap.height * dstAspect).toInt()
                val left = (bitmap.width - cropWidth) / 2
                android.graphics.Rect(left, 0, left + cropWidth, bitmap.height)
            } else {
                val cropHeight = (bitmap.width / dstAspect).toInt()
                val top = (bitmap.height - cropHeight) / 2
                android.graphics.Rect(0, top, bitmap.width, top + cropHeight)
            }
        } else {
            android.graphics.Rect(0, 0, bitmap.width, bitmap.height)
        }
        canvas.drawBitmap(bitmap, srcRect, rect, Paint(Paint.ANTI_ALIAS_FLAG))
    }
}
