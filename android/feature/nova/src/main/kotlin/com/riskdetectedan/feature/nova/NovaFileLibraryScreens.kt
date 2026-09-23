package com.riskdetectedan.feature.nova

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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** Opens the module record a followup row or file link points at, as a full page with its own back. */
typealias NovaRecordOpener = @Composable (NovaFollowupPage.Row, () -> Unit) -> Unit

/**
 * Dosyalarım (iOS `NovaFileLibraryScreen`): personal and company files in one
 * archive, narrowed to a company and a heading on request.
 */
@Composable
fun NovaFileLibraryScreen(client: NovaFileClient, companiesSource: suspend () -> List<NovaCompanyOption>, canWrite: Boolean, onBack: () -> Unit,
                          sources: (suspend (NovaFileEntry) -> List<NovaFollowupPage.Row>)? = null, openSource: NovaRecordOpener? = null,
                          initialCompany: String? = null, initialCategories: List<String>? = null, headingOverride: String? = null,
                          startInAddMode: Boolean = false) {
    var board by remember { mutableStateOf<NovaFileLibraryPage?>(null) }
    var catalogue by remember { mutableStateOf<NovaFileLibraryService.Catalogue?>(null) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var query by remember { mutableStateOf("") }
    var group by remember { mutableStateOf<NovaFileGroup?>(null) }
    var category by remember { mutableStateOf<String?>(null) }
    var company by remember { mutableStateOf(initialCompany) }
    var shown by remember { mutableIntStateOf(10) }
    var inspecting by remember { mutableStateOf<NovaFileEntry?>(null) }
    var adding by remember { mutableStateOf(startInAddMode) }
    var loading by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }
    var chooser by remember { mutableStateOf<String?>(null) }
    var openedSource by remember { mutableStateOf<NovaFollowupPage.Row?>(null) }
    val selectedName = board?.companies?.firstOrNull { it.id == company }?.name ?: companies.firstOrNull { it.id == company }?.name
    // The counters follow what the page shows: the heading, the company, otherwise the account.
    val visibleCounts = board?.let { page ->
        initialCategories?.let { page.counts(it) } ?: page.companies.firstOrNull { it.id == company }?.counts ?: page.counts
    }.orEmpty()
    fun count(value: NovaFileGroup) = value.states.sumOf { visibleCounts[it] ?: 0 }
    val filedHere = NovaFileState.entries.sumOf { visibleCounts[it] ?: 0 }
    val categories = catalogue?.categories.orEmpty()
    val offeredCategories = initialCategories?.let { codes -> categories.filter { it.code in codes } } ?: categories
    LaunchedEffect(Unit) {
        companies = runCatching { companiesSource() }.getOrDefault(emptyList())
        catalogue = runCatching { client.catalogue() }.getOrNull()
    }
    LaunchedEffect(reload, company, group, category, shown) {
        error = null; loading = true
        try {
            board = client.library(NovaFileQuery(query, group?.name, company, category ?: initialCategories?.singleOrNull(), shown))
        } catch (failure: Exception) {
            board = NovaFileLibraryPage()
            error = if (failure is NovaFileException) failure.failure.message else "Dosyalar alınamadı. Bağlantınızı kontrol edip tekrar deneyin."
        }
        loading = false
    }
    val source = openedSource
    if (source != null && openSource != null) { openSource(source) { openedSource = null; reload++ }; return }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 4.dp, bottom = novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(11.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaBackButton(onClick = onBack)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaText(headingOverride ?: NovaDestination.documents.title, style = NovaTypeToken.screenTitle)
                selectedName?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
            }
            // Personal and company files share one archive.
            if (canWrite) Row(Modifier.heightIn(min = 44.dp).clip(CircleShape).background(NovaColorToken.accent.color(), CircleShape).novaRowPress { adding = true }
                .padding(horizontal = 14.dp).testTag("file.library.new"), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("plus", 13.dp, tint = Color(0xFF111111)); NovaText("Dosya", style = NovaTypeToken.buttonSm, color = Color(0xFF111111))
            }
        }
        NovaHelpHint("Modüllerdeki ve ayrıca yüklediğiniz dosyaları firma ve başlığa göre bulun.")
        if (initialCompany == null) {
            NovaChooserButton("Firma", selectedName ?: "Tüm firmalar", "file.company.filter", open = chooser == "company") {
                chooser = if (chooser == "company") null else "company"
            }
            if (chooser == "company") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm firmalar")) + companies.map { NovaChooserOption(it.id, it.name) }, company,
                "file.company.filter.options") { company = it; group = null; category = null; query = ""; shown = 10; chooser = null }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaFileGroup.entries.forEach { value ->
                NovaListStat(value.title, value.symbol, count(value), Modifier.width(92.dp).testTag("file.stat.${value.name}"), selected = group == value) {
                    group = if (group == value) null else value; shown = 10; chooser = null
                }
            }
        }
        NovaSearchCapsule(query, "Dosya ara", "file.library.search") { query = it }
        LaunchedEffect(query) { if (board != null) { kotlinx.coroutines.delay(350); shown = 10; reload++ } }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaChooserButton("Durum", group?.title ?: "Tümü", "file.library.filter", Modifier.weight(1f), symbol = group?.symbol ?: "line.3.horizontal.decrease",
                open = chooser == "state") { chooser = if (chooser == "state") null else "state" }
            if (initialCategories == null) NovaChooserButton("Başlık", category?.let(NovaFileWords::category) ?: "Tüm başlıklar", "file.library.category",
                Modifier.weight(1f), symbol = "folder", open = chooser == "category") { chooser = if (chooser == "category") null else "category" }
        }
        if (chooser == "state") NovaChooserPanel(listOf(NovaChooserOption(null, "Tümü", filedHere, "square.grid.2x2")) +
            NovaFileGroup.entries.map { NovaChooserOption(it.name, it.title, count(it), it.symbol, NovaFileWords.tone(it)) }, group?.name, "file.library.filter") { picked ->
            group = NovaFileGroup.entries.firstOrNull { it.name == picked }; shown = 10; chooser = null
        }
        if (chooser == "category") {
            val held = { code: String -> board?.categoryCounts?.get(code)?.values?.sum() ?: 0 }
            NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm başlıklar", filedHere, "square.grid.2x2")) +
                categories.filter { held(it.code) > 0 || category == it.code }.map { NovaChooserOption(it.code, NovaFileWords.category(it.code), held(it.code), "folder") },
                category, "file.library.category") { category = it; shown = 10; chooser = null }
        }
        val current = board
        when {
            error != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(error!!, style = NovaTypeToken.metaQuiet) }
            current == null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText("Dosyalar yükleniyor…", style = NovaTypeToken.metaQuiet) }
            current.rows.isEmpty() -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaEmptyState(if (filedHere == 0) "Henüz dosya yok" else "Bu filtreye uyan dosya yok",
                    if (filedHere == 0) "Dosya ekleyerek belgelerinizi etiket, not ve bağlı kayıt bilgileriyle tek arşivde saklayabilirsiniz."
                    else "Arama veya filtreleri değiştirerek diğer dosyaları görüntüleyebilirsiniz.")
                if (canWrite && filedHere == 0) NovaButton("Dosya ekle", { adding = true }, Modifier.testTag("file.library.empty.add"), symbol = "folder.badge.plus")
            }
            else -> NovaListEntrance(true) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    current.rows.forEachIndexed { index, row -> FileCard(row, Modifier.novaRowEntrance(index)) { inspecting = row } }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        NovaText("${current.rows.size} / ${current.total} dosya", Modifier.weight(1f), NovaTypeToken.micro, NovaColorToken.textTertiary.color())
                        if (current.hasMore) Row(Modifier.heightIn(min = 40.dp).novaRowPress(enabled = !loading) { shown += 10 }.testTag("file.library.more"),
                            horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                            if (loading) NovaText("…", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                            else NovaIcon("chevron.down", 11.dp, tint = NovaColorToken.accentInk.color())
                            NovaText("Daha fazla göster", style = NovaTypeToken.meta, color = NovaColorToken.accentInk.color())
                        }
                    }
                }
            }
        }
    }
    val entry = inspecting
    NovaPopup(entry != null, { inspecting = null }, identifier = "file.entry.sheet") {
        if (entry != null) FileEntrySheet(entry, categories, client, canWrite, sources, onChanged = { reload++ }, onClosed = { inspecting = null },
            onOpenSource = if (openSource != null) { row -> inspecting = null; openedSource = row } else null)
    }
    NovaPopup(adding, { adding = false }, identifier = "file.add.sheet") {
        val loaded = catalogue
        NovaText("Dosya ekle", style = NovaTypeToken.sheetTitle)
        if (loaded == null) NovaText("Dosya seçenekleri yükleniyor…", style = NovaTypeToken.metaQuiet)
        else NovaFileAddInline(companies, company, offeredCategories, loaded.accepts, loaded.assurance, client) { adding = false; reload++ }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FileCard(row: NovaFileEntry, modifier: Modifier, onClick: () -> Unit) {
    val tone = NovaFileWords.tone(NovaFileGroup.of(row.state))
    NovaCard(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("file.library.row.${row.id.lowercase()}"), padding = 11) {
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                Box(Modifier.size(38.dp).background(tone.background.color(), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                    NovaIcon(NovaFileWords.symbol(row.state), 16.dp, tint = tone.ink.color())
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    NovaText(row.title, style = NovaTypeToken.cardTitle, maxLines = 2)
                    // The file name is a second line only when the expert named the entry differently.
                    if (row.fileName != row.title) NovaText(row.fileName, style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color(), maxLines = 1)
                }
                NovaStatusPill(row.state.title, tone, showsDot = false)
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                NovaTag("folder", NovaFileWords.category(row.category))
                if (row.fileExtension.isNotEmpty()) NovaTag("doc", row.fileExtension.uppercase())
                NovaTag("externaldrive", NovaFileWords.size(row.bytes))
            }
        }
    }
}

/** One filed document and everything that can be done with it (iOS `NovaFileEntrySheet`). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FileEntrySheet(entry: NovaFileEntry, categories: List<NovaFileCategory>, client: NovaFileClient, canWrite: Boolean,
                           sources: (suspend (NovaFileEntry) -> List<NovaFollowupPage.Row>)?, onChanged: () -> Unit, onClosed: () -> Unit,
                           onOpenSource: ((NovaFollowupPage.Row) -> Unit)?) {
    val coroutines = rememberCoroutineScope()
    val context = LocalContext.current
    var current by remember { mutableStateOf<NovaFileEntry?>(null) }
    var editing by remember { mutableStateOf(false) }
    var confirmingArchive by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var links by remember { mutableStateOf<List<NovaFollowupPage.Row>>(emptyList()) }
    var linksFailed by remember { mutableStateOf(false) }
    var linksRevision by remember { mutableIntStateOf(0) }
    val row = current ?: entry
    val tone = NovaFileWords.tone(NovaFileGroup.of(row.state))
    if (sources != null) LaunchedEffect(row.id, linksRevision) {
        try { links = sources(row); linksFailed = false } catch (_: Exception) { linksFailed = true }
    }
    fun run(work: suspend () -> Unit) = coroutines.launch {
        busy = true; error = null
        try { work() } catch (failure: Exception) { error = NovaFileWords.failure(failure) }
        busy = false
    }
    if (editing) {
        FileRenameSheet(row, categories) { title, category, note, tags ->
            current = client.rename(row.copy(tags = tags), title, category, note); editing = false; onChanged()
        }
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { NovaIcon(NovaFileWords.symbol(row.state), 19.dp, tint = tone.ink.color()) }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                NovaText(row.title, style = NovaTypeToken.sheetTitle, maxLines = 2)
                if (row.fileName != row.title) NovaText(row.fileName, style = NovaTypeToken.metaQuiet)
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            NovaStatusPill(row.state.title, tone)
            row.companyName?.let { NovaTag("building.2", it) }
            NovaTag("folder", NovaFileWords.category(row.category))
        }
        if (row.state.isStopped) NovaCard(Modifier.fillMaxWidth(), padding = 11, tint = tone.background.color()) {
            NovaText(NovaFileWords.rejection(row.rejectionCode), style = NovaTypeToken.meta)
            row.scanFinding?.takeIf { it.isNotEmpty() }?.let { NovaText(NovaFileWords.finding(it), style = NovaTypeToken.metaQuiet) }
            if (row.state == NovaFileState.scanFailed) NovaText("Denetim tamamlanamadığı için dosya arşive alınmadı. Bu, dosyanın zararlı olduğu anlamına gelmez; dosyayı yeniden ekleyerek tekrar deneyebilirsiniz.",
                style = NovaTypeToken.metaQuiet)
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 11) {
            NovaFactGrid(listOf(
                { m -> NovaFactCell("doc", "Tür", row.fileExtension.uppercase().ifEmpty { "—" }, m) },
                { m -> NovaFactCell("externaldrive", "Boyut", NovaFileWords.size(row.bytes), m) },
                { m -> NovaFactCell("magnifyingglass", "Saptanan tür", row.detectedType ?: "Henüz belirlenmedi", m) },
                { m -> NovaFactCell("clock", "Eklendi", row.createdAt?.take(10)?.let(NovaDay::label) ?: "—", m) }))
            if (row.tags.isNotEmpty()) NovaText(row.tags.joinToString(" · ") { "#$it" }, style = NovaTypeToken.meta)
            row.note?.takeIf { it.isNotEmpty() }?.let {
                NovaText("Not", Modifier.padding(top = 7.dp), NovaTypeToken.micro, NovaColorToken.textTertiary.color())
                NovaText(it, style = NovaTypeToken.metaQuiet)
            }
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 11, tint = NovaColorToken.surfaceMuted.color()) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("shield.lefthalf.filled", 12.dp, tint = NovaColorToken.textTertiary.color())
                NovaText("Denetim", style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
            }
            NovaText(when {
                row.scanner == null -> "Bu dosya henüz denetlenmedi."
                row.assurance == "format_inspection" -> "Biçim denetimi: gerçek tür, boyut, özet ve makro/çalışan içerik kontrol edildi."
                else -> "Dosya, tanımlı olmayan bir denetimden geçti."
            }, style = NovaTypeToken.metaQuiet)
            if (!row.malwareScanned) NovaText("Virüs taraması yapılmadı.", style = NovaTypeToken.micro, color = NovaColorToken.statusWarningInk.color())
            row.scanner?.let { NovaText(it, style = NovaTypeToken.micro, color = NovaColorToken.textMuted.color()) }
        }
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        if (linksFailed) NovaButton("Kayıt bağlantılarını yeniden yükle", { linksRevision++ }, variant = NovaButtonVariant.Muted, compact = true)
        links.forEach { link ->
            Row(Modifier.fillMaxWidth().heightIn(min = 40.dp).novaRowPress(enabled = onOpenSource != null) { onOpenSource?.invoke(link) },
                horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("link", 12.dp); NovaText("${link.typeTitle} · ${link.title}", Modifier.weight(1f), NovaTypeToken.meta)
                if (onOpenSource != null) NovaIcon("chevron.right", 10.dp)
            }
        }
        if (row.canDownload) NovaButton("Dosyayı aç", {
            run {
                val bytes = client.contents(row)
                val name = row.fileName.ifEmpty { "belge.${row.fileExtension}" }
                novaShareFile(context, bytes, name, NovaFileLibraryService.contentType(row.fileExtension))
            }
        }, Modifier.testTag("file.entry.open"), symbol = "arrow.down.doc", enabled = !busy, loading = busy)
        else if (row.state.isWorking) NovaButton("Denetimi tekrar çalıştır", { run { current = client.recheck(row); onChanged() } },
            Modifier.testTag("file.entry.recheck"), variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise", enabled = !busy, loading = busy)
        if (canWrite) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FileAction("square.and.pencil", "Düzenle", NovaStatus.Neutral, !busy, Modifier.weight(1f).testTag("file.entry.edit")) { editing = true }
                if (row.state.isWorking) FileAction("xmark.circle", "Yüklemeyi iptal et", NovaStatus.Danger, !busy, Modifier.weight(1f).testTag("file.entry.cancel")) {
                    run { client.cancel(row); onChanged(); onClosed() }
                } else FileAction("archivebox", "Listeden kaldır", NovaStatus.Danger, !busy, Modifier.weight(1f).testTag("file.entry.archive")) { confirmingArchive = true }
            }
            if (confirmingArchive) {
                NovaText("Kayıt listeden çıkar. Arşivdeki dosyanın kendisi silinmez.", style = NovaTypeToken.metaQuiet)
                NovaButton("Evet, arşivle", { run { client.archive(row); onChanged(); onClosed() } }, Modifier.testTag("file.entry.archive.confirm"),
                    variant = NovaButtonVariant.Danger, symbol = "archivebox", enabled = !busy, loading = busy)
            }
        }
    }
}

@Composable
private fun FileAction(symbol: String, label: String, status: NovaStatus, enabled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Row(modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(14.dp)).background(status.background.color(), RoundedCornerShape(14.dp))
        .novaRowPress(enabled = enabled, onClick = onClick), horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 13.dp, tint = status.ink.color())
        NovaText(label, style = NovaTypeToken.meta, color = status.ink.color())
    }
}

/** Renaming a filed entry, moving it to another heading, its note and tags. */
@Composable
private fun FileRenameSheet(entry: NovaFileEntry, categories: List<NovaFileCategory>, save: suspend (String, String, String, List<String>) -> Unit) {
    val coroutines = rememberCoroutineScope()
    val busyReporter = LocalNovaPopupBusy.current
    var title by remember { mutableStateOf(entry.title) }
    var category by remember { mutableStateOf(entry.category) }
    var note by remember { mutableStateOf(entry.note.orEmpty()) }
    var tags by remember { mutableStateOf(entry.tags.joinToString(", ")) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var choosing by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        NovaText("Dosya kaydını düzenle", style = NovaTypeToken.sheetTitle)
        NovaText(entry.fileName, style = NovaTypeToken.metaQuiet)
        NovaTextField("Başlık", title, { title = it }, identifier = "file.rename.title")
        NovaChooserButton("Başlık altında sakla", NovaFileWords.category(category), "file.rename.category", symbol = "folder", open = choosing) { choosing = !choosing }
        if (choosing) NovaChooserPanel(categories.map { NovaChooserOption(it.code, NovaFileWords.category(it.code), symbol = "folder") }, category,
            "file.rename.category.panel") { picked -> if (picked != null) category = picked; choosing = false }
        NovaTextField("Etiketler · virgülle ayırın", tags, { tags = it }, identifier = "file.rename.tags")
        NovaTextField("Not", note, { note = it }, identifier = "file.rename.note")
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        NovaButton("Kaydet", {
            coroutines.launch {
                busy = true; busyReporter(true); error = null
                try { save(title, category, note, tags.split(',').map { it.trim() }.filter { it.isNotEmpty() }) }
                catch (failure: Exception) { error = (failure as? NovaFileException)?.failure?.message ?: NovaFileFailure.validation.message }
                busy = false; busyReporter(false)
            }
        }, Modifier.testTag("file.rename.save"), symbol = "checkmark", enabled = !busy && title.isNotBlank(), loading = busy)
    }
}

/** Evrak Takibi (iOS `NovaFollowupScreen`): every dated record across the modules, opened at its source. */
@Composable
fun NovaFollowupScreen(load: suspend (company: String?, status: String?, query: String, offset: Int) -> NovaFollowupPage,
                       companiesSource: suspend () -> List<NovaCompanyOption>, events: kotlinx.coroutines.flow.Flow<Unit>, openSource: NovaRecordOpener,
                       onBack: () -> Unit, initialCompany: String? = null) {
    val coroutines = rememberCoroutineScope()
    var company by remember { mutableStateOf(initialCompany) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var page by remember { mutableStateOf<NovaFollowupPage?>(null) }
    var rows by remember { mutableStateOf<List<NovaFollowupPage.Row>>(emptyList()) }
    var query by remember { mutableStateOf("") }
    var status by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<NovaFollowupPage.Row?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    var chooser by remember { mutableStateOf<String?>(null) }
    suspend fun fetch(more: Boolean) {
        busy = true; failure = false
        if (!more) { rows = emptyList(); page = null }
        try {
            val result = load(company, status, query, if (more) rows.size else 0)
            page = result; rows = if (more) rows + result.rows else result.rows
        } catch (_: Exception) { failure = true }
        busy = false
    }
    LaunchedEffect(Unit) { companies = runCatching { companiesSource() }.getOrDefault(emptyList()) }
    LaunchedEffect(company, status, revision) { fetch(false) }
    LaunchedEffect(Unit) { events.collect { revision++ } }
    val open = selected
    if (open != null) { openSource(open) { selected = null; revision++ }; return }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).padding(bottom = novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaPageHeading("Evrak Takibi", onBack = onBack)
        NovaHelpHint("Süreler ilgili modüldeki kayıttan otomatik gelir. Bir kaydı açarak kaynağındaki bilgileri düzenleyebilirsiniz.")
        if (initialCompany == null) {
            NovaChooserButton("Firma", companies.firstOrNull { it.id == company }?.name ?: "Tüm firmalar", "followup.company", open = chooser == "company") {
                chooser = if (chooser == "company") null else "company"
            }
            if (chooser == "company") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm firmalar")) + companies.map { NovaChooserOption(it.id, it.name) }, company,
                "followup.company.options") { company = it; chooser = null }
        }
        page?.let { shown ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NovaListStat("Güncel", "checkmark.circle", shown.current, Modifier.weight(1f))
                NovaListStat("Yaklaşıyor", "clock", shown.soon, Modifier.weight(1f))
                NovaListStat("Süresi doldu", "exclamationmark.triangle", shown.expired, Modifier.weight(1f))
            }
        }
        NovaSearchCapsule(query, "Evrak veya firma ara", "followup.search") { query = it }
        LaunchedEffect(query) { kotlinx.coroutines.delay(350); if (page != null) revision++ }
        NovaChooserButton("Durum", status?.let(NovaFollowupPage::statusTitle) ?: "Tüm durumlar", "followup.status", open = chooser == "status") {
            chooser = if (chooser == "status") null else "status"
        }
        if (chooser == "status") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm durumlar")) +
            listOf("current", "soon", "expired", "undated").map { NovaChooserOption(it, NovaFollowupPage.statusTitle(it)) }, status, "followup.status.options") {
            status = it; chooser = null
        }
        if (busy && rows.isEmpty()) NovaLoadingView("Evraklar yükleniyor…", Modifier.heightIn(max = 200.dp))
        if (failure) {
            NovaText("Evrak takibi alınamadı.", style = NovaTypeToken.meta)
            NovaButton("Yeniden dene", { revision++ }, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
        }
        if (!busy && !failure && rows.isEmpty()) NovaEmptyState("Bu filtrede kayıt yok",
            "Süreli kayıtlar ilgili modüllere eklendiğinde yaklaşan ve geciken işler burada tek listede görünür.")
        NovaListEntrance(rows.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                rows.forEachIndexed { index, row ->
                    NovaCard(Modifier.fillMaxWidth().novaRowEntrance(index).clip(RoundedCornerShape(22.dp)).novaRowPress { selected = row }
                        .testTag("followup.row.${row.key}"), padding = 16) {
                        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                NovaIcon("doc.text", 14.dp); NovaText(row.title, Modifier.weight(1f), NovaTypeToken.cardTitle); NovaIcon("chevron.right", 10.dp)
                            }
                            NovaText("${row.companyName} · ${row.typeTitle}", style = NovaTypeToken.meta)
                            NovaText(NovaFollowupPage.statusTitle(row.status) + (row.dueOn?.let { " · ${NovaDay.label(it)}" } ?: ""), style = NovaTypeToken.meta)
                        }
                    }
                }
            }
        }
        if (page?.hasMore == true) NovaButton("Daha fazla", { coroutines.launch { fetch(true) } }, variant = NovaButtonVariant.Surface, enabled = !busy)
    }
}
