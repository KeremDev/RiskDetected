package com.riskdetectedan.core.data.reports

import android.content.Context
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
import com.riskdetectedan.core.data.R
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FineKinneyValues
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.ByteArrayOutputStream
import javax.inject.Inject
import javax.inject.Singleton

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

data class GeneratedPdf(
    val bytes: ByteArray,
    val pageCount: Int,
)

internal enum class PdfReportSection {
    Cover,
    FindingDetails,
    MethodReference,
    RiskAssessmentTable,
}

internal fun pdfReportSectionOrder(kind: String): List<PdfReportSection> =
    if (kind == "risk_analysis") {
        listOf(PdfReportSection.MethodReference, PdfReportSection.RiskAssessmentTable)
    } else {
        listOf(PdfReportSection.Cover, PdfReportSection.FindingDetails)
    }

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
 * since Home's rebuild. Per-finding source-photo associations and field-verification state are
 * retained as visible report metadata; the primary source image remains the cover photograph.
 */
@Singleton
class PdfReportGenerator @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    // A4 at ~150dpi — sharp enough for on-screen PDF viewers/printing without an unreasonably
    // large file for a text-heavy document.
    private val PAGE_WIDTH = 1240
    private val PAGE_HEIGHT = 1754
    private val MARGIN = 60f

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

    private fun bandLabel(band: String): String = context.getString(when (band.lowercase()) {
        "critical" -> R.string.rd_pdf_band_critical
        "high" -> R.string.rd_pdf_band_high
        "medium" -> R.string.rd_pdf_band_medium
        "low" -> R.string.rd_pdf_band_low
        else -> R.string.rd_pdf_band_unknown
    })

    /** Table column budget is a fixed char count, not a wrap — cutting to [max] mid-word without
     * marking it reads like a typo (verified on the real test render: "...malzeme isti" looked
     * broken, not truncated). One glyph of the budget goes to "…" when cut. */
    private fun truncateWithEllipsis(text: String, max: Int): String =
        if (text.length <= max) text else text.take(max - 1).trimEnd() + "…"

    fun generate(input: PdfReportInput): GeneratedPdf {
        val document = PdfDocument()
        var nextPageNumber = 1

        pdfReportSectionOrder(input.kind).forEach { section ->
            nextPageNumber = when (section) {
                PdfReportSection.Cover -> drawCoverPage(document, input, nextPageNumber)
                PdfReportSection.FindingDetails -> drawFindingPages(document, input, nextPageNumber)
                PdfReportSection.MethodReference -> drawRiskMethodReferencePage(document, input, nextPageNumber)
                PdfReportSection.RiskAssessmentTable -> drawRiskAssessmentTablePages(document, input, nextPageNumber)
            }
        }

        val output = ByteArrayOutputStream()
        document.writeTo(output)
        document.close()
        return GeneratedPdf(
            bytes = output.toByteArray(),
            pageCount = (nextPageNumber - 1).coerceAtLeast(1),
        )
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
        canvas.drawText(context.getString(R.string.rd_pdf_brand), MARGIN, y, brand)
        y += 30f
        val tagline = TextPaint().apply { color = COLOR_SLATE; textSize = 18f }
        canvas.drawText(context.getString(R.string.rd_pdf_tagline), MARGIN, y, tagline)
        y += 70f

        canvas.drawLine(MARGIN, y, PAGE_WIDTH - MARGIN, y, Paint().apply { color = COLOR_LINE; strokeWidth = 2f })
        y += 60f

        // Report title
        val title = TextPaint().apply { color = COLOR_ONYX; textSize = 40f; isFakeBoldText = true }
        y = drawWrapped(canvas, context.getString(if (input.kind == "risk_analysis") R.string.rd_pdf_risk_report else R.string.rd_pdf_standard_report), MARGIN, y, PAGE_WIDTH - 2 * MARGIN, title) + 12f
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
            context.getString(R.string.rd_pdf_prepared_by) to input.preparedByName,
            input.preparedByTitle?.takeIf { it.isNotBlank() }?.let { context.getString(R.string.rd_pdf_title) to it },
            input.certificateNumber?.takeIf { it.isNotBlank() }?.let { context.getString(R.string.rd_pdf_certificate_number) to it },
            context.getString(R.string.rd_pdf_analysis_focus) to input.canvasLabel,
            context.getString(R.string.rd_pdf_method) to context.getString(if (input.method == "matrix_5x5") R.string.rd_pdf_matrix_method else R.string.rd_pdf_fine_kinney_method),
            context.getString(R.string.rd_pdf_date) to (input.createdAt?.take(10) ?: "—"),
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
        canvas.drawText(context.getString(R.string.rd_pdf_finding_count, input.findings.size), MARGIN, y, summaryPaint)
        y += 40f
        var chipX = MARGIN
        listOf("critical", "high", "medium", "low").forEach { band ->
            val count = counts[band] ?: 0
            if (count > 0) {
                val chipPaint = Paint().apply { color = bandColor(band) }
                canvas.drawRoundRect(RectF(chipX, y - 26f, chipX + 130f, y + 4f), 8f, 8f, chipPaint)
                val chipText = TextPaint().apply { color = COLOR_WHITE; textSize = 16f; isFakeBoldText = true; textAlign = Paint.Align.CENTER }
                canvas.drawText(context.getString(R.string.rd_pdf_band_count, bandLabel(band), count), chipX + 65f, y - 6f, chipText)
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
            canvas.drawText(context.getString(R.string.rd_pdf_finding_details), MARGIN, y, h)
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
            canvas.drawText(context.getString(R.string.rd_pdf_finding_title, index + 1, finding.title), MARGIN, y, titlePaint)

            val chipPaint = Paint().apply { color = bandColor(band) }
            val chipLabel = "${bandLabel(band)}${score?.let { context.getString(R.string.rd_pdf_score_suffix, it) } ?: ""}"
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
            val verificationMeta = buildList {
                if (finding.sourcePhotoIndices.isNotEmpty()) {
                    add(context.getString(R.string.rd_pdf_source_photos, finding.sourcePhotoIndices.joinToString(", ")))
                }
                if (finding.needsFieldVerification) add(context.getString(R.string.rd_pdf_field_verification_required))
                add(context.getString(R.string.rd_pdf_ai_confidence, (finding.confidence.coerceIn(0.0, 1.0) * 100).toInt()))
            }.joinToString(" · ")
            val metaPaint = TextPaint().apply { color = COLOR_SLATE; textSize = 15f }
            y = drawWrapped(canvas, verificationMeta, MARGIN, y, PAGE_WIDTH - 2 * MARGIN, metaPaint) + 10f
            finding.description?.takeIf { it.isNotBlank() }?.let {
                val descPaint = TextPaint().apply { color = COLOR_ONYX; textSize = 18f }
                y = drawWrapped(canvas, it, MARGIN, y, PAGE_WIDTH - 2 * MARGIN, descPaint) + 16f
            }
            finding.rootCauseText?.takeIf { it.isNotBlank() }?.let {
                val labelPaint = TextPaint().apply { color = COLOR_SLATE; textSize = 15f; isFakeBoldText = true }
                canvas.drawText(context.getString(R.string.rd_pdf_root_cause), MARGIN, y, labelPaint)
                y += 22f
                val bodyPaint = TextPaint().apply { color = COLOR_ONYX; textSize = 17f }
                y = drawWrapped(canvas, it, MARGIN, y, PAGE_WIDTH - 2 * MARGIN, bodyPaint) + 16f
            }
            val measures = finding.recommendedMeasures
            if (!measures.isNullOrEmpty()) {
                val labelPaint = TextPaint().apply { color = COLOR_SLATE; textSize = 15f; isFakeBoldText = true }
                canvas.drawText(context.getString(R.string.rd_pdf_measures), MARGIN, y, labelPaint)
                y += 22f
                val bodyPaint = TextPaint().apply { color = COLOR_ONYX; textSize = 17f }
                measures.forEach { measure ->
                    val kindLabel = context.getString(if (measure.kind == "preventive") R.string.rd_pdf_preventive else R.string.rd_pdf_corrective)
                    // iOS intentionally ignores the model-provided title for the two known
                    // measure kinds and renders the canonical kind label once. The AI commonly
                    // returns that same label as `title` ("Düzeltici Önlem" / "Önleyici
                    // Kontrol"), so concatenating both produced duplicated report copy.
                    y = drawWrapped(canvas, context.getString(R.string.rd_pdf_measure_row, kindLabel, measure.text), MARGIN, y, PAGE_WIDTH - 2 * MARGIN, bodyPaint) + 8f
                }
                y += 8f
            } else {
                finding.recommendedAction?.takeIf { it.isNotBlank() }?.let {
                    val labelPaint = TextPaint().apply { color = COLOR_SLATE; textSize = 15f; isFakeBoldText = true }
                    canvas.drawText(context.getString(R.string.rd_pdf_recommended_action), MARGIN, y, labelPaint)
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

    /** First page of the iOS risk-analysis contract: selected method and its scoring reference. */
    private fun drawRiskMethodReferencePage(document: PdfDocument, input: PdfReportInput, startPage: Int): Int {
        var pageNumber = startPage
        val page = newPage(document, pageNumber)
        val canvas = page.canvas
        var y = MARGIN

        val isMatrix = input.method == "matrix_5x5"
        val title = TextPaint().apply { color = COLOR_ONYX; textSize = 30f; isFakeBoldText = true }
        canvas.drawText(
            context.getString(if (isMatrix) R.string.rd_pdf_matrix_reference else R.string.rd_pdf_fine_kinney_reference),
            MARGIN,
            y,
            title,
        )
        y += 60f

        val metaPaint = TextPaint().apply { color = COLOR_SLATE; textSize = 18f }
        val company = input.companyName?.takeIf { it.isNotBlank() } ?: "—"
        y = drawWrapped(
            canvas,
            context.getString(R.string.rd_pdf_reference_metadata, input.title, company, input.preparedByName),
            MARGIN,
            y,
            PAGE_WIDTH - 2 * MARGIN,
            metaPaint,
        ) + 50f

        val bodyPaint = TextPaint().apply { color = COLOR_ONYX; textSize = 20f }
        val legendText = if (isMatrix) {
            context.getString(R.string.rd_pdf_matrix_legend)
        } else {
            val p = FineKinneyValues.PROBABILITY.joinToString(", ")
            val f = FineKinneyValues.FREQUENCY.joinToString(", ")
            val s = FineKinneyValues.SEVERITY.joinToString(", ")
            context.getString(R.string.rd_pdf_fine_kinney_legend, p, f, s)
        }
        drawWrapped(canvas, legendText, MARGIN, y, PAGE_WIDTH - 2 * MARGIN, bodyPaint)

        drawFooter(canvas, pageNumber)
        document.finishPage(page)
        return pageNumber + 1
    }

    /** Remaining pages of the iOS risk-analysis contract: assessment rows and audit context. */
    private fun drawRiskAssessmentTablePages(document: PdfDocument, input: PdfReportInput, startPage: Int): Int {
        var pageNumber = startPage
        var page = newPage(document, pageNumber)
        var canvas = page.canvas
        var y = MARGIN

        val header = TextPaint().apply { color = COLOR_ONYX; textSize = 26f; isFakeBoldText = true }
        canvas.drawText(context.getString(R.string.rd_pdf_risk_table), MARGIN, y, header)
        y += 50f

        val isMatrix = input.method == "matrix_5x5"
        val headers = if (isMatrix) {
            listOf(
                context.getString(R.string.rd_pdf_column_number),
                context.getString(R.string.rd_pdf_column_finding),
                context.getString(R.string.rd_pdf_column_probability),
                context.getString(R.string.rd_pdf_column_severity),
                context.getString(R.string.rd_pdf_column_score),
                context.getString(R.string.rd_pdf_column_level),
                context.getString(R.string.rd_pdf_column_controls),
                context.getString(R.string.rd_pdf_column_references),
            )
        } else {
            listOf(
                context.getString(R.string.rd_pdf_column_number),
                context.getString(R.string.rd_pdf_column_finding),
                "O",
                "F",
                "Ş",
                context.getString(R.string.rd_pdf_column_score),
                context.getString(R.string.rd_pdf_column_level),
                context.getString(R.string.rd_pdf_column_controls),
                context.getString(R.string.rd_pdf_column_references),
            )
        }
        val widths = if (isMatrix) {
            listOf(0.04f, 0.24f, 0.07f, 0.07f, 0.08f, 0.10f, 0.25f, 0.15f)
        } else {
            listOf(0.04f, 0.20f, 0.055f, 0.055f, 0.055f, 0.075f, 0.10f, 0.265f, 0.155f)
        }
        val tableWidth = PAGE_WIDTH - 2 * MARGIN
        y = drawTableRow(canvas, MARGIN, y, tableWidth, widths, headers, isHeader = true)

        input.findings.forEachIndexed { index, finding ->
            val findingText = listOfNotNull(finding.title, finding.description?.takeIf { it.isNotBlank() })
                .joinToString("\n")
            val controls = buildList {
                finding.recommendedMeasures.orEmpty().filter { it.text.isNotBlank() }.forEach { add(it.text) }
                if (isEmpty()) finding.recommendedAction?.takeIf { it.isNotBlank() }?.let(::add)
                finding.rootCauseText?.takeIf { it.isNotBlank() }?.let {
                    add(context.getString(R.string.rd_pdf_root_cause_row, it))
                }
            }.joinToString("\n")
            val references = finding.referencesText?.takeIf { it.isNotBlank() } ?: "—"
            val band = if (isMatrix) finding.m5Band else finding.fkBand
            val score = if (isMatrix) finding.m5Score?.toString() else finding.fkScore?.let { "%.1f".format(it) }
            val values = if (isMatrix) {
                listOf(
                    "${index + 1}", findingText,
                    finding.m5Probability?.toString() ?: "—",
                    finding.m5Severity?.toString() ?: "—",
                    score ?: "—", bandLabel(band), controls, references,
                )
            } else {
                listOf(
                    "${index + 1}", findingText,
                    finding.fkProbability?.let { "%.1f".format(it) } ?: "—",
                    finding.fkFrequency?.let { "%.1f".format(it) } ?: "—",
                    finding.fkSeverity?.let { "%.1f".format(it) } ?: "—",
                    score ?: "—", bandLabel(band), controls, references,
                )
            }
            val estimatedRowHeight = estimateTableRowHeight(
                totalWidth = tableWidth,
                weights = widths,
                values = values,
            )
            if (y + estimatedRowHeight > PAGE_HEIGHT - MARGIN - 30f) {
                drawFooter(canvas, pageNumber)
                document.finishPage(page)
                pageNumber += 1
                page = newPage(document, pageNumber)
                canvas = page.canvas
                y = MARGIN
                y = drawTableRow(canvas, MARGIN, y, tableWidth, widths, headers, isHeader = true)
            }
            y = drawTableRow(canvas, MARGIN, y, tableWidth, widths, values, isHeader = false, bandForRow = band)
        }

        drawFooter(canvas, pageNumber)
        document.finishPage(page)
        return pageNumber + 1
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
        val rowHeight = if (isHeader) 48f else estimateTableRowHeight(totalWidth, weights, values)
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
            val cellLayout = StaticLayout.Builder
                .obtain(value, 0, value.length, paint, (cellWidth - 16f).coerceAtLeast(1f).toInt())
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setMaxLines(if (isHeader) 2 else 8)
                .setEllipsize(android.text.TextUtils.TruncateAt.END)
                .build()
            canvas.save()
            canvas.translate(cellX + 8f, y + 8f)
            cellLayout.draw(canvas)
            canvas.restore()
            canvas.drawLine(cellX + cellWidth, y, cellX + cellWidth, y + rowHeight, Paint().apply { color = COLOR_LINE; strokeWidth = 1f })
            cellX += cellWidth
        }
        canvas.drawLine(x, y + rowHeight, x + totalWidth, y + rowHeight, Paint().apply { color = COLOR_LINE; strokeWidth = 1f })
        return y + rowHeight
    }

    private fun estimateTableRowHeight(totalWidth: Float, weights: List<Float>, values: List<String>): Float {
        val paint = TextPaint().apply { textSize = 14f }
        val tallest = values.mapIndexed { index, value ->
            val cellWidth = (totalWidth * weights.getOrElse(index) { weights.last() } - 16f)
                .coerceAtLeast(1f)
                .toInt()
            StaticLayout.Builder
                .obtain(value, 0, value.length, paint, cellWidth)
                .setMaxLines(8)
                .setEllipsize(android.text.TextUtils.TruncateAt.END)
                .build()
                .height
        }.maxOrNull() ?: 0
        return (tallest + 18f).coerceIn(48f, 260f)
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
