package com.riskdetectedan.feature.nova

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import java.util.Locale
import java.text.Normalizer

@Composable
fun NovaDocumentWizardScreen(domain: String, companiesSource: suspend () -> List<NovaCompanyOption>,
                             workplacesSource: suspend (String) -> List<NovaWizardWorkplace>, files: NovaFileClient,
                             initialCompany: String? = null, onBack: () -> Unit) {
    val context = LocalContext.current
    val coroutines = rememberCoroutineScope()
    val list = rememberLazyListState()
    var runtime by remember { mutableStateOf<NovaDocumentWizardRuntime?>(null) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var workplaces by remember { mutableStateOf<List<NovaWizardWorkplace>>(emptyList()) }
    var company by remember { mutableStateOf<String?>(null) }
    var workplace by remember { mutableStateOf<String?>(null) }
    var selections by remember { mutableStateOf<Map<String, Set<String>>>(emptyMap()) }
    var states by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var method by remember { mutableStateOf("fk") }
    var preset by remember { mutableStateOf("standard") }
    var step by remember { mutableIntStateOf(0) }
    var search by remember { mutableStateOf("") }
    var shown by remember { mutableIntStateOf(12) }
    var chooser by remember { mutableStateOf<String?>(null) }
    var preview by remember { mutableStateOf<JsonObject?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    var scopeMessage by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var archivedHash by remember { mutableStateOf<String?>(null) }
    var download by remember { mutableStateOf<NovaWizardDownload?>(null) }
    var expanded by remember { mutableStateOf(false) }
    fun visibleQuestions(rt: NovaDocumentWizardRuntime) = rt.questions.filter { domain == "risk" || it.field !in listOf("method", "preset") }
    val title = if (domain == "risk") "Risk Analizi Sihirbazı" else "Acil Durum Planı Sihirbazı"
    fun changed() { preview = null; archivedHash = null; message = null }
    fun move(index: Int) { step = index; search = ""; shown = 12; chooser = null }
    val save = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        val captured = download
        if (uri != null && captured != null) coroutines.launch {
            message = try {
                withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { it.write(captured.bytes) } ?: error("Destination unavailable") }
                "Dosya kaydedildi."
            } catch (e: CancellationException) { throw e } catch (_: Exception) { "Dosya kaydedilemedi. Tekrar deneyebilirsiniz." }
            download = null
        } else download = null
    }
    DisposableEffect(Unit) { onDispose { runtime?.close() } }
    LaunchedEffect(Unit) {
        try { runtime = NovaDocumentWizardRuntime(context); runtime?.ready() }
        catch (e: CancellationException) { throw e } catch (_: Exception) { runtime?.close(); runtime = null; message = "Sihirbaz içeriği yüklenemedi." }
        try {
            companies = companiesSource()
            if (companies.any { it.id == initialCompany }) company = initialCompany
        } catch (e: CancellationException) { throw e } catch (_: Exception) { scopeMessage = "Firmalar yüklenemedi. Firma seçmeden devam edebilirsiniz." }
    }
    LaunchedEffect(company) {
        workplaces = emptyList(); workplace = null
        val selected = company
        if (selected != null) try { workplaces = workplacesSource(selected); scopeMessage = null }
        catch (e: CancellationException) { throw e } catch (_: Exception) { scopeMessage = "İşyeri listesi yüklenemedi. İşyeri seçmeden devam edebilirsiniz." }
    }
    LaunchedEffect(step) { if (runtime != null && list.layoutInfo.totalItemsCount > step + 2) list.animateScrollToItem(step + 2) }
    fun answers(rt: NovaDocumentWizardRuntime) = buildJsonObject {
        put("method", method); put("preset", preset)
        putJsonObject("scope") { put("company_id", company); put("workplace_id", workplace); put("company_name", companies.firstOrNull { it.id == company }?.name.orEmpty()); put("workplace_name", workplaces.firstOrNull { it.id == workplace }?.name.orEmpty()) }
        rt.choices.keys.forEach { key -> putJsonObject(key) { put("state", states[key] ?: "unknown"); put("ids", JsonArray(selections[key].orEmpty().sorted().map(::JsonPrimitive))) } }
    }
    fun generate(rt: NovaDocumentWizardRuntime) {
        coroutines.launch {
            busy = true
            try {
                preview = rt.generate(answers(rt), domain); step = visibleQuestions(rt).size; message = null
                if (domain == "emergency") NovaForYouService.recordUse("emergency_wizard")
            }
            catch (e: CancellationException) { throw e } catch (e: Exception) { message = e.message ?: "Taslak oluşturulamadı." }
            finally { busy = false }
        }
    }
    fun export(rt: NovaDocumentWizardRuntime, format: String) {
        coroutines.launch {
            busy = true
            try { val file = rt.download(format); download = file; save.launch(file.name) }
            catch (e: CancellationException) { throw e } catch (_: Exception) { message = "Dosya oluşturulamadı. Tekrar deneyebilirsiniz." }
            finally { busy = false }
        }
    }
    fun archive(rt: NovaDocumentWizardRuntime, snapshot: JsonObject) {
        coroutines.launch {
            busy = true
            try {
                val file = rt.download("docx")
                val hash = snapshot.wString("content_sha256")
                val draft = NovaFileDraft(title = "$title · Taslak", category = if (domain == "risk") "risk_assessment" else "emergency_plan", note = "Sihirbaz taslağı · $hash", fileName = file.name, fileExtension = "docx", bytes = file.bytes.size, sha256 = NovaFileDraft.sha256(file.bytes))
                val entry = files.file(company, draft, file.bytes)
                archivedHash = hash; message = "Dosyalarım: ${entry.state.title}."
            } catch (e: CancellationException) { throw e } catch (e: Exception) { message = (e as? NovaFileException)?.failure?.message ?: "Dosya arşive eklenemedi. İndirerek kullanabilirsiniz." }
            finally { busy = false }
        }
    }
    val rt = runtime
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 20.dp), state = list,
        contentPadding = PaddingValues(top = 12.dp, bottom = 24.dp + novaTabBarInset), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { NovaListHeading(title, onBack) }
        item { NovaHelpHint("Kapsamınızı seçin, taslağı oluşturun ve Word, Excel veya PDF olarak indirin. Firma seçimi isteğe bağlıdır.") }
        if (rt != null) itemsIndexed(visibleQuestions(rt), key = { _, q -> q.id }) { index, q ->
            NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(Modifier.fillMaxWidth().clickable(enabled = !busy) { move(index) }.testTag("wizard.step.${q.field}"), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        NovaText("${index + 1}", style = NovaTypeToken.meta)
                        Column(Modifier.weight(1f)) {
                            NovaText(q.title, style = NovaTypeToken.cardTitle)
                            if (step != index) NovaText(when (q.field) {
                                "scope" -> companies.firstOrNull { it.id == company }?.name ?: "Firma seçmeden"
                                "method" -> rt.options.wObject("method").wString(method)
                                "preset" -> rt.options.wObject("preset").wString(preset)
                                else -> if (states[q.field] == "none") "Yok" else if (selections[q.field].isNullOrEmpty()) "Belirtilmedi" else "${selections[q.field]?.size} seçenek"
                            }, style = NovaTypeToken.metaQuiet)
                        }
                        NovaIcon(if (step == index) "chevron.up" else "chevron.down", 16.dp)
                    }
                    if (step == index) {
                        NovaText(q.help, style = NovaTypeToken.meta)
                        when (q.field) {
                            "scope" -> {
                                NovaChooserButton("Firma", companies.firstOrNull { it.id == company }?.name ?: "Firma seçmeden devam et", "wizard.company", open = chooser == "company") { if (!busy) chooser = if (chooser == "company") null else "company" }
                                if (chooser == "company") NovaChooserPanel(listOf(NovaChooserOption(null, "Firma seçmeden devam et")) + companies.map { NovaChooserOption(it.id, it.name) }, company, "wizard.companies") { if (!busy) { company = it; workplace = null; workplaces = emptyList(); chooser = null; changed() } }
                                if (workplaces.isNotEmpty()) {
                                    NovaChooserButton("İşyeri", workplaces.firstOrNull { it.id == workplace }?.name ?: "İşyeri seçmeden devam et", "wizard.workplace", open = chooser == "workplace") { if (!busy) chooser = if (chooser == "workplace") null else "workplace" }
                                    if (chooser == "workplace") NovaChooserPanel(listOf(NovaChooserOption(null, "İşyeri seçmeden devam et")) + workplaces.map { NovaChooserOption(it.id, it.name) }, workplace, "wizard.workplaces") { if (!busy) { workplace = it; chooser = null; changed() } }
                                }
                                scopeMessage?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                            }
                            "method", "preset" -> rt.options.wObject(q.field).toSortedMap().forEach { (key, value) ->
                                WizardOption(value.jsonPrimitive.content, (if (q.field == "method") method else preset) == key, !busy) { if (q.field == "method") method = key else preset = key; changed() }
                            }
                            else -> {
                                NovaSearchCapsule(search, "Seçenek ara", "wizard.search.${q.field}") { search = it; shown = 12 }
                                val selected = selections[q.field].orEmpty()
                                val filtered = rt.choices[q.field].orEmpty().filter { search.isBlank() || (listOf(it.label) + it.aliases).any { word -> wizardSearchKey(word).contains(wizardSearchKey(search)) } }.sortedWith(compareByDescending<NovaWizardChoice> { it.id in selected }.thenBy { it.label })
                                filtered.take(shown).forEach { choice -> WizardOption(choice.label, choice.id in selected, !busy) {
                                    if (selected.size >= 100 && choice.id !in selected) message = "Bu başlıkta en fazla 100 seçenek seçebilirsiniz."
                                    else { val next = if (choice.id in selected) selected - choice.id else selected + choice.id; selections = selections + (q.field to next); states = states + (q.field to if (next.isEmpty()) "unknown" else "selected"); changed() }
                                } }
                                if (filtered.isEmpty()) NovaText("Eşleşen seçenek yok. Diğer sorulardan kapsam ekleyebilirsiniz.", style = NovaTypeToken.metaQuiet)
                                if (filtered.size > shown) NovaButton("Daha fazla göster", { shown += 20 }, symbol = "chevron.down", variant = NovaButtonVariant.Surface)
                                WizardOption("Yok", states[q.field] == "none", !busy) { selections = selections + (q.field to emptySet()); states = states + (q.field to "none"); changed() }
                                WizardOption("Bilmiyorum / sonra tamamlayacağım", (states[q.field] ?: "unknown") == "unknown", !busy) { selections = selections + (q.field to emptySet()); states = states + (q.field to "unknown"); changed() }
                                NovaText("${selected.size} seçenek seçildi", style = NovaTypeToken.metaQuiet)
                            }
                        }
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            if (index > 0) NovaButton("Geri", { move(index - 1) }, symbol = "chevron.left", variant = NovaButtonVariant.Surface, enabled = !busy)
                            Spacer(Modifier.weight(1f))
                            NovaButton(if (index == visibleQuestions(rt).lastIndex) "Taslak oluştur" else "Devam", { if (index == visibleQuestions(rt).lastIndex) generate(rt) else move(index + 1) }, symbol = "chevron.right", enabled = !busy)
                        }
                    }
                }
            }
        }
        val snapshot = preview
        if (snapshot != null && rt != null) item {
            NovaCard(Modifier.fillMaxWidth(), padding = 16) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    NovaText("Taslak hazır", style = NovaTypeToken.cardTitle)
                    NovaText(if (domain == "risk") "${snapshot.wArray("rows").size} risk · ${snapshot.wArray("unresolved").size} kapsamı netleşmemiş konu · ${snapshot.wArray("omitted").size} sınır dışında" else "${snapshot.wArray("cards").size} acil durum eylem kartı", style = NovaTypeToken.meta)
                    snapshot.wArray("input_conflicts").forEach { NovaHelpHint(it.jsonPrimitive.content) }
                    listOf("docx" to "Word indir", "xlsx" to "Excel indir", "pdf" to "PDF indir").forEach { (format, label) -> NovaButton(label, { export(rt, format) }, symbol = "arrow.down.doc", variant = NovaButtonVariant.Surface, enabled = !busy) }
                    NovaButton(if (archivedHash == snapshot.wString("content_sha256")) "Arşive gönderildi" else "Word dosyasını arşive ekle", { archive(rt, snapshot) }, symbol = "folder.badge.plus", enabled = !busy && archivedHash != snapshot.wString("content_sha256"))
                    NovaButton(if (expanded) "İçeriği daralt" else "Belge içeriği ve kapsam", { expanded = !expanded }, symbol = if (expanded) "chevron.up" else "chevron.down", variant = NovaButtonVariant.Surface)
                    if (expanded) {
                        snapshot.wArray(if (domain == "risk") "rows" else "cards").forEach { item -> NovaText(item.jsonObject.wString("id") + " · " + item.jsonObject.wString(if (domain == "risk") "scenario_tr" else "title_tr"), style = NovaTypeToken.meta) }
                        if (domain == "risk") {
                            snapshot.wArray("unresolved").forEach { item -> NovaText("Kapsamı netleşmemiş: " + item.jsonObject.wString("title") + "\nGerekli bilgi: " + item.jsonObject.wArray("missing_labels").joinToString("; ") { it.jsonPrimitive.content }, style = NovaTypeToken.meta) }
                            snapshot.wArray("omitted").forEach { NovaText("Sınır dışında: " + it.jsonObject.wString("title"), style = NovaTypeToken.meta) }
                        }
                    }
                }
            }
        }
        if (busy) item { NovaText("Hazırlanıyor…", style = NovaTypeToken.meta) }
        message?.let { item { NovaText(it, style = NovaTypeToken.meta) } }
    }
}

@Composable
private fun WizardOption(label: String, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(enabled = enabled, onClick = onClick).semantics { this.selected = selected }.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
        NovaIcon(if (selected) "checkmark.circle.fill" else "circle", 20.dp)
        NovaText(label, style = NovaTypeToken.body, modifier = Modifier.weight(1f))
    }
}

private fun wizardSearchKey(value: String) = Normalizer.normalize(value, Normalizer.Form.NFD)
    .replace(Regex("\\p{M}+"), "").lowercase(Locale.ROOT).replace('ı', 'i')
