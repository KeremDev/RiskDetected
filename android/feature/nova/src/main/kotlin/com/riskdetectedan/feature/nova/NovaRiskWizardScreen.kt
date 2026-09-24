package com.riskdetectedan.feature.nova

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Risk level colours shared by chips, bars and rows (mirrors the Excel bands). */
private object RiskTone {
    val order = listOf("critical", "high", "medium", "low", "insignificant")
    val names = mapOf("critical" to "Tolerans dışı", "high" to "Yüksek", "medium" to "Önemli / orta", "low" to "Olası / düşük", "insignificant" to "Önemsiz")
    fun colors(level: String, dark: Boolean): Pair<Color, Color> = when (level) {
        "critical" -> if (dark) Color(0x2EFF5A50) to Color(0xFFFF8A80) else Color(0xFFFDECEC) to Color(0xFFB42318)
        "high" -> if (dark) Color(0x2EFF9933) to Color(0xFFFFB35C) else Color(0xFFFFF4DE) to Color(0xFFC76A00)
        "medium" -> if (dark) Color(0x29F2D060) to Color(0xFFF2D060) else Color(0xFFFEF9C3) to Color(0xFF8A6100)
        "low" -> if (dark) Color(0x2950C878) to Color(0xFF6FD08C) else Color(0xFFE8F5EF) to Color(0xFF237A3B)
        else -> if (dark) Color(0x24AAB4BC) to Color(0xFFAAB4BC) else Color(0xFFEEF2F0) to Color(0xFF4B5563)
    }
    fun bar(level: String) = when (level) {
        "critical" -> Color(0xFFD64B40); "high" -> Color(0xFFE48B22); "medium" -> Color(0xFFE3BC2A); "low" -> Color(0xFF4BAF6A); else -> Color(0xFFA7B2AE)
    }
}

private val stepTitles = mapOf("firm" to "İşyeri", "sector" to "Faaliyet", "areas" to "Çalışma alanları", "equipment" to "Ekipmanlar",
    "materials" to "Maddeler", "tasks" to "İşler", "cond" to "Çalışma koşulları", "mgmt" to "Genel konular", "method" to "Yöntem",
    "cols" to "Tablo sütunları", "summary" to "Özet")

/** V6 risk analysis and emergency plan wizard (iOS `NovaRiskWizardScreen`): one question per page; answers live in RDBridge.
 * `mode = "emergency"` runs the Acil Durum Planı flow on the same answers; its pages live in NovaEmergencyWizardPages.kt. */
@Composable
fun NovaRiskWizardScreen(companiesSource: suspend () -> List<NovaCompanyOption>,
                         workplacesSource: suspend (String) -> List<NovaWizardWorkplace>, files: () -> NovaFileClient,
                         initialCompany: String? = null, mode: String = "risk", emergencyClient: NovaEmergencyClient? = null, onBack: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val list = rememberLazyListState()
    val dark = LocalNovaDark.current
    var runtime by remember { mutableStateOf<NovaRiskWizardRuntime?>(null) }
    var view by remember { mutableStateOf<RiskWizardView?>(null) }
    var result by remember { mutableStateOf<RiskWizardResult?>(null) }
    var step by remember { mutableStateOf("firm") }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var company by remember { mutableStateOf<String?>(null) }
    var chooser by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var sectorHits by remember { mutableStateOf<List<RiskWizardSectorHit>>(emptyList()) }
    var searchHits by remember { mutableStateOf<List<RiskWizardPick>>(emptyList()) }
    var expanded by remember { mutableStateOf<Set<String>>(emptySet()) }
    var filter by remember { mutableStateOf("all") }
    var scoreView by remember { mutableStateOf("fk") }
    var message by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var archived by remember { mutableStateOf(false) }
    var download by remember { mutableStateOf<NovaWizardDownload?>(null) }
    var plan by remember { mutableStateOf<EmergencyPlan?>(null) }
    var planSaved by remember { mutableStateOf(false) }
    var workplaces by remember { mutableStateOf<List<NovaWizardWorkplace>>(emptyList()) }
    var workplace by remember { mutableStateOf<String?>(null) }
    var workplaceChooser by remember { mutableStateOf(false) }
    var cardHits by remember { mutableStateOf<List<EmergencyCard>>(emptyList()) }
    var staff by remember { mutableStateOf<List<EmergencyWizardStaff>?>(null) }
    var staffQuery by remember { mutableStateOf("") }
    var openPerson by remember { mutableStateOf<String?>(null) }

    val save = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        val captured = download
        if (uri != null && captured != null) scope.launch {
            message = try {
                withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { it.write(captured.bytes) } ?: error("Destination unavailable") }
                "Dosya kaydedildi."
            } catch (e: CancellationException) { throw e } catch (_: Exception) { "Dosya kaydedilemedi. Tekrar deneyebilirsiniz." }
            download = null
        } else download = null
    }
    DisposableEffect(Unit) { onDispose { runtime?.close() } }
    LaunchedEffect(Unit) {
        try {
            val loaded = NovaRiskWizardRuntime(context)
            loaded.ready()
            runtime = loaded
            view = loaded.start("", SimpleDateFormat("dd.MM.yyyy", Locale("tr", "TR")).format(Date()), mode)
        } catch (e: CancellationException) { throw e } catch (_: Exception) { message = "Sihirbaz içeriği yüklenemedi." }
        try {
            companies = companiesSource()
            companies.firstOrNull { it.id == initialCompany }?.let { selected ->
                company = selected.id
                runtime?.let { rt -> view = rt.act(mapOf("type" to "firm", "field" to "name", "value" to selected.name)) }
            }
        } catch (e: CancellationException) { throw e } catch (_: Exception) { companies = emptyList() }
    }
    LaunchedEffect(step) { list.scrollToItem(0) }
    LaunchedEffect(company) {
        workplace = null; workplaces = emptyList(); staff = null
        val selected = company ?: return@LaunchedEffect
        if (mode != "emergency") return@LaunchedEffect
        workplaces = try { workplacesSource(selected) } catch (e: CancellationException) { throw e } catch (_: Exception) { emptyList() }
        if (workplaces.size == 1) workplace = workplaces.first().id
        val client = emergencyClient ?: return@LaunchedEffect
        staff = try {
            val support = runCatching { client.catalogue(selected).supportStaff.map { it.fullName }.toSet() }.getOrDefault(emptySet())
            client.employees(selected).map { EmergencyWizardStaff(it.id, it.name, listOfNotNull(it.jobTitle, it.department).joinToString(" · "), it.name in support) }
                .sortedWith(compareBy({ !it.isSupportStaff }, { it.name }))
        } catch (e: CancellationException) { throw e } catch (_: Exception) { null }
    }

    fun perform(action: Map<String, Any?>, after: (suspend () -> Unit)? = null) {
        val rt = runtime ?: return
        scope.launch {
            try {
                view = rt.act(action)
                if (step == "result" && view?.emergency != null) plan = rt.plan()
                else if (step == "result") result = rt.result()
                if (result != null) NovaForYouService.recordUse("risk_wizard")
                after?.invoke()
            } catch (e: CancellationException) { throw e } catch (e: Exception) { message = e.message ?: "İşlem tamamlanamadı." }
        }
    }
    val steps = (view?.steps ?: listOf("firm")) + "result"
    val index = steps.indexOf(step).coerceAtLeast(0)
    fun go(target: String) {
        val rt = runtime ?: return
        query = ""; searchHits = emptyList(); message = null
        scope.launch {
            try {
                if (target == "areas") view = rt.act(mapOf("type" to "enter", "step" to "areas"))
                if (target == "sector") sectorHits = rt.sectors("")
                if (target == "result" && view?.emergency != null) plan = rt.plan()
                else if (target == "result") result = rt.result()
                if (result != null) NovaForYouService.recordUse("risk_wizard")
            } catch (e: CancellationException) { throw e } catch (e: Exception) { message = e.message }
            step = target
        }
    }
    fun back() { if (index == 0) onBack() else go(steps[index - 1]) }
    BackHandler { back() }
    fun export(format: String) {
        val rt = runtime ?: return
        scope.launch {
            busy = true
            try { val file = rt.download(format); download = file; save.launch(file.name) }
            catch (e: CancellationException) { throw e } catch (_: Exception) { message = "Dosya oluşturulamadı. Tekrar deneyebilirsiniz." }
            finally { busy = false }
        }
    }
    fun savePlan() {
        val rt = runtime ?: return
        val client = emergencyClient ?: return
        val selected = company ?: return
        val emergency = view?.emergency ?: return
        scope.launch {
            busy = true
            try {
                EmergencyWizardSaver.save(rt, client, selected, workplace, emergency)
                planSaved = true; message = emergency.text("result.saved")
            } catch (e: CancellationException) { throw e } catch (e: Exception) {
                message = (e as? NovaFileException)?.failure?.message ?: emergencyMessage(e)
            } finally { busy = false }
        }
    }
    fun archive() {
        val rt = runtime ?: return
        scope.launch {
            busy = true
            try {
                val file = rt.download("xlsx")
                val draft = NovaFileDraft(title = "Risk Değerlendirmesi · Taslak", category = "risk_assessment", note = "Risk analizi sihirbazı",
                    fileName = file.name, fileExtension = "xlsx", bytes = file.bytes.size, sha256 = NovaFileDraft.sha256(file.bytes))
                val entry = files().file(company, draft, file.bytes)
                archived = true; message = "Dosyalarım: ${entry.state.title}."
            } catch (e: CancellationException) { throw e } catch (e: Exception) { message = (e as? NovaFileException)?.failure?.message ?: "Dosya arşive eklenemedi. İndirerek kullanabilirsiniz." }
            finally { busy = false }
        }
    }

    val current = view
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                val emergencyTexts = view?.emergency
                NovaListHeading(emergencyTexts?.text("title") ?: "Risk Analizi Sihirbazı", { back() })
                NovaText(if (emergencyTexts != null) {
                        if (step == "result") emergencyTexts.text("step.result") + " · ${plan?.cards?.size ?: 0}"
                        else "${index + 1} / ${steps.size - 1}" + (if (step.startsWith("fu:")) emergencyTexts.texts["step.fu"] else emergencyTexts.texts["step.$step"] ?: stepTitles[step])?.let { " · $it" }.orEmpty()
                    } else if (step == "result") "Analiz · ${result?.total ?: 0} madde"
                    else "Adım ${index + 1} / ${steps.size - 1} · ${if (step.startsWith("fu:")) "Takip sorusu" else stepTitles[step].orEmpty()}",
                    style = NovaTypeToken.metaQuiet)
                val progress by animateFloatAsState((index + 1f) / steps.size.coerceAtLeast(1), label = "progress")
                Box(Modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(NovaColorToken.surfaceMuted.color())) {
                    Box(Modifier.fillMaxWidth(progress).fillMaxHeight().background(NovaColorToken.accent.color()))
                }
            }
            LazyColumn(Modifier.weight(1f).padding(horizontal = 20.dp), state = list,
                contentPadding = PaddingValues(top = 4.dp, bottom = 132.dp + novaTabBarInset), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (current == null) item { NovaText(message ?: "Hazırlanıyor…", style = NovaTypeToken.meta) }
                else {
                    val kinds = mapOf(
                        "areas" to ("Hangi alanlarda çalışılıyor?" to "Faaliyetinize göre önerilen alanlar seçili geldi; olmayanları kaldırın."),
                        "equipment" to ("Hangi ekipman ve makineler kullanılıyor?" to "Yalnız işyerinde gerçekten kullanılanları seçin. Her ekipman kendi risklerini ekler."),
                        "materials" to ("Hangi kimyasal ve malzemelerle çalışılıyor?" to "Yakıtlar, gazlar, tozlar ve süreçte açığa çıkan maddeler dahil."),
                        "tasks" to ("Hangi işler yapılıyor?" to "Rutin ve periyodik işleri seçin; bakım, temizlik ve ikmal gibi işler de riski değiştirir."))
                    val emergency = current.emergency
                    when {
                        step == "firm" -> firmPage(current, companies, company, chooser, { chooser = !chooser }, { id ->
                            company = id; chooser = false
                            perform(mapOf("type" to "firm", "field" to "name", "value" to (companies.firstOrNull { it.id == id }?.name ?: "")))
                        }, workplaces, workplace, workplaceChooser, { workplaceChooser = !workplaceChooser }, { workplace = it; workplaceChooser = false },
                            { perform(mapOf("type" to "emp", "value" to it)) }) { field, value -> perform(mapOf("type" to "firm", "field" to field, "value" to value)) }
                        emergency != null && step == "site" -> emergencySitePage(emergency) { perform(it) }
                        emergency != null && step == "cards" -> emergencyCardsPage(emergency, query, cardHits, { value ->
                            query = value; scope.launch { cardHits = if (value.length >= 2) runtime?.cards(value) ?: emptyList() else emptyList() }
                        }) { action -> perform(action) { if (query.length >= 2) cardHits = runtime?.cards(query) ?: emptyList() } }
                        emergency != null && step == "team" -> emergencyTeamPage(emergency, staff, staffQuery, openPerson, { staffQuery = it }, { openPerson = it }) { perform(it) }
                        emergency != null && step == "fields" -> emergencyFieldsPage(emergency) { perform(it) }
                        emergency != null && step == "summary" -> emergencySummaryPage(current, emergency) { go(it) }
                        emergency != null && step == "result" -> plan?.let { p ->
                            emergencyResultPage(p, emergency, busy, emergencyClient != null && company != null, planSaved, expanded,
                                { id -> expanded = if (id in expanded) expanded - id else expanded + id }, { export(it) }) { savePlan() }
                        }
                        step == "sector" -> sectorPage(current, query, sectorHits, { value ->
                            query = value; scope.launch { sectorHits = runtime?.sectors(value) ?: emptyList() }
                        }, { hc -> perform(mapOf("type" to "hc", "id" to hc)) }) { id ->
                            perform(mapOf("type" to "sector", "id" to id)) { query = ""; sectorHits = runtime?.sectors("") ?: emptyList() }
                        }
                        step.startsWith("fu:") -> current.followups.firstOrNull { "fu:" + it.id == step }?.let { f ->
                            item { NovaText(f.context.uppercase(Locale("tr", "TR")), style = NovaTypeToken.overline) }
                            item { PageTitle(f.question, f.help) }
                            f.options.forEach { option ->
                                item(key = f.id + option.id) {
                                    OptionRow(option.title, "", emptyList(), option.badges, option.selected, single = !f.multi) {
                                        perform(mapOf("type" to "fu", "fid" to f.id, "id" to option.id))
                                    }
                                }
                            }
                        }
                        step in kinds -> {
                            val (title, help) = kinds.getValue(step)
                            picksPage(step, title, help, current.picks[step], query, searchHits, { value ->
                                query = value; scope.launch { searchHits = runtime?.search(step, value) ?: emptyList() }
                            }, { perform(mapOf("type" to "all", "kind" to step)) }) { id ->
                                perform(mapOf("type" to "pick", "kind" to step, "id" to id)) { if (query.length >= 2) searchHits = runtime?.search(step, query) ?: emptyList() }
                            }
                        }
                        step == "cond" -> {
                            item { PageTitle("Hangi koşullar geçerli?", "Özel politika gerektiren çalışan grupları ve çalışma düzeni ilgili maddeleri ekler.") }
                            current.conditions.forEach { c -> item(key = "c" + c.id) { OptionRow(c.title, "", emptyList(), emptyList(), c.selected) { perform(mapOf("type" to "cond", "id" to c.id)) } } }
                        }
                        step == "mgmt" -> {
                            val on = current.management.count { it.selected }
                            item { PageTitle("Yönetim ve yasal yükümlülükler", "Eğitim, sağlık gözetimi, acil durum, KKD ve periyodik kontroller her işyerinde değerlendirilir. Uygulanmayanları kapatın.") }
                            item { LinkRow("$on / ${current.management.size} konu açık", if (on == current.management.size) "Tümünü kapat" else "Tümünü aç") { perform(mapOf("type" to "mgAll")) } }
                            current.management.forEach { m -> item(key = m.id) { OptionRow(m.title, m.subtitle, emptyList(), emptyList(), m.selected) { perform(mapOf("type" to "mg", "id" to m.id)) } } }
                        }
                        step == "method" -> {
                            item { PageTitle("Risk hangi yöntemle skorlansın?", "İki yöntem de her zaman hesaplanır; burada raporda hangisinin gösterileceğini seçersiniz.") }
                            listOf(Triple("both", "Fine-Kinney ve 5×5 birlikte", "Önerilen · Denetimlerde en çok istenen biçim"),
                                Triple("fk", "Yalnız Fine-Kinney", "R = O × F × Ş · beş seviye"), Triple("m5", "Yalnız 5×5 (L tipi matris)", "R = O × Ş · 1–25")).forEach { (id, t, s) ->
                                item(key = id) { OptionRow(t, s, emptyList(), emptyList(), current.method == id, single = true) { perform(mapOf("type" to "method", "id" to id)) } }
                            }
                            item { NovaHelpHint("Katalog her madde için tipik saha koşulunda olasılık, frekans ve şiddet önerir. 5×5 olasılığı Fine-Kinney O × F çarpımından türetilir. Önlem sonrası skor, önerilen önlemlerin tamamı uygulandığında beklenen değerdir.") }
                        }
                        step == "cols" -> {
                            item { PageTitle("Tabloda hangi sütunlar olsun?", "Hazır bir düzen seçin ya da sütunları tek tek açıp kapatın. Zorunlu sütunlar kapatılamaz.") }
                            item {
                                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    listOf("standard" to "Standart", "compact" to "Kompakt", "full" to "Denetim için tam").forEach { (id, label) ->
                                        NovaChoiceChip(label, current.preset == id) { perform(mapOf("type" to "preset", "id" to id)) }
                                    }
                                }
                            }
                            current.columns.forEach { c ->
                                item(key = c.id) { OptionRow(c.title, if (c.required) "Zorunlu" else if (c.residual) "Önlem sonrası" else "", emptyList(), emptyList(), c.selected) {
                                    if (!c.required) perform(mapOf("type" to "col", "id" to c.id)) } }
                            }
                        }
                        step == "summary" -> summaryPage(current) { go(it) }
                        step == "result" -> result?.let { r ->
                            resultPage(r, current, dark, filter, scoreView, expanded, busy, archived, { filter = it }, { scoreView = it },
                                { id -> expanded = if (id in expanded) expanded - id else expanded + id }, { export(it) }, { archive() }) { perform(it) }
                        }
                    }
                    message?.let { item { NovaHelpHint(it) } }
                }
            }
        }
        if (current != null) Row(Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(NovaColorToken.canvas.color())
            .padding(start = 20.dp, end = 20.dp, top = 10.dp, bottom = 10.dp + novaTabBarInset), horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            if (step != "firm") NovaButton("Geri", { back() }, symbol = "chevron.left", variant = NovaButtonVariant.Surface, compact = true)
            val emergencyTexts = current.emergency
            if (step == "result" && emergencyTexts != null) NovaButton(emergencyTexts.text("result.download"), { export("docx") },
                Modifier.weight(1f).testTag("emergencyWizard.download"), symbol = "arrow.down.doc", enabled = !busy)
            else if (step == "result") NovaButton("Excel indir", { export("xlsx") }, Modifier.weight(1f).testTag("riskWizard.excel"), symbol = "arrow.down.doc", enabled = !busy)
            else {
                val followup = current.followups.firstOrNull { "fu:" + it.id == step }
                val label = if (emergencyTexts != null && step == "summary") emergencyTexts.text("next.summary")
                    else if (step == "summary") "Analizi oluştur" else if (followup != null && followup.options.none { it.selected }) "Atla" else "Devam"
                NovaButton(label, { if (index + 1 < steps.size) go(steps[index + 1]) }, Modifier.weight(1f).testTag("riskWizard.next"),
                    symbol = if (step == "summary") "sparkles" else "chevron.right", enabled = !busy && !(step == "sector" && current.sectors.isEmpty()))
            }
        }
    }
}

@Composable
internal fun PageTitle(title: String, help: String) {
    Column(Modifier.fillMaxWidth().padding(bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        NovaText(title, style = NovaTypeToken.sheetTitle)
        if (help.isNotEmpty()) NovaText(help, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
    }
}

@Composable
private fun LinkRow(label: String, action: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        NovaText(label, Modifier.weight(1f), style = NovaTypeToken.overline)
        NovaText(action, Modifier.clickable(onClick = onClick).padding(6.dp), style = NovaTypeToken.label, color = NovaColorToken.accentInk.color())
    }
}

@Composable
internal fun Tag(text: String, background: Color, ink: Color) {
    NovaText(text, Modifier.background(background, RoundedCornerShape(6.dp)).padding(horizontal = 7.dp, vertical = 3.dp), style = NovaTypeToken.micro, color = ink)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun OptionRow(title: String, subtitle: String, reasons: List<String>, badges: List<String>, selected: Boolean, single: Boolean = false, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Row(Modifier.fillMaxWidth().clip(shape).background((if (selected) NovaColorToken.accentSoft else NovaColorToken.surface).color())
        .border(1.5.dp, if (selected) NovaColorToken.accent.color() else Color.Transparent, shape)
        .clickable(onClick = onClick).semantics { this.selected = selected }.padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        NovaIcon(if (selected) (if (single) "largecircle.fill.circle" else "checkmark.square.fill") else (if (single) "circle" else "square"), 20.dp,
            tint = if (selected) NovaColorToken.accentInk.color() else NovaColorToken.textTertiary.color())
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaText(title, style = NovaTypeToken.bodyStrong)
            if (subtitle.isNotEmpty()) NovaText(subtitle, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
            if (reasons.isNotEmpty() || badges.isNotEmpty()) FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                badges.forEach { Tag(it, NovaColorToken.statusNeutralBg.color(), NovaColorToken.statusNeutralInk.color()) }
                reasons.forEach { Tag(it, NovaColorToken.statusSuccessBg.color(), NovaColorToken.statusSuccessInk.color()) }
            }
        }
    }
}

@Composable
internal fun InputField(label: String, value: String, placeholder: String, onChange: (String) -> Unit) {
    var text by remember(value) { mutableStateOf(value) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        NovaText(label, style = NovaTypeToken.label)
        Box(Modifier.fillMaxWidth().background(NovaColorToken.surface.color(), RoundedCornerShape(12.dp)).padding(horizontal = 14.dp, vertical = 12.dp)) {
            if (text.isEmpty()) NovaText(placeholder, style = NovaTypeToken.body, color = NovaColorToken.textPlaceholder.color())
            BasicTextField(text, { text = it; onChange(it) }, Modifier.fillMaxWidth(), textStyle = novaTextStyle(NovaTypeToken.body).copy(color = NovaColorToken.text.color()),
                cursorBrush = SolidColor(NovaColorToken.text.color()), singleLine = true)
        }
    }
}

private fun LazyListScope.firmPage(v: RiskWizardView, companies: List<NovaCompanyOption>, company: String?, chooser: Boolean, toggleChooser: () -> Unit,
                                   pickCompany: (String?) -> Unit, workplaces: List<NovaWizardWorkplace>, workplace: String?, workplaceChooser: Boolean,
                                   toggleWorkplaces: () -> Unit, pickWorkplace: (String?) -> Unit, employees: (String) -> Unit, change: (String, String) -> Unit) {
    val emergency = v.emergency
    if (emergency != null) item { PageTitle(emergency.text("firm.title"), emergency.text("firm.help")) }
    else item { PageTitle("Analiz hangi işyeri için?", "İsteğe bağlı; rapor kapağında ve dosya adında kullanılır. Çalışan sayısı kurul ve temsilci gibi genel konuları etkiler.") }
    if (companies.isNotEmpty()) {
        item { NovaChooserButton("Firma", companies.firstOrNull { it.id == company }?.name ?: "Firma seçmeden devam et", "riskWizard.company", open = chooser) { toggleChooser() } }
        if (chooser) item {
            NovaChooserPanel(listOf(NovaChooserOption(null, "Firma seçmeden devam et")) + companies.map { NovaChooserOption(it.id, it.name) }, company, "riskWizard.companies") { pickCompany(it) }
        }
    }
    if (emergency != null && workplaces.size > 1) {
        item { NovaChooserButton("İşyeri", workplaces.firstOrNull { it.id == workplace }?.name ?: "İşyeri seçmeden devam et", "emergencyWizard.workplace", open = workplaceChooser) { toggleWorkplaces() } }
        if (workplaceChooser) item {
            NovaChooserPanel(listOf(NovaChooserOption(null, "İşyeri seçmeden devam et")) + workplaces.map { NovaChooserOption(it.id, it.name) }, workplace, "emergencyWizard.workplaces") { pickWorkplace(it) }
        }
    }
    item { InputField("Firma / işyeri adı", v.firm.name, "Örn. Yıldız Sondaj Ltd.") { change("name", it) } }
    item { InputField("Adres", v.firm.address, "İlçe / il") { change("address", it) } }
    if (emergency != null) item {
        Box(Modifier.testTag("emergencyWizard.employees")) {
            InputField(emergency.text("firm.employees"), emergency.employees?.toString().orEmpty(), emergency.text("firm.employeesPlaceholder")) { employees(it) }
        }
    } else item {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaText("Çalışan sayısı", style = NovaTypeToken.label)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("1-9" to "1–9", "10-49" to "10–49", "50-249" to "50–249", "250+" to "250+").forEach { (id, label) ->
                    NovaChoiceChip(label, v.firm.employees == id) { change("employees", id) }
                }
            }
        }
    }
    item { InputField(emergency?.text("firm.date") ?: "Değerlendirme tarihi", v.firm.date, "gg.aa.yyyy") { change("date", it) } }
}

private fun LazyListScope.sectorPage(v: RiskWizardView, query: String, hits: List<RiskWizardSectorHit>, onQuery: (String) -> Unit,
                                     onHazard: (String) -> Unit, toggle: (String) -> Unit) {
    item { PageTitle("İşyerinin ana faaliyeti nedir?", "Faaliyet adını, bilinen adıyla ya da NACE kodunu yazın. İlk seçtiğiniz ana faaliyet sayılır.") }
    if (v.sectors.isNotEmpty()) {
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                v.sectors.forEachIndexed { i, s -> NovaChoiceChip((if (i == 0) "Ana: " else "") + s.title + "  ✕", true) { toggle(s.id) } }
            }
        }
        item {
            NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                NovaText("Tehlike sınıfı", style = NovaTypeToken.label)
                NovaText(if (v.hazardClassManual) "Elle seçildi" else "Faaliyete göre önerildi; firmanın NACE koduyla doğrulayın", style = NovaTypeToken.metaQuiet)
                Spacer(Modifier.height(8.dp))
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("low" to "Az tehlikeli", "medium" to "Tehlikeli", "high" to "Çok tehlikeli").forEach { (id, label) ->
                        NovaChoiceChip(label, v.hazardClass == id) { onHazard(id) }
                    }
                }
            }
        }
    }
    item { NovaSearchCapsule(query, "Örn. su sondajı, akaryakıt, 47.30", "riskWizard.sectorSearch") { onQuery(it) } }
    item { NovaText(if (query.length < 2) "Sık seçilenler" else "${hits.size} sonuç", style = NovaTypeToken.overline) }
    hits.forEach { hit ->
        item(key = "s" + hit.id) {
            OptionRow(hit.title, hit.subtitle, emptyList(), if (hit.hazardClassLabel.isEmpty()) emptyList() else listOf(hit.hazardClassLabel),
                v.sectors.any { it.id == hit.id }) { toggle(hit.id) }
        }
    }
    if (query.length >= 2 && hits.isEmpty()) item { NovaText("Bu aramayla faaliyet bulunamadı. Daha genel bir kelime deneyin (ör. inşaat, depo, sondaj).", style = NovaTypeToken.metaQuiet) }
}

private fun LazyListScope.picksPage(kind: String, title: String, help: String, picks: RiskWizardPicks?, query: String, hits: List<RiskWizardPick>,
                                    onQuery: (String) -> Unit, onAll: () -> Unit, toggle: (String) -> Unit) {
    item { PageTitle(title, help) }
    item { LinkRow("Önerilenler · ${picks?.suggested?.size ?: 0}", if (picks?.suggested.isNullOrEmpty()) "" else if (picks?.allSelected == true) "Seçimi kaldır" else "Tümünü seç") { onAll() } }
    if (picks?.suggested.isNullOrEmpty()) item { NovaText("Bu faaliyet için hazır öneri yok. Aşağıdan arayarak ekleyebilirsiniz.", style = NovaTypeToken.metaQuiet) }
    fun row(p: RiskWizardPick, prefix: String) = item(key = prefix + p.id) {
        OptionRow(p.title, listOf(p.subtitle, p.detail).filter { it.isNotEmpty() }.joinToString("\n"), p.reasons, p.badges, p.selected) { toggle(p.id) }
    }
    picks?.suggested?.forEach { row(it, "s") }
    if (!picks?.added.isNullOrEmpty()) { item { NovaText("Eklediğiniz · ${picks?.added?.size}", style = NovaTypeToken.overline) }; picks?.added?.forEach { row(it, "a") } }
    if (!picks?.generic.isNullOrEmpty()) { item { NovaText("Diğer genel alanlar", style = NovaTypeToken.overline) }; picks?.generic?.forEach { row(it, "g") } }
    item { NovaText("Başka ekle", style = NovaTypeToken.overline) }
    item { NovaSearchCapsule(query, "Listede yoksa arayın", "riskWizard.search.$kind") { onQuery(it) } }
    hits.forEach { row(it, "h") }
}

private fun LazyListScope.summaryPage(v: RiskWizardView, edit: (String) -> Unit) {
    item { PageTitle("${v.rowCount} risk maddesiyle analiz hazır", "Seçimlerinizi kontrol edin. Analizi oluşturduktan sonra satırları düzenleyebilir, çıkarabilir ve indirebilirsiniz.") }
    item {
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            listOf(Triple("İşyeri", v.firm.name.ifEmpty { "—" }, "firm"),
                Triple("Faaliyet", v.sectors.joinToString(", ") { it.title } + if (v.hazardClassLabel.isNotEmpty()) " · " + v.hazardClassLabel else "", "sector"),
                Triple("Alanlar", "${v.picks["areas"]?.count ?: 0} seçili", "areas"), Triple("Ekipmanlar", "${v.picks["equipment"]?.count ?: 0} seçili", "equipment"),
                Triple("Maddeler", "${v.picks["materials"]?.count ?: 0} seçili", "materials"), Triple("İşler", "${v.picks["tasks"]?.count ?: 0} seçili", "tasks"),
                Triple("Genel konular", "${v.management.count { it.selected }} konu", "mgmt"),
                Triple("Yöntem", mapOf("both" to "Fine-Kinney ve 5×5", "fk" to "Fine-Kinney", "m5" to "5×5")[v.method] ?: v.method, "method")).forEach { (label, value, target) ->
                Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f)) {
                        NovaText(label, style = NovaTypeToken.metaQuiet)
                        NovaText(value, style = NovaTypeToken.body)
                    }
                    NovaText("Düzenle", Modifier.clickable { edit(target) }.padding(4.dp), style = NovaTypeToken.label, color = NovaColorToken.accentInk.color())
                }
            }
        }
    }
    item { NovaCard(Modifier.fillMaxWidth(), padding = 14) { Distribution("Önerilen skorlara göre · Fine-Kinney", listOf("Mevcut" to (v.counts["fk"] ?: emptyMap()))) } }
}

@Composable
private fun Distribution(title: String, sets: List<Pair<String, Map<String, Int>>>) {
    NovaText(title, style = NovaTypeToken.cardTitle)
    Spacer(Modifier.height(6.dp))
    sets.forEach { (label, counts) ->
        val total = counts.values.sum().coerceAtLeast(1)
        Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaText(label, Modifier.width(96.dp), style = NovaTypeToken.metaQuiet)
            Row(Modifier.weight(1f).height(10.dp).clip(CircleShape)) {
                RiskTone.order.forEach { level -> val n = counts[level] ?: 0; if (n > 0) Box(Modifier.weight(n.toFloat() / total).fillMaxHeight().background(RiskTone.bar(level))) }
            }
            NovaText("${counts.values.sum()}", Modifier.width(34.dp), style = NovaTypeToken.meta)
        }
    }
    RiskTone.order.forEach { level ->
        Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.size(10.dp).clip(RoundedCornerShape(3.dp)).background(RiskTone.bar(level)))
            NovaText(RiskTone.names[level].orEmpty(), Modifier.weight(1f), style = NovaTypeToken.meta)
            sets.forEach { (_, counts) -> NovaText("${counts[level] ?: 0}", Modifier.width(44.dp), style = NovaTypeToken.meta) }
        }
    }
}

private fun number(value: Double) = if (value == Math.rint(value)) value.toLong().toString() else String.format(Locale("tr", "TR"), "%.1f", value)

@Composable
private fun LevelChip(score: RiskWizardScore, dark: Boolean, showScore: Boolean = true) {
    val (background, ink) = RiskTone.colors(score.level, dark)
    Row(Modifier.background(background, RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Box(Modifier.size(6.dp).clip(CircleShape).background(ink))
        NovaText((if (showScore) number(score.score) + " · " else "") + score.label, style = NovaTypeToken.badge, color = ink, maxLines = 1)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ScorePair(label: String, before: RiskWizardScore, after: RiskWizardScore, dark: Boolean) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        NovaText(label, Modifier.width(26.dp).align(Alignment.CenterVertically), style = NovaTypeToken.micro)
        LevelChip(before, dark)
        NovaIcon("arrow.right", 12.dp, Modifier.align(Alignment.CenterVertically), tint = NovaColorToken.textSecondary.color())
        LevelChip(after, dark)
    }
}

private fun LazyListScope.resultPage(r: RiskWizardResult, v: RiskWizardView, dark: Boolean, filter: String, scoreView: String, expanded: Set<String>,
                                     busy: Boolean, archived: Boolean, onFilter: (String) -> Unit, onScoreView: (String) -> Unit, onToggle: (String) -> Unit,
                                     onExport: (String) -> Unit, onArchive: () -> Unit, act: (Map<String, Any?>) -> Unit) {
    val showFK = r.method != "m5" && (r.method != "both" || scoreView == "fk")
    val showM5 = r.method != "fk" && (r.method != "both" || scoreView == "m5")
    item { PageTitle(v.firm.name.ifEmpty { "Risk değerlendirmesi" }, v.sectors.joinToString(", ") { it.title } + " · ${r.total} madde" + if (r.removedCount > 0) " · ${r.removedCount} çıkarıldı" else "") }
    if (r.method != "m5") item { NovaCard(Modifier.fillMaxWidth(), padding = 14) { Distribution("Fine-Kinney", listOf("Mevcut" to (r.counts["fk"] ?: emptyMap()), "Önlem sonrası" to (r.counts["rfk"] ?: emptyMap()))) } }
    if (r.method != "fk") item { NovaCard(Modifier.fillMaxWidth(), padding = 14) { Distribution("5×5 matris", listOf("Mevcut" to (r.counts["m5"] ?: emptyMap()), "Önlem sonrası" to (r.counts["rm5"] ?: emptyMap()))) } }
    item {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaButton("Word", { onExport("docx") }, symbol = "doc.text", variant = NovaButtonVariant.Surface, enabled = !busy, compact = true)
            NovaButton("PDF", { onExport("pdf") }, symbol = "doc.richtext", variant = NovaButtonVariant.Surface, enabled = !busy, compact = true)
            NovaButton(if (archived) "Arşivde" else "Arşive ekle", onArchive, symbol = "folder.badge.plus", variant = NovaButtonVariant.Surface, enabled = !busy && !archived, compact = true)
        }
    }
    if (r.method == "both") item {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaChoiceChip("Fine-Kinney", scoreView == "fk") { onScoreView("fk") }
            NovaChoiceChip("5×5", scoreView == "m5") { onScoreView("m5") }
        }
    }
    item {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("all" to "Tümü", "critical" to "Tolerans dışı", "high" to "Yüksek", "medium" to "Önemli / orta", "low" to "Olası / düşük", "removed" to "Çıkarılan").forEach { (id, label) ->
                NovaChoiceChip(label, filter == id) { onFilter(id) }
            }
        }
    }
    val rows = r.rows.filter { row ->
        when (filter) {
            "all" -> true
            "removed" -> row.removed
            else -> !row.removed && (if (showM5 && !showFK) row.m5.level else row.fk.level) == filter
        }
    }
    if (rows.isEmpty()) item { NovaText("Bu filtrede madde yok.", style = NovaTypeToken.metaQuiet) }
    rows.forEachIndexed { i, row ->
        if (i == 0 || rows[i - 1].section != row.section) item(key = "h" + row.id) { NovaText(row.section, Modifier.padding(top = 10.dp), style = NovaTypeToken.cardTitle) }
        item(key = row.id) { ResultRow(row, dark, showFK, showM5, row.id in expanded, { onToggle(row.id) }, act) }
    }
    item { NovaHelpHint("Skorlar katalog önerisidir; değerlendirme ekibi sahada doğrulamalı ve gerektiğinde düzenlemelidir.") }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ResultRow(row: RiskWizardRow, dark: Boolean, showFK: Boolean, showM5: Boolean, open: Boolean, onToggle: () -> Unit, act: (Map<String, Any?>) -> Unit) {
    NovaCard(Modifier.fillMaxWidth().alpha(if (row.removed) 0.55f else 1f).testTag("riskWizard.row.${row.id}"), padding = 14) {
        Row(Modifier.fillMaxWidth().clickable(onClick = onToggle), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaText(if (row.removed) "—" else "${row.number}", Modifier.width(24.dp), style = NovaTypeToken.metaQuiet)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                NovaText(row.hazard, style = NovaTypeToken.bodyStrong)
                NovaText(row.risk, style = NovaTypeToken.meta)
                if (showFK) ScorePair("FK", row.fk, row.rfk, dark)
                if (showM5 || open) ScorePair("5×5", row.m5, row.rm5, dark)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (row.isNew) RiskTone.colors("low", dark).let { Tag("Yeni", it.first, it.second) }
                    if (row.edited) Tag("Düzenlendi", NovaColorToken.statusInfoBg.color(), NovaColorToken.statusInfoInk.color())
                    if (row.severe) RiskTone.colors("high", dark).let { Tag("Ağır sonuç", it.first, it.second) }
                }
            }
            NovaIcon(if (open) "chevron.up" else "chevron.down", 16.dp, tint = NovaColorToken.textSecondary.color())
        }
        if (open) {
            Spacer(Modifier.height(10.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (row.check.isNotEmpty()) NovaHelpHint("Sahada kontrol: " + row.check)
                Detail("Olası sonuç", row.consequence)
                if (row.affected.isNotEmpty()) Detail("Etkilenenler", row.affected)
                Detail("Neden geldi", row.reasons.joinToString(" · "))
                if (row.owner.isNotEmpty()) Detail("Sorumlu", row.owner)
                if (row.legal.isNotEmpty()) Detail("Mevzuat", row.legal.joinToString(" · "))
                NovaText("Alınacak önlemler", style = NovaTypeToken.label)
                row.controls.forEach { control ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val tone = when (control.hierarchy) {
                            "ppe" -> RiskTone.colors("high", dark)
                            "administrative" -> NovaColorToken.statusNeutralBg.color() to NovaColorToken.statusNeutralInk.color()
                            "engineering" -> NovaColorToken.statusInfoBg.color() to NovaColorToken.statusInfoInk.color()
                            else -> RiskTone.colors("low", dark)
                        }
                        Tag(control.label, tone.first, tone.second)
                        Column(Modifier.weight(1f)) {
                            NovaText(control.text, style = NovaTypeToken.body)
                            if (control.owner.isNotEmpty()) NovaText(control.owner, style = NovaTypeToken.metaQuiet)
                        }
                    }
                }
                ScoreEditor("Fine-Kinney · mevcut", row.fk, dark, null, listOf(
                    Triple("O", "p", listOf(0.2, 0.5, 1.0, 3.0, 6.0, 10.0)), Triple("F", "f", listOf(0.5, 1.0, 2.0, 3.0, 6.0, 10.0)), Triple("Ş", "s", listOf(1.0, 3.0, 7.0, 15.0, 40.0, 100.0)))) { f, value ->
                    act(mapOf("type" to "edit", "id" to row.id, "key" to "fk", "field" to f, "value" to value)) }
                ScoreEditor("Fine-Kinney · önlem sonrası", row.rfk, dark, null, listOf(
                    Triple("O", "p", listOf(0.2, 0.5, 1.0, 3.0, 6.0, 10.0)), Triple("F", "f", listOf(0.5, 1.0, 2.0, 3.0, 6.0, 10.0)), Triple("Ş", "s", listOf(1.0, 3.0, 7.0, 15.0, 40.0, 100.0)))) { f, value ->
                    act(mapOf("type" to "edit", "id" to row.id, "key" to "rfk", "field" to f, "value" to value)) }
                val five = listOf(1.0, 2.0, 3.0, 4.0, 5.0)
                ScoreEditor("5×5 · mevcut", row.m5, dark, if (row.m5Manual) "Elle girildi" else "FK’dan türetildi", listOf(Triple("O", "l", five), Triple("Ş", "s", five))) { f, value ->
                    act(mapOf("type" to "edit", "id" to row.id, "key" to "m5", "field" to f, "value" to value)) }
                ScoreEditor("5×5 · önlem sonrası", row.rm5, dark, if (row.rm5Manual) "Elle girildi" else "FK’dan türetildi", listOf(Triple("O", "l", five), Triple("Ş", "s", five))) { f, value ->
                    act(mapOf("type" to "edit", "id" to row.id, "key" to "rm5", "field" to f, "value" to value)) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaButton(if (row.removed) "Geri al" else "Analizden çıkar", { act(mapOf("type" to if (row.removed) "restore" else "remove", "id" to row.id)) },
                        symbol = if (row.removed) "arrow.uturn.backward" else "trash", variant = NovaButtonVariant.Surface, compact = true)
                    if (row.edited) NovaButton("Önerilen skora dön", { act(mapOf("type" to "reset", "id" to row.id)) }, symbol = "arrow.counterclockwise",
                        variant = NovaButtonVariant.Surface, compact = true)
                }
            }
        }
    }
}

@Composable
private fun Detail(label: String, value: String) {
    Column {
        NovaText(label, style = NovaTypeToken.metaQuiet)
        NovaText(value, style = NovaTypeToken.body)
    }
}

@Composable
private fun ScoreEditor(title: String, score: RiskWizardScore, dark: Boolean, note: String?, factors: List<Triple<String, String, List<Double>>>,
                        onPick: (String, Double) -> Unit) {
    var menu by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxWidth().background(NovaColorToken.surfaceMuted.color().copy(alpha = 0.6f), RoundedCornerShape(14.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            NovaText(title, Modifier.weight(1f), style = NovaTypeToken.label)
            note?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            factors.forEach { (label, field, values) ->
                val current = when (field) { "p" -> score.p; "f" -> score.f; "l" -> score.l; else -> score.s } ?: 0.0
                Column(Modifier.widthIn(min = 46.dp).heightIn(min = 44.dp).background(NovaColorToken.surface.color(), RoundedCornerShape(10.dp))
                    .clickable { menu = if (menu == field) null else field }.padding(horizontal = 8.dp, vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    NovaText(label, style = NovaTypeToken.micro)
                    NovaText(number(current), style = NovaTypeToken.bodyStrong)
                }
            }
            Spacer(Modifier.weight(1f))
            NovaText(number(score.score), style = NovaTypeToken.sectionTitle)
        }
        factors.firstOrNull { it.second == menu }?.let { (_, field, values) ->
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                values.forEach { value -> NovaChoiceChip(number(value), false) { menu = null; onPick(field, value) } }
            }
        }
        LevelChip(score, dark, showScore = false)
    }
}
