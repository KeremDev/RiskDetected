package com.riskdetectedan.core.data.nova

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

enum class NovaGeneratedReportKind(val title: String, val detail: String, val symbol: String) {
    company("Firma raporu", "Firmanın bütün süreç sayılarını tek tabloda gösterir.", "building.2"),
    training("Eğitim raporu", "Gerçekleşen eğitim, süre ve katılımcı kayıtlarını listeler.", "graduationcap"),
    pending("Bekleyen işler", "Bekleyen, yaklaşan ve geciken işleri bir araya getirir.", "clock.badge.exclamationmark"),
    completed("Tamamlanan işler", "Toplam kayıtlardan bekleyenler çıkarılarak tamamlanan işleri gösterir.", "checkmark.circle"),
    visits("Ziyaret raporu", "Ziyaret tarihi, süre, işyeri ve görüşme kayıtlarını listeler.", "figure.walk"),
    allProcesses("Tüm süreçler", "Acil durumdan kontrol listelerine kadar tüm takip özetini verir.", "square.grid.2x2");

    /** The suggested headings for this kind; all start selected. */
    val content: List<Triple<String, String, String>> get() = when (this) {
        training -> listOf(Triple("training", "Eğitim", "graduationcap"), Triple("date", "Tarih", "calendar"),
            Triple("trainer", "Eğitici", "person.crop.rectangle"), Triple("company", "Firma", "building.2"), Triple("participants", "Katılımcı", "person.3"))
        visits -> listOf(Triple("company", "Firma", "building.2"), Triple("workplace", "İşyeri", "building"), Triple("date", "Tarih", "calendar"),
            Triple("duration", "Süre", "clock"), Triple("contact", "Görüşülen kişi", "person"), Triple("note", "Not", "text.alignleft"))
        else -> listOf(Triple("risk_assessment", "Risk değerlendirmeleri", "checkmark.shield"),
            Triple("emergency_plan", "Acil durum planları", "light.beacon.max"), Triple("drill", "Tatbikatlar", "figure.run"),
            Triple("appointment", "Atama ve temsilciler", "person.badge.shield.checkmark"), Triple("checklist_run", "Kontrol listeleri", "checklist"),
            Triple("equipment", "Periyodik kontroller", "checkmark.shield"), Triple("nonconformity", "Uygunsuzluklar", "exclamationmark.triangle"),
            Triple("training", "Eğitimler", "graduationcap"), Triple("site_visit", "Ziyaretler", "figure.walk"),
            Triple("annual_work_plan", "Yıllık çalışma planları", "calendar"), Triple("board", "Kurul ve toplantılar", "person.3"),
            Triple("katip_contract", "İSG-KATİP sözleşmeleri", "doc.text"))
    }
}

@Serializable data class NovaGeneratedReport(val id: String, val title: String, val kind: NovaGeneratedReportKind, val companyName: String? = null,
                                             val period: String, val format: String, val createdAt: Long, val filename: String)

/** Reports built on this device, kept per account in app storage (iOS `NovaGeneratedReportArchive`). */
class NovaGeneratedReportArchive(context: Context, owner: String) {
    private val directory = File(context.filesDir, "nova/reports/${owner.lowercase()}")
    private val index = File(directory, "index.json")
    private val list = ListSerializer(NovaGeneratedReport.serializer())

    fun load(): List<NovaGeneratedReport> = runCatching { Json.decodeFromString(list, index.readText()) }.getOrDefault(emptyList())
        .filter { file(it).exists() }.sortedByDescending { it.createdAt }

    fun store(bytes: ByteArray, title: String, kind: NovaGeneratedReportKind, companyName: String?, period: String, format: String): NovaGeneratedReport {
        check(directory.isDirectory || directory.mkdirs())
        val id = UUID.randomUUID().toString()
        val value = NovaGeneratedReport(id, title, kind, companyName, period, format, System.currentTimeMillis(),
            "$id.${if (format == "PDF") "pdf" else "xlsx"}")
        file(value).writeBytes(bytes)
        val temp = File(directory, "index.tmp")
        temp.writeText(Json.encodeToString(list, listOf(value) + load()))
        check(temp.renameTo(index))
        return value
    }

    fun file(report: NovaGeneratedReport) = File(directory, report.filename)
}
