package com.riskdetectedan.feature.nova

import android.content.Intent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

/** Risk method and score inputs (iOS `NovaRiskScoreEditor`). */
@Composable
fun NovaRiskScoreEditor(score: NovaRiskScoreInput, onChange: (NovaRiskScoreInput) -> Unit, allowsClearing: Boolean = true) {
    NovaCard(Modifier.fillMaxWidth(), padding = 14) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaText("Risk metodu", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaRiskMethod.entries.forEach { method ->
                    NovaChoiceChip(NovaNonconformityWords.method(method), score.method == method,
                        identifier = "risk.method.${method.wire}") { onChange(score.select(method)) }
                }
                if (allowsClearing && score.method != null) Box(Modifier.heightIn(min = 40.dp)
                    .novaRowPress { onChange(score.select(null)) }.testTag("risk.method.none").padding(horizontal = 12.dp),
                    contentAlignment = Alignment.Center) { NovaText("Skorsuz", style = NovaTypeToken.meta) }
            }
            when (score.method) {
                NovaRiskMethod.fineKinney -> {
                    RiskScale("Olasılık", NovaRiskMethod.probabilityScale, score.probability, "probability") { onChange(score.copy(probability = it)) }
                    RiskScale("Frekans", NovaRiskMethod.frequencyScale, score.frequency, "frequency") { onChange(score.copy(frequency = it)) }
                    RiskScale("Şiddet", NovaRiskMethod.severityScale, score.severity, "severity") { onChange(score.copy(severity = it)) }
                }
                NovaRiskMethod.matrix5x5 -> {
                    RiskMatrix("Olasılık", score.matrixProbability, "probability") { onChange(score.copy(matrixProbability = it)) }
                    RiskMatrix("Şiddet", score.matrixSeverity, "severity") { onChange(score.copy(matrixSeverity = it)) }
                }
                null -> NovaText("Skorlamak için bir metot seçin.", style = NovaTypeToken.metaQuiet)
            }
            val value = score.score
            val band = score.band
            if (value != null && band != null) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaStatusPill(NovaNonconformityWords.band(band.name), NovaNonconformityWords.tone(band.name))
                NovaText("Skor ${NovaNonconformityWords.score(value)} · kaydedilen bandı sunucu hesaplar", style = NovaTypeToken.metaQuiet)
            } else if (score.method != null) NovaText("Skor için tüm değerleri seçin.", style = NovaTypeToken.metaQuiet)
        }
    }
}

@Composable
private fun RiskScale(label: String, values: List<Double>, selected: Double?, id: String, onPick: (Double) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        NovaText(label, style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            values.forEach { value ->
                val text = NovaNonconformityWords.score(value)
                NovaChoiceChip(text, selected == value, identifier = "risk.$id.$text", inverse = true) { onPick(value) }
            }
        }
    }
}

@Composable
private fun RiskMatrix(label: String, selected: Int?, id: String, onPick: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        NovaText(label, style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            NovaRiskMethod.matrixScale.forEach { value ->
                NovaChoiceChip(value.toString(), selected == value, identifier = "risk.$id.$value", inverse = true) { onPick(value) }
            }
        }
    }
}

/** Every nonconformity and improvement the account can see, across companies. */
@Composable
fun NovaNonconformityBoardScreen(load: suspend () -> List<NovaNonconformityEntry>, companies: List<NovaCompanyOption>,
                                 today: String, revision: Any, onOpen: (NovaNonconformityEntry) -> Unit,
                                 onCreate: (() -> Unit)?, onBack: () -> Unit) {
    var entries by remember { mutableStateOf<List<NovaNonconformityEntry>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var filter by remember { mutableStateOf(NovaNonconformityFilter()) }
    var openFilter by remember { mutableStateOf<String?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    LaunchedEffect(reload, revision) {
        error = null
        try { entries = load() } catch (failure: Exception) {
            entries = null
            error = NovaNonconformityWords.message(failure, "Uygunsuzluklar yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
    val all = entries.orEmpty()
    val visible = all.filter { it.matches(filter, today) }
    val overdue = all.count { it.isOverdue(today) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).padding(bottom = novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaBackButton(onClick = onBack)
            NovaText("Uygunsuzluklar", Modifier.weight(1f), NovaTypeToken.screenTitle)
            if (onCreate != null) Row(Modifier.heightIn(min = 40.dp).clip(CircleShape).background(NovaColorToken.accent.color(), CircleShape)
                .novaRowPress(onClick = onCreate).testTag("nonconformity.new").padding(horizontal = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("plus", 14.dp, tint = Color(0xFF111111))
                NovaText("Yeni", style = NovaTypeToken.buttonSm, color = Color(0xFF111111))
            }
        }
        NovaSearchCapsule(filter.query, "Başlık, firma veya işyeri ara", "nonconformity.search") { filter = filter.copy(query = it) }
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            NovaChooserButton("Firma", companies.firstOrNull { it.id == filter.companyId }?.name ?: "Tümü",
                "nonconformity.filter.company", Modifier.weight(1f), open = openFilter == "company") { openFilter = if (openFilter == "company") null else "company" }
            NovaChooserButton("Durum", if (filter.overdueOnly) "Termini geçen" else filter.state?.let { NovaNonconformityWords.state(it.name) } ?: "Tümü",
                "nonconformity.filter.state", Modifier.weight(1f), open = openFilter == "state") { openFilter = if (openFilter == "state") null else "state" }
            NovaChooserButton("Kayıt türü", filter.kind?.let(NovaNonconformityWords::recordKind) ?: "Tümü",
                "nonconformity.filter.kind", Modifier.weight(1f), open = openFilter == "kind") { openFilter = if (openFilter == "kind") null else "kind" }
        }
        val key = openFilter
        AnimatedVisibility(key != null, enter = fadeIn(NovaMotion.easeOut()) + expandVertically(NovaMotion.easeOut(), Alignment.Top),
            exit = fadeOut(NovaMotion.easeOut()) + shrinkVertically(NovaMotion.easeOut(), Alignment.Top)) {
            if (key != null) {
                val allOption = NovaChooserOption(null, "Tümü")
                val options = when (key) {
                    "company" -> listOf(allOption) + companies.map { NovaChooserOption(it.id, it.name) }
                    "state" -> listOf(allOption, NovaChooserOption("overdue", "Termini geçen", count = overdue)) +
                        NovaNonconformityState.entries.map { NovaChooserOption(it.name, NovaNonconformityWords.state(it.name)) }
                    else -> listOf(allOption) + NovaNonconformityRecordKind.entries.map { NovaChooserOption(it.name, NovaNonconformityWords.recordKind(it)) }
                }
                val selection = when (key) {
                    "company" -> filter.companyId
                    "state" -> if (filter.overdueOnly) "overdue" else filter.state?.name
                    else -> filter.kind?.name
                }
                NovaChooserPanel(options, selection, "nonconformity.filter.$key.options") { value ->
                    filter = when (key) {
                        "company" -> filter.copy(companyId = value)
                        "state" -> filter.copy(overdueOnly = value == "overdue", state = value?.let(NovaNonconformityState::of))
                        else -> filter.copy(kind = NovaNonconformityRecordKind.of(value))
                    }
                    openFilter = null
                }
            }
        }
        if (entries != null) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaText("${visible.size} / ${all.size} kayıt", Modifier.weight(1f), NovaTypeToken.metaQuiet)
            if (!filter.isEmpty) Box(Modifier.heightIn(min = 32.dp).novaRowPress { filter = NovaNonconformityFilter() }
                .testTag("nonconformity.filter.reset"), contentAlignment = Alignment.Center) {
                NovaText("Filtreleri temizle", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
            }
            Box(Modifier.size(40.dp).novaRowPress { reload++ }.semantics { contentDescription = "Listeyi yenile" }
                .testTag("nonconformity.refresh"), contentAlignment = Alignment.Center) { NovaIcon("arrow.clockwise", 18.dp) }
        }
        when {
            error != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(error!!, style = NovaTypeToken.metaQuiet) }
            entries == null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText("Kayıtlar yükleniyor", style = NovaTypeToken.metaQuiet) }
            visible.isEmpty() -> NovaEmptyState(
                if (filter.isEmpty) "Henüz uygunsuzluk kaydı yok" else "Bu filtrelerle eşleşen kayıt yok",
                if (filter.isEmpty) "Hızlıca uygunsuzluk ekleyebilir, düzeltme sürecini ve terminleri dijital ortamda takip edebilirsiniz."
                else "Arama veya filtreleri değiştirerek diğer uygunsuzluk kayıtlarını görüntüleyebilirsiniz.")
            else -> NovaListEntrance(visible.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    visible.forEachIndexed { index, entry -> NonconformityCard(entry, today, Modifier.novaRowEntrance(index)) { onOpen(entry) } }
                }
            }
        }
    }
}

@Composable
fun NovaSearchCapsule(value: String, placeholder: String, identifier: String, onChange: (String) -> Unit) {
    val ink = NovaColorToken.text.color()
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).background(NovaColorToken.surface.color(), CircleShape).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaIcon("magnifyingglass", 15.dp, tint = NovaColorToken.textTertiary.color())
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) NovaText(placeholder, color = NovaColorToken.textPlaceholder.color(), maxLines = 1)
            BasicTextField(value, onChange, Modifier.fillMaxWidth().testTag(identifier).semantics { contentDescription = placeholder },
                singleLine = true, textStyle = novaTextStyle(NovaTypeToken.body).copy(color = ink), cursorBrush = SolidColor(ink))
        }
        if (value.isNotEmpty()) Box(Modifier.size(32.dp).novaRowPress { onChange("") }.semantics { contentDescription = "Aramayı temizle" },
            contentAlignment = Alignment.Center) { NovaIcon("xmark.circle", 16.dp, tint = NovaColorToken.textTertiary.color()) }
    }
}

/** Compact by design: a picture, the title, and the rest as icons rather than sentences. */
@Composable
private fun NonconformityCard(entry: NovaNonconformityEntry, today: String, modifier: Modifier, onClick: () -> Unit) {
    NovaCard(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick)
        .testTag("nonconformity.row.${entry.id.lowercase()}"), padding = 10) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(58.dp).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(13.dp)), contentAlignment = Alignment.Center) {
                NovaIcon(if (entry.row.cameFromFinding) "photo" else entry.row.sourceSymbol, 18.dp, tint = NovaColorToken.textTertiary.color())
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                NovaText(entry.row.title, style = NovaTypeToken.cardTitle, maxLines = 2)
                Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaStatusPill(NovaNonconformityWords.band(entry.row.severity), NovaNonconformityWords.tone(entry.row.severity))
                    NovaStatusPill(NovaNonconformityWords.state(entry.row.state), NovaStatus.Neutral, showsDot = false)
                    if (entry.row.kind == NovaNonconformityRecordKind.improvement)
                        NovaIcon("lightbulb", 14.dp, Modifier.semantics { contentDescription = "Geliştirme önerisi" },
                            tint = NovaColorToken.statusInfoInk.color())
                }
                Fact("building.2", entry.companyName)
                Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                    Fact("calendar", entry.row.openedOn)
                    entry.row.dueOn?.let { Fact("clock", it, if (entry.isOverdue(today)) NovaColorToken.statusDangerInk.color() else null) }
                    Fact(entry.row.sourceSymbol, entry.row.sourceTitle)
                }
            }
            NovaIcon("chevron.right", 13.dp, Modifier.padding(top = 3.dp), tint = NovaColorToken.textTertiary.color())
        }
    }
}

@Composable
private fun Fact(symbol: String, text: String, tone: Color? = null) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 12.dp, tint = tone ?: NovaColorToken.textTertiary.color())
        NovaText(text, style = NovaTypeToken.micro, color = tone ?: NovaColorToken.textSecondary.color(), maxLines = 1)
    }
}

private enum class RecordPanel { none, detail, state, action, verify }

/** One record in a popup: read, edit, move, act and verify without a second page. */
@Composable
fun NovaNonconformityRecordSheet(entry: NovaNonconformityEntry, client: NovaRecordClient, canWrite: Boolean) {
    val context = LocalContext.current
    val coroutines = rememberCoroutineScope()
    val busyReporter = LocalNovaPopupBusy.current
    var row by remember { mutableStateOf<NovaNonconformityRow?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var panel by remember { mutableStateOf(RecordPanel.none) }
    var move by remember { mutableStateOf<NovaNonconformityEdge?>(null) }
    var reason by remember { mutableStateOf("") }
    var assignee by remember { mutableStateOf("") }
    var actionText by remember { mutableStateOf("") }
    var actionAssignee by remember { mutableStateOf("") }
    var verifyAccepted by remember { mutableStateOf(true) }
    var verifyNote by remember { mutableStateOf("") }
    var detail by remember { mutableStateOf(NovaNonconformityDetailDraft()) }
    var openingIndex by remember { mutableStateOf<Int?>(null) }
    val current = row ?: entry.row
    val state = NovaNonconformityState.of(current.state) ?: NovaNonconformityState.draft
    val hasAcceptedVerification = current.verifications.orEmpty().any { it.outcome == "accepted" }
    LaunchedEffect(entry.id) {
        try { row = client.load() } catch (failure: Exception) { error = NovaNonconformityWords.message(failure, "Kayıt yüklenemedi. Tekrar deneyin.") }
    }
    fun run(work: suspend () -> Unit) {
        coroutines.launch {
            busy = true; busyReporter(true); error = null
            try { work() } catch (failure: Exception) {
                error = NovaNonconformityWords.message(failure, "Kayıt açılamadı. Bilgileri kontrol edip aynı işlemi tekrar deneyin.")
            }
            busy = false; busyReporter(false)
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            NovaText(current.title, style = NovaTypeToken.sheetTitle)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                NovaStatusPill(NovaNonconformityWords.band(current.severity), NovaNonconformityWords.tone(current.severity))
                NovaStatusPill(NovaNonconformityWords.state(current.state), NovaStatus.Neutral, showsDot = false)
                if (current.kind == NovaNonconformityRecordKind.improvement)
                    NovaStatusPill(NovaNonconformityWords.recordKind(NovaNonconformityRecordKind.improvement), NovaStatus.Info, showsDot = false)
            }
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            val facts = buildList {
                add("building.2" to entry.companyName)
                val place = entry.workplaceName
                if (place != null && novaFold(place) != novaFold(entry.companyName)) add("mappin" to "İşyeri · $place")
                add("calendar" to current.openedOn)
                current.dueOn?.let { add("clock" to it) }
                current.closedOn?.let { add("checkmark.seal" to it) }
                current.assigneeContact?.takeIf { it.isNotEmpty() }?.let { add("person.crop.rectangle" to it) }
                add(current.sourceSymbol to current.sourceTitle)
            }
            facts.chunked(2).forEach { pair ->
                Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                    pair.forEach { (symbol, text) ->
                        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            NovaIcon(symbol, 14.dp, tint = NovaColorToken.textTertiary.color())
                            NovaText(text, style = NovaTypeToken.metaQuiet)
                        }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    NovaText("Kayıt detayı", Modifier.weight(1f), NovaTypeToken.sectionTitle)
                    if (canWrite) Row(Modifier.heightIn(min = 34.dp).novaRowPress {
                        detail = NovaNonconformityDetailDraft.of(current.detail)
                        panel = if (panel == RecordPanel.detail) RecordPanel.none else RecordPanel.detail
                    }.testTag("nonconformity.detail.edit"), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                        val ink = NovaColorToken.accentInk.color()
                        NovaIcon(if (panel == RecordPanel.detail) "xmark" else "square.and.pencil", 13.dp, tint = ink)
                        NovaText(if (panel == RecordPanel.detail) "Vazgeç" else "Düzenle", style = NovaTypeToken.meta, color = ink)
                    }
                }
                val stored = current.detail
                when {
                    panel == RecordPanel.detail -> {
                        NovaTextField("Açıklama", detail.description, { detail = detail.copy(description = it) }, identifier = "record.description", multiline = true)
                        NovaTextField("Önlem", detail.measure, { detail = detail.copy(measure = it) }, identifier = "record.measure", multiline = true)
                        NovaTextField("Mevzuat bilgisi", detail.legislation, { detail = detail.copy(legislation = it) }, identifier = "record.legislation", multiline = true)
                        NovaTextField("Firma sorumlusu", detail.responsible, { detail = detail.copy(responsible = it) }, identifier = "record.responsible")
                        NovaRiskScoreEditor(detail.score, { detail = detail.copy(score = it) })
                        NovaButton("Değişiklikleri kaydet", { run { row = client.saveDetail(detail); panel = RecordPanel.none } },
                            Modifier.testTag("nonconformity.detail.save"), symbol = "checkmark", loading = busy,
                            enabled = !busy && (detail.score.isEmpty || detail.score.isComplete))
                    }
                    stored != null -> {
                        LabelledValue("Açıklama", stored.description)
                        LabelledValue("Önlem", stored.controlMeasure)
                        LabelledValue("Mevzuat bilgisi", stored.legislationRef)
                        LabelledValue("Firma sorumlusu", stored.responsibleContact)
                        val method = NovaRiskMethod.of(stored.riskMethod)
                        val score = stored.riskScore
                        if (method != null && score != null) Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaStatusPill(NovaNonconformityWords.band(stored.riskBand), NovaNonconformityWords.tone(stored.riskBand))
                            NovaText("${NovaNonconformityWords.score(score)} · ${NovaNonconformityWords.method(method)}", style = NovaTypeToken.metaQuiet)
                        }
                    }
                    else -> {
                        NovaHelpHint("Bu kaydın ayrıntıları henüz tamamlanmamış. Düzenle ile gözlemi, alınacak önlemi, sorumluyu ve risk puanını ekleyebilirsiniz.")
                        if (canWrite) NovaButton("Kaydı tamamla", { detail = NovaNonconformityDetailDraft.of(current.detail); panel = RecordPanel.detail },
                            variant = NovaButtonVariant.Surface, symbol = "square.and.pencil")
                    }
                }
            }
        }
        val downloads = current.evidenceDownloads.orEmpty()
        if (downloads.isNotEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaText("Kanıt fotoğrafları", style = NovaTypeToken.sectionTitle)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    downloads.forEachIndexed { index, download ->
                        Column(Modifier.size(64.dp).clip(RoundedCornerShape(12.dp)).background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(12.dp))
                            .novaRowPress(openingIndex == null) {
                                openingIndex = index; error = null
                                coroutines.launch {
                                    try {
                                        val bytes = client.download(download.bucket, download.path)
                                        novaShareFile(context, bytes, download.path.substringAfterLast('/').ifEmpty { "kanit.jpg" }, "image/jpeg")
                                    } catch (_: Exception) { error = "Dosya servisi şu anda kullanılamıyor." }
                                    openingIndex = null
                                }
                            }.testTag("nonconformity.evidence.$index"), horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)) {
                            if (openingIndex == index) NovaSpinner(NovaColorToken.accentInk.color()) else NovaIcon("photo", 18.dp, tint = NovaColorToken.accentInk.color())
                            NovaText("Foto ${index + 1}", style = NovaTypeToken.micro)
                        }
                    }
                }
            }
        }
        if (canWrite) {
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                listOf(Triple(RecordPanel.state, "arrow.triangle.branch", "Durum"), Triple(RecordPanel.action, "hammer", "Aksiyon"),
                    Triple(RecordPanel.verify, "checkmark.shield", "Doğrula")).forEach { (target, symbol, title) ->
                    val on = panel == target
                    val fill by animateFloatAsState(if (on) 1f else 0f, NovaMotion.easeOut(0.14), label = "op")
                    val ink = if (on) NovaColorToken.accentInk.color() else NovaColorToken.textSecondary.color()
                    Column(Modifier.weight(1f).heightIn(min = 54.dp).clip(RoundedCornerShape(14.dp))
                        .background(androidx.compose.ui.graphics.lerp(NovaColorToken.surface.color(), NovaColorToken.statusSuccessBg.color(), fill), RoundedCornerShape(14.dp))
                        .novaRowPress { panel = if (on) RecordPanel.none else target }.testTag("nonconformity.panel.${target.name}"),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically)) {
                        NovaIcon(symbol, 18.dp, tint = ink)
                        NovaText(title, style = NovaTypeToken.micro, color = ink)
                    }
                }
            }
            AnimatedVisibility(panel in setOf(RecordPanel.state, RecordPanel.action, RecordPanel.verify),
                enter = fadeIn(NovaMotion.easeOut()) + expandVertically(NovaMotion.easeOut(), Alignment.Top),
                exit = fadeOut(NovaMotion.easeOut()) + shrinkVertically(NovaMotion.easeOut(), Alignment.Top)) {
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        when (panel) {
                            RecordPanel.state -> {
                                val moves = NovaNonconformityMachine.moves(state)
                                if (moves.isEmpty()) NovaText("Bu kayıt için başka bir durum geçişi yok.", style = NovaTypeToken.metaQuiet)
                                else {
                                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        moves.forEach { edge ->
                                            NovaChoiceChip(NovaNonconformityWords.state(edge.to.name), move?.id == edge.id,
                                                identifier = "nonconformity.move.${edge.to.name}") {
                                                if (edge.requiresVerification && !hasAcceptedVerification) {
                                                    error = "Kapatmadan önce kabul edilmiş bir doğrulama gerekiyor."
                                                } else { error = null; move = edge; reason = ""; assignee = "" }
                                            }
                                        }
                                    }
                                    val edge = move
                                    AnimatedVisibility(edge != null, enter = fadeIn(NovaMotion.easeOut()) + expandVertically(NovaMotion.easeOut(), Alignment.Top),
                                        exit = fadeOut(NovaMotion.easeOut()) + shrinkVertically(NovaMotion.easeOut(), Alignment.Top)) {
                                        if (edge != null) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                            if (edge.requiresAssignee) NovaTextField("Atanan kişi", assignee, { assignee = it }, identifier = "record.assignee")
                                            NovaTextField(if (edge.requiresReason) "Gerekçe *" else "Gerekçe", reason, { reason = it },
                                                identifier = "record.reason", multiline = true)
                                            if (edge.requiresReason) NovaText("Bu geçiş gerekçesiz kaydedilmez; en az beş karakter yazın.",
                                                style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
                                            val ready = !(edge.requiresReason && reason.trim().length < 5) && !(edge.requiresAssignee && assignee.isBlank())
                                            NovaButton("Geçişi kaydet", { run { row = client.transition(edge.to, reason, assignee); move = null; panel = RecordPanel.none } },
                                                Modifier.testTag("nonconformity.move.save"), symbol = "arrow.right", enabled = !busy && ready, loading = busy)
                                        }
                                    }
                                }
                            }
                            RecordPanel.action -> {
                                NovaTextField("Yapılacak iş", actionText, { actionText = it }, identifier = "record.action", multiline = true)
                                NovaTextField("Sorumlu", actionAssignee, { actionAssignee = it }, identifier = "record.action.assignee")
                                NovaText("Aksiyonun sorumlusu bir uygulama kullanıcısı değildir; yalnız kayıtta görünür.",
                                    style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
                                NovaButton("Ekle", { run { row = client.addAction(actionText, actionAssignee); actionText = ""; actionAssignee = ""; panel = RecordPanel.none } },
                                    Modifier.testTag("nonconformity.action.add"), symbol = "plus", enabled = !busy && actionText.isNotBlank(), loading = busy)
                            }
                            RecordPanel.verify -> {
                                NovaSegmented(listOf(true to "Kabul", false to "Ret"), verifyAccepted, { verifyAccepted = it }, identifier = "record.verify.outcome")
                                NovaTextField("Not", verifyNote, { verifyNote = it }, identifier = "record.verify.note", multiline = true)
                                NovaText("Reddedilen doğrulama kaydı kapatmaz; yeni bir döngü başlatır.",
                                    style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
                                NovaButton("Doğrula", { run { row = client.verify(verifyAccepted, verifyNote); verifyNote = ""; panel = RecordPanel.none } },
                                    Modifier.testTag("nonconformity.verify"), symbol = "checkmark.shield", enabled = !busy, loading = busy)
                            }
                            else -> Unit
                        }
                    }
                }
            }
        }
        val actions = current.actions.orEmpty()
        val records = current.verifications.orEmpty()
        if (actions.isNotEmpty() || records.isNotEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 12) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (actions.isNotEmpty()) {
                    NovaText("Düzeltici aksiyonlar", style = NovaTypeToken.sectionTitle)
                    actions.forEach { action ->
                        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                            NovaIcon("hammer", 13.dp, tint = NovaColorToken.textTertiary.color())
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                NovaText(action.description, style = NovaTypeToken.metaQuiet)
                                listOfNotNull(action.assignee, action.dueOn).firstOrNull()?.let {
                                    NovaText(it, style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
                                }
                            }
                        }
                    }
                }
                if (records.isNotEmpty()) {
                    NovaText("Uzman doğrulaması", style = NovaTypeToken.sectionTitle)
                    records.forEach { record ->
                        Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaStatusPill(if (record.outcome == "accepted") "Kabul" else "Ret",
                                if (record.outcome == "accepted") NovaStatus.Success else NovaStatus.Danger)
                            NovaText(record.verifiedOn, style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
                        }
                    }
                }
            }
        }
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
    }
}

@Composable
private fun LabelledValue(label: String, text: String?) {
    if (text.isNullOrEmpty()) return
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        NovaText(label, style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
        NovaText(text, style = NovaTypeToken.metaQuiet)
    }
}

/** Writes bytes to the app cache and hands them to the system share/open sheet. */
fun novaShareFile(context: android.content.Context, bytes: ByteArray, fileName: String, mime: String) {
    val directory = File(context.cacheDir, "nova/${UUID.randomUUID()}").apply { mkdirs() }
    val file = File(directory, fileName.replace('/', '_'))
    file.writeBytes(bytes)
    val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
    val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(intent, fileName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}
