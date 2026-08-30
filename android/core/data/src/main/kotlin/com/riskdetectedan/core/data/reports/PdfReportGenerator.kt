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
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.ByteArrayOutputStream
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/** Plain-value mirror of `PDFReportService.ReportInput`. Call sites resolve platform image and
 * backend objects into bytes/strings before rendering so the iOS and Android layout contracts can
 * remain equivalent while this generator stays deterministic and testable. */
data class PdfReportInput(
    val analysisId: String = "",
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
    val coverPhotoBytesList: List<ByteArray> = emptyList(),
    val analysisSummary: String? = null,
    val analysisSectorLabel: String? = null,
    val languageCode: String = "tr",
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
        listOf(
            PdfReportSection.MethodReference,
            PdfReportSection.RiskAssessmentTable,
        )
    } else {
        listOf(PdfReportSection.Cover, PdfReportSection.FindingDetails)
    }

/** Android counterpart to the current `PDFReportService.swift` contract: A4 landscape, identical
 * standard-report page order, identical risk-report page order, matching method references,
 * assessment columns, band colours, photo collage, audit metadata and pagination rules. */
@Singleton
class PdfReportGenerator @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private companion object {
        const val TABLE_BODY_MAX_LINES = 18
        const val TABLE_TEXT_SIZE = 7f
    }

    // Same A4 landscape coordinate system as PDFReportService.swift (72 dpi / PDF points).
    // Text and vector shapes stay sharp in PDF; source photos retain their own raster detail.
    private val PAGE_WIDTH = 842
    private val PAGE_HEIGHT = 595
    private val MARGIN = 42f

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
        val nextPageNumber = if (input.kind == "risk_analysis") {
            val pages = paginateRiskAssessmentRows(input)
            val totalPages = 1 + pages.size
            drawRiskMethodReferencePage(document, input, startPage = 1, totalPages = totalPages)
            drawRiskAssessmentTablePages(document, input, startPage = 2, pages = pages, totalPages = totalPages)
        } else {
            val totalPages = standardTotalPageCount(input)
            drawCoverPage(document, input, startPage = 1, totalPages = totalPages)
            drawFindingPages(document, input, startPage = 2, totalPages = totalPages)
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

    private fun drawCoverPage(document: PdfDocument, input: PdfReportInput, startPage: Int, totalPages: Int): Int {
        val page = newPage(document, startPage)
        val canvas = page.canvas
        drawStandardChrome(canvas, input, context.getString(R.string.rd_pdf_standard_report), startPage, totalPages)

        drawTextRect(canvas, input.title, RectF(42f, 92f, 482f, 128f), 24f, COLOR_ONYX, bold = true)
        val meta = buildList {
            add(input.createdAt?.take(10) ?: "—")
            input.analysisSectorLabel?.takeIf(String::isNotBlank)?.let { add("${copy(input, "Analiz kapsamı", "Analysis scope")}: $it") }
            add("${copy(input, "Analiz odağı", "Analysis focus")}: ${input.canvasLabel}")
            add(context.getString(R.string.rd_pdf_finding_count, input.findings.size))
        }.joinToString(" · ")
        drawTextRect(canvas, meta, RectF(42f, 130f, 562f, 156f), 12f, COLOR_SLATE, bold = true)
        drawSummaryCards(canvas, input, 42f, 180f)

        val photos = (input.coverPhotoBytesList.ifEmpty { listOfNotNull(input.coverPhotoBytes) }).take(5)
            .mapNotNull { bytes -> runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull() }
        if (photos.isNotEmpty()) drawCoverImages(canvas, photos, RectF(548f, 92f, 800f, 270f))
        else drawPlaceholder(canvas, RectF(548f, 92f, 800f, 270f), copy(input, "Fotoğraf", "Photo"))

        drawRoundedRect(canvas, RectF(42f, 340f, 800f, 426f), 10f, Color.WHITE, COLOR_LINE, 1f)
        drawTextRect(canvas, copy(input, "Uygunsuzluk Özeti", "Finding Summary"), RectF(56f, 351f, 280f, 371f), 11f, COLOR_SLATE, bold = true)
        val summary = input.analysisSummary?.trim().takeUnless { it.isNullOrEmpty() }
            ?: copy(
                input,
                "${input.findings.size} bulgu tespit edildi. Bulgular ${methodName(input)} metoduna göre önceliklendirilmiştir.",
                "${input.findings.size} findings were identified and prioritised using the ${methodName(input)} method.",
            )
        drawTextRect(canvas, summary, RectF(56f, 375f, 786f, 415f), 10f, COLOR_ONYX)

        val credential = listOfNotNull(
            input.preparedByTitle?.takeIf(String::isNotBlank),
            input.certificateNumber?.takeIf(String::isNotBlank)?.let { "${copy(input, "Belge no", "Certificate no.")}: $it" },
        ).joinToString(" · ")
        val company = listOfNotNull(
            input.companyName?.takeIf(String::isNotBlank)?.let { "${copy(input, "Firma", "Company")}: $it" },
            input.companyAddress?.takeIf(String::isNotBlank),
        ).joinToString(" · ")
        val footer = listOf(
            "${copy(input, "Hazırlayan", "Prepared by")}: ${input.preparedByName}",
            credential.ifBlank { copy(input, "İSG Uzmanı", "Safety professional") },
            company,
            "${copy(input, "Doküman No", "Document no.")}: #${documentNumber(input)}",
        ).filter(String::isNotBlank).joinToString(" · ")
        drawTextRect(canvas, footer, RectF(42f, 448f, 800f, 470f), 9.5f, COLOR_SLATE)
        drawTextRect(canvas, reportDisclaimer(input), RectF(42f, 472f, 800f, 491f), 7.2f, COLOR_SLATE, align = Paint.Align.CENTER)
        drawMethodLegend(canvas, input, RectF(42f, 496f, 800f, 544f))

        document.finishPage(page)
        return startPage + 1
    }

    private fun drawFindingPages(document: PdfDocument, input: PdfReportInput, startPage: Int, totalPages: Int): Int {
        if (input.findings.isEmpty()) return startPage
        var pageNumber = startPage
        var page = newPage(document, pageNumber)
        var canvas = page.canvas
        var y = 122f

        fun header() {
            drawStandardChrome(canvas, input, context.getString(R.string.rd_pdf_finding_details), pageNumber, totalPages)
            drawStandardTableHeader(canvas, input)
            y = 122f
        }
        header()

        input.findings.forEachIndexed { index, finding ->
            val rowHeight = standardFindingRowHeight(finding, input)
            if (y > 122f && y + rowHeight > 553f) {
                document.finishPage(page)
                pageNumber += 1
                page = newPage(document, pageNumber)
                canvas = page.canvas
                header()
            }
            drawStandardFindingRow(canvas, input, finding, index + 1, y, rowHeight)
            y += rowHeight + 8f
        }

        document.finishPage(page)
        return pageNumber + 1
    }

    /** First page of the iOS risk-analysis contract: selected method and its scoring reference. */
    private fun drawRiskMethodReferencePage(document: PdfDocument, input: PdfReportInput, startPage: Int, totalPages: Int): Int {
        val page = newPage(document, startPage)
        val canvas = page.canvas
        val isMatrix = input.method == "matrix_5x5"
        val title = if (isMatrix) {
            copy(input, "5x5 L-TİPİ MATRİS REFERANS TABLOSU", "5×5 L-TYPE MATRIX REFERENCE TABLE")
        } else {
            copy(input, "FINE-KINNEY METODU REFERANS TABLOSU", "FINE-KINNEY METHOD REFERENCE TABLE")
        }
        drawRiskChrome(canvas, input, title, startPage, totalPages)
        if (isMatrix) drawMatrixReference(canvas, input, 32f, 82f) else drawFineKinneyReference(canvas, input, 32f, 82f)
        drawRiskInfoStrip(canvas, input, RectF(32f, 520f, 810f, 562f))
        document.finishPage(page)
        return startPage + 1
    }

    /** Remaining pages of the iOS risk-analysis contract: assessment rows and audit context. */
    private fun drawRiskAssessmentTablePages(
        document: PdfDocument,
        input: PdfReportInput,
        startPage: Int,
        pages: List<List<PdfAssessmentRow>>,
        totalPages: Int,
    ): Int {
        if (pages.isEmpty()) return startPage
        var pageNumber = startPage
        pages.forEach { rows ->
            val page = newPage(document, pageNumber)
            val canvas = page.canvas
            val methodTitle = if (input.method == "matrix_5x5") {
                copy(input, "TEHLİKE VE RİSK DEĞERLENDİRME FORMU (5x5 L-TİPİ)", "HAZARD AND RISK ASSESSMENT FORM (5×5 L-TYPE)")
            } else {
                copy(input, "TEHLİKE VE RİSK DEĞERLENDİRME FORMU (FINE-KINNEY)", "HAZARD AND RISK ASSESSMENT FORM (FINE-KINNEY)")
            }
            drawRiskChrome(canvas, input, methodTitle, pageNumber, totalPages)
            drawRiskAssessmentTable(canvas, input, rows)
            document.finishPage(page)
            pageNumber += 1
        }
        return pageNumber
    }

    private data class PdfAssessmentRow(val ordinal: Int, val finding: Finding, val height: Float)

    private fun copy(input: PdfReportInput, tr: String, en: String): String =
        if (input.languageCode.lowercase().startsWith("en")) en else tr

    private fun methodName(input: PdfReportInput): String =
        if (input.method == "matrix_5x5") context.getString(R.string.rd_pdf_matrix_method)
        else context.getString(R.string.rd_pdf_fine_kinney_method)

    private fun documentNumber(input: PdfReportInput): String = input.analysisId
        .replace("-", "")
        .take(8)
        .uppercase(Locale.US)
        .ifBlank { "REPORT" }

    private fun drawStandardChrome(
        canvas: Canvas,
        input: PdfReportInput,
        title: String,
        page: Int,
        totalPages: Int,
    ) {
        canvas.drawColor(Color.parseColor("#FBFCFA"))
        drawReportLogo(canvas, input, RectF(42f, 26f, 162f, 60f))
        if (input.companyLogoBytes == null && !input.companyName.isNullOrBlank()) {
            drawTextRect(canvas, input.companyName, RectF(172f, 32f, 282f, 52f), 10f, COLOR_SLATE, bold = true)
        }
        drawTextRect(canvas, title, RectF(220f, 31f, 580f, 54f), 13f, COLOR_SLATE, bold = true, align = Paint.Align.CENTER)
        drawTextRect(
            canvas,
            "${copy(input, "Sayfa", "Page")} $page/$totalPages",
            RectF(660f, 31f, 800f, 54f),
            10f,
            COLOR_SLATE,
            align = Paint.Align.RIGHT,
        )
        canvas.drawRect(RectF(42f, 70f, 800f, 72f), Paint().apply { color = COLOR_ONYX })
    }

    private fun drawRiskChrome(
        canvas: Canvas,
        input: PdfReportInput,
        title: String,
        page: Int,
        totalPages: Int,
    ) {
        canvas.drawColor(Color.WHITE)
        drawRoundedRect(canvas, RectF(32f, 24f, 810f, 66f), 0f, Color.WHITE, COLOR_ONYX, 1.4f)
        drawTextRect(canvas, title, RectF(44f, 35f, 798f, 55f), 13f, COLOR_ONYX, bold = true, align = Paint.Align.CENTER)
        drawReportLogo(canvas, input, RectF(40f, 29f, 144f, 57f))
        drawTextRect(
            canvas,
            "${copy(input, "Sayfa", "Page")} $page/$totalPages",
            RectF(716f, 37f, 806f, 53f),
            8f,
            COLOR_SLATE,
            align = Paint.Align.RIGHT,
        )
    }

    private fun drawReportLogo(canvas: Canvas, input: PdfReportInput, rect: RectF) {
        val logo = input.companyLogoBytes?.let { runCatching { BitmapFactory.decodeByteArray(it, 0, it.size) }.getOrNull() }
        if (logo != null) drawBitmapFit(canvas, logo, rect) else {
            drawTextRect(canvas, context.getString(R.string.rd_pdf_brand), rect, 20f, COLOR_ONYX, bold = true)
        }
    }

    private fun drawSummaryCards(canvas: Canvas, input: PdfReportInput, x: Float, y: Float) {
        val width = 110f
        val gap = 10f
        listOf("critical", "high", "medium", "low").forEachIndexed { index, band ->
            val count = input.findings.count { finding ->
                val raw = if (input.method == "matrix_5x5") finding.m5Band else finding.fkBand
                raw.equals(band, ignoreCase = true)
            }
            val rect = RectF(x + index * (width + gap), y, x + index * (width + gap) + width, y + 72f)
            drawRoundedRect(canvas, rect, 12f, tintColor(bandColor(band), .12f), Color.TRANSPARENT, 0f)
            drawTextRect(canvas, count.toString(), RectF(rect.left + 12f, rect.top + 8f, rect.right - 8f, rect.top + 37f), 24f, bandColor(band), bold = true)
            drawTextRect(canvas, bandLabel(band).uppercase(), RectF(rect.left + 12f, rect.top + 42f, rect.right - 8f, rect.bottom - 7f), 10f, bandColor(band), bold = true)
        }
    }

    private fun drawCoverImages(canvas: Canvas, images: List<Bitmap>, rect: RectF) {
        if (images.size == 1) {
            drawBitmapFit(canvas, images.first(), rect, cropToFill = true)
            return
        }
        val visible = images.take(5)
        val gap = 6f
        val columns = if (visible.size <= 2) visible.size else 3
        val rows = kotlin.math.ceil(visible.size.toDouble() / columns).toInt()
        val cellWidth = (rect.width() - (columns - 1) * gap) / columns
        val cellHeight = (rect.height() - (rows - 1) * gap) / rows
        visible.forEachIndexed { index, bitmap ->
            val column = index % columns
            val row = index / columns
            val cell = RectF(
                rect.left + column * (cellWidth + gap),
                rect.top + row * (cellHeight + gap),
                rect.left + column * (cellWidth + gap) + cellWidth,
                rect.top + row * (cellHeight + gap) + cellHeight,
            )
            drawBitmapFit(canvas, bitmap, cell, cropToFill = true)
            drawTextRect(canvas, (index + 1).toString(), RectF(cell.left + 6f, cell.top + 4f, cell.left + 28f, cell.top + 20f), 9f, Color.WHITE, bold = true, align = Paint.Align.CENTER)
        }
    }

    private fun drawPlaceholder(canvas: Canvas, rect: RectF, label: String) {
        drawRoundedRect(canvas, rect, 14f, Color.parseColor("#F1F3F2"), Color.TRANSPARENT, 0f)
        drawTextRect(canvas, label.uppercase(), rect, 10f, COLOR_SLATE, bold = true, align = Paint.Align.CENTER)
    }

    private fun drawMethodLegend(canvas: Canvas, input: PdfReportInput, rect: RectF) {
        drawRoundedRect(canvas, rect, 10f, Color.WHITE, COLOR_LINE, 1f)
        val scored = input.findings.filter(Finding::isScored)
        val values = scored.mapNotNull { if (input.method == "matrix_5x5") it.m5Score?.toDouble() else it.fkScore }
        drawTextRect(canvas, copy(input, "Metodoloji", "Methodology"), RectF(rect.left + 14f, rect.top + 6f, rect.left + 134f, rect.top + 23f), 11f, COLOR_SLATE, bold = true)
        drawTextRect(canvas, "${methodName(input)} · R = ${if (input.method == "matrix_5x5") "O × Ş" else "O × F × Ş"}", RectF(rect.left + 14f, rect.top + 24f, rect.left + 300f, rect.bottom - 5f), 11f, COLOR_ONYX)
        drawTextRect(canvas, "${copy(input, "En yüksek", "Highest")}: ${scoreText(values.maxOrNull() ?: 0.0)}", RectF(rect.left + 340f, rect.top + 14f, rect.left + 500f, rect.bottom - 4f), 12f, COLOR_ONYX, bold = true)
        drawTextRect(canvas, "${copy(input, "Toplam", "Total")}: ${scoreText(values.sum())}", RectF(rect.left + 520f, rect.top + 14f, rect.right - 14f, rect.bottom - 4f), 12f, COLOR_ONYX, bold = true)
    }

    private fun reportDisclaimer(input: PdfReportInput): String = copy(
        input,
        "Bu rapor saha güvenliği değerlendirmesini destekler; yetkili kişi değerlendirmesinin yerine geçmez ve mevzuata uygunluk kararı oluşturmaz.",
        "This report supports a safety review; it does not replace assessment by a competent person or determine legal compliance.",
    )

    private fun standardTotalPageCount(input: PdfReportInput): Int {
        if (input.findings.isEmpty()) return 1
        var pages = 2
        var y = 122f
        input.findings.forEach { finding ->
            val height = standardFindingRowHeight(finding, input)
            if (y > 122f && y + height > 553f) {
                pages += 1
                y = 122f
            }
            y += height + 8f
        }
        return pages
    }

    private fun drawStandardTableHeader(canvas: Canvas, input: PdfReportInput) {
        drawTextRect(canvas, "#", RectF(42f, 91f, 70f, 111f), 9f, COLOR_SLATE, bold = true)
        drawTextRect(canvas, copy(input, "RİSK / KANIT", "RISK / EVIDENCE"), RectF(78f, 91f, 378f, 111f), 9f, COLOR_SLATE, bold = true)
        drawTextRect(canvas, copy(input, "SKOR", "SCORE"), RectF(414f, 91f, 484f, 111f), 9f, COLOR_SLATE, bold = true)
        drawTextRect(canvas, copy(input, "ÖNLEM / KONTROL TEDBİRLERİ", "ACTION / CONTROL MEASURES"), RectF(504f, 91f, 800f, 111f), 8.2f, COLOR_SLATE, bold = true)
        canvas.drawRect(RectF(42f, 114f, 800f, 115f), Paint().apply { color = COLOR_LINE })
    }

    private fun standardFindingRowHeight(finding: Finding, input: PdfReportInput): Float {
        val titleHeight = measuredHeight(finding.title, 302f, 12f, bold = true).coerceAtLeast(18f)
        val descriptionHeight = measuredHeight(finding.description.orEmpty(), 302f, 9f)
        val actionHeight = measuredHeight(actionText(finding, input), 296f, 10f)
        return maxOf(82f, 10f + titleHeight + 7f + descriptionHeight + 12f, 24f + actionHeight).coerceAtMost(431f)
    }

    private fun drawStandardFindingRow(
        canvas: Canvas,
        input: PdfReportInput,
        finding: Finding,
        ordinal: Int,
        y: Float,
        height: Float,
    ) {
        drawRoundedRect(canvas, RectF(42f, y, 800f, y + height), 10f, Color.WHITE, COLOR_LINE, 1f)
        drawTextRect(canvas, ordinal.toString(), RectF(54f, y + 10f, 78f, y + 32f), 12f, COLOR_ONYX, bold = true)
        val titleHeight = measuredHeight(finding.title, 302f, 12f, bold = true).coerceAtLeast(18f)
        drawTextRect(canvas, finding.title, RectF(90f, y + 9f, 392f, y + 9f + titleHeight), 12f, COLOR_ONYX, bold = true)
        drawTextRect(canvas, finding.description.orEmpty(), RectF(90f, y + 16f + titleHeight, 392f, y + height - 12f), 9f, COLOR_SLATE)
        if (finding.isScored) {
            val band = if (input.method == "matrix_5x5") finding.m5Band else finding.fkBand
            val score = if (input.method == "matrix_5x5") finding.m5Score?.toDouble() else finding.fkScore
            drawRoundedRect(canvas, RectF(412f, y + 14f, 482f, y + 48f), 8f, bandColor(band), Color.TRANSPARENT, 0f)
            drawTextRect(canvas, scoreText(score ?: 0.0), RectF(412f, y + 19f, 482f, y + 42f), 16f, Color.WHITE, bold = true, align = Paint.Align.CENTER)
            drawTextRect(canvas, bandLabel(band), RectF(402f, y + 52f, 492f, y + 69f), 8f, bandColor(band), bold = true, align = Paint.Align.CENTER)
        } else {
            drawTextRect(canvas, copy(input, "Saha teyidi", "Field verification"), RectF(402f, y + 22f, 492f, y + 48f), 9f, COLOR_SLATE, bold = true, align = Paint.Align.CENTER)
        }
        drawTextRect(canvas, actionText(finding, input), RectF(504f, y + 12f, 788f, y + height - 12f), 10f, COLOR_ONYX)
    }

    private fun actionText(finding: Finding, input: PdfReportInput): String {
        val measures = finding.recommendedMeasures.orEmpty().filter { it.text.isNotBlank() }
        val measureText = if (measures.isEmpty()) finding.recommendedAction.orEmpty().trim() else measures.joinToString("\n") { measure ->
            val label = when (measure.kind.lowercase()) {
                "preventive" -> copy(input, "Önleyici Kontrol", "Preventive control")
                "corrective" -> copy(input, "Düzeltici Önlem", "Corrective action")
                else -> measure.title?.takeIf(String::isNotBlank) ?: copy(input, "Kontrol Tedbiri", "Control measure")
            }
            "$label: ${measure.text}"
        }
        val root = finding.rootCauseText.orEmpty().trim()
        return listOf(measureText, root.takeIf(String::isNotBlank)?.let { "${copy(input, "Kök neden", "Root cause")}: $it" }.orEmpty())
            .filter(String::isNotBlank).joinToString("\n\n")
    }

    private fun drawRiskInfoStrip(canvas: Canvas, input: PdfReportInput, rect: RectF) {
        drawRoundedRect(canvas, rect, 0f, Color.parseColor("#F1F3F2"), COLOR_ONYX, 1f)
        val unspecified = copy(input, "Belirtilmedi", "Not provided")
        val left = buildString {
            input.analysisSectorLabel?.takeIf(String::isNotBlank)?.let { append("${copy(input, "Analiz kapsamı", "Analysis scope")}: $it\n") }
            append("${copy(input, "Analiz", "Analysis")}: ${input.title}\n")
            append("${copy(input, "Firma", "Company")}: ${input.companyName ?: unspecified}\n")
            append("${copy(input, "Firma bilgisi", "Company details")}: ${input.companyAddress ?: unspecified}")
        }
        drawTextRect(canvas, left, RectF(rect.left + 10f, rect.top + 4f, rect.left + 270f, rect.bottom - 2f), 7.4f, COLOR_SLATE, bold = true)
        val middle = "${copy(input, "Hazırlayan", "Prepared by")}: ${input.preparedByName}\n${copy(input, "Ünvan", "Title")}: ${input.preparedByTitle ?: unspecified}\n${copy(input, "Belge No", "Certificate no.")}: ${input.certificateNumber ?: unspecified}"
        drawTextRect(canvas, middle, RectF(rect.left + 294f, rect.top + 4f, rect.left + 514f, rect.bottom - 2f), 7.4f, COLOR_SLATE, bold = true)
        val right = "${copy(input, "Tarih", "Date")}: ${input.createdAt?.take(10) ?: unspecified}\n${copy(input, "Doküman No", "Document no.")}: #${documentNumber(input)}"
        drawTextRect(canvas, right, RectF(rect.left + 548f, rect.top + 8f, rect.right - 10f, rect.bottom - 4f), 7.4f, COLOR_ONYX, bold = true, align = Paint.Align.RIGHT)
    }

    private fun riskTableWidths(input: PdfReportInput): List<Float> {
        val includesRegulatory = input.findings.any { !it.referencesText.isNullOrBlank() }
        return if (input.method == "matrix_5x5") {
            if (includesRegulatory) listOf(22f, 58f, 132f, 66f, 26f, 26f, 38f, 56f, 170f, 130f, 54f)
            else listOf(22f, 58f, 132f, 66f, 26f, 26f, 38f, 56f, 300f, 54f)
        } else {
            if (includesRegulatory) listOf(22f, 54f, 130f, 62f, 24f, 24f, 24f, 38f, 58f, 168f, 140f, 58f)
            else listOf(22f, 54f, 130f, 62f, 24f, 24f, 24f, 38f, 58f, 308f, 58f)
        }
    }

    private fun riskHeaders(input: PdfReportInput): List<String> {
        val regulatory = input.findings.any { !it.referencesText.isNullOrBlank() }
        val en = input.languageCode.startsWith("en")
        return if (input.method == "matrix_5x5") {
            buildList {
                addAll(if (en) listOf("No.", "Activity\narea", "Hazardous condition / behaviour", "Risk", "P", "S", "R", "Risk\nband", "Control measures") else listOf("No", "Faaliyet\nAlanı", "Tehlikeli durum / davranış", "Risk", "O", "Ş", "R", "Risk\nderecesi", "Önlem / kontrol tedbirleri"))
                if (regulatory) add(if (en) "Regulation" else "Mevzuat")
                add(if (en) "Due" else "Termin")
            }
        } else buildList {
            addAll(if (en) listOf("No.", "Activity\narea", "Hazardous condition / behaviour", "Risk", "P", "F", "S", "R", "Risk\nband", "Control measures") else listOf("No", "Faaliyet\nAlanı", "Tehlikeli durum / davranış", "Risk", "O", "F", "Ş", "R", "Risk\nderecesi", "Önlem / kontrol tedbirleri"))
            if (regulatory) add(if (en) "Regulation" else "Mevzuat")
            add(if (en) "Due" else "Termin")
        }
    }

    private fun riskValues(input: PdfReportInput, finding: Finding, ordinal: Int): List<String> {
        val regulatory = input.findings.any { !it.referencesText.isNullOrBlank() }
        val values = mutableListOf(
            ordinal.toString(),
            input.canvasLabel,
            "${finding.title}\n${finding.description.orEmpty()}",
            finding.category.orEmpty(),
        )
        val band: String
        if (input.method == "matrix_5x5") {
            values += finding.m5Probability?.toString() ?: "—"
            values += finding.m5Severity?.toString() ?: "—"
            values += finding.m5Score?.toString() ?: "—"
            band = finding.m5Band
        } else {
            values += scoreText(finding.fkProbability ?: 0.0)
            values += scoreText(finding.fkFrequency ?: 0.0)
            values += scoreText(finding.fkSeverity ?: 0.0)
            values += scoreText(finding.fkScore ?: 0.0)
            band = finding.fkBand
        }
        values += bandLabel(band)
        values += actionText(finding, input)
        if (regulatory) values += finding.referencesText.orEmpty()
        values += suggestedDue(input, band)
        return values
    }

    private fun suggestedDue(input: PdfReportInput, band: String): String = when (band.lowercase()) {
        "critical" -> copy(input, "Hemen / 1 hafta", "Immediate / 1 week")
        "high" -> copy(input, "1-3 ay", "1–3 months")
        "medium" -> copy(input, "6 ay", "6 months")
        else -> copy(input, "1 yıl / kontrol", "1 year / review")
    }

    private fun paginateRiskAssessmentRows(input: PdfReportInput): List<List<PdfAssessmentRow>> {
        val findings = input.findings.filter(Finding::isScored)
        if (findings.isEmpty()) return emptyList()
        val widths = riskTableWidths(input)
        val available = PAGE_HEIGHT - 82f - 44f - 32f
        val pages = mutableListOf<MutableList<PdfAssessmentRow>>()
        var current = mutableListOf<PdfAssessmentRow>()
        var used = 0f
        findings.forEachIndexed { index, finding ->
            val height = estimateAbsoluteRowHeight(widths, riskValues(input, finding, index + 1)).coerceAtMost(available)
            if (current.isNotEmpty() && used + height > available) {
                pages += current
                current = mutableListOf()
                used = 0f
            }
            current += PdfAssessmentRow(index + 1, finding, height)
            used += height
        }
        if (current.isNotEmpty()) pages += current
        return pages
    }

    private fun drawRiskAssessmentTable(canvas: Canvas, input: PdfReportInput, rows: List<PdfAssessmentRow>) {
        val widths = riskTableWidths(input)
        drawAbsoluteTableRow(canvas, 32f, 82f, widths, riskHeaders(input), 44f, header = true)
        var y = 126f
        rows.forEach { row ->
            val band = if (input.method == "matrix_5x5") row.finding.m5Band else row.finding.fkBand
            val values = riskValues(input, row.finding, row.ordinal)
            val scoreColumn = if (input.method == "matrix_5x5") 6 else 7
            val bandColumn = scoreColumn + 1
            drawAbsoluteTableRow(canvas, 32f, y, widths, values, row.height, band = band, scoreColumn = scoreColumn, bandColumn = bandColumn)
            y += row.height
        }
    }

    private fun drawAbsoluteTableRow(
        canvas: Canvas,
        x: Float,
        y: Float,
        widths: List<Float>,
        values: List<String>,
        height: Float,
        header: Boolean = false,
        band: String? = null,
        scoreColumn: Int = -1,
        bandColumn: Int = -1,
    ) {
        var left = x
        widths.forEachIndexed { index, width ->
            val emphasized = !header && (index == scoreColumn || index == bandColumn)
            val fill = when {
                header -> Color.parseColor("#345A86")
                emphasized -> bandColor(band.orEmpty())
                else -> Color.WHITE
            }
            canvas.drawRect(RectF(left, y, left + width, y + height), Paint().apply { color = fill })
            canvas.drawRect(RectF(left, y, left + width, y + height), Paint().apply { color = COLOR_ONYX; style = Paint.Style.STROKE; strokeWidth = .55f })
            drawTextRect(
                canvas,
                values.getOrElse(index) { "" },
                RectF(left + 4f, y + if (header) 8f else 6f, left + width - 4f, y + height - 5f),
                if (header) 7f else if (emphasized) 7.5f else 6.8f,
                if (header || emphasized) Color.WHITE else COLOR_ONYX,
                bold = header || emphasized || index == 0,
                align = if (index <= 1 || emphasized) Paint.Align.CENTER else Paint.Align.LEFT,
                maxLines = if (header) 3 else TABLE_BODY_MAX_LINES,
            )
            left += width
        }
    }

    private fun estimateAbsoluteRowHeight(widths: List<Float>, values: List<String>): Float = values.mapIndexed { index, value ->
        measuredHeight(value, (widths.getOrElse(index) { widths.last() } - 8f).coerceAtLeast(1f), 6.8f)
    }.maxOrNull()?.plus(14f)?.coerceAtLeast(34f) ?: 34f

    private fun drawFineKinneyReference(canvas: Canvas, input: PdfReportInput, x: Float, y: Float) {
        val en = input.languageCode.startsWith("en")
        val probability = if (en) listOf(
            listOf("10", "Expected; near certain"), listOf("6", "High; quite possible"), listOf("3", "Possible"), listOf("1", "Possible but unlikely"), listOf("0.5", "Unexpected but possible"), listOf("0.2", "Not expected"),
        ) else listOf(
            listOf("10", "Beklenir, kesin"), listOf("6", "Yüksek, oldukça mümkün"), listOf("3", "Olası"), listOf("1", "Mümkün fakat düşük"), listOf("0.5", "Beklenmez fakat mümkün"), listOf("0.2", "Beklenmez"),
        )
        val frequency = if (en) listOf(
            listOf("10", "Almost continuous / several times per hour"), listOf("6", "Frequent / once or several times per day"), listOf("3", "Occasional / several times per week"), listOf("2", "Infrequent / several times per month"), listOf("1", "Rare / several times per year"), listOf("0.5", "Very rare / once per year or less"),
        ) else listOf(
            listOf("10", "Hemen hemen sürekli / saatte birkaç defa"), listOf("6", "Sık / günde bir veya birkaç defa"), listOf("3", "Ara sıra / haftada birkaç defa"), listOf("2", "Sık değil / ayda birkaç defa"), listOf("1", "Seyrek / yılda birkaç defa"), listOf("0.5", "Çok seyrek / yılda bir veya daha az"),
        )
        val severity = if (en) listOf(
            listOf("100", "Multiple fatalities / environmental disaster"), listOf("40", "Fatality / serious environmental harm"), listOf("15", "Permanent injury or work loss"), listOf("7", "Significant injury / external first aid"), listOf("3", "Minor injury / on-site first aid"), listOf("1", "Near miss / no environmental harm"),
        ) else listOf(
            listOf("100", "Birden fazla ölümlü kaza / çevresel felaket"), listOf("40", "Ölümlü kaza / ciddi çevresel zarar"), listOf("15", "Kalıcı hasar veya iş kaybı"), listOf("7", "Önemli yaralanma / dış ilk yardım"), listOf("3", "Küçük yaralanma / iç ilk yardım"), listOf("1", "Ucuz atlatma / çevresel zarar yok"),
        )
        val value = copy(input, "Değer", "Value")
        drawReferenceTable(canvas, copy(input, "OLASILIK (O)", "PROBABILITY (P)"), listOf(value, copy(input, "Zararın gerçekleşme olasılığı", "Likelihood of harm")), probability, RectF(x, y, x + 246f, y + 212f))
        drawReferenceTable(canvas, copy(input, "FREKANS (F)", "FREQUENCY (F)"), listOf(value, copy(input, "Tehlikeye maruz kalma tekrarı", "Exposure frequency")), frequency, RectF(x + 264f, y, x + 510f, y + 212f))
        drawReferenceTable(canvas, copy(input, "ŞİDDET (Ş)", "SEVERITY (S)"), listOf(value, copy(input, "İnsan/çevre üzerinde tahmini zarar", "Estimated harm to people/environment")), severity, RectF(x + 528f, y, x + 774f, y + 212f))
        val riskRows = if (en) listOf(
            listOf("1801 ≤ R", "Intolerable", "Stop work immediately; consider isolating the area.", "Immediate / 1 week"), listOf("401 ≤ R < 1801", "Act as soon as possible", "Restrict activity until risk is reduced.", "Less than 1 month"), listOf("201 ≤ R < 401", "Substantial risk", "Take urgent action and monitor the activity.", "1–3 months"), listOf("71 ≤ R < 201", "Significant risk", "Start a corrective action plan.", "6 months"), listOf("21 ≤ R < 71", "Possible risk", "Maintain and monitor controls.", "1 year"), listOf("R < 21", "Minor risk", "Additional controls may not be required.", "Review"),
        ) else listOf(
            listOf("1801 ≤ R", "Tolerans gösterilemez", "İş derhal durdurulur; tesis/çevre kapatılması düşünülebilir.", "Hemen / 1 hafta"), listOf("401 ≤ R < 1801", "En kısa sürede giderilecek", "Risk kabul edilebilir seviyeye düşene kadar faaliyet kısıtlanır.", "1 aydan kısa"), listOf("201 ≤ R < 401", "Esaslı risk", "Acil önlem alınır ve faaliyet izlenir.", "1-3 ay"), listOf("71 ≤ R < 201", "Önemli risk", "Düzeltici faaliyet planı başlatılır.", "6 ay"), listOf("21 ≤ R < 71", "Olası risk", "Kontroller sürdürülür ve izlenir.", "1 yıl"), listOf("R < 21", "Önemsiz risk", "İlave kontrole gerek olmayabilir.", "Kontrol"),
        )
        drawReferenceTable(
            canvas,
            copy(input, "RİSK DEĞERİ (R = O x F x Ş)", "RISK VALUE (R = P × F × S)"),
            listOf(copy(input, "Risk değeri", "Risk value"), copy(input, "Risk adı", "Risk band"), copy(input, "Eylem", "Action"), copy(input, "Termin", "Due")),
            riskRows,
            RectF(x, y + 244f, x + 774f, y + 422f),
            rowColors = listOf("critical", "critical", "high", "medium", "low", "low"),
        )
    }

    private fun drawMatrixReference(canvas: Canvas, input: PdfReportInput, x: Float, y: Float) {
        val en = input.languageCode.startsWith("en")
        val probability = if (en) listOf(listOf("1", "Very unlikely"), listOf("2", "Unlikely"), listOf("3", "Possible"), listOf("4", "Likely"), listOf("5", "Very likely"))
        else listOf(listOf("1", "Gerçekleşme ihtimali çok az"), listOf("2", "Gerçekleşme ihtimali az"), listOf("3", "Gerçekleşme ihtimali var"), listOf("4", "Gerçekleşme ihtimali yüksek"), listOf("5", "Gerçekleşme ihtimali çok yüksek"))
        val severity = if (en) listOf(listOf("1", "Minor injury / no lost time"), listOf("2", "Minor injury requiring first aid"), listOf("3", "Lost time or treatment required"), listOf("4", "Long-term absence / serious injury"), listOf("5", "Permanent disability or fatality"))
        else listOf(listOf("1", "Hafif yaralanmalar / iş günü kaybı yok"), listOf("2", "İlk yardım gerektiren küçük yaralanma"), listOf("3", "İş günü kaybı veya tedavi gerektiren yaralanma"), listOf("4", "Uzun süreli kayıp / ağır yaralanma"), listOf("5", "Kalıcı iş göremezlik veya ölüm"))
        drawReferenceTable(canvas, copy(input, "OLASILIK (O)", "PROBABILITY (P)"), listOf(copy(input, "Derece", "Rating"), copy(input, "Tanım", "Description")), probability, RectF(x, y, x + 360f, y + 162f))
        drawReferenceTable(canvas, copy(input, "ŞİDDET (Ş)", "SEVERITY (S)"), listOf(copy(input, "Derece", "Rating"), copy(input, "Tanım", "Description")), severity, RectF(x + 392f, y, x + 774f, y + 162f))
        val matrix = RectF(x + 74f, y + 214f, x + 694f, y + 446f)
        drawTextRect(canvas, copy(input, "5x5 Risk Matrisi - R = O x Ş", "5×5 Risk Matrix — R = P × S"), RectF(matrix.left, matrix.top - 28f, matrix.right, matrix.top - 8f), 12f, COLOR_ONYX, bold = true, align = Paint.Align.CENTER)
        val cellW = matrix.width() / 6f
        val cellH = matrix.height() / 6f
        for (row in 0..5) for (column in 0..5) {
            val cell = RectF(matrix.left + column * cellW, matrix.top + row * cellH, matrix.left + (column + 1) * cellW, matrix.top + (row + 1) * cellH)
            val score = row * column
            val fill = if (row == 0 || column == 0) Color.parseColor("#F1F3F2") else matrixColor(score)
            drawRoundedRect(canvas, cell, 0f, fill, if (row == 0 || column == 0) COLOR_LINE else Color.WHITE, 1f)
            val label = when {
                row == 0 && column == 0 -> copy(input, "O / Ş", "P / S")
                row == 0 -> column.toString()
                column == 0 -> row.toString()
                else -> score.toString()
            }
            drawTextRect(canvas, label, cell, if (row == 0 || column == 0) 9f else 10f, COLOR_ONYX, bold = true, align = Paint.Align.CENTER)
        }
    }

    private fun drawReferenceTable(
        canvas: Canvas,
        title: String,
        columns: List<String>,
        rows: List<List<String>>,
        rect: RectF,
        rowColors: List<String> = emptyList(),
    ) {
        drawTextRect(canvas, title, RectF(rect.left, rect.top, rect.right, rect.top + 20f), 10f, COLOR_ONYX, bold = true, align = Paint.Align.CENTER)
        val tableTop = rect.top + 24f
        val rowHeight = (rect.bottom - tableTop) / (rows.size + 1)
        val firstColumn = if (columns.size == 2) rect.width() * .25f else rect.width() * .18f
        val remaining = rect.width() - firstColumn
        val widths = listOf(firstColumn) + List(columns.size - 1) { remaining / (columns.size - 1) }
        drawAbsoluteTableRow(canvas, rect.left, tableTop, widths, columns, rowHeight, header = true)
        var y = tableTop + rowHeight
        rows.forEachIndexed { index, values ->
            val fillBand = rowColors.getOrNull(index)
            var left = rect.left
            widths.forEachIndexed { column, width ->
                val fill = fillBand?.let { tintColor(bandColor(it), .14f) } ?: Color.WHITE
                drawRoundedRect(canvas, RectF(left, y, left + width, y + rowHeight), 0f, fill, COLOR_LINE, .6f)
                drawTextRect(canvas, values.getOrElse(column) { "" }, RectF(left + 3f, y + 3f, left + width - 3f, y + rowHeight - 3f), if (columns.size > 2) 6.2f else 7f, COLOR_ONYX, bold = column == 0, align = if (column == 0) Paint.Align.CENTER else Paint.Align.LEFT, maxLines = 4)
                left += width
            }
            y += rowHeight
        }
    }

    private fun matrixColor(score: Int): Int = when {
        score >= 15 -> Color.parseColor("#F0736A")
        score >= 10 -> Color.parseColor("#F0A55C")
        score >= 5 -> Color.parseColor("#F2D56B")
        else -> Color.parseColor("#8BCB95")
    }

    private fun scoreText(value: Double): String = if (value % 1.0 == 0.0) value.toInt().toString()
    else String.format(Locale.US, "%.1f", value)

    private fun measuredHeight(text: String, width: Float, size: Float, bold: Boolean = false): Float {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = size; isFakeBoldText = bold }
        return StaticLayout.Builder.obtain(text, 0, text.length, paint, width.coerceAtLeast(1f).toInt())
            .setLineSpacing(1f, 1f).build().height.toFloat()
    }

    private fun drawTextRect(
        canvas: Canvas,
        text: String,
        rect: RectF,
        size: Float,
        color: Int,
        bold: Boolean = false,
        align: Paint.Align = Paint.Align.LEFT,
        maxLines: Int = Int.MAX_VALUE,
    ) {
        if (text.isEmpty() || rect.width() <= 0f || rect.height() <= 0f) return
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            this.textSize = size
            this.color = color
            isFakeBoldText = bold
            textAlign = Paint.Align.LEFT
        }
        val alignment = when (align) {
            Paint.Align.CENTER -> Layout.Alignment.ALIGN_CENTER
            Paint.Align.RIGHT -> Layout.Alignment.ALIGN_OPPOSITE
            else -> Layout.Alignment.ALIGN_NORMAL
        }
        val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, rect.width().toInt())
            .setAlignment(alignment)
            .setLineSpacing(1f, 1f)
            .setMaxLines(maxLines)
            .setEllipsize(android.text.TextUtils.TruncateAt.END)
            .build()
        canvas.save()
        canvas.clipRect(rect)
        val verticalOffset = if (layout.height < rect.height()) ((rect.height() - layout.height) / 2f).coerceAtLeast(0f) else 0f
        canvas.translate(rect.left, rect.top + verticalOffset)
        layout.draw(canvas)
        canvas.restore()
    }

    private fun drawRoundedRect(canvas: Canvas, rect: RectF, radius: Float, fill: Int, stroke: Int, strokeWidth: Float) {
        canvas.drawRoundRect(rect, radius, radius, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = fill; style = Paint.Style.FILL })
        if (strokeWidth > 0f && stroke != Color.TRANSPARENT) canvas.drawRoundRect(
            rect,
            radius,
            radius,
            Paint(Paint.ANTI_ALIAS_FLAG).apply { color = stroke; style = Paint.Style.STROKE; this.strokeWidth = strokeWidth },
        )
    }

    private fun tintColor(color: Int, alpha: Float): Int = Color.argb(
        (255 * alpha).toInt(),
        Color.red(color),
        Color.green(color),
        Color.blue(color),
    )

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
            textSize = TABLE_TEXT_SIZE
            isFakeBoldText = isHeader
        }
        values.forEachIndexed { i, value ->
            val cellWidth = totalWidth * weights[i]
            val cellLayout = StaticLayout.Builder
                .obtain(value, 0, value.length, paint, (cellWidth - 16f).coerceAtLeast(1f).toInt())
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setMaxLines(if (isHeader) 2 else TABLE_BODY_MAX_LINES)
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
        // Measurement and drawing must use the exact same typography. Measuring at 14sp and
        // drawing at 15sp let StaticLayout render one or two extra visual lines outside the
        // measured row, so long descriptions overlapped the following finding in the real PDF.
        val paint = TextPaint().apply { textSize = TABLE_TEXT_SIZE }
        val tallest = values.mapIndexed { index, value ->
            val cellWidth = (totalWidth * weights.getOrElse(index) { weights.last() } - 16f)
                .coerceAtLeast(1f)
                .toInt()
            StaticLayout.Builder
                .obtain(value, 0, value.length, paint, cellWidth)
                .setMaxLines(TABLE_BODY_MAX_LINES)
                .setEllipsize(android.text.TextUtils.TruncateAt.END)
                .build()
                .height
        }.maxOrNull() ?: 0
        // Long corrective-action and legislation cells must remain readable. Do not cap the
        // measured height below StaticLayout's actual height; the page-break branch above moves
        // the complete row to a fresh page when necessary.
        return (tallest + 18f).coerceAtLeast(48f)
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
