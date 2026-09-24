package com.riskdetectedan.feature.nova

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate

/** The report pages' calls bound to one identity; the design preview supplies its own. */
interface NovaReportClient {
    /** Scopes the on-device archive, so one account never lists another's reports. */
    val owner: String
    val companies: suspend () -> List<NovaCompanyOption>
    suspend fun trainings(): List<NovaTrainingSession>
    suspend fun visits(company: String?, offset: Int): NovaProcessPage
    suspend fun tracking(company: String?): NovaModuleTrackingSnapshot
    suspend fun documents(offset: Int): List<NovaProcessDocument>
    suspend fun document(id: String, version: Int): NovaProcessRow
}

class NovaServiceReportClient(private val training: NovaTrainingService, private val process: NovaProcessService,
                              private val statistics: NovaStatisticsService, private val identity: IsgWorkspaceIdentity,
                              override val companies: suspend () -> List<NovaCompanyOption>) : NovaReportClient {
    override val owner get() = identity.userId.lowercase()
    override suspend fun trainings(): List<NovaTrainingSession> {
        val rows = mutableListOf<NovaTrainingSession>(); var after: String? = null; val seen = mutableSetOf<String>()
        do {
            val page = training.list(identity, after = after)
            rows += page.rows; after = page.nextId
        } while (after != null && seen.add(after))
        return rows
    }
    override suspend fun visits(company: String?, offset: Int) = process.page(identity, "site_visit", company, offset = offset)
    override suspend fun tracking(company: String?) = statistics.tracking(identity, company)
    override suspend fun documents(offset: Int) = process.documents(identity, offset)
    override suspend fun document(id: String, version: Int) = process.document(identity, id, version)
}

/** Hands a stored report to a viewer; a missing file or no viewer answers with a message rather than a crash. */
private fun shareReport(context: Context, archive: NovaGeneratedReportArchive, report: NovaGeneratedReport): String? = runCatching {
    val name = report.title.replace(Regex("[\\\\/:*?\"<>|]"), "-") + if (report.format == "PDF") ".pdf" else ".xlsx"
    novaShareFile(context, archive.file(report).readBytes(), name, if (report.format == "PDF") "application/pdf" else NovaXlsx.MIME)
}.exceptionOrNull()?.let { "Rapor açılamadı. Dosyayı yeniden oluşturup tekrar deneyin." }

@Composable
private fun GeneratedReportRow(report: NovaGeneratedReport, onClick: () -> Unit) {
    NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("report.generated.${report.id}"), padding = 13) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon(if (report.format == "PDF") "doc.text" else "tablecells", 16.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaText(report.title, style = NovaTypeToken.bodyStrong)
                NovaText(listOfNotNull(report.companyName, report.period, report.format).joinToString(" · "), style = NovaTypeToken.metaQuiet)
            }
            NovaIcon("arrow.down.circle", 16.dp)
        }
    }
}

private sealed interface ReportPage {
    data class Create(val kind: NovaGeneratedReportKind, val skipsType: Boolean) : ReportPage
    data object Archive : ReportPage
}

/** Rapor Merkezi (iOS `NovaReportCenter`). */
@Composable
fun NovaReportCenter(client: NovaReportClient, analysisReports: @Composable () -> Unit, onBack: () -> Unit) {
    val context = LocalContext.current
    val archive = remember(client.owner) { NovaGeneratedReportArchive(context, client.owner) }
    var page by remember { mutableStateOf<ReportPage?>(null) }
    var recent by remember { mutableStateOf(archive.load()) }
    var failure by remember { mutableStateOf<String?>(null) }
    val open = page
    if (open != null) {
        val close: () -> Unit = { page = null; recent = archive.load() }
        when (open) {
            is ReportPage.Create -> NovaReportCreateFlow(client, archive, open.kind, open.skipsType, close)
            ReportPage.Archive -> NovaReportArchive(client, analysisReports, close)
        }
        return
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaListHeading("Rapor Merkezi", onBack) {
            NovaButton("Arşiv", { page = ReportPage.Archive }, Modifier.testTag("report.center.archive"), variant = NovaButtonVariant.Surface,
                symbol = "archivebox", compact = true)
        }
        NovaListHint("Firma, eğitim, bekleyen işler, tamamlanan işler ve ziyaretler için kapsamlı rapor oluşturun; PDF veya Excel çıktısını indirin.")
        NovaListActionButton("Yeni rapor oluştur", "doc.badge.plus", identifier = "report.center.create") {
            page = ReportPage.Create(NovaGeneratedReportKind.company, false)
        }
        NovaListSectionHeading("Rapor türleri", "${NovaGeneratedReportKind.entries.size} tür")
        NovaGeneratedReportKind.entries.chunked(2).forEach { pair ->
            Row(Modifier.height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pair.forEach { kind ->
                    NovaCard(Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(22.dp)).novaRowPress { page = ReportPage.Create(kind, true) }
                        .testTag("report.center.kind.${kind.name}"), padding = 13) {
                        Column(Modifier.heightIn(min = 112.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            NovaIcon(kind.symbol, 20.dp, tint = NovaColorToken.accentInk.color())
                            NovaText(kind.title, style = NovaTypeToken.bodyStrong)
                            NovaText(kind.detail, style = NovaTypeToken.metaQuiet, maxLines = 3)
                        }
                    }
                }
            }
        }
        if (recent.isNotEmpty()) {
            NovaListSectionHeading("Son oluşturulanlar", "${recent.size} rapor")
            failure?.let { NovaTaskErrorSummary(it) }
            recent.take(3).forEach { report -> GeneratedReportRow(report) { failure = shareReport(context, archive, report) } }
        }
    }
}

private fun periodTitle(period: String) = when (period) { "30" -> "Son 30 gün"; "90" -> "Son 90 gün"; "365" -> "Son 1 yıl"; else -> "Tüm zamanlar" }

private fun withinPeriod(value: String, period: String): Boolean {
    val days = period.toLongOrNull() ?: return true
    val day = runCatching { LocalDate.parse(value.take(10)) }.getOrNull() ?: return true
    return !day.isBefore(LocalDate.now().minusDays(days))
}

/** The report builder (iOS `NovaReportCreateFlow`): type, scope and period, headings, format, review. */
@Composable
private fun NovaReportCreateFlow(client: NovaReportClient, archive: NovaGeneratedReportArchive, initialKind: NovaGeneratedReportKind, skipsType: Boolean,
                                 onClose: () -> Unit) {
    val context = LocalContext.current
    val coroutines = rememberCoroutineScope()
    val minimum = if (skipsType) 1 else 0
    var step by remember { mutableIntStateOf(minimum) }
    var kind by remember { mutableStateOf(initialKind) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var company by remember { mutableStateOf<String?>(null) }
    var period by remember { mutableStateOf("90") }
    var format by remember { mutableStateOf("PDF") }
    var selected by remember { mutableStateOf(initialKind.content.map { it.first }.toSet()) }
    var customFields by remember { mutableStateOf<List<String>>(emptyList()) }
    var customValues by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var customDraft by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var working by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var generated by remember { mutableStateOf<NovaGeneratedReport?>(null) }
    LaunchedEffect(Unit) {
        try { companies = client.companies() } catch (_: Exception) { failure = "Firmalar yüklenemedi; tüm firmalar kapsamında devam edebilirsiniz." }
        loading = false
    }
    val done = generated
    if (done != null) {
        BackHandler(onBack = onClose)
        NovaTaskSuccessView("Rapor hazır", "${done.title} oluşturuldu ve Rapor Arşivi > Özel Raporlar bölümüne kaydedildi.", "Rapor Merkezine dön",
            onClose, nextTitle = "Raporu indir", onNext = { shareReport(context, archive, done) })
        return
    }
    val companyName = companies.firstOrNull { it.id == company }?.name
    val options = kind.content
    val chosenTitles = options.filter { it.first in selected }.map { it.second } + customFields
    suspend fun lines(): Pair<List<String>, List<List<String>>> {
        val custom = customFields.map { customValues[it].orEmpty() }
        val columns = options.filter { it.first in selected }
        return when (kind) {
            NovaGeneratedReportKind.training -> {
                val rows = client.trainings().filter { session ->
                    (company == null || session.companies.any { it.companyId.sameId(company) }) && withinPeriod(session.heldOn, period)
                }
                (columns.map { it.second } + customFields) to rows.map { session ->
                    val values = mapOf("training" to session.title, "date" to session.heldOn, "trainer" to session.trainer,
                        "company" to session.companies.joinToString(", ") { it.companyName }, "participants" to session.count.toString())
                    columns.map { values[it.first].orEmpty() } + custom
                }
            }
            NovaGeneratedReportKind.visits -> {
                var page = client.visits(company, 0)
                val rows = page.rows.toMutableList()
                while (page.hasMore && rows.size < 500) { page = client.visits(company, rows.size); rows += page.rows }
                (columns.map { it.second } + customFields) to rows.filter { withinPeriod(it.date, period) }.map { row ->
                    val values = mapOf("company" to row.companyName, "workplace" to row.workplaceName.orEmpty(), "date" to row.date.take(10),
                        "duration" to row.values["duration_minutes"].novaText(), "contact" to row.values["responsible_contact"].novaText(),
                        "note" to row.values["expert_note"].novaText())
                    columns.map { values[it.first].orEmpty() } + custom
                }
            }
            else -> {
                val rows = client.tracking(company).rows.filter { row ->
                    row.kind in selected && when (kind) {
                        NovaGeneratedReportKind.pending -> (row.pending ?: 0) > 0 || (row.overdue ?: 0) > 0
                        NovaGeneratedReportKind.completed -> maxOf(0, (row.total ?: 0) - (row.pending ?: 0)) > 0
                        else -> true
                    }
                }
                (listOf("Firma", "Süreç", "Toplam", "Tamamlanan", "Bekleyen", "Geciken", "Yaklaşan") + customFields) to rows.map { row ->
                    val total = row.total ?: 0; val pending = row.pending ?: 0
                    listOf(row.companyName, NovaModuleTrackingSnapshot.Summary(row.kind, row.available, total, pending, row.overdue ?: 0,
                        row.upcoming ?: 0, row.review ?: 0, row.nextOn).title, "$total", "${maxOf(0, total - pending)}", "$pending",
                        "${row.overdue ?: 0}", "${row.upcoming ?: 0}") + custom
                }
            }
        }
    }
    fun generate() = coroutines.launch {
        working = true; failure = null
        try {
            val (headers, rows) = lines()
            val title = "${kind.title} · ${companyName ?: "Tüm firmalar"}"
            val subtitle = periodTitle(period)
            val bytes = withContext(Dispatchers.Default) {
                if (format == "Excel") NovaXlsx.workbook(listOf(NovaXlsx.Sheet("Rapor", listOf(headers) + rows, headers.map { 24 }, freeze = true, filter = true)))
                else NovaPdfWriter(header = { title }) { page -> "İSGADA · $subtitle · Sayfa $page" }.run {
                    paragraph(title, 20f, true, 4f)
                    paragraph(subtitle, 11f, after = 14f)
                    paragraph(headers.joinToString("  •  "), 10f, true)
                    rows.forEach { paragraph(it.joinToString("  •  "), 9f) }
                    if (rows.isEmpty()) paragraph("Seçilen kapsamda kayıt bulunamadı.", 11f)
                    finish()
                }
            }
            generated = withContext(Dispatchers.IO) { archive.store(bytes, title, kind, companyName, subtitle, format) }
        } catch (_: Exception) { failure = "Rapor oluşturulamadı. Bağlantınızı kontrol edip yeniden deneyin." }
        working = false
    }
    val goBack: () -> Unit = { failure = null; if (step > minimum) step-- else onClose() }
    val titles = listOf("Rapor türü", "Kapsam ve dönem", "Rapor içeriği", "Çıktı biçimi", "Kontrol ve oluştur")
    if (loading) {
        BackHandler(onBack = onClose)
        NovaLoadingView("Rapor seçenekleri hazırlanıyor…")
        return
    }
    NovaModuleTask("Rapor oluştur", if (skipsType) step else step + 1, if (skipsType) 4 else 5, titles[step],
        if (step == 4) "Raporu oluştur" else "Devam", if (step == 4) "doc.badge.plus" else "arrow.right", working, goBack, {
            failure = null
            when {
                step == 2 && selected.isEmpty() && customFields.isEmpty() -> failure = "Rapora en az bir başlık ekleyin."
                step < 4 -> step++
                else -> generate()
            }
        }, failure) {
        when (step) {
            0 -> {
                NovaText("Neyi raporlamak istiyorsunuz?", style = NovaTypeToken.sectionTitle)
                NovaGeneratedReportKind.entries.forEach { item ->
                    SelectableCard(item.symbol, item.title, item.detail, kind == item, "report.create.kind.${item.name}") {
                        kind = item; selected = item.content.map { it.first }.toSet(); customFields = emptyList(); customValues = emptyMap(); customDraft = ""
                    }
                }
            }
            1 -> {
                NovaText("Firma ve dönem", style = NovaTypeToken.sectionTitle)
                NovaFilterField("Firma", listOf(NovaChooserOption(null, "Tüm firmalar")) + companies.map { NovaChooserOption(it.id, it.name) }, company,
                    "report.create.company") { company = it }
                val periods = listOf("30", "90", "365", "all")
                NovaSegmentedControl(listOf("Son 30 gün", "Son 90 gün", "Son 1 yıl", "Tüm zamanlar"), periods.indexOf(period)) { period = periods[it] }
            }
            2 -> {
                NovaText("Raporda neler yer alsın?", style = NovaTypeToken.sectionTitle)
                NovaHelpHint("Önerilen başlıkların tamamı seçili gelir. İstemediğiniz başlıkları çıkarabilir veya rapora özel bir alan ekleyebilirsiniz.")
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaCompactActionButton("Tümünü seç", "checkmark.circle", Modifier.weight(1f)) { selected = options.map { it.first }.toSet() }
                    NovaCompactActionButton("Seçimi temizle", "xmark.circle", Modifier.weight(1f)) { selected = emptySet() }
                }
                options.forEach { (id, title, symbol) ->
                    SelectableCard(symbol, title, null, id in selected, "report.create.content.$id") {
                        selected = if (id in selected) selected - id else selected + id
                    }
                }
                NovaCard(Modifier.fillMaxWidth(), padding = 13) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        NovaText("Özel alan ekle", style = NovaTypeToken.bodyStrong)
                        Row(verticalAlignment = Alignment.Bottom) {
                            NovaTextField("Alan adı", customDraft, { customDraft = it }, Modifier.weight(1f), placeholder = "Örn. Yönetici notu")
                            Box(Modifier.size(44.dp).clip(CircleShape).novaRowPress {
                                val title = customDraft.trim()
                                if (title.isNotEmpty() && title.toByteArray().size <= 80 && customFields.none { it.equals(title, true) }) {
                                    customFields = customFields + title; customValues = customValues + (title to ""); customDraft = ""
                                }
                            }.semantics { contentDescription = "Özel alanı ekle" }.testTag("report.create.custom.add"),
                                contentAlignment = Alignment.Center) { NovaIcon("plus", 16.dp) }
                        }
                        customFields.forEach { title ->
                            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    NovaText(title, Modifier.weight(1f), NovaTypeToken.label)
                                    Box(Modifier.size(44.dp).clip(CircleShape).novaRowPress {
                                        customFields = customFields - title; customValues = customValues - title
                                    }.semantics { contentDescription = "$title alanını kaldır" }, contentAlignment = Alignment.Center) {
                                        NovaIcon("xmark.circle", 15.dp, tint = NovaColorToken.statusDangerInk.color())
                                    }
                                }
                                NovaTextField(title, customValues[title].orEmpty(), { customValues = customValues + (title to it) },
                                    placeholder = "Bu raporda görünecek değer (isteğe bağlı)")
                            }
                        }
                    }
                }
            }
            3 -> {
                NovaText("Çıktı biçimi", style = NovaTypeToken.sectionTitle)
                val formats = listOf("PDF", "Excel")
                NovaSegmentedControl(formats, formats.indexOf(format)) { format = formats[it] }
                NovaWhyDisclosure {
                    NovaText("PDF paylaşım ve imza süreçleri için; Excel ise filtreleme ve kurum içi çalışma için uygundur.", style = NovaTypeToken.metaQuiet)
                }
            }
            else -> {
                NovaText("Rapor özeti", style = NovaTypeToken.sectionTitle)
                NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                        listOf("Kapsam" to kind.title, "Firma" to (companyName ?: "Tüm firmalar"), "Dönem" to periodTitle(period),
                            "İçerik" to "${chosenTitles.size} başlık", "Çıktı" to format).forEach { (label, value) ->
                            Row {
                                NovaText(label, Modifier.weight(1f), NovaTypeToken.metaQuiet)
                                NovaText(value, style = NovaTypeToken.bodyStrong)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SelectableCard(symbol: String, title: String, detail: String?, on: Boolean, identifier: String, onClick: () -> Unit) {
    NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag(identifier), padding = 13,
        tint = if (on) NovaColorToken.statusSuccessBg.color() else null) {
        Row(horizontalArrangement = Arrangement.spacedBy(11.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon(symbol, 16.dp, Modifier.width(26.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaText(title, style = NovaTypeToken.bodyStrong)
                detail?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
            }
            NovaIcon(if (on) "checkmark.circle.fill" else "circle", 18.dp,
                tint = if (on) NovaColorToken.accentInk.color() else NovaColorToken.textMuted.color())
        }
    }
}

private enum class ArchiveSection(val title: String) {
    process("Süreç belgeleri"), analysis("Analiz raporları"), nonconformity("Uygunsuzluk raporları"), custom("Özel raporlarım")
}

/** Rapor Arşivi (iOS `NovaProcessArchive`): server documents by version, analysis reports and this device's own reports. */
@Composable
fun NovaReportArchive(client: NovaReportClient, analysisReports: @Composable () -> Unit, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    val coroutines = rememberCoroutineScope()
    val archive = remember(client.owner) { NovaGeneratedReportArchive(context, client.owner) }
    var section by remember { mutableStateOf(ArchiveSection.process) }
    var entries by remember { mutableStateOf<List<NovaProcessDocument>>(emptyList()) }
    var custom by remember(section) { mutableStateOf(archive.load()) }
    var busy by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var more by remember { mutableStateOf(false) }
    suspend fun load(append: Boolean) {
        busy = true; failure = null
        try {
            val page = client.documents(if (append) entries.size else 0)
            entries = if (append) entries + page else page
            more = page.size == 20
        } catch (error: Exception) { failure = NovaProcessService.message(error) }
        busy = false
    }
    fun open(entry: NovaProcessDocument, excel: Boolean) = coroutines.launch {
        busy = true; failure = null
        try {
            val row = client.document(entry.id, entry.version)
            val kind = NovaProcessKind.get(entry.kind)
            val bytes = withContext(Dispatchers.Default) { if (excel) NovaProcessExport.xlsx(row, kind) else NovaProcessExport.pdf(row, kind) }
            novaShareFile(context, bytes, NovaProcessExport.fileName(row, kind, if (excel) "xlsx" else "pdf"), if (excel) NovaXlsx.MIME else "application/pdf")
        } catch (error: Exception) { failure = NovaProcessService.message(error) }
        busy = false
    }
    LaunchedEffect(Unit) { load(false) }
    Column(Modifier.fillMaxSize().padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPageHeading("Rapor Arşivi", modifier = Modifier.padding(horizontal = 20.dp), onBack = onBack)
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ArchiveSection.entries.forEach { item ->
                val on = section == item
                Box(Modifier.heightIn(min = 42.dp).clip(CircleShape).background((if (on) NovaColorToken.accent else NovaColorToken.surface).color(), CircleShape)
                    .novaRowPress { section = item }.testTag("report.archive.${item.name}").padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                    NovaText(item.title, style = if (on) NovaTypeToken.buttonSm else NovaTypeToken.meta,
                        color = if (on) NovaColorToken.onAccent.color() else NovaColorToken.text.color())
                }
            }
        }
        if (section == ArchiveSection.analysis) {
            Box(Modifier.weight(1f)) { analysisReports() }
            return@Column
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp + novaTabBarInset),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (busy) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { NovaSpinner(NovaColorToken.text.color(), size = 22.dp) }
            failure?.let {
                NovaTaskErrorSummary(it)
                NovaButton("Yeniden dene", { coroutines.launch { load(false) } }, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
            }
            if (section == ArchiveSection.custom) {
                if (custom.isEmpty()) NovaEmptyState("Henüz özel rapor yok",
                    "Rapor Merkezi'nde oluşturduğunuz firma, eğitim, iş ve ziyaret raporları burada saklanır.")
                custom.forEach { report -> GeneratedReportRow(report) { failure = shareReport(context, archive, report) } }
                return@Column
            }
            val findings = section == ArchiveSection.nonconformity
            val visible = entries.filter { it.isFinding == findings }
            if (visible.isEmpty() && !busy && failure == null) NovaEmptyState(
                if (findings) "Henüz uygunsuzluk raporu yok" else "Henüz süreç belgesi yok",
                if (findings) "Uygunsuzluk raporları oluşturulduğunda firma ve sürüm bilgileriyle burada görünür."
                else "Hazırladığınız süreç belgeleri ve önceki sürümleri burada görünür.")
            visible.forEach { entry ->
                NovaCard(Modifier.fillMaxWidth().testTag("report.archive.entry.${entry.key}"), padding = 16) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        NovaText(if (entry.isFinding) "Uygunsuzluk Raporu" else NovaProcessKind.get(entry.kind).title, style = NovaTypeToken.cardTitle)
                        NovaText(entry.companyName, style = NovaTypeToken.meta)
                        NovaText("${entry.documentNo} · Sürüm ${entry.version}", style = NovaTypeToken.metaQuiet)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            NovaButton("PDF indir", { open(entry, false) }, variant = NovaButtonVariant.Surface, enabled = !busy, symbol = "doc.text", compact = true)
                            NovaButton("Excel indir", { open(entry, true) }, variant = NovaButtonVariant.Surface, enabled = !busy, symbol = "tablecells", compact = true)
                        }
                    }
                }
            }
            if (more && section == ArchiveSection.process) NovaButton("Daha fazla", { coroutines.launch { load(true) } }, variant = NovaButtonVariant.Surface,
                enabled = !busy, symbol = "chevron.down")
        }
    }
}
