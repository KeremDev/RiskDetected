package com.riskdetectedan.feature.nova

import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant

/** What the analysis list reads (iOS `NovaAnalysisListScreen` closures). */
class NovaAnalysisListClient(
    val load: suspend (offset: Int) -> Pair<List<NovaAnalysisSummary>, Boolean>,
    val stats: suspend () -> NovaAnalysisListStats,
    val thumbnail: suspend (String) -> ByteArray?,
)

private enum class AnalysisFilter(val title: String) { all("Tümü"), critical("Kritik"), unassigned("Firmasız"), unreviewed("İncelenmemiş") }
private enum class AnalysisSort(val title: String) { newest("En yeni"), highestRisk("En yüksek risk"), mostFindings("En çok bulgu"), unreviewed("İncelenmemiş önce") }

private fun riskRank(band: String?) = when (band) { "critical" -> 4; "high" -> 3; "medium" -> 2; "low" -> 1; else -> 0 }

@Composable
internal fun NovaAnalysisFact(symbol: String, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 9.dp, tint = NovaColorToken.textTertiary.color())
        NovaText(text, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color(), maxLines = 1)
    }
}

@Composable
private fun HeaderIconButton(symbol: String, label: String, tag: String, onClick: () -> Unit) {
    Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(14.dp))
        .novaRowPress(onClick = onClick).semantics { contentDescription = label }.testTag(tag), contentAlignment = Alignment.Center) {
        NovaIcon(symbol, 15.dp)
    }
}

@Composable
private fun CompactControl(symbol: String, title: String, emphasized: Boolean, tag: String, onClick: () -> Unit) {
    val ink = if (emphasized) NovaColorToken.accentInk.color() else NovaColorToken.text.color()
    Row(Modifier.heightIn(min = 38.dp).clip(CircleShape).background(if (emphasized) NovaColorToken.statusSuccessBg.color() else NovaColorToken.surface.color())
        .border(1.dp, if (emphasized) NovaColorToken.accentInk.color() else NovaColorToken.border.color(), CircleShape)
        .novaRowPress(onClick = onClick).padding(horizontal = 12.dp).testTag(tag), horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 11.dp, tint = ink)
        NovaText(title, style = NovaTypeToken.meta, color = ink)
        NovaIcon("chevron.down", 8.dp, tint = ink)
    }
}

@Composable
private fun RemovableFilter(title: String, onClick: () -> Unit) {
    val ink = NovaColorToken.accentInk.color()
    Row(Modifier.heightIn(min = 30.dp).clip(CircleShape).background(NovaColorToken.statusSuccessBg.color()).novaRowPress(onClick = onClick)
        .padding(horizontal = 10.dp).semantics { contentDescription = "$title filtresini kaldır" },
        horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaText(title, style = NovaTypeToken.micro, color = ink)
        NovaIcon("xmark", 8.dp, tint = ink)
    }
}

/**
 * Analizler (iOS `NovaAnalysisListScreen`): every completed analysis on the account with its picture and labels;
 * an unassigned one is not hidden, it is the row that still needs a decision.
 */
@Composable
fun NovaAnalysisListScreen(client: NovaAnalysisListClient, onOpen: (String) -> Unit, onBack: () -> Unit,
                           onNewPhotoAnalysis: (() -> Unit)? = null, onReports: (() -> Unit)? = null) {
    BackHandler(onBack = onBack)
    val coroutines = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<NovaAnalysisSummary>?>(null) }
    var totals by remember { mutableStateOf<NovaAnalysisListStats?>(null) }
    var statsError by remember { mutableStateOf<String?>(null) }
    var hasMore by remember { mutableStateOf(false) }
    var loadingMore by remember { mutableStateOf(false) }
    val images = remember { mutableStateMapOf<String, ImageBitmap>() }
    var error by remember { mutableStateOf<String?>(null) }
    var query by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(AnalysisFilter.all) }
    var sort by remember { mutableStateOf(AnalysisSort.newest) }
    var company by remember { mutableStateOf<String?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    var menu by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(reload) {
        error = null
        try { val (page, more) = client.load(0); rows = page; hasMore = more }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { rows = emptyList(); hasMore = false; error = "Analizler alınamadı. Bağlantınızı kontrol edip tekrar deneyin." }
    }
    LaunchedEffect(reload) {
        statsError = null
        try { totals = client.stats() } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
            totals = null; statsError = "Toplam istatistikler alınamadı."
        }
    }
    val all = rows.orEmpty()
    val companyNames = all.mapNotNull { it.companyName }.distinct().sorted()
    val activeFilters = (if (filter == AnalysisFilter.all) 0 else 1) + (if (company == null) 0 else 1)
    val visible = all.filter { row ->
        row.matches(query) && (company == null || row.companyName == company) && when (filter) {
            AnalysisFilter.all -> true; AnalysisFilter.critical -> row.highestBand == "critical"
            AnalysisFilter.unassigned -> row.isUnassigned; AnalysisFilter.unreviewed -> !row.isReviewed
        }
    }.sortedWith { left, right ->
        val newest = compareValues(right.createdAt ?: Instant.MIN, left.createdAt ?: Instant.MIN)
        when (sort) {
            AnalysisSort.newest -> newest
            AnalysisSort.highestRisk -> compareValues(riskRank(right.highestBand), riskRank(left.highestBand)).takeIf { it != 0 } ?: newest
            AnalysisSort.mostFindings -> compareValues(right.findingCount ?: 0, left.findingCount ?: 0).takeIf { it != 0 } ?: newest
            AnalysisSort.unreviewed -> compareValues(left.isReviewed, right.isReviewed).takeIf { it != 0 } ?: newest
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset)
        .testTag("analysis.list"), verticalArrangement = Arrangement.spacedBy(11.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaBackButton(onClick = onBack)
            NovaText("Analizler", Modifier.weight(1f), NovaTypeToken.screenTitle)
            if (onReports != null) HeaderIconButton("ellipsis", "Diğer işlemler", "analysis.list.reports") { menu = "more" }
            if (onNewPhotoAnalysis != null) Row(Modifier.heightIn(min = 44.dp).clip(CircleShape).background(NovaColorToken.accent.color())
                .novaRowPress(onClick = onNewPhotoAnalysis).padding(horizontal = 14.dp).testTag("analysis.list.new"),
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("plus", 13.dp, tint = androidx.compose.ui.graphics.Color(0xFF111111))
                NovaText("Yeni", style = NovaTypeToken.buttonSm, color = androidx.compose.ui.graphics.Color(0xFF111111))
            }
        }
        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(16.dp)).background(NovaColorToken.surface.color())
            .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(16.dp)).padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically) {
            listOf(Triple(totals?.total, "analiz", NovaStatus.Neutral), Triple(totals?.critical, "kritik", NovaStatus.Danger),
                Triple(totals?.findings, "bulgu", NovaStatus.Neutral)).forEachIndexed { index, (value, label, status) ->
                if (index > 0) Box(Modifier.width(1.dp).height(22.dp).background(NovaColorToken.hairline.color()))
                Row(Modifier.weight(1f).heightIn(min = 44.dp), horizontalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically) {
                    NovaText(value?.toString() ?: "—", style = NovaTypeToken.cardTitle, color = status.ink.color())
                    NovaText(label, style = NovaTypeToken.metaQuiet)
                }
            }
        }
        statsError?.let { message ->
            Row(Modifier.padding(horizontal = 3.dp).testTag("analysis.list.stats.error"), horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("exclamationmark.circle", 12.dp, tint = NovaColorToken.statusDangerInk.color())
                NovaText(message, Modifier.weight(1f), NovaTypeToken.micro, color = NovaColorToken.statusDangerInk.color())
                NovaText("Yenile", Modifier.novaRowPress { reload++ }, NovaTypeToken.buttonSm, color = NovaColorToken.accentInk.color())
            }
        }
        NovaSearchCapsule(query, "Analiz, firma veya sektör ara", "analysis.list.search") { query = it }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            CompactControl("line.3.horizontal.decrease", if (activeFilters == 0) "Filtre" else "Filtre · $activeFilters", activeFilters > 0,
                "analysis.list.filter") { menu = "filter" }
            CompactControl("arrow.up.arrow.down", sort.title, false, "analysis.list.sort") { menu = "sort" }
        }
        if (filter != AnalysisFilter.all || company != null) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            if (filter != AnalysisFilter.all) RemovableFilter(filter.title) { filter = AnalysisFilter.all }
            company?.let { RemovableFilter(it) { company = null } }
        }
        when {
            error != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    NovaText(error!!, style = NovaTypeToken.metaQuiet)
                    NovaCompactActionButton("Tekrar dene", "arrow.clockwise", Modifier.width(IntrinsicSize.Max)) { reload++ }
                }
            }
            rows == null -> NovaLoadingView("Analizler yükleniyor…")
            visible.isEmpty() -> NovaEmptyState("Henüz analiz kaydı yok",
                "Fotoğraf veya metin analizi oluşturarak riskleri, uzman görüşlerini ve önerileri dijital ortamda saklayabilirsiniz.")
            else -> NovaListEntrance(true) {
                Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
                    visible.forEachIndexed { index, row ->
                        LaunchedEffect(row.id) {
                            if (images[row.id] != null) return@LaunchedEffect
                            val bytes = client.thumbnail(row.id) ?: return@LaunchedEffect
                            withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }?.let { images[row.id] = it.asImageBitmap() }
                        }
                        Row(Modifier.fillMaxWidth().novaRowEntrance(index).clip(RoundedCornerShape(16.dp)).background(NovaColorToken.surface.color())
                            .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(16.dp)).novaRowPress { onOpen(row.id) }.padding(11.dp)
                            .testTag("analysis.list.row.${row.id.lowercase()}"), horizontalArrangement = Arrangement.spacedBy(11.dp),
                            verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(58.dp).clip(RoundedCornerShape(13.dp)).background(NovaColorToken.surfaceMuted.color()),
                                contentAlignment = Alignment.Center) {
                                images[row.id]?.let { Image(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
                                    ?: NovaIcon("photo", 16.dp, tint = NovaColorToken.textTertiary.color())
                            }
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    NovaText(NovaAnalysisPresentation.title(row.title), Modifier.weight(1f), NovaTypeToken.cardTitle, maxLines = 1)
                                    row.highestBand?.let { band ->
                                        Box(Modifier.size(6.dp).clip(CircleShape).background(NovaNonconformityWords.tone(band).ink.color()))
                                        NovaText(NovaNonconformityWords.band(band), style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color())
                                    }
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    NovaAnalysisFact("calendar", NovaAnalysisPresentation.dateOnly(row.createdOn))
                                    row.findingCount?.let { NovaAnalysisFact("exclamationmark.triangle", "$it bulgu") }
                                    if (row.photoCount > 0) NovaAnalysisFact("photo", "${row.photoCount}")
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    NovaAnalysisFact("building.2", row.companyName ?: "Firmasız")
                                    row.sectorLabel?.let { NovaAnalysisFact("square.grid.2x2", it) }
                                }
                            }
                            NovaIcon("chevron.right", 12.dp, tint = NovaColorToken.textTertiary.color())
                        }
                    }
                    // Only on the account's own unfiltered order: filtering one page client-side would hide rows a later page holds.
                    if (hasMore && query.isEmpty() && company == null && filter == AnalysisFilter.all) Row(Modifier.fillMaxWidth().heightIn(min = 44.dp)
                        .novaRowPress(enabled = !loadingMore) {
                            loadingMore = true
                            coroutines.launch {
                                try { val (page, more) = client.load(all.size); rows = all + page; hasMore = more }
                                catch (cancelled: CancellationException) { throw cancelled }
                                catch (_: Exception) { error = "Analizler alınamadı. Bağlantınızı kontrol edip tekrar deneyin." }
                                loadingMore = false
                            }
                        }.testTag("analysis.list.more"), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.CenterVertically) {
                        if (loadingMore) NovaSpinner(NovaColorToken.accentInk.color(), size = 14.dp)
                        NovaText("Daha fazla göster", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                    }
                }
            }
        }
    }
    NovaPopup(menu != null, { menu = null }, identifier = "analysis.list.menu") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            when (menu) {
                "more" -> {
                    NovaPopupHeading("Diğer işlemler", "ellipsis")
                    NovaPopupOption("Analiz Raporları", "doc.text", identifier = "analysis.list.menu.reports") { menu = null; onReports?.invoke() }
                }
                "filter" -> {
                    NovaPopupHeading("Filtre", "line.3.horizontal.decrease")
                    NovaText("Durum", style = NovaTypeToken.label)
                    AnalysisFilter.entries.forEach { option -> NovaRadioRow(option.title, filter == option) { filter = option; menu = null } }
                    if (companyNames.isNotEmpty()) {
                        NovaText("Firma", style = NovaTypeToken.label)
                        NovaRadioRow("Tüm firmalar", company == null) { company = null; menu = null }
                        companyNames.forEach { name -> NovaRadioRow(name, company == name) { company = name; menu = null } }
                    }
                }
                "sort" -> {
                    NovaPopupHeading("Sıralama", "arrow.up.arrow.down")
                    AnalysisSort.entries.forEach { option -> NovaRadioRow(option.title, sort == option) { sort = option; menu = null } }
                }
            }
        }
    }
}

private enum class ReportFilter(val title: String) { all("Tümü"), document("PDF"), spreadsheet("Excel") }

private fun fileSize(bytes: Long): String = if (bytes < 1_000_000) "${maxOf(1, bytes / 1_000)} KB"
    else String.format(java.util.Locale.forLanguageTag("tr-TR"), "%.1f MB", bytes / 1_000_000.0)

/** Analiz Raporları (iOS `NovaAnalysisReportsScreen`): the archive of reports produced from photo analyses. */
@Composable
fun NovaAnalysisReportsScreen(load: suspend (Int) -> Pair<List<NovaAnalysisReportEntry>, Boolean>,
                              download: suspend (NovaAnalysisReportEntry) -> ByteArray, onBack: () -> Unit,
                              onOpenAnalysis: ((String) -> Unit)? = null) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    val coroutines = rememberCoroutineScope()
    var rows by remember { mutableStateOf<List<NovaAnalysisReportEntry>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var query by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf(ReportFilter.all) }
    var reload by remember { mutableIntStateOf(0) }
    var hasMore by remember { mutableStateOf(false) }
    var loadingMore by remember { mutableStateOf(false) }
    var downloading by remember { mutableStateOf<String?>(null) }
    var downloadError by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(reload) {
        error = null
        try { val (page, more) = load(0); rows = page; hasMore = more }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { rows = emptyList(); hasMore = false; error = "Raporlar alınamadı. Bağlantınızı kontrol edip tekrar deneyin." }
    }
    val all = rows.orEmpty()
    val visible = all.filter { row -> row.matches(query) && when (filter) {
        ReportFilter.all -> true; ReportFilter.document -> !row.isSpreadsheet; ReportFilter.spreadsheet -> row.isSpreadsheet } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset)
        .testTag("analysis.reports"), verticalArrangement = Arrangement.spacedBy(11.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaBackButton(onClick = onBack)
            NovaText("Analiz Raporları", Modifier.weight(1f), NovaTypeToken.screenTitle)
            HeaderIconButton("arrow.clockwise", "Listeyi yenile", "analysis.reports.refresh") { reload++ }
        }
        val spreadsheets = all.count { it.isSpreadsheet }
        NovaMetricStrip(listOf(
            NovaMetricStripItem("total", if (rows == null) "—" else "${all.size}", "Dosya", "doc.text", NovaStatus.Neutral),
            NovaMetricStripItem("pdf", if (rows == null) "—" else "${all.size - spreadsheets}", "PDF", "doc.text", NovaStatus.Info),
            NovaMetricStripItem("excel", if (rows == null) "—" else "$spreadsheets", "Excel", "tablecells", NovaStatus.Neutral),
            NovaMetricStripItem("companies", if (rows == null) "—" else "${all.mapNotNull { it.companyName }.toSet().size}", "Firma", "building.2",
                NovaStatus.Neutral)))
        NovaListHint("Oluşturduğunuz PDF ve Excel raporlarını arayıp dosya türüne göre filtreleyin.")
        NovaSearchCapsule(query, "Rapor ara", "analysis.reports.search") { query = it }
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            ReportFilter.entries.forEach { value ->
                NovaChoiceChip(value.title, filter == value, identifier = "analysis.reports.filter.${value.name}", inverse = true) { filter = value }
            }
        }
        NovaListSectionHeading("Raporlar", "${visible.size} rapor")
        when {
            error != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(error!!, style = NovaTypeToken.metaQuiet) }
            rows == null -> NovaLoadingView("Raporlar yükleniyor…")
            visible.isEmpty() -> NovaEmptyState("Henüz analizden rapor oluşturmadınız.",
                "Bir analizin raporunu oluşturarak PDF ve Excel çıktılarını denetimlerde hızlıca bulabilir, firma bazında saklayabilirsiniz.")
            else -> NovaListEntrance(true) {
                Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
                    visible.forEachIndexed { index, row ->
                        NovaCard(Modifier.fillMaxWidth().novaRowEntrance(index).testTag("analysis.reports.row.${row.id.lowercase()}"), padding = 10) {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                Row(Modifier.weight(1f).novaRowPress(enabled = row.analysisId != null) { row.analysisId?.let { onOpenAnalysis?.invoke(it) } },
                                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                                        NovaIcon(if (row.isSpreadsheet) "tablecells" else "doc.text", 17.dp, tint = NovaColorToken.accentInk.color())
                                    }
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                                        NovaText(row.title, style = NovaTypeToken.cardTitle, maxLines = 1)
                                        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                            NovaAnalysisFact("calendar", row.createdOn)
                                            row.fileSize?.let { NovaAnalysisFact("arrow.down.circle", fileSize(it)) }
                                        }
                                        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                            NovaTag("building.2", row.companyName ?: "Firmasız", if (row.companyName == null) NovaStatus.Info else NovaStatus.Neutral)
                                            if (row.methodLabel.isNotEmpty()) NovaTag("slider.horizontal.3", row.methodLabel)
                                        }
                                    }
                                    if (row.analysisId != null) NovaIcon("chevron.right", 12.dp, tint = NovaColorToken.textTertiary.color())
                                }
                                Box(Modifier.size(36.dp).clip(CircleShape).novaRowPress(enabled = downloading == null) {
                                    downloading = row.id
                                    coroutines.launch {
                                        try {
                                            val bytes = download(row)
                                            val name = row.fileName.ifBlank { "ISGADA_Rapor_${row.id.take(8)}.${if (row.isSpreadsheet) "xlsx" else "pdf"}" }
                                            novaShareFile(context, bytes, name, if (row.isSpreadsheet)
                                                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" else "application/pdf")
                                        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                                            downloadError = "Rapor indirilemedi. Lütfen tekrar deneyin."
                                        }
                                        downloading = null
                                    }
                                }.semantics { contentDescription = "Raporu indir" }.testTag("analysis.reports.download.${row.id.lowercase()}"),
                                    contentAlignment = Alignment.Center) {
                                    if (downloading == row.id) NovaSpinner(NovaColorToken.accentInk.color(), size = 16.dp)
                                    else NovaIcon("arrow.down.circle", 18.dp, tint = NovaColorToken.accentInk.color())
                                }
                            }
                        }
                    }
                    if (hasMore && query.isEmpty() && filter == ReportFilter.all) Row(Modifier.fillMaxWidth().heightIn(min = 44.dp)
                        .novaRowPress(enabled = !loadingMore) {
                            loadingMore = true
                            coroutines.launch {
                                try { val (page, more) = load(all.size); rows = all + page; hasMore = more }
                                catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { hasMore = true }
                                loadingMore = false
                            }
                        }.testTag("analysis.reports.more"), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.CenterVertically) {
                        if (loadingMore) NovaSpinner(NovaColorToken.accentInk.color(), size = 14.dp)
                        NovaText("Daha fazla göster", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                    }
                }
            }
        }
    }
    NovaNoticeDialog(downloadError, "Rapor", { downloadError = null })
}
