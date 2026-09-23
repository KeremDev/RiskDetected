package com.riskdetectedan.feature.nova

import androidx.compose.foundation.background
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
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Kontrol Listeleri: the ready catalogue and the expert's own lists (iOS `NovaChecklistListsScreen`). */
@Composable
fun NovaChecklistListsScreen(client: NovaChecklistClient, canWrite: Boolean, initialCompany: String?, onBack: () -> Unit, onStart: (String) -> Unit) {
    val coroutines = rememberCoroutineScope()
    var mine by remember { mutableStateOf(false) }
    var library by remember { mutableStateOf<NovaChecklistLibrary?>(null) }
    var templates by remember { mutableStateOf<List<NovaChecklistTemplate>>(emptyList()) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var search by remember { mutableStateOf("") }
    var sector by remember { mutableStateOf<String?>(null) }
    var kind by remember { mutableStateOf<String?>(null) }
    var showingFilters by remember { mutableStateOf(false) }
    var showingCreate by remember { mutableStateOf(false) }
    var detail by remember { mutableStateOf<NovaChecklistTemplateDetail?>(null) }
    var editing by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    val hasCriteria = search.isNotBlank() || sector != null || kind != null
    val filterCount = (if (sector == null) 0 else 1) + (if (kind == null) 0 else 1)
    suspend fun loadLibrary(reset: Boolean) {
        if (!hasCriteria) { loading = false; failure = null; return }
        val current = library
        val offset = if (reset || current == null) 0 else current.offset + current.limit
        loading = true; failure = null
        try {
            val value = client.library(search, sector, kind, offset)
            library = if (reset || current == null) value else value.copy(rows = current.rows + value.rows)
        } catch (error: Exception) { failure = checklistMessage(error) }
        loading = false
    }
    suspend fun loadTemplates() {
        loading = true; failure = null
        try { templates = client.templates(initialCompany) } catch (error: Exception) { failure = checklistMessage(error) }
        loading = false
    }
    LaunchedEffect(Unit) {
        loading = true; failure = null
        try {
            companies = client.companies()
            library = client.library("", null, null, 0)
            templates = client.templates(initialCompany)
        } catch (error: Exception) { failure = checklistMessage(error) }
        loading = false
    }
    LaunchedEffect(search) { if (!mine) { delay(280); loadLibrary(true) } }
    LaunchedEffect(mine) { if (mine) loadTemplates() else loadLibrary(true) }
    val open = detail
    if (open != null) {
        TemplateDetailScreen(open, canWrite, onBack = { detail = null }, onStart = { detail = null; onStart(open.templateCode) },
            onCopy = { try { client.copyTemplate(initialCompany, open.templateCode, null); loadTemplates(); null } catch (error: Exception) { checklistMessage(error) } },
            onAssign = {
                val company = initialCompany ?: return@TemplateDetailScreen "Listeyi firmaya atamak için Kontroller ekranından firma filtresi seçin."
                try { client.assignTemplate(company, null, open.templateCode); null } catch (error: Exception) { checklistMessage(error) }
            })
        return
    }
    val edited = editing
    if (edited != null) { MyListEditor(client, initialCompany, edited) { editing = null; coroutines.launch { loadTemplates() } }; return }
    if (showingCreate) {
        CreateListScreen(onBack = { showingCreate = false }) { title ->
            try {
                client.draftTemplate(initialCompany, title)
                val values = client.templates(initialCompany)
                templates = values
                val created = values.firstOrNull { novaFold(it.title) == novaFold(title) } ?: return@CreateListScreen "Liste oluşturuldu ancak düzenleme ekranı açılamadı."
                showingCreate = false; editing = created.templateCode; null
            } catch (error: Exception) { checklistMessage(error) }
        }
        return
    }
    androidx.activity.compose.BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(top = 12.dp, bottom = 30.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        NovaListHeading("Kontrol Listeleri", onBack) {
            if (mine && canWrite) NovaButton("Yeni liste", { showingCreate = true }, Modifier.testTag("nova.checklist.template.create"), symbol = "plus", compact = true)
        }
        NovaSegmentedControl(listOf("Hazır listeler", "Listelerim"), if (mine) 1 else 0, Modifier.testTag("nova.checklist.lists.section")) { mine = it == 1 }
        if (!mine) {
            NovaHelpHint("Sektör, ekipman, faaliyet veya tehlikeye göre arayın; filtre düğmesiyle sonuçları daraltın.")
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f)) { NovaSearchCapsule(search, "Sektör, ekipman veya iş ara", "nova.checklist.library.search") { search = it } }
                Box(Modifier.size(46.dp).clip(RoundedCornerShape(12.dp)).background(NovaColorToken.surface.color(), RoundedCornerShape(12.dp))
                    .novaRowPress { showingFilters = true }.semantics { contentDescription = if (filterCount == 0) "Filtre" else "Filtre, $filterCount etkin" },
                    contentAlignment = Alignment.Center) {
                    NovaIcon("line.3.horizontal.decrease", 16.dp)
                    if (filterCount > 0) Box(Modifier.align(Alignment.TopEnd).padding(2.dp).size(17.dp).background(NovaColorToken.accent.color(), CircleShape),
                        contentAlignment = Alignment.Center) { NovaText("$filterCount", style = NovaTypeToken.micro) }
                }
            }
            val shown = library
            when {
                !hasCriteria -> ChecklistMessage("magnifyingglass", "Bir liste bulun", "Liste adına göre arayın veya sektör ve tür filtresi seçin.")
                loading && shown == null -> NovaLoadingView("Listeler yükleniyor…", Modifier.heightIn(max = 200.dp))
                failure != null -> ChecklistMessage("wifi.exclamationmark", "Hazır listeler yüklenemedi", failure!!, "Yeniden dene") { coroutines.launch { loadLibrary(true) } }
                shown != null && shown.rows.isEmpty() -> ChecklistMessage("magnifyingglass", "Sonuç bulunamadı", "Arama kelimenizi veya filtreleri değiştirin.",
                    if (filterCount > 0) "Filtreleri temizle" else null) { sector = null; kind = null; coroutines.launch { loadLibrary(true) } }
                shown != null -> Column {
                    shown.rows.forEach { item ->
                        ListRow(item.title, listOfNotNull(item.sectorName, novaChecklistKindTitle(item.kind)).joinToString(" · "), "${item.items} soru",
                            Modifier.testTag("nova.checklist.library.${item.catalogTemplateCode}")) {
                            coroutines.launch { failure = null; try { detail = client.templateDetail(item.templateCode) } catch (error: Exception) { failure = checklistMessage(error) } }
                        }
                        NovaDivider()
                    }
                    if (shown.hasMore) NovaButton("Daha fazla göster", { coroutines.launch { loadLibrary(false) } }, Modifier.padding(top = 14.dp),
                        variant = NovaButtonVariant.Surface, symbol = "chevron.down")
                }
            }
        } else when {
            loading && templates.isEmpty() -> NovaLoadingView("Listeler yükleniyor…", Modifier.heightIn(max = 200.dp))
            failure != null -> ChecklistMessage("wifi.exclamationmark", "Listeleriniz yüklenemedi", failure!!, "Yeniden dene") { coroutines.launch { loadTemplates() } }
            templates.isEmpty() -> ChecklistMessage("list.bullet.rectangle", "Henüz listeniz yok",
                "Yeni bir liste oluşturup hazır maddelerden seçebilir veya kendi sorularınızı yazabilirsiniz.")
            else -> Column {
                templates.forEach { template ->
                    val version = template.draft ?: template.published ?: template.versions.firstOrNull()
                    ListRow(template.title, "${version?.statusTitle ?: "Taslak"} · ${version?.items?.size ?: 0} soru", null) { editing = template.templateCode }
                    NovaDivider()
                }
            }
        }
    }
    NovaPopup(showingFilters, { showingFilters = false }, identifier = "nova.checklist.library.filter") {
        NovaPopupHeading("Filtre", symbol = "line.3.horizontal.decrease")
        NovaText("Tür", style = NovaTypeToken.label)
        (listOf<Pair<String?, String>>(null to "Tümü") + listOf("sector" to "Sektör", "activity" to "Faaliyet", "equipment" to "Ekipman", "hazard" to "Tehlike",
            "general" to "Genel")).forEach { (code, title) -> FilterChoice(title, kind == code) { kind = code } }
        NovaText("Sektör", style = NovaTypeToken.label)
        FilterChoice("Tümü", sector == null) { sector = null }
        library?.sectors.orEmpty().forEach { item -> FilterChoice("${item.name} (${item.count})", sector == item.code) { sector = item.code } }
        if (sector != null || kind != null) NovaButton("Tüm filtreleri temizle", { sector = null; kind = null }, variant = NovaButtonVariant.Muted)
        NovaButton("Uygula", { showingFilters = false; coroutines.launch { loadLibrary(true) } }, symbol = "checkmark")
    }
}

@Composable
private fun FilterChoice(title: String, on: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress(onClick = onClick).semantics { selected = on }, verticalAlignment = Alignment.CenterVertically) {
        NovaText(title, Modifier.weight(1f)); if (on) NovaIcon("checkmark", 13.dp)
    }
}

@Composable
private fun ListRow(title: String, subtitle: String, detail: String?, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Row(modifier.fillMaxWidth().novaRowPress(onClick = onClick).padding(vertical = 14.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaText(title, style = NovaTypeToken.bodyStrong)
            NovaText(subtitle, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            detail?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color()) }
        }
        Box(Modifier.size(32.dp, 44.dp), contentAlignment = Alignment.Center) { NovaIcon("chevron.right", 11.dp, tint = NovaColorToken.textMuted.color()) }
    }
}

/** One ready list: its questions, blank exports, copy and assign (iOS `NovaChecklistTemplateDetailScreen`). */
@Composable
private fun TemplateDetailScreen(template: NovaChecklistTemplateDetail, canWrite: Boolean, onBack: () -> Unit, onStart: () -> Unit,
                                 onCopy: suspend () -> String?, onAssign: suspend () -> String?) {
    val coroutines = rememberCoroutineScope()
    val context = LocalContext.current
    var working by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var menu by remember { mutableStateOf(false) }
    fun perform(work: suspend () -> String?) = coroutines.launch { working = true; failure = work(); working = false; menu = false }
    androidx.activity.compose.BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize()) {
        ChecklistHeader("Liste detayı", "Listeler", onBack) {
            Box(Modifier.size(44.dp).novaRowPress { menu = true }.semantics { contentDescription = "Diğer işlemler" }, contentAlignment = Alignment.Center) {
                NovaIcon("ellipsis.circle", 20.dp)
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            NovaText(template.title, style = NovaTypeToken.screenTitle)
            NovaText(listOfNotNull(novaChecklistKindTitle(template.kind), "${template.items.size} soru").joinToString(" · "), color = NovaColorToken.textSecondary.color())
            template.scopeNote?.takeIf { it.isNotEmpty() }?.let { NovaText(it) }
            if (template.professionalReviewStatus == "approved") Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("checkmark.seal", 12.dp, tint = NovaColorToken.statusSuccessInk.color())
                NovaText("Uzmanlık alanı incelemesi tamamlandı", style = NovaTypeToken.meta, color = NovaColorToken.statusSuccessInk.color())
            }
            NovaText("Sorular", style = NovaTypeToken.sectionTitle)
            template.items.forEach { item ->
                Row(Modifier.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    NovaText("${item.position}.", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color()); NovaText(item.prompt)
                }
                NovaDivider()
            }
            failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        }
        if (canWrite) ChecklistBottomAction { NovaButton("Bu listeyle kontrol başlat", onStart, symbol = "play", loading = working) }
    }
    NovaPopup(menu, { menu = false }, identifier = "nova.checklist.template.menu") {
        NovaPopupOption("Boş PDF", "doc") {
            runCatching { novaShareFile(context, NovaChecklistExport.pdf(template), NovaChecklistExport.name(template.templateCode, "pdf"), "application/pdf") }
                .onFailure { failure = "PDF oluşturulamadı." }
            menu = false
        }
        NovaPopupOption("Boş Excel", "tablecells") {
            runCatching { novaShareFile(context, NovaChecklistExport.xlsx(template), NovaChecklistExport.name(template.templateCode, "xlsx"), NovaXlsx.MIME) }
                .onFailure { failure = "Excel dosyası oluşturulamadı." }
            menu = false
        }
        if (canWrite) {
            NovaPopupOption("Listelerime kopyala", "doc.on.doc") { perform(onCopy) }
            NovaPopupOption("Firmaya ata", "building.2") { perform(onAssign) }
        }
    }
}

@Composable
private fun CreateListScreen(onBack: () -> Unit, onCreate: suspend (String) -> String?) {
    val coroutines = rememberCoroutineScope()
    var title by remember { mutableStateOf("") }
    var working by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    androidx.activity.compose.BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize()) {
        ChecklistHeader("Yeni liste", "Listelerim", onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            NovaText("Listenize bir ad verin", style = NovaTypeToken.screenTitle)
            NovaText("Sonraki ekranda hazır maddelerden seçim yapabilir veya kendi sorularınızı ekleyebilirsiniz.", color = NovaColorToken.textSecondary.color())
            NovaTextField("Liste adı", title, { title = it }, identifier = "nova.checklist.templates.name")
            failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        }
        ChecklistBottomAction {
            NovaButton(if (working) "Oluşturuluyor…" else "Listeyi oluştur", {
                coroutines.launch { working = true; failure = onCreate(title.trim()); working = false }
            }, symbol = "plus", enabled = title.isNotBlank() && !working, loading = working)
        }
    }
}

/** Editing one of the expert's own lists; a published version is never edited (iOS `NovaChecklistMyListEditorScreen`). */
@Composable
private fun MyListEditor(client: NovaChecklistClient, company: String?, templateCode: String, onBack: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    var template by remember { mutableStateOf<NovaChecklistTemplate?>(null) }
    var showingCatalogue by remember { mutableStateOf(false) }
    var showingManual by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var itemMenu by remember { mutableStateOf<NovaChecklistTemplateItem?>(null) }
    suspend fun load() {
        loading = true; failure = null
        try { template = client.templates(company).firstOrNull { it.templateCode == templateCode } } catch (error: Exception) { failure = checklistMessage(error) }
        loading = false
    }
    LaunchedEffect(Unit) { load() }
    val version = template?.let { it.draft ?: it.published ?: it.versions.firstOrNull() }
    val editable = version?.isDraft == true && template?.isProduct == false
    fun run(work: suspend (NovaChecklistTemplateVersion) -> Unit) = coroutines.launch {
        val current = version ?: return@launch
        working = true; failure = null
        try { work(current); load() } catch (error: Exception) { failure = checklistMessage(error) }
        working = false
    }
    if (showingCatalogue && version != null) {
        CatalogItemPicker(client, onBack = { showingCatalogue = false }) { selection ->
            try { client.copyItems(company, templateCode, version.version, version.revision, listOf(selection)); load(); null } catch (error: Exception) { checklistMessage(error) }
        }
        return
    }
    if (showingManual && version != null) {
        ManualItemScreen(onBack = { showingManual = false }) { prompt, allowsNa ->
            try {
                val position = version.items.size + 1
                client.setItem(company, templateCode, version.version, version.revision, "q$position", prompt, allowsNa, position)
                load(); showingManual = false; null
            } catch (error: Exception) { checklistMessage(error) }
        }
        return
    }
    androidx.activity.compose.BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize()) {
        ChecklistHeader("Listeyi düzenle", "Listelerim", onBack)
        val loaded = template
        when {
            loading && loaded == null -> NovaLoadingView("Liste yükleniyor…", Modifier.padding(20.dp).heightIn(max = 200.dp))
            loaded != null && version != null -> {
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        NovaText(loaded.title, style = NovaTypeToken.screenTitle)
                        NovaText("${version.statusTitle} · v${version.version} · ${version.items.size} soru", color = NovaColorToken.textSecondary.color())
                    }
                    if (editable) Column {
                        EditorAction("Hazır maddelerden seç", "Katalogda ara ve listeye ekle", "text.badge.plus") { showingCatalogue = true }
                        NovaDivider()
                        EditorAction("Kendi sorunu yaz", "Bu listeye özel bir soru ekle", "square.and.pencil") { showingManual = true }
                    }
                    NovaText("Sorular", style = NovaTypeToken.sectionTitle)
                    if (version.items.isEmpty()) ChecklistMessage("list.number", "Henüz soru yok", "Hazır maddelerden seçin veya kendi sorunuzu yazın.")
                    else version.items.sortedBy { it.position }.forEach { item ->
                        Row(Modifier.padding(vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            NovaText("${item.position}.", Modifier.width(24.dp), NovaTypeToken.meta, NovaColorToken.textMuted.color())
                            NovaText(item.prompt, Modifier.weight(1f))
                            if (editable) Box(Modifier.size(44.dp).novaRowPress { itemMenu = item }.semantics { contentDescription = "Soru işlemleri" },
                                contentAlignment = Alignment.Center) { NovaIcon("ellipsis", 14.dp) }
                        }
                        NovaDivider()
                    }
                    if (!editable) NovaText("Yayımlanmış sürüm değiştirilemez. Değişiklikler yeni bir taslak sürüm üzerinden yapılır.", style = NovaTypeToken.meta,
                        color = NovaColorToken.textSecondary.color())
                    failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
                }
                if (editable) ChecklistBottomAction {
                    NovaButton(if (working) "Yayımlanıyor…" else "Listeyi yayımla", {
                        run { current -> client.publishTemplate(company, templateCode, current.version, current.revision, "Uygulama üzerinden uzman tarafından yayımlandı.") }
                    }, symbol = "checkmark.seal", enabled = version.items.isNotEmpty() && !working, loading = working)
                }
            }
            else -> ChecklistMessage("wifi.exclamationmark", "Liste yüklenemedi", failure ?: "Liste bulunamadı.", "Yeniden dene") { coroutines.launch { load() } }
        }
    }
    val item = itemMenu
    NovaPopup(item != null, { itemMenu = null }, identifier = "nova.checklist.item.menu") {
        if (item != null && version != null) {
            val codes = version.items.sortedBy { it.position }.map { it.itemCode }
            val index = codes.indexOf(item.itemCode)
            fun move(delta: Int) {
                val next = codes.toMutableList()
                if (index + delta !in next.indices) return
                next[index] = next[index + delta].also { next[index + delta] = next[index] }
                itemMenu = null
                run { current -> client.reorderItems(company, templateCode, current.version, current.revision, next) }
            }
            if (index > 0) NovaPopupOption("Yukarı taşı", "arrow.up") { move(-1) }
            if (index < codes.size - 1) NovaPopupOption("Aşağı taşı", "arrow.down") { move(1) }
            NovaPopupOption("Soruyu kaldır", "trash") {
                itemMenu = null
                run { current -> client.removeItem(company, templateCode, current.version, current.revision, item.itemCode) }
            }
        }
    }
}

@Composable
private fun EditorAction(title: String, subtitle: String, symbol: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().novaRowPress(onClick = onClick).padding(vertical = 13.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 18.dp, Modifier.width(28.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            NovaText(title, style = NovaTypeToken.bodyStrong)
            NovaText(subtitle, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        NovaIcon("chevron.right", 12.dp, tint = NovaColorToken.textMuted.color())
    }
}

/** Searching the catalogue for single questions to copy into a draft list. */
@Composable
private fun CatalogItemPicker(client: NovaChecklistClient, onBack: () -> Unit, onAdd: suspend (NovaChecklistItemSelection) -> String?) {
    val coroutines = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var result by remember { mutableStateOf<NovaChecklistLibrary?>(null) }
    var working by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var added by remember { mutableStateOf<Set<String>>(emptySet()) }
    LaunchedEffect(query) {
        delay(280)
        if (query.isBlank()) { result = null; failure = null; return@LaunchedEffect }
        working = true; failure = null
        try { result = client.library(query, null, null, 0) } catch (error: Exception) { failure = checklistMessage(error) }
        working = false
    }
    androidx.activity.compose.BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize()) {
        ChecklistHeader("Hazır madde ekle", "Listeye dön", onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 14.dp, bottom = 30.dp + novaTabBarInset)) {
            NovaSearchCapsule(query, "Soru, risk, ekipman veya konu ara", "nova.checklist.builder.search") { query = it }
            Spacer(Modifier.height(14.dp))
            val items = result?.matchedItems
            when {
                query.isBlank() -> ChecklistMessage("magnifyingglass", "Hazır madde bulun", "Yazdıkça katalogdaki sorular süzülecek.")
                working && result == null -> NovaLoadingView("Maddeler yükleniyor…", Modifier.heightIn(max = 200.dp))
                failure != null -> ChecklistMessage("wifi.exclamationmark", "Maddeler yüklenemedi", failure!!)
                items != null && items.isEmpty() -> ChecklistMessage("magnifyingglass", "Sonuç bulunamadı", "Daha kısa bir konu, risk veya ekipman adı deneyin.")
                items != null -> items.forEach { item ->
                    val context = item.contexts.firstOrNull() ?: return@forEach
                    val key = context.templateCode + ":" + context.itemCode
                    val done = key in added
                    Row(Modifier.fillMaxWidth().novaRowPress(enabled = !working && !done) {
                        coroutines.launch {
                            working = true
                            failure = onAdd(NovaChecklistItemSelection(context.templateCode, context.itemCode))
                            if (failure == null) added = added + key
                            working = false
                        }
                    }.padding(vertical = 12.dp).semantics { contentDescription = if (done) "Eklendi" else "Listeye ekle" },
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            NovaText(item.prompt)
                            NovaText(listOfNotNull(context.sectorName, item.riskTopic).joinToString(" · "), style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                        }
                        Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { NovaIcon(if (done) "checkmark.circle.fill" else "plus.circle", 20.dp) }
                    }
                    NovaDivider()
                }
            }
        }
    }
}

@Composable
private fun ManualItemScreen(onBack: () -> Unit, onAdd: suspend (String, Boolean) -> String?) {
    val coroutines = rememberCoroutineScope()
    var prompt by remember { mutableStateOf("") }
    var allowsNa by remember { mutableStateOf(true) }
    var working by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    androidx.activity.compose.BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize()) {
        ChecklistHeader("Yeni soru", "Listeye dön", onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            NovaText("Kontrol sorusunu yazın", style = NovaTypeToken.screenTitle)
            NovaTextField("Soru", prompt, { prompt = it }, identifier = "nova.checklist.templates.prompt", multiline = true)
            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).novaRowPress { allowsNa = !allowsNa }.semantics { selected = allowsNa },
                horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon(if (allowsNa) "checkmark.square.fill" else "square", 15.dp, tint = NovaColorToken.accentInk.color())
                NovaText("“Uygulanamaz” yanıtına izin ver")
            }
            failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        }
        ChecklistBottomAction {
            NovaButton(if (working) "Ekleniyor…" else "Soruyu ekle", {
                coroutines.launch { working = true; failure = onAdd(prompt.trim(), allowsNa); working = false }
            }, symbol = "plus", enabled = prompt.isNotBlank() && !working, loading = working)
        }
    }
}
