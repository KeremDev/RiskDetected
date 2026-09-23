package com.riskdetectedan.feature.nova

import android.graphics.Bitmap
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** The closures the analysis detail needs (iOS `NovaAnalysisDetailClient`). */
class NovaAnalysisDetailClient(
    val load: suspend () -> NovaAnalysisDetailData,
    /** The pictures the analysis ran on; missing ones are simply absent. */
    val photos: suspend () -> List<Bitmap>,
    val companies: suspend () -> List<NovaAnalysisCompanyOption>,
    val assign: suspend (String) -> Unit,
    val workplaces: suspend (String) -> List<NovaNonconformityWorkplace>,
    val file: suspend (NovaAnalysisFileRequest) -> NovaFindingOutcome,
    val edit: suspend (NovaAnalysisFindingEdit) -> Unit,
    val remove: suspend (NovaAnalysisItem) -> Unit,
    val react: suspend (NovaAnalysisItem, NovaAnalysisSectionKind, NovaAnalysisReaction) -> Unit,
    /** Returns the file name the report was archived under. */
    val report: suspend (NovaAnalysisReportRequest) -> String,
)

private data class SectionTone(val status: NovaStatus, val symbol: String)

private fun sectionTone(kind: NovaAnalysisSectionKind) = when (kind) {
    NovaAnalysisSectionKind.riskAnalysis -> SectionTone(NovaStatus.Danger, "exclamationmark.triangle")
    NovaAnalysisSectionKind.expertRecommendations -> SectionTone(NovaStatus.Warning, "text.bubble")
    NovaAnalysisSectionKind.trainingRecommendations -> SectionTone(NovaStatus.Info, "graduationcap")
    NovaAnalysisSectionKind.approvedNotebook -> SectionTone(NovaStatus.Neutral, "doc.text")
}

internal fun analysisSectionTitle(kind: NovaAnalysisSectionKind) = when (kind) {
    NovaAnalysisSectionKind.riskAnalysis -> "Risk Analizi"; NovaAnalysisSectionKind.expertRecommendations -> "Uzman Görüşü"
    NovaAnalysisSectionKind.trainingRecommendations -> "Eğitim Önerileri"; NovaAnalysisSectionKind.approvedNotebook -> "Onaylı Defter"
}

/** A small icon-and-text tag (iOS `NovaAnalysisTag`). */
@Composable
internal fun NovaAnalysisTag(symbol: String, text: String, status: NovaStatus = NovaStatus.Neutral) {
    Row(Modifier.clip(CircleShape).background(status.background.color()).padding(horizontal = 8.dp, vertical = 5.dp)
        .semantics { contentDescription = text }, horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 9.dp, tint = status.ink.color())
        NovaText(text, style = NovaTypeToken.micro, color = status.ink.color())
    }
}

/** The two published methods side by side; choosing one changes which score is read, never what is stored. */
@Composable
internal fun NovaAnalysisMethodToggle(method: NovaRiskMethod, modifier: Modifier = Modifier, onChange: (NovaRiskMethod) -> Unit) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaRiskMethod.entries.forEach { value ->
            val on = method == value
            Row(Modifier.weight(1f).heightIn(min = 32.dp).clip(RoundedCornerShape(11.dp))
                .background(if (on) NovaColorToken.statusSuccessBg.color() else NovaColorToken.surface.color())
                .border(if (on) 1.4.dp else 1.dp, if (on) NovaColorToken.accentInk.color() else NovaColorToken.border.color(), RoundedCornerShape(11.dp))
                .novaRowPress { onChange(value) }.padding(vertical = 2.dp).testTag("analysis.detail.method.${value.wire}"),
                horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                if (on) NovaIcon("checkmark", 9.dp, tint = NovaColorToken.accentInk.color())
                NovaText(NovaNonconformityWords.method(value), style = NovaTypeToken.badge,
                    color = if (on) NovaColorToken.accentInk.color() else NovaColorToken.textSecondary.color())
            }
        }
    }
}

@Composable
private fun OutcomeLine(outcome: NovaFindingOutcome) = when (outcome) {
    NovaFindingOutcome.Opened -> NovaAnalysisTag("checkmark.circle", "Uygunsuzluk açıldı", NovaStatus.Success)
    NovaFindingOutcome.AlreadyOpen -> NovaAnalysisTag("clock.arrow.circlepath", "Bu bulgunun uygunsuzluğu zaten vardı")
    is NovaFindingOutcome.Failed -> NovaAnalysisTag("exclamationmark.circle", outcome.message, NovaStatus.Danger)
    is NovaFindingOutcome.Refused -> NovaAnalysisTag("exclamationmark.circle", NovaNonconformityWords.failure(outcome.failure), NovaStatus.Danger)
}

/**
 * Analiz Sonucu (iOS `NovaAnalysisDetailScreen`): summary, the first-priority finding, the sections as tabs, and
 * the finding pages with editing, feedback, filing and the report.
 */
@Composable
fun NovaAnalysisDetailScreen(client: NovaAnalysisDetailClient, onBack: () -> Unit, canWrite: Boolean = true, canEdit: Boolean = true,
                             canReact: Boolean = true, canFileTraining: Boolean = true, canReport: Boolean = true,
                             reportResultIsArchiveName: Boolean = true) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    var data by remember { mutableStateOf<NovaAnalysisDetailData?>(null) }
    var pictures by remember { mutableStateOf<List<Bitmap>>(emptyList()) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var section by remember { mutableStateOf(NovaAnalysisSectionKind.riskAnalysis) }
    var method by remember { mutableStateOf(NovaRiskMethod.fineKinney) }
    var methodChosen by remember { mutableStateOf(false) }
    val outcomes = remember { mutableStateMapOf<String, NovaFindingOutcome>() }
    val reactions = remember { mutableStateMapOf<String, NovaAnalysisReaction>() }
    var inspecting by remember { mutableStateOf<NovaAnalysisItem?>(null) }
    var editing by remember { mutableStateOf<NovaAnalysisItem?>(null) }
    var deleting by remember { mutableStateOf<NovaAnalysisItem?>(null) }
    var preview by remember { mutableStateOf<Bitmap?>(null) }
    var reporting by remember { mutableStateOf(false) }
    var assigning by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    LaunchedEffect(reload) {
        loadError = null; data = null
        try {
            val value = client.load()
            data = value
            // The expert's own method opens the screen; after that the toggle owns the choice.
            if (!methodChosen) method = value.method
            pictures = client.photos()
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
            loadError = "Analiz yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin."
        }
    }
    fun photoFor(item: NovaAnalysisItem): Bitmap? = item.photoIndices.firstOrNull()?.takeIf { it in 1..pictures.size }?.let { pictures[it - 1] }
    fun withReaction(item: NovaAnalysisItem) = reactions[item.id]?.let { item.copy(reaction = it) } ?: item
    val inspected = inspecting
    val current = data
    if (inspected != null && current != null) {
        NovaAnalysisItemDetailScreen(inspected, section, method, photoFor(inspected), current, reactions[inspected.id] ?: inspected.reaction, canWrite,
            canEdit, canReact, section != NovaAnalysisSectionKind.trainingRecommendations || canFileTraining,
            react = { value -> client.react(inspected, section, value); reactions[inspected.id] = value },
            filing = { onDone -> NovaAnalysisFilingScreen(current, inspected, section, method, client, { id, outcome -> outcomes[id] = outcome }, onDone) },
            onBack = { inspecting = null }, onEdit = { inspecting = null; editing = inspected }, onDelete = { inspecting = null; deleting = inspected })
        return
    }
    BackHandler(onBack = onBack)
    val items = current?.section(section)?.items.orEmpty()
    val displayItems = if (section != NovaAnalysisSectionKind.riskAnalysis) items
        else items.sortedWith(compareByDescending<NovaAnalysisItem> { it.value(method) ?: -1.0 }.thenBy { it.ordinal })
    fun react(item: NovaAnalysisItem, value: NovaAnalysisReaction) {
        val previous = reactions[item.id] ?: item.reaction
        reactions[item.id] = value
        coroutines.launch {
            try { client.react(item, section, value) } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                // The answer did not reach the server, so the card must not keep showing it.
                reactions[item.id] = previous; notice = "Geri bildirim kaydedilemedi. Tekrar deneyin."
            }
        }
    }
    Column(Modifier.fillMaxSize().testTag("analysis.detail")) {
        Row(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            NovaBackButton(onClick = onBack)
            NovaText("Analiz Sonucu", style = NovaTypeToken.screenTitle)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when {
                loadError != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        NovaText(loadError!!)
                        NovaCompactActionButton("Tekrar dene", "arrow.clockwise", Modifier.width(IntrinsicSize.Max), identifier = "nova.analysis.retry") { reload++ }
                    }
                }
                current == null -> repeat(4) { index ->
                    Box(Modifier.fillMaxWidth().height(if (index == 0) 82.dp else 104.dp).clip(RoundedCornerShape(16.dp))
                        .background(NovaColorToken.surfaceMuted.color()))
                }
                else -> {
                    SummaryCard(current, pictures, canWrite, onAssign = { assigning = true }, onPreview = { preview = it })
                    ResultOverview(current, method) { inspecting = it }
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        current.sections.filter { it.kind != NovaAnalysisSectionKind.approvedNotebook }.forEach { entry ->
                            val on = section == entry.kind
                            val tone = sectionTone(entry.kind)
                            val ink = if (on) NovaColorToken.onInverse.color() else NovaColorToken.text.color()
                            Row(Modifier.heightIn(min = 38.dp).clip(CircleShape).background(if (on) NovaColorToken.inverse.color() else NovaColorToken.surface.color())
                                .border(1.dp, if (on) NovaColorToken.inverse.color() else NovaColorToken.border.color(), CircleShape)
                                .novaRowPress { section = entry.kind }.padding(horizontal = 11.dp).testTag("analysis.detail.section.${entry.kind.wire}"),
                                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                NovaIcon(tone.symbol, 12.dp, tint = ink)
                                NovaText(analysisSectionTitle(entry.kind), style = NovaTypeToken.meta, color = ink)
                                NovaText("${entry.items.size}", Modifier.clip(CircleShape).background(if (on) NovaColorToken.onInverse.color().copy(alpha = 0.16f)
                                    else tone.status.background.color()).padding(horizontal = 6.dp, vertical = 2.dp), NovaTypeToken.micro,
                                    color = if (on) NovaColorToken.onInverse.color() else tone.status.ink.color())
                            }
                        }
                    }
                    if (items.isEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 14) { NovaText("Bu bölümde kayıt yok.", style = NovaTypeToken.metaQuiet) }
                    else if (section == NovaAnalysisSectionKind.riskAnalysis) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaText("Skorlama", Modifier.weight(1f), NovaTypeToken.metaQuiet)
                            NovaAnalysisMethodToggle(method, Modifier.widthIn(max = 230.dp)) { method = it; methodChosen = true }
                        }
                        displayItems.forEach { item ->
                            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                                FindingCard(withReaction(item), method) { inspecting = item }
                                outcomes[item.id]?.let { OutcomeLine(it) }
                            }
                        }
                    } else displayItems.forEach { item ->
                        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                            AdviceCard(withReaction(item), section) { inspecting = item }
                            outcomes[item.id]?.let { OutcomeLine(it) }
                        }
                    }
                }
            }
        }
        if (current != null) Row(Modifier.fillMaxWidth().background(NovaColorToken.canvas.color().copy(alpha = 0.98f))
            .padding(horizontal = 16.dp).padding(top = 5.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.width(74.dp).height(54.dp).clip(RoundedCornerShape(18.dp)).novaControlBackground(18.dp)
                .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(18.dp)).novaRowPress(onClick = onBack).testTag("analysis.detail.back"),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                NovaIcon("chevron.left", 13.dp)
                NovaText("Geri Dön", style = NovaTypeToken.badge)
            }
            if (canWrite && canReport) Row(Modifier.weight(1f).height(54.dp).clip(RoundedCornerShape(18.dp)).background(NovaColorToken.inverse.color())
                .novaRowPress { reporting = true }.padding(start = 16.dp, end = 8.dp).testTag("analysis.detail.report"),
                verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("doc.text", 15.dp, tint = NovaColorToken.onInverse.color())
                NovaText("Rapor oluştur", Modifier.weight(1f), NovaTypeToken.buttonSm, color = NovaColorToken.onInverse.color(),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                Box(Modifier.size(38.dp), contentAlignment = Alignment.Center) { NovaIcon("paperplane", 13.dp, tint = NovaColorToken.onInverse.color()) }
            }
        }
    }
    val edited = editing
    NovaPopup(edited != null, { editing = null }, identifier = "analysis.edit") {
        if (edited != null && current != null) key(edited.id) {
            NovaAnalysisEditSheet(edited, method, onCancel = { editing = null }) { values ->
                client.edit(values.copy(analysisId = current.analysisId, findingId = edited.id))
                editing = null; reload++
            }
        }
    }
    val removed = deleting
    NovaPopup(removed != null, { deleting = null }, identifier = "analysis.delete") {
        if (removed != null) key(removed.id) {
            NovaAnalysisDeleteSheet(removed, onCancel = { deleting = null }) { client.remove(removed); deleting = null; reload++ }
        }
    }
    NovaPopup(preview != null, { preview = null }, identifier = "analysis.photo") {
        preview?.let { Image(it.asImageBitmap(), "Analiz fotoğrafı", Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)), contentScale = ContentScale.Fit) }
    }
    NovaPopup(reporting, { reporting = false }, identifier = "analysis.report") {
        if (reporting && current != null) NovaAnalysisReportSheet(current, method) { request ->
            val name = client.report(request)
            reporting = false
            notice = if (reportResultIsArchiveName) "Rapor arşive kaydedildi: $name" else name
        }
    }
    NovaPopup(assigning, { assigning = false }, identifier = "analysis.assign") {
        if (assigning) NovaAnalysisCompanySheet(client.companies) { company ->
            client.assign(company); assigning = false; celebrate("Analiz firmaya bağlandı."); reload++
        }
    }
    NovaNoticeDialog(notice, "Analiz", { notice = null })
}

@Composable
private fun SummaryFact(symbol: String, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 10.dp, tint = NovaColorToken.textTertiary.color())
        NovaText(text, style = NovaTypeToken.metaQuiet, color = NovaColorToken.textSecondary.color(), maxLines = 1)
    }
}

@Composable
private fun SummaryCard(data: NovaAnalysisDetailData, pictures: List<Bitmap>, canWrite: Boolean, onAssign: () -> Unit, onPreview: (Bitmap) -> Unit) {
    NovaCard(Modifier.fillMaxWidth(), padding = 11) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                val first = pictures.firstOrNull()
                Box(Modifier.size(54.dp).clip(RoundedCornerShape(12.dp)).background(NovaColorToken.surfaceMuted.color())
                    .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(12.dp))
                    .then(if (first != null) Modifier.novaRowPress { onPreview(first) }.semantics { contentDescription = "Analiz fotoğrafını büyüt" }
                        .testTag("analysis.detail.photo") else Modifier), contentAlignment = Alignment.Center) {
                    if (first != null) {
                        Image(first.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                        if (pictures.size > 1) NovaText("${pictures.size}", Modifier.align(Alignment.BottomEnd).padding(3.dp).clip(CircleShape)
                            .background(NovaColorToken.inverse.color().copy(alpha = 0.8f)).padding(horizontal = 5.dp, vertical = 2.dp), NovaTypeToken.micro,
                            color = NovaColorToken.onInverse.color())
                    } else NovaIcon("photo", 18.dp, tint = NovaColorToken.textTertiary.color())
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    NovaText(NovaAnalysisPresentation.title(data.title), style = NovaTypeToken.cardTitle, maxLines = 2)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        SummaryFact("building.2", data.companyName ?: "Firmasız")
                        if (data.companyName == null && canWrite) Row(Modifier.novaRowPress(onClick = onAssign).testTag("analysis.detail.assign"),
                            horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaIcon("plus.circle", 10.dp, tint = NovaColorToken.accentInk.color())
                            NovaText("Firmaya ata", style = NovaTypeToken.metaQuiet, color = NovaColorToken.accentInk.color())
                        }
                        data.sectorLabel?.let { SummaryFact("square.grid.2x2", it) }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        SummaryFact("calendar", NovaAnalysisPresentation.dateOnly(data.createdOn))
                        if (data.photoCount > 0) SummaryFact("photo", "${data.photoCount} fotoğraf")
                    }
                }
            }
            if (data.isProjectionMissing) NovaText("Bu eski analizde ek öneri bölümleri bulunmuyor; kayıtlı risk bulguları gösteriliyor.",
                style = NovaTypeToken.metaQuiet)
        }
    }
}

@Composable
private fun ResultOverview(data: NovaAnalysisDetailData, method: NovaRiskMethod, onOpen: (NovaAnalysisItem) -> Unit) {
    val risk = data.section(NovaAnalysisSectionKind.riskAnalysis)
    val distribution = risk?.distribution(method).orEmpty().toMap()
    val highest = risk?.highest(method)
    val highestBand = highest?.band(method)
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(NovaColorToken.surface.color())
        .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(16.dp)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.heightIn(min = 54.dp), verticalAlignment = Alignment.CenterVertically) {
            listOf(Triple("${risk?.items?.size ?: 0}", "Bulgu", NovaStatus.Neutral), Triple("${distribution["critical"] ?: 0}", "Kritik", NovaStatus.Danger),
                Triple("${distribution["high"] ?: 0}", "Yüksek", NovaStatus.Warning),
                Triple(highest?.value(method)?.let(NovaNonconformityWords::score) ?: "—", NovaNonconformityWords.method(method),
                    NovaNonconformityWords.tone(highestBand))).forEachIndexed { index, (value, label, status) ->
                if (index > 0) Box(Modifier.width(1.dp).height(28.dp).background(NovaColorToken.hairline.color()))
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(value, style = NovaTypeToken.sectionTitle, color = status.ink.color())
                    NovaText(label, style = NovaTypeToken.micro, color = NovaColorToken.textSecondary.color(), maxLines = 1)
                }
            }
        }
        if (highest != null && highestBand in setOf("critical", "high")) Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
            .background(NovaColorToken.surfaceMuted.color()).border(1.dp, NovaColorToken.hairline.color(), RoundedCornerShape(12.dp))
            .novaRowPress { onOpen(highest) }.padding(11.dp).testTag("analysis.detail.priority"), horizontalArrangement = Arrangement.spacedBy(9.dp),
            verticalAlignment = Alignment.CenterVertically) {
            val ink = NovaNonconformityWords.tone(highestBand).ink.color()
            NovaIcon("exclamationmark.triangle.fill", 15.dp, tint = ink)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaText("Öncelikli bulgu", style = NovaTypeToken.micro, color = ink)
                NovaText(highest.title, style = NovaTypeToken.metaQuiet, maxLines = 2)
            }
            NovaIcon("chevron.right", 11.dp, tint = NovaColorToken.textTertiary.color())
        }
    }
}

@Composable
private fun FindingCard(item: NovaAnalysisItem, method: NovaRiskMethod, onOpen: () -> Unit) {
    val band = item.band(method)
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(NovaColorToken.surface.color())
        .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(16.dp)).novaRowPress(onClick = onOpen).padding(13.dp)
        .testTag("analysis.finding.${item.id.lowercase()}"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Box(Modifier.size(22.dp).clip(CircleShape).background(NovaColorToken.inverse.color()), contentAlignment = Alignment.Center) {
                NovaText("${item.ordinal}", style = NovaTypeToken.badge, color = NovaColorToken.onInverse.color())
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                NovaText(item.title, style = NovaTypeToken.cardTitle)
                if (band != null) Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaStatusPill(NovaNonconformityWords.band(band), NovaNonconformityWords.tone(band))
                    item.value(method)?.let { NovaText("${NovaNonconformityWords.score(it)} puan", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color()) }
                }
            }
            NovaIcon("chevron.right", 11.dp, tint = NovaColorToken.textTertiary.color())
        }
        if (item.body.isNotEmpty()) NovaText(item.body, style = NovaTypeToken.metaQuiet, maxLines = 3)
    }
}

/** One unscored row; it is never painted as if it carried a band. */
@Composable
private fun AdviceCard(item: NovaAnalysisItem, kind: NovaAnalysisSectionKind, onOpen: () -> Unit) {
    val tone = sectionTone(kind)
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(NovaColorToken.surface.color())
        .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(16.dp)).novaRowPress(onClick = onOpen).padding(13.dp)
        .testTag("analysis.advice.${item.id.lowercase()}"), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon(tone.symbol, 13.dp, tint = tone.status.ink.color())
            NovaText((item.category ?: item.audience)?.uppercase(java.util.Locale.forLanguageTag("tr-TR")) ?: "Kayıt #${item.ordinal}",
                Modifier.weight(1f), NovaTypeToken.micro, color = tone.status.ink.color(), maxLines = 1)
            NovaIcon("chevron.right", 11.dp, tint = NovaColorToken.textTertiary.color())
        }
        NovaText(item.title, style = NovaTypeToken.cardTitle, maxLines = 3)
        if (item.audience != null && item.category != null) Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("person.2", 10.dp, tint = NovaColorToken.textTertiary.color())
            NovaText(item.audience.orEmpty(), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color(), maxLines = 1)
        }
        if (item.body.isNotEmpty()) NovaText(item.body, style = NovaTypeToken.metaQuiet, maxLines = 3)
        if (item.durationValue != null && item.durationLabel != null) NovaAnalysisTag("clock", "${item.durationLabel}: ${item.durationValue}")
    }
}

/** A finding is a destination (iOS `NovaAnalysisItemDetailScreen`): photo, title, the full fields, score and feedback. */
@Composable
private fun NovaAnalysisItemDetailScreen(item: NovaAnalysisItem, section: NovaAnalysisSectionKind, method: NovaRiskMethod, photo: Bitmap?,
                                         data: NovaAnalysisDetailData, reaction: NovaAnalysisReaction, canWrite: Boolean, canEdit: Boolean,
                                         canReact: Boolean, canFile: Boolean,
                                         react: suspend (NovaAnalysisReaction) -> Unit, filing: @Composable (onDone: () -> Unit) -> Unit,
                                         onBack: () -> Unit, onEdit: () -> Unit, onDelete: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    var chosen by remember(item.id) { mutableStateOf(reaction) }
    var scoreExpanded by remember { mutableStateOf(false) }
    var feedbackBusy by remember { mutableStateOf(false) }
    var feedbackError by remember { mutableStateOf<String?>(null) }
    var filingOpen by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    if (filingOpen) { filing { filingOpen = false }; return }
    BackHandler(onBack = onBack)
    val meta = listOfNotNull(data.companyName, NovaAnalysisPresentation.title(data.title).ifEmpty { null },
        NovaAnalysisPresentation.dateOnly(data.createdOn).ifEmpty { null }).distinct().joinToString(" · ")
    val blocks = buildList {
        fun add(title: String, symbol: String, text: String?) { text?.trim()?.takeIf { it.isNotEmpty() }?.let { add(Triple(title, symbol, it)) } }
        add("Ne gözlendi?", "eye", item.body)
        if (item.measures.isEmpty()) add("Düzeltici önlem", "checkmark.seal", item.measure)
        else item.measures.forEach { add(if (it.isPreventive) "Önleyici faaliyet" else "Düzeltici önlem", if (it.isPreventive) "shield" else "checkmark.seal", it.text) }
        add("Kök neden", "magnifyingglass", item.rootCause)
        add("Mevzuat ve ek bilgiler", "book", item.references)
        item.durationValue?.let { add(item.durationLabel ?: "Önerilen süre", "clock", listOfNotNull(it, item.durationNote).joinToString("\n")) }
    }
    val score = item.score(method)
    Column(Modifier.fillMaxSize().testTag("analysis.finding.detail")) {
        Row(Modifier.padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            NovaBackButton(Modifier.testTag("analysis.finding.detail.back"), onClick = onBack)
            NovaText("Bulgu Detayı", Modifier.weight(1f), NovaTypeToken.screenTitle)
            if (canWrite && canEdit && section.isScored) Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp))
                .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(14.dp)).novaRowPress { menu = true }
                .semantics { contentDescription = "Bulgu işlemleri" }, contentAlignment = Alignment.Center) { NovaIcon("ellipsis", 15.dp) }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 28.dp)) {
            Box(Modifier.fillMaxWidth().height(if (photo == null) 120.dp else 190.dp).clip(RoundedCornerShape(16.dp)).background(NovaColorToken.surfaceMuted.color()),
                contentAlignment = Alignment.Center) {
                if (photo != null) Image(photo.asImageBitmap(), "Bulguyla ilişkili kaynak fotoğraf", Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                else Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    NovaIcon("photo", 24.dp); NovaText("Kaynak görsel yüklenemedi", style = NovaTypeToken.metaQuiet)
                }
            }
            Column(Modifier.padding(top = 14.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaStatusPill(if (section.isScored) NovaNonconformityWords.band(item.band(method)) else "Uzman görüşü",
                        if (section.isScored) NovaNonconformityWords.tone(item.band(method)) else NovaStatus.Warning)
                    NovaText("Bulgu #${item.ordinal}", style = NovaTypeToken.micro, color = NovaColorToken.textSecondary.color())
                }
                NovaText(item.title, style = NovaTypeToken.sheetTitle)
                if (meta.isNotEmpty()) NovaText(meta, style = NovaTypeToken.metaQuiet, maxLines = 2)
            }
            blocks.forEach { (title, symbol, text) ->
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaDivider(Modifier.padding(top = 16.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon(symbol, 13.dp); NovaText(title, style = NovaTypeToken.bodyStrong)
                    }
                    NovaText(text)
                }
            }
            val value = score?.value
            if (score != null && value != null) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaDivider(Modifier.padding(top = 16.dp))
                val tone = NovaNonconformityWords.tone(score.band)
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(tone.background.color()).novaRowPress { scoreExpanded = !scoreExpanded }
                    .padding(11.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        NovaText("${NovaNonconformityWords.score(value)} · ${NovaNonconformityWords.band(score.band)}", style = NovaTypeToken.cardTitle,
                            color = tone.ink.color())
                        NovaText(NovaNonconformityWords.method(method), style = NovaTypeToken.micro, color = NovaColorToken.textSecondary.color())
                    }
                    NovaText("Skor nasıl oluştu?", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                    NovaIcon(if (scoreExpanded) "chevron.up" else "chevron.down", 10.dp)
                }
                if (scoreExpanded) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    score.factors.forEach { NovaAnalysisTag("number", "${it.label} ${NovaNonconformityWords.score(it.value)}") }
                    if (score.factors.isNotEmpty()) NovaText("= ${NovaNonconformityWords.score(value)}", style = NovaTypeToken.meta)
                }
            }
            if (canWrite && canReact) Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                NovaDivider(Modifier.padding(top = 16.dp))
                NovaText("Bu bulgu faydalı mıydı?", style = NovaTypeToken.label)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(Triple(NovaAnalysisReaction.like, "hand.thumbsup", "Faydalı"), Triple(NovaAnalysisReaction.dislike, "hand.thumbsdown", "Faydalı değil"))
                        .forEach { (value, symbol, label) ->
                            val selected = chosen == value
                            val ink = if (selected) NovaColorToken.accentInk.color() else NovaColorToken.text.color()
                            Row(Modifier.weight(1f).heightIn(min = 42.dp).clip(RoundedCornerShape(12.dp))
                                .background(if (selected) NovaColorToken.statusSuccessBg.color() else NovaColorToken.surface.color())
                                .border(1.dp, if (selected) NovaColorToken.accentInk.color() else NovaColorToken.border.color(), RoundedCornerShape(12.dp))
                                .novaRowPress(enabled = !feedbackBusy) {
                                    val next = if (selected) NovaAnalysisReaction.none else value
                                    feedbackBusy = true; feedbackError = null
                                    coroutines.launch {
                                        try { react(next); chosen = next } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                                            feedbackError = "Geri bildirim kaydedilemedi. Tekrar deneyin."
                                        }
                                        feedbackBusy = false
                                    }
                                }.testTag("analysis.item.${value.name}"), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
                                verticalAlignment = Alignment.CenterVertically) {
                                NovaIcon(if (selected) "$symbol.fill" else symbol, 13.dp, tint = ink)
                                NovaText(label, style = NovaTypeToken.bodyStrong, color = ink)
                            }
                        }
                }
                feedbackError?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
            }
        }
        if (canWrite && canFile && section.isFileable) Box(Modifier.fillMaxWidth().background(NovaColorToken.canvas.color().copy(alpha = 0.98f))
            .padding(horizontal = 16.dp, vertical = 8.dp)) {
            NovaButton("Uygunsuzluk oluştur", { filingOpen = true }, Modifier.testTag("analysis.finding.file"), symbol = "plus.circle")
        }
    }
    NovaPopup(menu, { menu = false }, identifier = "analysis.finding.menu") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaPopupHeading("Bulgu işlemleri", "ellipsis")
            NovaPopupOption("Düzenle", "square.and.pencil", identifier = "analysis.item.edit") { menu = false; onEdit() }
            NovaPopupOption("Sil", "trash", identifier = "analysis.item.delete") { menu = false; onDelete() }
        }
    }
}

/**
 * Uygunsuzluk oluştur (iOS `NovaAnalysisFilingScreen` + `NovaAnalysisFileSheet`): the company (fixed when the analysis
 * already has one), the workplace, the record kind for unscored items and a severity when the band cannot be read.
 */
@Composable
private fun NovaAnalysisFilingScreen(data: NovaAnalysisDetailData, item: NovaAnalysisItem, section: NovaAnalysisSectionKind, method: NovaRiskMethod,
                                     client: NovaAnalysisDetailClient, record: (String, NovaFindingOutcome) -> Unit, onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    var companies by remember { mutableStateOf<List<NovaAnalysisCompanyOption>?>(null) }
    var company by remember { mutableStateOf(data.companyId) }
    var workplaces by remember { mutableStateOf<List<NovaNonconformityWorkplace>?>(null) }
    var workplace by remember { mutableStateOf<String?>(null) }
    var kind by remember { mutableStateOf(NovaNonconformityRecordKind.nonconformity) }
    var severity by remember { mutableStateOf<NovaNonconformitySeverity?>(null) }
    var outcome by remember { mutableStateOf<NovaFindingOutcome?>(null) }
    var running by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        if (data.companyId == null) companies = runCatching { client.companies() }.getOrElse { error = "Firma listesi alınamadı. Tekrar deneyin."; emptyList() }
    }
    LaunchedEffect(company) {
        val chosen = company ?: return@LaunchedEffect
        workplaces = null; workplace = null
        try { val loaded = client.workplaces(chosen); workplaces = loaded; workplace = loaded.singleOrNull()?.id }
        catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { workplaces = emptyList(); error = "İşyeri listesi alınamadı. Tekrar deneyin." }
    }
    val needsSeverity = !section.isScored || item.band(method) == null || item.isUnreadableBand(method)
    val ready = !needsSeverity || severity != null
    BackHandler(enabled = !running, onBack = onClose)
    Column(Modifier.fillMaxSize().testTag("analysis.file")) {
        NovaTaskHeader("Uygunsuzluk oluştur", 1, 1, if (company == null) "Firma seçin" else "Kayıt bilgileri",
            Modifier.padding(horizontal = 18.dp).padding(top = 10.dp), onClose = { if (!running) onClose() })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(11.dp)) {
            if (company == null) {
                NovaText("Kaydın açılacağı firmayı seçin.", style = NovaTypeToken.metaQuiet)
                when {
                    companies == null -> NovaLoadingView("Firmalar yükleniyor…")
                    companies!!.isEmpty() -> NovaEmptyState("Firma yok", "Kayıt açmak için önce bir firma ekleyin.")
                    else -> companies!!.forEach { option ->
                        NovaPopupOption(option.name, "building.2", option.detail, identifier = "analysis.file.company.${option.id}") { company = option.id }
                    }
                }
            } else {
                val name = data.companyName ?: companies?.firstOrNull { it.id == company }?.name.orEmpty()
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).novaControlBackground(14.dp).padding(horizontal = 14.dp, vertical = 4.dp)
                    .heightIn(min = 44.dp), horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("building.2", 16.dp)
                    NovaText(name, Modifier.weight(1f), NovaTypeToken.label, maxLines = 2)
                    if (data.companyId == null && !running) Row(Modifier.heightIn(min = 36.dp).novaRowPress { company = null },
                        horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon("arrow.left.arrow.right", 11.dp); NovaText("Değiştir", style = NovaTypeToken.micro)
                    }
                }
                NovaHelpHint("Analiz kaydı olduğu gibi kalır. Seçtikleriniz için firmada ayrı kayıt açılır.")
                if (!section.isScored) Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    NovaText("Kayıt türü", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
                    NovaSegmentedControl(NovaNonconformityRecordKind.entries.map(NovaNonconformityWords::recordKind), kind.ordinal) {
                        if (!running) kind = NovaNonconformityRecordKind.entries[it]
                    }
                }
                val places = workplaces
                when {
                    places == null -> NovaLoadingView("İşyerleri yükleniyor…")
                    places.isEmpty() -> NovaCard(Modifier.fillMaxWidth(), padding = 14) { NovaText("Bu firmada kayıt açılacak bir işyeri yok.", style = NovaTypeToken.metaQuiet) }
                    places.size > 1 -> NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            NovaText("İşyeri", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
                            places.forEach { place ->
                                NovaRadioRow(place.name, workplace == place.id, identifier = "analysis.file.workplace.${place.id.lowercase()}") {
                                    if (!running) workplace = place.id
                                }
                            }
                        }
                    }
                }
                NovaCard(Modifier.fillMaxWidth(), padding = 13) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        NovaText(item.title, style = NovaTypeToken.cardTitle)
                        if (needsSeverity) {
                            NovaText(if (section.isScored) "Bu bulgunun risk bandı okunamadı. Önem derecesini siz seçin."
                                else "Bu madde skorsuz geliyor. Önem derecesini siz seçin.", style = NovaTypeToken.metaQuiet)
                            OsgbPicker("Önem derecesi", NovaNonconformitySeverity.entries.map { it.name }, severity?.name,
                                "analysis.file.severity.${item.id.lowercase()}", NovaNonconformitySeverity.entries.associate { it.name to NovaNonconformityWords.severity(it) },
                                placeholder = "Önem derecesi seçin") { value -> severity = NovaNonconformitySeverity.valueOf(value) }
                        } else item.band(method)?.let { NovaStatusPill(NovaNonconformityWords.band(it), NovaNonconformityWords.tone(it)) }
                        outcome?.let { OutcomeLine(it) }
                    }
                }
                error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
            }
        }
        if (company != null) Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            val settled = outcome is NovaFindingOutcome.Failed || outcome is NovaFindingOutcome.Refused
            if (settled) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                // No blanket success line: the row above carries its own result.
                NovaText("İşlem bitti. Bulgunun sonucu kendi satırında yazıyor.", style = NovaTypeToken.metaQuiet)
                NovaButton("Listeye dön", onClose, Modifier.testTag("analysis.file.done"), variant = NovaButtonVariant.Surface, symbol = "list.bullet")
            }
            else NovaButton(if (running) "Kaydediliyor…" else "Uygunsuzluk oluştur", {
                val target = workplace ?: return@NovaButton
                running = true
                coroutines.launch {
                    val result = client.file(NovaAnalysisFileRequest(company, item, section, target,
                        if (section.isScored) NovaNonconformityRecordKind.nonconformity else kind, if (section.isScored) item.band(method) else null,
                        severity, if (section.isScored) method else null))
                    outcome = result
                    record(item.id, result)
                    running = false
                    if (result == NovaFindingOutcome.Opened || result == NovaFindingOutcome.AlreadyOpen) {
                        celebrate("Uygunsuzluk kaydı oluşturuldu!")
                        onClose()
                    }
                }
            }, Modifier.testTag("analysis.file.run"), symbol = "checkmark", enabled = !running && workplace != null && ready)
        }
    }
}

/** Editing one scored finding (iOS `NovaAnalysisEditSheet`); an unfinished score is never sent. */
@Composable
internal fun NovaAnalysisEditSheet(item: NovaAnalysisItem, method: NovaRiskMethod, onCancel: () -> Unit, save: suspend (NovaAnalysisFindingEdit) -> Unit) {
    val coroutines = rememberCoroutineScope()
    var title by remember { mutableStateOf(item.title) }
    var category by remember { mutableStateOf(item.category.orEmpty()) }
    var body by remember { mutableStateOf(item.body) }
    var measure by remember { mutableStateOf(item.measure.orEmpty()) }
    var references by remember { mutableStateOf(item.references.orEmpty()) }
    var score by remember { mutableStateOf(NovaRiskScoreInput(method = method)) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        NovaText("Bulguyu düzenle", style = NovaTypeToken.sheetTitle)
        NovaCard(Modifier.fillMaxWidth(), padding = 13) {
            Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                NovaTextField("Başlık", title, { title = it }, identifier = "analysis.edit.title")
                NovaTextField("Kategori", category, { category = it }, identifier = "analysis.edit.category")
                NovaTextField("Açıklama", body, { body = it }, identifier = "analysis.edit.body", multiline = true)
                NovaTextField("Önlem", measure, { measure = it }, identifier = "analysis.edit.measure", multiline = true)
                NovaTextField("Mevzuat", references, { references = it }, identifier = "analysis.edit.references", multiline = true)
            }
        }
        NovaRiskScoreEditor(score, { score = it }, allowsClearing = false)
        NovaText("Değişiklikleriniz bulguya işlenir; skoru yeniden girerseniz bandı sunucu hesaplar.", style = NovaTypeToken.metaQuiet)
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        NovaButton("Değişiklikleri kaydet", {
            busy = true; error = null
            coroutines.launch {
                try {
                    save(NovaAnalysisFindingEdit("", item.id, title, category, body, measure, references,
                        if (score.isComplete) score else NovaRiskScoreInput()))
                } catch (cancelled: CancellationException) { throw cancelled } catch (failure: NovaNonconformityException) {
                    error = NovaNonconformityWords.failure(failure.failure)
                } catch (_: Exception) { error = "Bulgu güncellenemedi. Aynı işlemi tekrar deneyin." }
                busy = false
            }
        }, Modifier.testTag("analysis.item.save"), symbol = "checkmark", enabled = !busy && title.isNotBlank(), loading = busy)
        NovaButton("Vazgeç", onCancel, Modifier.testTag("analysis.item.cancel"), variant = NovaButtonVariant.Surface, symbol = "xmark", enabled = !busy)
    }
}

/** Deleting one finding says what will be lost before the press that does it. */
@Composable
internal fun NovaAnalysisDeleteSheet(item: NovaAnalysisItem, onCancel: () -> Unit, remove: suspend () -> Unit) {
    val coroutines = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        NovaText("Bulguyu sil", style = NovaTypeToken.sheetTitle)
        NovaCard(Modifier.fillMaxWidth(), padding = 13, tint = NovaColorToken.statusDangerBg.color()) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                NovaText(item.title, style = NovaTypeToken.cardTitle, color = NovaColorToken.statusDangerInk.color())
                NovaText("Bu bulgu analizden kalıcı olarak silinecek.", style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color())
            }
        }
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        NovaButton("Evet, sil", {
            busy = true; error = null
            coroutines.launch {
                try { remove() } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                    error = "Bulgu silinemedi. Aynı işlemi tekrar deneyin."
                }
                busy = false
            }
        }, Modifier.testTag("analysis.item.delete.confirm"), variant = NovaButtonVariant.Danger, symbol = "trash", enabled = !busy, loading = busy)
        NovaButton("Vazgeç", onCancel, variant = NovaButtonVariant.Surface, symbol = "xmark", enabled = !busy)
    }
}

/** PDF or Excel under a chosen method, filed against the analysis company when asked (iOS `NovaAnalysisReportSheet`). */
@Composable
private fun NovaAnalysisReportSheet(data: NovaAnalysisDetailData, method: NovaRiskMethod, generate: suspend (NovaAnalysisReportRequest) -> Unit) {
    val coroutines = rememberCoroutineScope()
    var format by remember { mutableStateOf<NovaAnalysisReportFormat?>(NovaAnalysisReportFormat.pdf) }
    var chosen by remember { mutableStateOf(method) }
    var attach by remember { mutableStateOf(true) }
    var running by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(42.dp), contentAlignment = Alignment.Center) { NovaIcon("doc.text", 20.dp, tint = NovaColorToken.accentInk.color()) }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                NovaText("Rapor oluştur", style = NovaTypeToken.sheetTitle)
                NovaText("Rapor arşivinize kaydedilir. Firma seçiliyse Analiz Raporu olarak o firmaya işlenir.", style = NovaTypeToken.metaQuiet)
            }
        }
        listOf(Triple(NovaAnalysisReportFormat.pdf, "doc.text", "Standart Rapor" to "Analizin tüm bölümlerini içeren PDF dökümü."),
            Triple(NovaAnalysisReportFormat.excel, "tablecells", "Risk Analizi Tablosu" to "Bulguları seçtiğiniz metotla hesaplayan Excel tablosu."))
            .forEach { (value, symbol, words) ->
                val on = format == value
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).novaControlBackground(18.dp)
                    .border(if (on) 1.5.dp else 1.dp, if (on) NovaColorToken.accentInk.color() else NovaColorToken.border.color(), RoundedCornerShape(18.dp))
                    .novaRowPress { format = value }.padding(12.dp).testTag("analysis.report.format.${value.name}"), horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                    Box(Modifier.size(42.dp), contentAlignment = Alignment.Center) {
                        NovaIcon(symbol, 17.dp, tint = if (on) NovaColorToken.accentInk.color() else NovaColorToken.textSecondary.color())
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        NovaText(words.first, style = NovaTypeToken.cardTitle); NovaText(words.second, style = NovaTypeToken.metaQuiet)
                    }
                    NovaIcon(if (on) "checkmark.circle.fill" else "circle", 19.dp,
                        tint = if (on) NovaColorToken.accentInk.color() else NovaColorToken.borderStrong.color())
                }
            }
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            NovaText("Risk metodu", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
            NovaAnalysisMethodToggle(chosen) { chosen = it }
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            val name = data.companyName
            if (name != null) NovaCompanyToggleRow("$name firmasına işle", attach, !running) { attach = it }
            else NovaText("Analiz bir firmaya bağlı değil; rapor yalnız arşivinize kaydedilir.", style = NovaTypeToken.metaQuiet)
        }
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        NovaButton(if (format == null) "Rapor türü seçin" else "Oluştur", {
            val chosenFormat = format ?: return@NovaButton
            running = true; error = null
            coroutines.launch {
                try {
                    generate(NovaAnalysisReportRequest(data.analysisId, chosenFormat, chosen, if (attach) data.companyId else null))
                } catch (cancelled: CancellationException) { throw cancelled } catch (failure: Exception) {
                    // The server owns the report quota; its refusal is shown as it is.
                    error = (failure as? NovaAnalysisException)?.message?.takeIf { it.length > 12 } ?: "Rapor oluşturulamadı. Aynı işlemi tekrar deneyin."
                }
                running = false
            }
        }, Modifier.testTag("analysis.report.run"), symbol = "arrow.down.doc", enabled = !running && format != null, loading = running)
    }
}

/** Picks the company an analysis is assigned to, later than the intake step (iOS `NovaAnalysisCompanySheet`). */
@Composable
private fun NovaAnalysisCompanySheet(load: suspend () -> List<NovaAnalysisCompanyOption>, assign: suspend (String) -> Unit) {
    val coroutines = rememberCoroutineScope()
    var companies by remember { mutableStateOf<List<NovaAnalysisCompanyOption>?>(null) }
    var selected by remember { mutableStateOf<String?>(null) }
    var running by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        companies = try { load() } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
            error = "Firma listesi alınamadı. Tekrar deneyin."; emptyList()
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        NovaText("Firmaya ata", style = NovaTypeToken.sheetTitle)
        if (companies == null) NovaLoadingView("Firmalar yükleniyor…")
        else if (companies!!.isEmpty() && error == null) NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            NovaText("Atanacak pilot firma bulunamadı.", style = NovaTypeToken.metaQuiet)
        }
        companies.orEmpty().forEach { company ->
            val on = selected == company.id
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(NovaColorToken.surface.color())
                .border(1.dp, if (on) NovaColorToken.accentInk.color() else androidx.compose.ui.graphics.Color.Transparent, RoundedCornerShape(22.dp))
                .novaRowPress(enabled = !running) { selected = company.id }.padding(14.dp).testTag("analysis.assign.${company.id.lowercase()}"),
                horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon(if (on) "checkmark.circle.fill" else "circle", 18.dp, tint = if (on) NovaColorToken.accentInk.color() else NovaColorToken.borderStrong.color())
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(company.name, style = NovaTypeToken.cardTitle)
                    if (company.detail.isNotEmpty()) NovaText(company.detail, style = NovaTypeToken.metaQuiet)
                }
            }
        }
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        NovaButton("Ata", {
            val company = selected ?: return@NovaButton
            running = true; error = null
            coroutines.launch {
                try { assign(company) } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                    error = "Analiz firmaya bağlanamadı. Tekrar deneyin."
                }
                running = false
            }
        }, Modifier.testTag("analysis.assign.run"), symbol = "checkmark", enabled = !running && selected != null, loading = running)
    }
}
