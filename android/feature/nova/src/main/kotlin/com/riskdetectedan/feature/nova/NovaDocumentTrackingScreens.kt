package com.riskdetectedan.feature.nova

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException

/** What the tracker reads (iOS `NovaDocumentTrackingClient`, read side). */
class NovaDocumentTrackingClient(
    val portfolio: suspend (NovaDocumentQuery) -> NovaDocumentPortfolio,
    val companies: suspend () -> List<NovaCompanyOption>,
    val detail: (suspend (String, String) -> NovaDocumentObligation)? = null,
)

/**
 * The document tracker as the pilot keeps it: read-only "Önceki Evrak Kayıtları" for one company,
 * opened from its follow-up row (iOS `NovaDocumentTrackingScreen` with `canWrite: false` and a
 * locked company). The list is a tally of tracked documents, never a verdict about the company.
 */
@Composable
internal fun NovaDocumentTrackingScreen(client: NovaDocumentTrackingClient, company: String, heading: String, onBack: () -> Unit,
                                       initialRecordId: String? = null) {
    var board by remember { mutableStateOf<NovaDocumentPortfolio?>(null) }
    var companies by remember { mutableStateOf(emptyList<NovaCompanyOption>()) }
    var error by remember { mutableStateOf<String?>(null) }
    var query by remember { mutableStateOf("") }
    var status by remember { mutableStateOf<NovaDocumentStatus?>(null) }
    var chooser by remember { mutableStateOf(false) }
    var shown by remember { mutableIntStateOf(NovaDocumentQuery().limit) }
    var inspecting by remember { mutableStateOf<NovaDocumentObligation?>(null) }
    var loading by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }
    BackHandler(onBack = onBack)
    LaunchedEffect(Unit) { companies = runCatching { client.companies() }.getOrDefault(emptyList()) }
    LaunchedEffect(initialRecordId) {
        if (initialRecordId != null) inspecting = runCatching { client.detail?.invoke(company, initialRecordId) }.getOrNull()
    }
    LaunchedEffect(reload, status, company, shown) {
        error = null; loading = true
        try {
            board = client.portfolio(NovaDocumentQuery(query.trim(), status, company, limit = shown))
        } catch (cancelled: CancellationException) { throw cancelled } catch (failure: NovaDocumentFailure) {
            board = NovaDocumentPortfolio(); error = failure.reason.message
        } catch (_: Exception) {
            board = NovaDocumentPortfolio(); error = "Evrak takibi alınamadı. Bağlantınızı kontrol edip tekrar deneyin."
        }
        loading = false
    }
    val summary = board?.companies?.firstOrNull { it.id == company }
    val selectedName = summary?.name ?: companies.firstOrNull { it.id == company }?.name
    // The server's headline covers the account; the page reads its own company's tally.
    val counts = summary?.counts.orEmpty()
    val trackedHere = NovaDocumentStatus.entries.sumOf { counts[it] ?: 0 }
    NovaPageSurface {
        Column(Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState())
            .padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(11.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaBackButton(onClick = onBack)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(heading, style = NovaTypeToken.screenTitle)
                    selectedName?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                }
            }
            NovaListHint("Firma evraklarının güncel, yaklaşan ve süresi geçmiş kayıtlarını inceleyin.")
            NovaDocumentStatus.entries.chunked(if (novaFontScaleIsAccessibility()) 2 else 4).forEach { chunk ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    chunk.forEach { value ->
                        NovaListStat(value.title, value.symbol, counts[value] ?: 0, Modifier.weight(1f).testTag("document.stat.${value.wire}"),
                            selected = status == value, status = when (value) {
                                NovaDocumentStatus.missing -> NovaStatus.Neutral
                                NovaDocumentStatus.dueSoon -> NovaStatus.Warning
                                NovaDocumentStatus.expired -> NovaStatus.Danger
                                NovaDocumentStatus.valid -> NovaStatus.Success
                            }) { status = if (status == value) null else value; shown = NovaDocumentQuery().limit }
                    }
                    repeat((if (novaFontScaleIsAccessibility()) 2 else 4) - chunk.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            NovaListHint("Bu liste takip ettiğiniz evrakların sayımıdır; firmanın veya bir kişinin uygunluğuna dair karar değildir. " +
                "Sağlık evrakı bu listede tutulmaz ve dosyanın kendisi burada saklanmaz.")
            NovaSearchCapsule(query, "Evrak ara", "document.tracking.search") { query = it }
            LaunchedEffect(query) { kotlinx.coroutines.delay(350); if (board != null) { shown = NovaDocumentQuery().limit; reload++ } }
            NovaChooserButton("Durum", status?.title ?: "Tüm durumlar", "document.tracking.filter.state", open = chooser) {
                chooser = !chooser
            }
            if (chooser) NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm durumlar")) +
                NovaDocumentStatus.entries.map { NovaChooserOption(it.wire, it.title, counts[it] ?: 0, it.symbol) },
                status?.wire, "document.tracking.filter.state.options") {
                status = it?.let(NovaDocumentStatus::of); shown = NovaDocumentQuery().limit; chooser = false
            }
            val shownBoard = board
            shownBoard?.let { NovaListSectionHeading("Evrak Takibi", "${it.rows.size} / ${it.total} kayıt") }
            when {
                error != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(error!!, style = NovaTypeToken.metaQuiet) }
                shownBoard == null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText("Evrak takibi yükleniyor…", style = NovaTypeToken.metaQuiet) }
                shownBoard.rows.isEmpty() -> if (trackedHere == 0) NovaEmptyState("Henüz takip edilen evrak yok",
                    "Modüllere eklediğiniz süreli belgelerin güncel, yaklaşan ve süresi geçen durumlarını burada izleyebilirsiniz.")
                    else NovaEmptyState("Bu filtreye uyan kayıt yok", "Filtreyi değiştirerek diğer evrak takip kayıtlarını görüntüleyebilirsiniz.")
                else -> {
                    shownBoard.rows.forEach { row -> DocumentRow(row) { inspecting = row } }
                    if (shownBoard.hasMore) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                        Row(Modifier.heightIn(min = 40.dp).novaRowPress(enabled = !loading) { shown += NovaDocumentQuery().limit }
                            .testTag("document.tracking.more"), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                            if (loading) NovaText("…", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                            else NovaIcon("chevron.down", 11.dp, tint = NovaColorToken.accentInk.color())
                            NovaText("Daha fazla göster", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                        }
                    }
                }
            }
        }
    }
    val open = inspecting
    NovaPopup(open != null, onDismissRequest = { inspecting = null }, identifier = "document.obligation") {
        if (open != null) DocumentObligationSheet(open)
    }
}

@Composable
private fun DocumentRow(row: NovaDocumentObligation, onClick: () -> Unit) {
    val palette = tone(row.status)
    NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("document.tracking.row.${row.id}"), padding = 11) {
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                Box(Modifier.size(38.dp).clip(RoundedCornerShape(12.dp)).background(palette.background.color()), contentAlignment = Alignment.Center) {
                    NovaIcon(NovaDocumentWords.kindSymbol(row.kindCode), 16.dp, tint = palette.ink.color())
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    NovaText(row.title, style = NovaTypeToken.cardTitle, maxLines = 2)
                    // The kind is only worth a second line when the expert renamed the entry away from it.
                    if (NovaDocumentWords.kind(row.kindCode) != row.title) NovaText(NovaDocumentWords.kind(row.kindCode), style = NovaTypeToken.micro,
                        color = NovaColorToken.textTertiary.color())
                }
                NovaStatusPill(row.status.title, palette, showsDot = false)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                NovaAnalysisTag(if (row.basis == NovaDocumentBasis.legal) "book" else "person", row.basis.title)
                row.latestValidUntil?.let { NovaAnalysisTag("calendar", it, palette) }
            }
        }
    }
}

/** One tracked obligation in full: what it is, who says it is owed and which copies are on file. */
@Composable
private fun DocumentObligationSheet(row: NovaDocumentObligation) {
    val palette = tone(row.status)
    val muted = NovaColorToken.textTertiary.color()
    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(palette.background.color()), contentAlignment = Alignment.Center) {
                NovaIcon(NovaDocumentWords.kindSymbol(row.kindCode), 19.dp, tint = palette.ink.color())
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                NovaText(row.title, style = NovaTypeToken.sheetTitle, maxLines = 2)
                if (NovaDocumentWords.kind(row.kindCode) != row.title) NovaText(NovaDocumentWords.kind(row.kindCode), style = NovaTypeToken.metaQuiet)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaStatusPill(row.status.title, palette)
            row.companyName?.let { NovaAnalysisTag("building.2", it) }
            NovaAnalysisTag(if (row.basis == NovaDocumentBasis.legal) "book" else "person", row.basis.title)
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 11) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                // The basis is the expert's own, so it is attributed to them, not presented as a finding.
                if (row.basis == NovaDocumentBasis.legal && row.legalRef != null) Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText("Uzmanın dayandığı mevzuat", style = NovaTypeToken.micro, color = muted)
                    NovaText(row.legalRef!!, style = NovaTypeToken.meta)
                }
                listOf(
                    listOf(Triple("building.2", "Kapsam", "Tüm firma"),
                        Triple("hourglass", "Geçerlilik", row.validityDays?.let { "$it gün" } ?: "Süresiz")),
                    listOf(Triple("bell", "Uyarı penceresi", "${row.noticeDays} gün"),
                        Triple("person", "Sorumlu", row.responsibleContact ?: "—")),
                ).forEach { pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        pair.forEach { (symbol, label, value) ->
                            Row(Modifier.weight(1f).clip(RoundedCornerShape(11.dp)).background(NovaColorToken.surfaceMuted.color()).padding(8.dp),
                                horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                                NovaIcon(symbol, 11.dp, Modifier.padding(top = 2.dp), tint = muted)
                                Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                                    NovaText(label, style = NovaTypeToken.micro, color = muted)
                                    NovaText(value, style = NovaTypeToken.meta, maxLines = 2)
                                }
                            }
                        }
                    }
                }
                row.note?.takeIf { it.isNotEmpty() }?.let { note ->
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        NovaText("Not", style = NovaTypeToken.micro, color = muted)
                        NovaText(note, style = NovaTypeToken.metaQuiet)
                    }
                }
            }
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 11) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaText("Dosyadaki kopyalar", style = NovaTypeToken.cardTitle)
                // The tracker keeps a reference, never the document itself.
                NovaText("Dosyanın kendisi burada saklanmaz; aslının nerede olduğuna dair kaydınız tutulur.", style = NovaTypeToken.micro, color = muted)
                if (row.copies.isEmpty()) NovaText("Henüz kopya kaydedilmedi.", style = NovaTypeToken.metaQuiet)
                row.copies.forEach { copy ->
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(NovaColorToken.surfaceMuted.color()).padding(9.dp),
                        verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            NovaAnalysisTag("calendar", copy.issuedOn)
                            if (copy.validUntil != null) NovaAnalysisTag("hourglass", copy.validUntil!!) else NovaAnalysisTag("infinity", "Süresiz")
                        }
                        copy.documentNo?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.meta) }
                        copy.locationNote?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                    }
                }
            }
        }
    }
}

private fun tone(status: NovaDocumentStatus) = when (status) {
    NovaDocumentStatus.missing, NovaDocumentStatus.expired -> NovaStatus.Danger
    NovaDocumentStatus.dueSoon -> NovaStatus.Warning
    NovaDocumentStatus.valid -> NovaStatus.Success
}
