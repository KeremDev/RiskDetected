package com.riskdetectedan.feature.nova

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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.flow.Flow
import java.time.LocalDate
import java.time.ZoneId

/** The statistics page's calls bound to one identity; the design preview supplies its own. */
interface NovaStatisticsClient {
    suspend fun load(company: String?, months: Int): NovaStatisticsSnapshot
    suspend fun visits(company: String?, from: String, to: String): NovaVisitSummary
    suspend fun followup(company: String?): NovaFollowupPage
    suspend fun tracking(company: String?): NovaModuleTrackingSnapshot
    /** This account's record changes (iOS `isgada.records.changed`). */
    val changes: Flow<Unit>
}

class NovaServiceStatisticsClient(private val statistics: NovaStatisticsService, private val process: NovaProcessService,
                                  private val followups: NovaFollowupService, private val identity: IsgWorkspaceIdentity,
                                  override val changes: Flow<Unit>) : NovaStatisticsClient {
    override suspend fun load(company: String?, months: Int) = statistics.load(identity, company, months)
    override suspend fun visits(company: String?, from: String, to: String) = process.visitSummary(identity, company, from, to)
    override suspend fun followup(company: String?) = followups.load(identity, company)
    override suspend fun tracking(company: String?) = statistics.tracking(identity, company)
}

/** Opens one tracked module page (iOS `NovaTrackedModuleDestination`). */
typealias NovaTrackedModuleOpener = @Composable (kind: String, company: String?, onBack: () -> Unit) -> Unit

private sealed interface StatisticsPage {
    data class Tracked(val kind: String) : StatisticsPage
    data object Followup : StatisticsPage
}

/** İstatistikler (iOS `NovaStatisticsScreen`): current stock and period activity under separate headings. */
@Composable
fun NovaStatisticsScreen(client: NovaStatisticsClient, onBack: () -> Unit, onNavigate: (NovaDestination) -> Unit,
                         openTracked: NovaTrackedModuleOpener, openFollowup: @Composable (company: String?, onBack: () -> Unit) -> Unit) {
    var company by remember { mutableStateOf<String?>(null) }
    var months by remember { mutableIntStateOf(6) }
    var snapshot by remember { mutableStateOf<NovaStatisticsSnapshot?>(null) }
    var options by remember { mutableStateOf<List<NovaStatisticsSnapshot.Company>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf(false) }
    var revision by remember { mutableIntStateOf(0) }
    var page by remember { mutableStateOf<StatisticsPage?>(null) }
    val open = page
    if (open != null) {
        val close: () -> Unit = { page = null; revision++ }
        BackHandler(onBack = close)
        when (open) {
            is StatisticsPage.Tracked -> openTracked(open.kind, company, close)
            StatisticsPage.Followup -> openFollowup(company, close)
        }
        return
    }
    LaunchedEffect(client) { client.changes.collect { revision++ } }
    LaunchedEffect(company, months, revision) {
        loading = true; failed = false; snapshot = null
        try {
            val result = client.load(company, months)
            snapshot = result; options = result.companies
        } catch (_: Exception) { failed = true }
        loading = false
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset)
        .testTag("nova.statistics.screen"), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            NovaPageHeading("İstatistikler", "Çalışmalarınızın güncel görünümü", modifier = Modifier.weight(1f), onBack = onBack)
            Box(Modifier.size(44.dp).clip(CircleShape).novaRowPress(enabled = !loading) { revision++ }
                .semantics { contentDescription = "İstatistikleri yenile" }, contentAlignment = Alignment.Center) { NovaIcon("arrow.clockwise", 16.dp) }
        }
        NovaFilterField("Firma", listOf(NovaChooserOption(null, "Tüm firmalar")) + options.map { NovaChooserOption(it.id, it.name) }, company,
            "nova.statistics.company") { company = it }
        NovaFilterField("Dönem", listOf("1" to "Bu ay", "3" to "3 ay", "6" to "6 ay", "12" to "12 ay").map { NovaChooserOption(it.first, it.second) },
            months.toString(), "nova.statistics.period") { picked -> picked?.toIntOrNull()?.let { months = it } }
        VisitPeriodCard(client, company, months, revision)
        FollowupSummaryCard(client, company, revision) { page = StatisticsPage.Followup }
        NovaModuleTrackingCard(client::tracking, company, revision) { page = StatisticsPage.Tracked(it) }
        val data = snapshot
        when {
            loading -> Box(Modifier.fillMaxWidth().heightIn(min = 320.dp), contentAlignment = Alignment.Center) { NovaLoadingView("İstatistikler hazırlanıyor…") }
            failed || data == null -> NovaCard(Modifier.fillMaxWidth(), padding = 20) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon("wifi.exclamationmark", 16.dp); NovaText("Veriler alınamadı", style = NovaTypeToken.bodyStrong)
                    }
                    NovaText("Bağlantınızı kontrol edip yeniden deneyin. Önceki filtreye ait sayılar gösterilmiyor.", style = NovaTypeToken.metaQuiet)
                    NovaButton("Tekrar dene", { revision++ }, symbol = "arrow.clockwise")
                }
            }
            else -> {
                StatisticsBody(data, onNavigate) { company = it }
                NovaText("Aktif firmalarınız ve firma seçilmediğinde firmasız fotoğraf analizleri kapsanır. Arşivlenmiş firmalar dahil değildir.",
                    style = NovaTypeToken.metaQuiet)
                NovaText("Güncelleme: ${NovaStatisticsSnapshot.dayLabel(data.today)} · İstanbul", style = NovaTypeToken.micro)
            }
        }
    }
}

@Composable
private fun SectionTitle(title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        NovaText(title, style = NovaTypeToken.sectionTitle)
        NovaText(subtitle, style = NovaTypeToken.metaQuiet)
    }
}

@Composable
private fun Distribution(title: String, count: Int, total: Int, tone: NovaColorToken) {
    Column(Modifier.semantics { contentDescription = "$title: $count" }, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row {
            NovaText(title, Modifier.weight(1f), NovaTypeToken.meta)
            NovaText(count.toString(), style = NovaTypeToken.bodyStrong)
        }
        Box(Modifier.fillMaxWidth().height(5.dp).background(NovaColorToken.surfaceMuted.color(), CircleShape)) {
            Box(Modifier.fillMaxWidth(minOf(1f, count.toFloat() / maxOf(1, total))).fillMaxHeight().background(tone.color(), CircleShape))
        }
    }
}

@Composable
private fun StatisticsLink(title: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().novaRowPress(onClick = onClick).padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaText(title, Modifier.weight(1f), NovaTypeToken.buttonSm, color = NovaColorToken.accentInk.color())
        NovaIcon("arrow.right", 13.dp, tint = NovaColorToken.accentInk.color())
    }
}

@Composable
private fun StatisticsBody(data: NovaStatisticsSnapshot, onNavigate: (NovaDestination) -> Unit, onCompany: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionTitle("Portföyünüz", "Bugünkü kayıtlar · dönem filtresinden bağımsız")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaListStat("Aktif firma", "building.2", data.companyCount.toString(), Modifier.weight(1f))
            NovaListStat("Personel", "person.2", data.personnel.toString(), Modifier.weight(1f))
            NovaListStat("İşyeri", "building", data.workplaces.toString(), Modifier.weight(1f))
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionTitle("Seçili dönemde", "${NovaStatisticsSnapshot.dayLabel(data.fromDay)} – ${NovaStatisticsSnapshot.dayLabel(data.today)}")
        listOf(
            listOf(Triple("Fotoğraf analizi", data.analyses, "viewfinder") to NovaDestination.analyses,
                Triple("Eğitim", data.trainings, "graduationcap") to NovaDestination.training),
            listOf(Triple("Eğitim alan kişi", data.trainedPeople, "person.2") to NovaDestination.training,
                Triple("Eğitim kaydı", data.trainingEnrollments, "person.crop.rectangle.stack") to NovaDestination.training),
        ).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pair.forEach { (metric, destination) ->
                    NovaListStat(metric.first, metric.third, metric.second.toString(), Modifier.weight(1f)
                        .semantics { contentDescription = "${metric.first}: ${metric.second}. Tüm kayıtları aç" }) { onNavigate(destination) }
                }
            }
        }
        NovaText("Aynı eğitimdeki farklı firmalar eğitim sayısını artırmaz. Bir kişi farklı eğitimlerde birden fazla kişi × eğitim kaydı oluşturabilir.",
            style = NovaTypeToken.metaQuiet)
    }
    MonthlyActivity(data)
    NovaCard(Modifier.fillMaxWidth(), padding = 18) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            SectionTitle("Uygunsuzluklar", "Bugünkü açık kayıtların durumu")
            val findings = data.findings
            if (findings == null) Unavailable("Uygunsuzluk istatistikleri bu hesapta henüz kullanılamıyor.")
            else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaListStat("Açık", "exclamationmark.circle", findings.open.toString(), Modifier.weight(1f))
                    NovaListStat("Gecikmiş", "clock.badge.exclamationmark", findings.overdue.toString(), Modifier.weight(1f))
                    NovaListStat("Doğrulamada", "checkmark.circle.badge.questionmark", findings.pending.toString(), Modifier.weight(1f))
                }
                NovaDivider()
                listOf(Triple("critical", "Kritik", NovaColorToken.statusDangerInk), Triple("high", "Yüksek", NovaColorToken.statusWarningInk),
                    Triple("medium", "Orta", NovaColorToken.statusInfoInk), Triple("low", "Düşük", NovaColorToken.accentInk)).forEach { (key, title, tone) ->
                    Distribution(title, findings.severity[key] ?: 0, findings.open, tone)
                }
                NovaText("Seçili dönemde ${findings.opened} kayıt açıldı; bugün kapalı olan ${findings.closed} kayıt bu dönemde kapatıldı. " +
                    "İyileştirme önerileri dahil değildir.", style = NovaTypeToken.metaQuiet)
                StatisticsLink("Tüm uygunsuzlukları aç") { onNavigate(NovaDestination.findings) }
            }
        }
    }
    NovaCard(Modifier.fillMaxWidth(), padding = 18) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            SectionTitle("Evrak durumu", "Takip edilen evrakların güncel durumu")
            val documents = data.documents
            if (documents == null) Unavailable("Evrak istatistikleri bu hesapta henüz kullanılamıyor.")
            else {
                val total = data.documentTotal ?: 0
                Distribution("Geçerli", documents["valid"] ?: 0, total, NovaColorToken.accentInk)
                Distribution("Süresi yaklaşıyor", documents["due_soon"] ?: 0, total, NovaColorToken.statusWarningInk)
                Distribution("Süresi dolmuş", documents["expired"] ?: 0, total, NovaColorToken.statusDangerInk)
                Distribution("Eksik", documents["missing"] ?: 0, total, NovaColorToken.statusNeutralInk)
                if (total == 0) NovaText("Henüz takibe alınmış evrak yok.", style = NovaTypeToken.metaQuiet)
                StatisticsLink("Evrak takibini aç") { onNavigate(NovaDestination.documentChecklist) }
            }
        }
    }
    NovaCard(Modifier.fillMaxWidth(), padding = 18) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            SectionTitle("Firma dağılımı", "İstatistiklerini filtrelemek için firma seçin")
            if (data.selectedCompanies.isEmpty()) NovaText("Henüz aktif firma yok.", style = NovaTypeToken.metaQuiet)
            data.selectedCompanies.forEach { item ->
                Row(Modifier.fillMaxWidth().novaRowPress { onCompany(item.id) }.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("building.2", 15.dp, tint = NovaColorToken.accentInk.color())
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        NovaText(item.name, style = NovaTypeToken.bodyStrong)
                        NovaText("${item.personnel} personel · ${item.workplaces} işyeri", style = NovaTypeToken.metaQuiet)
                    }
                    NovaIcon("chevron.right", 11.dp, tint = NovaColorToken.textSecondary.color())
                }
            }
            StatisticsLink("Firmaları aç") { onNavigate(NovaDestination.companies) }
        }
    }
}

@Composable
private fun Unavailable(text: String) {
    Row(Modifier.padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon("info.circle", 14.dp, tint = NovaColorToken.textSecondary.color())
        NovaText(text, style = NovaTypeToken.metaQuiet)
    }
}

/** Monthly bars for analyses or trainings; a tap shows that month's total. */
@Composable
private fun MonthlyActivity(data: NovaStatisticsSnapshot) {
    var trainings by remember { mutableStateOf(false) }
    var selected by remember(data) { mutableStateOf<String?>(null) }
    val maximum = maxOf(1, data.series.maxOfOrNull { if (trainings) it.trainings else it.analyses } ?: 1)
    NovaCard(Modifier.fillMaxWidth(), padding = 18) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            SectionTitle("Aylık hareket", "Bir aya dokunarak toplamını görün")
            NovaSegmentedControl(listOf("Analizler", "Eğitimler"), if (trainings) 1 else 0) { trainings = it == 1 }
            BoxWithConstraints(Modifier.fillMaxWidth().testTag("nova.statistics.chart")) {
                val width = maxOf(maxWidth, (data.months * 52 - 8).dp)
                Row(Modifier.horizontalScroll(rememberScrollState()).width(width).height(148.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.Bottom) {
                    data.series.forEach { item ->
                        val value = if (trainings) item.trainings else item.analyses
                        val tone = if (value == 0) NovaColorToken.surfaceMuted.color()
                            else (if (trainings) NovaColorToken.accentInk else NovaColorToken.statusInfoInk).color()
                                .copy(alpha = if (selected == null || selected == item.month) 1f else 0.35f)
                        Column(Modifier.weight(1f).fillMaxHeight().novaRowPress { selected = item.month }
                            .semantics { contentDescription = "${item.label} ${item.month.take(4)}, $value ${if (trainings) "eğitim" else "analiz"}" },
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.Bottom)) {
                            NovaSizedText(value.toString(), 10f, FontWeight.SemiBold, NovaColorToken.textSecondary.color(), maxLines = 1)
                            Box(Modifier.fillMaxWidth().height(maxOf(3f, 100f * value / maximum).dp).clip(RoundedCornerShape(5.dp)).background(tone))
                            NovaSizedText(item.label, 11f, FontWeight.Normal, NovaColorToken.textSecondary.color(), maxLines = 1)
                        }
                    }
                }
            }
            val item = data.series.firstOrNull { it.month == selected }
            if (item != null) NovaText("${item.label} ${item.month.take(4)} · ${if (trainings) item.trainings else item.analyses} ${if (trainings) "eğitim" else "analiz"}",
                style = NovaTypeToken.bodyStrong)
            else NovaText(if ((if (trainings) data.trainings else data.analyses) == 0) "Bu dönemde henüz kayıt yok."
                else "Aylık toplamlar, tamamlanan kayıtlardan hesaplanır.", style = NovaTypeToken.metaQuiet)
        }
    }
}

/** Visits in the selected period (iOS `NovaVisitPeriodCard`), from the first day of the earliest month to today. */
@Composable
private fun VisitPeriodCard(client: NovaStatisticsClient, company: String?, months: Int, revision: Int) {
    var summary by remember { mutableStateOf<NovaVisitSummary?>(null) }
    var failed by remember { mutableStateOf(false) }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(company, months, revision, retry) {
        summary = null; failed = false
        val today = LocalDate.now(ZoneId.of("Europe/Istanbul"))
        val from = today.withDayOfMonth(1).minusMonths((months - 1).toLong())
        try { summary = client.visits(company, from.toString(), today.toString()) } catch (_: Exception) { failed = true }
    }
    NovaCard(Modifier.fillMaxWidth(), padding = 14) {
        Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("figure.walk", 15.dp); NovaText("Dönemdeki ziyaretler", style = NovaTypeToken.cardTitle)
            }
            val shown = summary
            when {
                shown != null -> {
                    Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                        NovaText("${shown.visits} ziyaret", style = NovaTypeToken.label)
                        NovaText(shown.recordedMinutes?.let { "${it / 60} sa ${it % 60} dk" } ?: "Süre belirtilmedi", style = NovaTypeToken.label)
                    }
                    NovaText("${shown.timedVisits} ziyaretin süresi kayıtlı. Tarih aralığı üstteki dönem seçimine göre hesaplanır.", style = NovaTypeToken.meta)
                }
                failed -> NovaText("Ziyaret özetini yeniden yükle", Modifier.novaRowPress { retry++ }, NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                else -> NovaSpinner(NovaColorToken.text.color(), size = 18.dp)
            }
        }
    }
}

/** Document dates at a glance (iOS `NovaFollowupSummaryCard`); opens Evrak Takibi. */
@Composable
private fun FollowupSummaryCard(client: NovaStatisticsClient, company: String?, revision: Int, onOpen: () -> Unit) {
    var page by remember { mutableStateOf<NovaFollowupPage?>(null) }
    LaunchedEffect(company, revision) { page = runCatching { client.followup(company) }.getOrNull() }
    NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onOpen).testTag("nova.statistics.followup"), padding = 14) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("doc.badge.clock", 15.dp); NovaText("Evrak süreleri", style = NovaTypeToken.cardTitle)
            }
            val shown = page
            NovaText(if (shown != null) "${shown.current} güncel · ${shown.soon} yaklaşıyor · ${shown.expired} süresi doldu" else "Evrak ve belge sürelerini aç",
                style = NovaTypeToken.meta)
        }
    }
}

/** Süreçler ve Takip (iOS `NovaModuleTrackingCard`): record counts per module, no legal score. */
@Composable
fun NovaModuleTrackingCard(load: suspend (String?) -> NovaModuleTrackingSnapshot, company: String?, revision: Int, onOpen: (String) -> Unit) {
    var snapshot by remember { mutableStateOf<NovaModuleTrackingSnapshot?>(null) }
    var failed by remember { mutableStateOf(false) }
    var retry by remember { mutableIntStateOf(0) }
    var expanded by remember { mutableStateOf(false) }
    LaunchedEffect(company, revision, retry) {
        snapshot = null; failed = false
        try { snapshot = load(company) } catch (_: Exception) { failed = true }
    }
    NovaCard(Modifier.fillMaxWidth(), padding = 16) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                NovaText("Süreçler ve Takip", Modifier.weight(1f), NovaTypeToken.cardTitle)
                Box(Modifier.size(44.dp).clip(CircleShape).novaRowPress { retry++ }.semantics { contentDescription = "Süreç özetini yenile" },
                    contentAlignment = Alignment.Center) { NovaIcon("arrow.clockwise", 15.dp) }
            }
            val shown = snapshot
            when {
                failed -> NovaText("Süreç özeti alınamadı. Yenileyerek tekrar deneyin.")
                shown == null -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { NovaSpinner(NovaColorToken.text.color(), size = 20.dp) }
                shown.rows.isEmpty() -> NovaText("Takip için önce firma ekleyin.")
                else -> {
                    // KKD zimmet is moving to its own Formlar module; it stays out of this list until then.
                    val summaries = shown.summaries.filter { it.id != "ppe" }
                    summaries.take(if (expanded) summaries.size else 4).forEach { row ->
                        Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).novaRowPress(enabled = row.available) { onOpen(row.route) }
                            .testTag("nova.tracking.${row.id}"), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            NovaIcon(row.symbol, 18.dp, Modifier.width(22.dp))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                NovaText(row.title, style = NovaTypeToken.bodyStrong)
                                if (row.available) {
                                    trackingSummary(row)?.let { NovaText(it, style = NovaTypeToken.meta) }
                                    row.nextOn?.let { NovaText("Sonraki tarih: " + NovaStatisticsSnapshot.dayLabel(it), style = NovaTypeToken.meta) }
                                } else NovaText("Bu modül şu anda kullanılamıyor", style = NovaTypeToken.meta)
                            }
                            NovaText(if (row.available) row.total.toString() else "—", style = NovaTypeToken.bodyStrong)
                            NovaIcon("chevron.right", 11.dp, Modifier.padding(top = 4.dp))
                        }
                    }
                    Box(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress { expanded = !expanded }, contentAlignment = Alignment.Center) {
                        NovaText(if (expanded) "Daha az göster" else "Tüm süreçleri göster", style = NovaTypeToken.buttonSm)
                    }
                    NovaText("Kayıt sayıları · Yaklaşan: 30 gün · " + NovaStatisticsSnapshot.dayLabel(shown.today), style = NovaTypeToken.micro)
                }
            }
        }
    }
}

/** Nothing to say when nothing needs attention: the title and count already carry that. */
private fun trackingSummary(row: NovaModuleTrackingSnapshot.Summary): String? {
    val parts = buildList {
        if (row.pending > 0) add("${row.pending} bekleyen")
        if (row.overdue > 0) add("${row.overdue} tarihi geçmiş")
        if (row.upcoming > 0) add("${row.upcoming} yaklaşan")
        if (row.review > 0) add("${row.review} süre bilgisi eksik")
    }
    return if (parts.isNotEmpty()) parts.joinToString(" · ") else if (row.total == 0) null else "Kayıtları görüntüle"
}
