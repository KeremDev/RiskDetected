package com.riskdetectedan.feature.nova

import android.content.Context
import androidx.activity.compose.BackHandler
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.*
import com.riskdetectedan.core.data.nova.NovaNonconformitySeverity
import com.riskdetectedan.core.data.nova.NovaRiskScoreInput
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.time.LocalDate
import java.util.UUID

/** "n/m başlık tamamlandı" with its bar (iOS `IsgParityProgress`). */
@Composable
private fun OsgbParityProgress(completed: Int, total: Int) {
    NovaCard(Modifier.fillMaxWidth(), padding = 12) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                NovaText("$completed/$total başlık tamamlandı", Modifier.weight(1f), NovaTypeToken.label)
                NovaStatusPill(if (completed == total) "Kaydedilebilir" else "Bilgi bekliyor", if (completed == total) NovaStatus.Success else NovaStatus.Warning)
            }
            Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(NovaColorToken.borderMuted.color())) {
                Box(Modifier.fillMaxWidth(completed.toFloat() / maxOf(1, total)).fillMaxHeight().clip(CircleShape).background(NovaColorToken.accent.color()))
            }
        }
    }
}

/** "Akıştan çıkılsın mı?" for flows whose progress would be lost. */
@Composable
private fun OsgbExitConfirm(visible: Boolean, title: String, onExit: () -> Unit, onStay: () -> Unit) {
    NovaPopup(visible, onStay, identifier = "osgb.exit.confirm") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaPopupHeading(title, "exclamationmark.triangle", subtitle = "Henüz kaydedilmemiş bilgiler silinir.")
            NovaPopupOption("Çık", "xmark.circle", identifier = "osgb.exit.leave") { onStay(); onExit() }
            NovaPopupOption("Devam et", "arrow.right", identifier = "osgb.exit.stay", onClick = onStay)
        }
    }
}

@Composable
private fun OsgbReview(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        NovaText(label, style = NovaTypeToken.metaQuiet)
        NovaText(value.ifEmpty { "Belirtilmedi" }, style = NovaTypeToken.bodyStrong)
    }
}

private data class OsgbTopic(val id: String = UUID.randomUUID().toString(), val title: String, val minutes: Int)

private fun topicPlan(total: Int, workSpecific: Int): List<OsgbTopic> {
    val remaining = total - workSpecific
    val general = remaining / 6; val health = remaining / 3
    return listOf(OsgbTopic(title = "Genel konular", minutes = general), OsgbTopic(title = "Sağlık konuları", minutes = health),
        OsgbTopic(title = "Teknik konular", minutes = remaining - general - health), OsgbTopic(title = "İşe özgü riskler", minutes = workSpecific))
}

private data class OsgbStatutoryPreset(val id: String, val title: String, val validityYears: Int, val topics: List<OsgbTopic>) {
    val minutes: Int get() = topics.sumOf { it.minutes }
}

private val statutoryPresets = listOf(
    OsgbStatutoryPreset("legal-low", "Temel İSG Eğitimi · Az Tehlikeli", 3, topicPlan(480, 120)),
    OsgbStatutoryPreset("legal-medium", "Temel İSG Eğitimi · Tehlikeli", 2, topicPlan(720, 180)),
    OsgbStatutoryPreset("legal-high", "Temel İSG Eğitimi · Çok Tehlikeli", 1, topicPlan(960, 240)),
)

/**
 * Eğitim ekle for a workspace company (iOS `IsgWorkspaceTrainingCreateEditor`): a completed training from a statutory
 * template, the OSGB catalog or a custom title, recorded and completed in one replay-safe workflow.
 */
@Composable
fun NovaOsgbTrainingCreateEditor(scope: NovaOsgbScope, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    val steps = listOf("Eğitim ve konular", "Tarih, yöntem ve yer", "Eğiticiler", "Katılımcılar", "Kontrol ve kaydet")
    var curricula by remember { mutableStateOf<List<IsgWorkspaceAdvancedRecord>>(emptyList()) }
    var employees by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var curriculumId by remember { mutableStateOf<String?>(null) }
    var templateKey by remember { mutableStateOf("custom") }
    var topics by remember { mutableStateOf<List<OsgbTopic>>(emptyList()) }
    var validityYears by remember { mutableIntStateOf(1) }
    var title by remember { mutableStateOf("") }
    var trainer by remember { mutableStateOf("") }
    var method by remember { mutableStateOf("face_to_face") }
    var location by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var notesOpen by remember { mutableStateOf(false) }
    var heldOn by remember { mutableStateOf(osgbToday()) }
    var hasValidity by remember { mutableStateOf(false) }
    var validUntil by remember { mutableStateOf(LocalDate.now().plusYears(1).toString()) }
    var minutes by remember { mutableIntStateOf(60) }
    var query by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }
    var attachment by remember { mutableStateOf<OsgbAttachment?>(null) }
    var step by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var validation by remember { mutableStateOf<String?>(null) }
    var editingTopics by remember { mutableStateOf(false) }
    var confirmingExit by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf(false) }
    val workflow = remember { OsgbWorkflowIds() }
    val usable = curricula.filter { it.status == "published" && !it.flag("assessment_required") }
    fun syncMinutes(values: List<OsgbTopic>) { minutes = maxOf(1, values.sumOf { maxOf(0, it.minutes) }) }
    fun refreshValidity() { validUntil = runCatching { LocalDate.parse(heldOn).plusYears(validityYears.toLong()).toString() }.getOrDefault(validUntil) }
    fun applyTemplate(key: String) {
        templateKey = key
        statutoryPresets.firstOrNull { it.id == key }?.let { preset ->
            curriculumId = null; title = preset.title; topics = preset.topics; validityYears = preset.validityYears; hasValidity = true
            syncMinutes(topics); refreshValidity(); return
        }
        usable.firstOrNull { "curriculum:${it.id}" == key }?.let { row ->
            curriculumId = row.id; title = row.title
            topics = row.topics.map { OsgbTopic(title = it.title, minutes = it.durationMinutes) }
                .ifEmpty { listOf(OsgbTopic(title = row.title, minutes = row.text("total_minutes")?.toIntOrNull() ?: 60)) }
            validityYears = 1; syncMinutes(topics); return
        }
        curriculumId = null; topics = emptyList()
    }
    LaunchedEffect(Unit) {
        loading = true; error = null
        try {
            coroutineScope {
                val a = async { scope.repository.trainingRecords(scope.context, scope.companyId, IsgWorkspaceTrainingAdvancedKind.CURRICULA) }
                val b = async { scope.repository.directory(scope.context, scope.companyId, "employees") }
                curricula = a.await(); employees = b.await()
            }
            applyTemplate(when (scope.companyHazardClass.lowercase()) {
                "low", "az_tehlikeli", "az tehlikeli" -> "legal-low"; "high", "cok_tehlikeli", "çok tehlikeli" -> "legal-high"; else -> "legal-medium"
            })
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
            error = "Eğitim kataloğu veya personel listesi yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin."
        }
        loading = false
    }
    if (saved) {
        NovaTaskSuccessView("Eğitim kaydedildi", "${selected.size} katılımcı için $minutes dakikalık gerçekleşen eğitim kaydı oluşturuldu.",
            "Eğitimlere dön", onDone)
        return
    }
    if (editingTopics) {
        BackHandler { editingTopics = false }
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(18.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                NovaPageHeading("Konular ve süre", onBack = { editingTopics = false })
                Row(verticalAlignment = Alignment.CenterVertically) {
                    NovaText("Toplam süre", Modifier.weight(1f), NovaTypeToken.metaQuiet)
                    NovaText("$minutes dakika", style = NovaTypeToken.sectionTitle)
                }
                topics.forEachIndexed { index, topic ->
                    fun update(value: OsgbTopic) { topics = topics.toMutableList().also { it[index] = value }; syncMinutes(topics) }
                    NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                        Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                            NovaTextField("Konu", topic.title, { update(topic.copy(title = it)) }, identifier = "osgb.training.topic.$index")
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Box(Modifier.weight(1f)) {
                                    OsgbStepper("${topic.minutes} dakika", topic.minutes, 5..2_000, "osgb.training.topic.$index.minutes") {
                                        update(topic.copy(minutes = (it / 5) * 5))
                                    }
                                }
                                Box(Modifier.size(44.dp).clip(CircleShape).novaRowPress {
                                    topics = topics.filterIndexed { i, _ -> i != index }; syncMinutes(topics)
                                }.semantics { contentDescription = "Konuyu sil" }, contentAlignment = Alignment.Center) {
                                    NovaIcon("trash", 16.dp, tint = NovaColorToken.statusDangerInk.color())
                                }
                            }
                        }
                    }
                }
                NovaCompactActionButton("İşyerine özgü konu ekle", "plus", Modifier.width(IntrinsicSize.Max)) {
                    topics = topics + OsgbTopic(title = "", minutes = 30); syncMinutes(topics)
                }
            }
            NovaTaskStickyActions("Bitti", onBack = {}, onPrimary = { editingTopics = false }, primarySymbol = "checkmark", canGoBack = false)
        }
        return
    }
    val completeFlags = listOf(
        title.isNotBlank() && minutes > 0,
        heldOn <= osgbToday() && (!hasValidity || validUntil > heldOn),
        trainer.isNotBlank(),
        selected.isNotEmpty(),
    )
    fun complete(index: Int) = if (index == 4) completeFlags.all { it } else completeFlags[index]
    fun save() {
        if (!completeFlags.all { it } || saving) return
        val participants = selected.sorted()
        val topicText = topics.mapIndexed { index, topic -> "${index + 1}. ${topic.title.trim()} (${topic.minutes} dk)" }.joinToString("\n")
        val trainingNotes = listOf(notes.trim(), if (topicText.isEmpty()) "" else "Eğitim konuları:\n$topicText").filter { it.isNotEmpty() }.joinToString("\n\n")
        val create = buildJsonObject {
            put("action", "save"); put("expected_version", 0); put("title", title.trim()); put("trainer", trainer.trim()); put("method", method)
            put("starts_at", osgbInstant(heldOn)); put("duration_minutes", minutes)
            put("valid_until", if (hasValidity) JsonPrimitive(validUntil) else JsonNull); put("location", location.trim()); put("notes", trainingNotes)
            put("participants", JsonArray(participants.map { buildJsonObject { put("id", it); put("attended", false) } }))
        }
        saving = true; error = null
        coroutines.launch {
            try {
                val uploaded = attachment?.let { file ->
                    scope.repository.uploadFile(scope.context, workflow.id("training.file.upload",
                        buildJsonObject { put("filename", file.filename); put("digest", file.digest) }), scope.companyId, file.title, file.filename,
                        "training_material", file.data)
                }
                val created = scope.repository.mutateDomain(scope.context, workflow.id("training.create", create), scope.companyId,
                    IsgWorkspaceDomain.TRAINING, create)
                val id = IsgWorkspaceMutations.recordId(created) ?: error("id")
                var expected = IsgWorkspaceMutations.version(created) ?: 0
                curriculumId?.let { curriculum ->
                    val link = buildJsonObject {
                        put("action", "training_link_curriculum"); put("id", id); put("expected_version", expected); put("curriculum_id", curriculum)
                    }
                    scope.repository.mutateTrainingAdvanced(scope.context, workflow.id("training.link", link), scope.companyId, link)
                    expected = scope.repository.snapshot(scope.context, scope.companyId, IsgWorkspaceDomain.TRAINING).rows
                        .firstOrNull { it.id.equals(id, true) }?.version ?: error("version")
                }
                val complete = buildJsonObject {
                    put("action", "complete"); put("id", id); put("expected_version", expected)
                    put("participants", JsonArray(participants.map { buildJsonObject { put("id", it); put("attended", true) } }))
                }
                scope.repository.mutateDomain(scope.context, workflow.id("training.complete", complete), scope.companyId, IsgWorkspaceDomain.TRAINING, complete)
                uploaded?.let { (entry, _) ->
                    scope.repository.mutateDomain(scope.context, workflow.id("training.file.attach",
                        buildJsonObject { put("entry_id", entry); put("parent_id", id) }), scope.companyId, IsgWorkspaceDomain.FILES, buildJsonObject {
                        put("action", "attach"); put("entry_id", entry); put("parent_kind", "training"); put("parent_id", id); put("field_name", "attachment")
                    })
                }
                celebrate("Eğitim kaydı oluşturuldu!")
                saved = true
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                error = "Eğitim tamamlanamadı. Katalog, tarih, eğitici ve katılımcı bilgilerini kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }
    OsgbExitConfirm(confirmingExit, "Eğitim akışından çıkılsın mı?", onDone) { confirmingExit = false }
    NovaModuleTask("Eğitim ekle", step + 1, steps.size, steps[step], if (step == 4) "Eğitimi kaydet" else "Devam",
        if (step == 4) "checkmark" else "arrow.right", saving, { if (step > 0) { validation = null; step-- } else confirmingExit = true }, {
            validation = null
            when {
                !complete(step) -> validation = listOf("Eğitim başlığını ve toplam süreyi kontrol edin.", "Eğitim tarihi ve geçerlilik bilgisini kontrol edin.",
                    "En az bir eğitici adı veya kurum bilgisi girin.", "En az bir katılımcı seçin.", "Önceki adımlarda tamamlanmamış bilgi var.")[step]
                step < 4 -> step++
                else -> save()
            }
        }, error) {
        if (loading) { NovaLoadingView("Eğitim kataloğu ve personel hazırlanıyor…"); return@NovaModuleTask }
        NovaText("Bilgiler akış boyunca korunur.", style = NovaTypeToken.micro)
        validation?.let { NovaTaskErrorSummary(it) }
        when (step) {
            0 -> {
                OsgbPicker("Kayıtlı eğitim", listOf("custom") + statutoryPresets.map { it.id } + usable.map { "curriculum:${it.id}" }, templateKey,
                    "osgb.training.template", mapOf("custom" to "Özel eğitim") + statutoryPresets.associate { it.id to "${it.title} · ${it.minutes} dk" } +
                        usable.associate { "curriculum:${it.id}" to "${it.title} · ${it.text("total_minutes") ?: "0"} dk" }) { applyTemplate(it) }
                NovaTextField("Eğitim başlığı", title, { title = it }, identifier = "osgb.training.title")
                if (topics.isNotEmpty()) Row(Modifier.fillMaxWidth().heightIn(min = 54.dp).clip(RoundedCornerShape(14.dp)).novaControlBackground(14.dp)
                    .novaRowPress { editingTopics = true }.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(11.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("list.bullet.rectangle", 18.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        NovaText("Konular ve süre", style = NovaTypeToken.bodyStrong)
                        NovaText("${topics.size} konu · $minutes dakika", style = NovaTypeToken.metaQuiet)
                    }
                    NovaIcon("chevron.right", 12.dp)
                } else OsgbStepper("Süre: $minutes dakika", minutes, 1..100_000, "osgb.training.minutes") { minutes = it }
                NovaCompanyAccordion("Ek bilgiler", "note.text", notesOpen, { notesOpen = it }, identifier = "osgb.training.notes") {
                    NovaTextField("Eğitim notu (isteğe bağlı)", notes, { notes = it }, identifier = "osgb.training.note", multiline = true)
                }
            }
            1 -> {
                NovaDayField("Tamamlandığı tarih", heldOn, { heldOn = minOf(it, osgbToday()); if (hasValidity) refreshValidity() }, "osgb.training.date")
                NovaSegmentedControl(listOf("face_to_face", "online", "mixed").map(IsgWorkspaceDisplayText::value),
                    listOf("face_to_face", "online", "mixed").indexOf(method).coerceAtLeast(0)) { method = listOf("face_to_face", "online", "mixed")[it] }
                NovaTextField("Konum / toplantı bağlantısı", location, { location = it }, identifier = "osgb.training.location")
                NovaCompanyToggleRow("Geçerlilik tarihi ekle", hasValidity, !saving) { hasValidity = it; if (it) refreshValidity() }
                if (hasValidity) {
                    NovaDayField("Geçerlilik tarihi", validUntil, { validUntil = it }, "osgb.training.valid")
                    NovaHelpHint("Tarih tehlike sınıfına göre $validityYears yıl sonrası olarak önerildi; gerekirse değiştirebilirsiniz.")
                }
            }
            2 -> {
                NovaTextField("Eğitici ad soyad / kurum", trainer, { trainer = it }, identifier = "osgb.training.trainer")
                NovaHelpHint("Eğitici bu gerçekleşen eğitim kaydının tamamı için kullanılır.")
            }
            3 -> {
                val needle = query.trim()
                val rows = if (needle.isEmpty()) employees else employees.filter { it.second.contains(needle, true) }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    NovaText("Firma personeli", Modifier.weight(1f), NovaTypeToken.bodyStrong)
                    NovaText("${selected.size} seçili", style = NovaTypeToken.metaQuiet)
                }
                NovaSearchCapsule(query, "Personel ara", "osgb.training.search") { query = it }
                if (employees.isNotEmpty()) {
                    val all = selected.size == employees.size
                    NovaCompactActionButton(if (all) "Seçimi temizle" else "Tümünü seç", if (all) "xmark.circle" else "checkmark.circle",
                        Modifier.width(IntrinsicSize.Max)) { selected = if (all) emptySet() else employees.map { it.first }.toSet() }
                }
                when {
                    employees.isEmpty() -> NovaHelpHint("Eğitim kaydetmek için önce firma personeli ekleyin.")
                    rows.isEmpty() -> NovaHelpHint("Aramanızla eşleşen personel bulunamadı.")
                }
                rows.forEach { (id, name) ->
                    NovaRadioRow(name, id in selected, identifier = "osgb.training.employee.$id") {
                        selected = if (id in selected) selected - id else selected + id
                    }
                }
                NovaHelpHint("Kaydettiğinizde seçilen personelin eğitime katıldığını beyan etmiş olursunuz.")
            }
            else -> {
                NovaText("Kaydetmeden önce kontrol edin", style = NovaTypeToken.sectionTitle)
                NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        OsgbReview("Eğitim", title); NovaDivider()
                        OsgbReview("Yöntem", IsgWorkspaceDisplayText.value(method)); OsgbReview("Tarih", heldOn)
                        OsgbReview("Süre", "$minutes dakika"); OsgbReview("Eğitici", trainer); OsgbReview("Katılımcı", "${selected.size} kişi")
                        if (location.isNotBlank()) OsgbReview("Yer", location.trim())
                    }
                }
                OsgbAttachmentField("Eğitim belgesi veya yoklama ekle (isteğe bağlı)", attachment, { attachment = it })
                NovaHelpHint("Bir bilgiyi değiştirmek için Geri ile ilgili adıma dönebilirsiniz.")
            }
        }
    }
}

private fun scoreText(value: Double) = if (value % 1.0 == 0.0) value.toLong().toString() else value.toString().replace('.', ',')

/**
 * Elle Uygunsuzluk for a workspace company (iOS `IsgWorkspaceManualNonconformityEditor`): the same six headings as
 * the expert panel; hazard, control, legislation and score travel as the first corrective action.
 */
@Composable
fun NovaOsgbManualNonconformityEditor(scope: NovaOsgbScope, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    val steps = listOf("attachment", "workplace", "hazard", "scoring", "legislation", "responsible")
    var workplaces by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var workplaceId by remember { mutableStateOf<String?>(null) }
    var title by remember { mutableStateOf("") }
    var hazard by remember { mutableStateOf("") }
    var control by remember { mutableStateOf("") }
    var severity by remember { mutableStateOf(NovaNonconformitySeverity.medium) }
    var score by remember { mutableStateOf(NovaRiskScoreInput()) }
    var legislation by remember { mutableStateOf("") }
    var responsible by remember { mutableStateOf("") }
    var openedOn by remember { mutableStateOf(osgbToday()) }
    var dueOn by remember { mutableStateOf(osgbDay(30)) }
    var attachment by remember { mutableStateOf<OsgbAttachment?>(null) }
    var open by remember { mutableStateOf<String?>("attachment") }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val workflow = remember { OsgbWorkflowIds() }
    BackHandler(enabled = !saving, onBack = onDone)
    LaunchedEffect(Unit) {
        try { workplaces = scope.repository.directory(scope.context, scope.companyId, "workplaces"); workplaceId = workplaces.firstOrNull()?.first }
        catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = "İşyeri listesi alınamadı. Bağlantınızı kontrol edip yeniden deneyin." }
        loading = false
    }
    fun complete(step: String) = when (step) {
        "attachment" -> attachment != null
        "workplace" -> workplaceId != null && dueOn >= openedOn
        "hazard" -> title.isNotBlank() && hazard.isNotBlank() && control.isNotBlank()
        "scoring" -> score.isComplete
        "legislation" -> legislation.isNotBlank()
        else -> responsible.isNotBlank()
    }
    val titles = mapOf("attachment" to "Fotoğraf ve kanıt", "workplace" to "İşyeri ve tarihler", "hazard" to "Tehlike ve önlem",
        "scoring" to "Risk skoru · isteğe bağlı", "legislation" to "Mevzuat · isteğe bağlı", "responsible" to "Sorumlu · isteğe bağlı")
    val symbols = mapOf("attachment" to "camera", "workplace" to "building.2", "hazard" to "exclamationmark.triangle", "scoring" to "number.square",
        "legislation" to "books.vertical", "responsible" to "person.crop.circle")
    val canSave = workplaceId != null && title.isNotBlank() && hazard.isNotBlank() && control.isNotBlank() && dueOn >= openedOn &&
        (score.isEmpty || score.isComplete)
    fun save() {
        val place = workplaceId ?: return
        if (!canSave || saving) return
        val create = buildJsonObject {
            put("action", "create"); put("workplace_id", place); put("source_kind", "manual"); put("source_ref", JsonNull)
            put("title", title.trim()); put("severity", severity.name); put("opened_on", openedOn); put("due_on", dueOn)
        }
        saving = true; error = null
        coroutines.launch {
            try {
                val uploaded = attachment?.let { file ->
                    scope.repository.uploadFile(scope.context, workflow.id("nonconformity.file.upload",
                        buildJsonObject { put("filename", file.filename); put("digest", file.digest) }), scope.companyId, file.title, file.filename, "other", file.data)
                }
                val created = scope.repository.mutateDomain(scope.context, workflow.id("nonconformity.create", create), scope.companyId,
                    IsgWorkspaceDomain.NONCONFORMITY, create)
                val id = IsgWorkspaceMutations.recordId(created) ?: error("id")
                val detail = buildList {
                    add("Tehlike: ${hazard.trim()}"); add("Önlem: ${control.trim()}")
                    if (legislation.isNotBlank()) add("Mevzuat: ${legislation.trim()}")
                    val value = score.score; val method = score.method
                    if (value != null && method != null) add("Risk skoru (${method.name}): ${scoreText(value)}")
                }.joinToString("\n")
                val action = buildJsonObject {
                    put("action", "add_action"); put("id", id); put("expected_version", IsgWorkspaceMutations.version(created) ?: 0)
                    put("description", detail.take(1000)); put("assignee_contact", responsible.trim().takeIf { it.isNotEmpty() }?.let(::JsonPrimitive) ?: JsonNull)
                    put("due_on", dueOn)
                }
                scope.repository.mutateDomain(scope.context, workflow.id("nonconformity.detail", action), scope.companyId, IsgWorkspaceDomain.NONCONFORMITY, action)
                uploaded?.let { (entry, _) ->
                    scope.repository.mutateDomain(scope.context, workflow.id("nonconformity.file.attach",
                        buildJsonObject { put("entry_id", entry); put("parent_id", id) }), scope.companyId, IsgWorkspaceDomain.FILES, buildJsonObject {
                        put("action", "attach"); put("entry_id", entry); put("parent_kind", "nonconformity"); put("parent_id", id); put("field_name", "attachment")
                    })
                }
                celebrate("Uygunsuzluk kaydı oluşturuldu!")
                onDone()
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                error = "Uygunsuzluk kaydedilemedi. İşyeri, tarih ve zorunlu alanları kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPageHeading("Elle Uygunsuzluk", "Normal uzman paneliyle aynı alanlar ve adımlı kayıt akışı", onBack = onDone)
        if (loading) { NovaLoadingView("İşyerleri hazırlanıyor…"); return@Column }
        OsgbParityProgress(steps.count(::complete), steps.size)
        steps.forEach { step ->
            NovaCompanyAccordion(titles.getValue(step), symbols.getValue(step), open == step, { open = if (it) step else null },
                state = if (complete(step)) NovaCompletionState.complete else NovaCompletionState.missing,
                identifier = "workspace.nonconformity.step.$step") {
                when (step) {
                    "attachment" -> OsgbAttachmentField("Fotoğraf veya kanıt ekle (isteğe bağlı)", attachment, { attachment = it })
                    "workplace" -> if (workplaces.isEmpty()) NovaEmptyState("İşyeri bulunamadı", "Uygunsuzluk eklemek için önce firmaya bir işyeri ekleyin.")
                    else {
                        OsgbPicker("İşyeri", workplaces.map { it.first }, workplaceId, "osgb.finding.workplace", workplaces.toMap()) { workplaceId = it }
                        NovaDayField("Kayıt tarihi", openedOn, { openedOn = it }, "osgb.finding.opened")
                        NovaDayField("Termin", dueOn, { dueOn = it }, "osgb.finding.due")
                    }
                    "hazard" -> {
                        NovaTextField("Tehlike başlığı", title, { title = it }, identifier = "osgb.finding.title")
                        NovaTextField("Açıklama", hazard, { hazard = it }, identifier = "osgb.finding.hazard", multiline = true)
                        NovaTextField("Önlem", control, { control = it }, identifier = "osgb.finding.control", multiline = true)
                        NovaText("Önem derecesi", style = NovaTypeToken.label)
                        NovaSegmentedControl(NovaNonconformitySeverity.entries.map { NovaNonconformityWords.severity(it) }, severity.ordinal) {
                            severity = NovaNonconformitySeverity.entries[it]
                        }
                    }
                    "scoring" -> NovaRiskScoreEditor(score, { score = it })
                    "legislation" -> NovaTextField("İlgili madde, yönetmelik veya standart (isteğe bağlı)", legislation, { legislation = it },
                        identifier = "osgb.finding.legislation", multiline = true)
                    else -> {
                        NovaTextField("Firmadaki sorumlu kişi (isteğe bağlı)", responsible, { responsible = it }, identifier = "osgb.finding.responsible")
                        NovaHelpHint("Bu kişi uygulama kullanıcısı olmak zorunda değildir; kaydın takip bilgisinde görünür.")
                    }
                }
                if (complete(step)) {
                    val index = steps.indexOf(step)
                    (steps.drop(index + 1) + steps.take(index)).firstOrNull { !complete(it) }?.let { next ->
                        NovaButton("Sıradaki: ${titles.getValue(next)}", { open = next }, variant = NovaButtonVariant.Surface, symbol = "chevron.down")
                    }
                }
            }
        }
        error?.let { NovaHelpHint(it) }
        NovaButton(if (saving) "Kaydediliyor…" else "Kaydı aç", ::save, symbol = "checkmark", enabled = canSave && !saving)
    }
}

/**
 * Risk değerlendirmesi ekle / Yeni sürüm (iOS `IsgWorkspaceRiskCreateEditor`): a workplace's first full assessment,
 * or a new full, partial or metadata version of the one in force, saved as a draft.
 */
@Composable
fun NovaOsgbRiskCreateEditor(scope: NovaOsgbScope, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    val steps = listOf("Tarih ve kapsam", "Dosya", "Kontrol ve kaydet")
    var workplaces by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var assessments by remember { mutableStateOf<List<IsgWorkspaceRecord>>(emptyList()) }
    var workplaceId by remember { mutableStateOf<String?>(null) }
    var kind by remember { mutableStateOf("full") }
    var summary by remember { mutableStateOf("") }
    var reason by remember { mutableStateOf("") }
    var date by remember { mutableStateOf(osgbToday()) }
    var attachment by remember { mutableStateOf<OsgbAttachment?>(null) }
    var step by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var validation by remember { mutableStateOf<String?>(null) }
    var confirmingExit by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf(false) }
    val attempt = remember { IsgWorkspaceMutationAttempt() }
    val workflow = remember { OsgbWorkflowIds() }
    val assessment = workplaceId?.let { id -> assessments.firstOrNull { it.fact("workplace_id")?.lowercase() == id } }
    val needsReason = assessment != null && kind in setOf("partial", "metadata")
    val needsScope = kind == "partial"
    LaunchedEffect(Unit) {
        try {
            coroutineScope {
                val a = async { scope.repository.directory(scope.context, scope.companyId, "workplaces") }
                val b = async { scope.repository.snapshot(scope.context, scope.companyId, IsgWorkspaceDomain.RISK).rows }
                workplaces = a.await(); assessments = b.await()
            }
            workplaceId = workplaces.firstOrNull()?.first
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
            error = "İşyeri veya risk sürümleri yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin."
        }
        loading = false
    }
    if (saved) {
        NovaTaskSuccessView("Risk değerlendirmesi taslağı oluşturuldu", "Değerlendirme sürümü kaydedildi. Ayrıntı ekranından kontrol edip kesinleştirebilirsiniz.",
            "Risk değerlendirmelerine dön", onDone)
        return
    }
    val detailsComplete = workplaceId != null && date <= osgbToday() && (!needsScope || summary.isNotBlank()) && (!needsReason || reason.trim().length >= 10)
    fun save() {
        val place = workplaceId ?: return
        if (!detailsComplete || saving) return
        val current = assessment?.fact("current_version")?.toIntOrNull() ?: 0
        val base = assessment?.fact("base_assessment_on") ?: date
        val payload = buildJsonObject {
            put("action", "draft"); put("workplace_id", place); put("expected_current", current); put("kind", kind)
            put("assessment_on", if (kind == "full") date else base); put("revision_on", if (kind == "full") JsonNull else JsonPrimitive(date))
            put("scope", buildJsonObject { if (needsScope) put("summary", summary.trim()) })
            put("reason", if (needsReason) JsonPrimitive(reason.trim()) else JsonNull)
        }
        val mutation = attempt.id("risk.draft", payload.toString())
        saving = true; error = null
        coroutines.launch {
            try {
                val uploaded = attachment?.let { file ->
                    scope.repository.uploadFile(scope.context, workflow.id("risk.file.upload",
                        buildJsonObject { put("filename", file.filename); put("digest", file.digest) }), scope.companyId, file.title, file.filename,
                        "risk_assessment", file.data)
                }
                val created = scope.repository.mutateDomain(scope.context, mutation, scope.companyId, IsgWorkspaceDomain.RISK, payload)
                val id = IsgWorkspaceMutations.recordId(created)
                if (uploaded != null && id != null) scope.repository.mutateDomain(scope.context, workflow.id("risk.file.attach",
                    buildJsonObject { put("entry_id", uploaded.first); put("parent_id", id) }), scope.companyId, IsgWorkspaceDomain.FILES, buildJsonObject {
                    put("action", "attach"); put("entry_id", uploaded.first); put("parent_kind", "risk_assessment"); put("parent_id", id)
                    put("field_name", "assessment")
                })
                celebrate("Risk değerlendirmesi kaydedildi.")
                saved = true
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                error = "Risk sürümü oluşturulamadı. Tarih, kapsam ve gerekçe bilgilerini kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }
    OsgbExitConfirm(confirmingExit, "Risk değerlendirmesi akışından çıkılsın mı?", onDone) { confirmingExit = false }
    NovaModuleTask(if (assessment == null) "Risk değerlendirmesi ekle" else "Yeni sürüm", step + 1, steps.size, steps[step],
        if (step == 2) "Taslağı kaydet" else "Devam", if (step == 2) "checkmark" else "arrow.right", saving,
        { if (step > 0) { validation = null; step-- } else confirmingExit = true }, {
            validation = null
            when {
                (step == 0 || step == 2) && !detailsComplete -> validation = if (step == 0)
                    "İşyeri, tarih ve gerekiyorsa kapsam ile gerekçe bilgilerini kontrol edin." else "Bu adım tamamlanmadan devam edilemiyor."
                step < 2 -> step++
                else -> save()
            }
        }, error) {
        if (loading) { NovaLoadingView("İşyeri ve sürüm bilgileri hazırlanıyor…"); return@NovaModuleTask }
        validation?.let { NovaTaskErrorSummary(it) }
        when (step) {
            0 -> {
                OsgbPicker("İşyeri", workplaces.map { it.first }, workplaceId, "osgb.risk.workplace", workplaces.toMap()) {
                    workplaceId = it; kind = "full"; reason = ""; summary = ""
                }
                if (assessment == null) {
                    NovaFormValueRow("Sürüm türü", "square.stack.3d.up") { NovaText("Tam değerlendirme", style = NovaTypeToken.bodyStrong) }
                    NovaHelpHint("Bu işyerindeki ilk kayıt tam değerlendirme olarak açılır.")
                } else NovaSegmentedControl(listOf("Tam yenileme", "Kısmi revizyon", "Bilgi düzeltmesi"),
                    listOf("full", "partial", "metadata").indexOf(kind)) { kind = listOf("full", "partial", "metadata")[it] }
                NovaDayField(if (kind == "full") "Değerlendirme tarihi" else "Revizyon tarihi", date, { date = minOf(it, osgbToday()) }, "osgb.risk.date")
                if (kind != "full") assessment?.fact("base_assessment_on")?.let { base ->
                    NovaFormValueRow("İlk değerlendirme", "calendar") { NovaText(base, style = NovaTypeToken.bodyStrong) }
                }
                if (needsScope) NovaTextField("Kapsam özeti", summary, { summary = it }, identifier = "osgb.risk.scope", multiline = true)
                if (needsReason) NovaTextField("Değişiklik gerekçesi · en az 10 karakter", reason, { reason = it }, identifier = "osgb.risk.reason", multiline = true)
                NovaHelpHint(if (kind == "full") "Geçerlilik, taslak kesinleştirilirken işyeri tehlike sınıfına göre hesaplanır."
                    else "İlk değerlendirme tarihi korunur; yalnız bu sürümün değişiklikleri kaydedilir.")
            }
            1 -> {
                NovaText("Risk değerlendirmesi dosyası", style = NovaTypeToken.sectionTitle)
                OsgbAttachmentField("PDF veya belge ekle (isteğe bağlı)", attachment, { attachment = it })
                NovaHelpHint("Dosya eklemeden de taslak oluşturabilir, daha sonra kayıt ayrıntısından belge bağlayabilirsiniz.")
            }
            else -> {
                NovaText("Kaydetmeden önce kontrol edin", style = NovaTypeToken.sectionTitle)
                NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        OsgbReview("İşyeri", workplaces.firstOrNull { it.first == workplaceId }?.second.orEmpty())
                        OsgbReview("Sürüm", IsgWorkspaceDisplayText.value(kind))
                        OsgbReview(if (kind == "full") "Değerlendirme" else "Revizyon", date)
                        if (needsScope) OsgbReview("Kapsam", summary.trim())
                        if (needsReason) OsgbReview("Gerekçe", reason.trim())
                        OsgbReview("Dosya", attachment?.filename ?: "Daha sonra eklenebilir")
                    }
                }
            }
        }
    }
}

/** Ekipman Ekle (iOS `IsgWorkspaceEquipmentCreateEditor`): inventory entry whose control period comes from the company rule. */
@Composable
fun NovaOsgbEquipmentCreateEditor(scope: NovaOsgbScope, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    val steps = listOf("type", "identity", "period", "attachment")
    var workplaces by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var catalog by remember { mutableStateOf(IsgWorkspaceEquipmentCatalog(emptyList(), emptyList())) }
    var workplaceId by remember { mutableStateOf<String?>(null) }
    var typeCode by remember { mutableStateOf("") }
    var customType by remember { mutableStateOf("") }
    var serial by remember { mutableStateOf("") }
    var location by remember { mutableStateOf("") }
    var acquiredOn by remember { mutableStateOf(osgbToday()) }
    var attachment by remember { mutableStateOf<OsgbAttachment?>(null) }
    var open by remember { mutableStateOf<String?>("type") }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val attempt = remember { IsgWorkspaceMutationAttempt() }
    val workflow = remember { OsgbWorkflowIds() }
    BackHandler(enabled = !saving, onBack = onDone)
    LaunchedEffect(Unit) {
        try {
            coroutineScope {
                val a = async { scope.repository.directory(scope.context, scope.companyId, "workplaces") }
                val b = async { scope.repository.equipmentCatalog(scope.context, scope.companyId) }
                workplaces = a.await(); catalog = b.await()
            }
            workplaceId = workplaces.firstOrNull()?.first; typeCode = catalog.suggestions.firstOrNull()?.code ?: "other_equipment"
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
            error = "İşyeri veya ekipman kataloğu yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin."
        }
        loading = false
    }
    val typeLabel = if (typeCode == "other_equipment") customType.trim() else IsgWorkspaceDisplayText.value(typeCode)
    fun complete(step: String) = when (step) {
        "type" -> typeCode.isNotEmpty() && typeLabel.isNotEmpty(); "identity" -> workplaceId != null
        "period" -> acquiredOn <= osgbToday(); else -> true
    }
    val titles = mapOf("type" to "Ekipman türü", "identity" to "İşyeri ve kimlik", "period" to "Tarih ve kontrol süresi", "attachment" to "Dosya ve kanıt")
    val symbols = mapOf("type" to "shippingbox", "identity" to "number", "period" to "calendar.badge.clock", "attachment" to "doc.badge.plus")
    val period = catalog.rules.firstOrNull { it.equipmentType == typeCode }?.periodMonths
        ?: catalog.suggestions.firstOrNull { it.code == typeCode }?.defaultPeriodMonths
    fun save() {
        val place = workplaceId ?: return
        if (!steps.all(::complete) || saving) return
        val payload = buildJsonObject {
            put("action", "register"); put("workplace_id", place); put("equipment_type", typeCode); put("equipment_type_label", typeLabel)
            put("serial_tag", serial.trim().ifEmpty { UUID.randomUUID().toString().take(8) }); put("acquired_on", acquiredOn)
            put("location_note", location.trim())
        }
        val mutation = attempt.id("equipment.register", payload.toString())
        saving = true; error = null
        coroutines.launch {
            try {
                val uploaded = attachment?.let { file ->
                    scope.repository.uploadFile(scope.context, workflow.id("equipment.file.upload",
                        buildJsonObject { put("filename", file.filename); put("digest", file.digest) }), scope.companyId, file.title, file.filename,
                        "inspection_report", file.data)
                }
                val created = scope.repository.mutateDomain(scope.context, mutation, scope.companyId, IsgWorkspaceDomain.EQUIPMENT, payload)
                val id = IsgWorkspaceMutations.recordId(created)
                if (uploaded != null && id != null) scope.repository.mutateDomain(scope.context, workflow.id("equipment.file.attach",
                    buildJsonObject { put("entry_id", uploaded.first); put("parent_id", id) }), scope.companyId, IsgWorkspaceDomain.FILES, buildJsonObject {
                    put("action", "attach"); put("entry_id", uploaded.first); put("parent_kind", "equipment"); put("parent_id", id); put("field_name", "attachment")
                })
                celebrate("Ekipman kaydedildi.")
                onDone()
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                error = "Ekipman eklenemedi. Tür, işyeri ve kimlik bilgilerini kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPageHeading("Ekipman Ekle", "Ekipman envantere eklenir; kontrol raporu ekipman ayrıntısından kaydedilir", onBack = onDone)
        if (loading) { NovaLoadingView("Ekipman türleri ve süreler hazırlanıyor…"); return@Column }
        OsgbParityProgress(steps.count(::complete), steps.size)
        steps.forEach { step ->
            NovaCompanyAccordion(titles.getValue(step), symbols.getValue(step), open == step, { open = if (it) step else null },
                state = if (complete(step)) NovaCompletionState.complete else NovaCompletionState.missing, identifier = "workspace.equipment.step.$step") {
                when (step) {
                    "type" -> {
                        OsgbPicker("Ekipman türü", catalog.suggestions.map { it.code }.ifEmpty { listOf("other_equipment") }, typeCode,
                            "osgb.equipment.type") { typeCode = it }
                        if (typeCode == "other_equipment") NovaTextField("Ekipman türü", customType, { customType = it }, identifier = "osgb.equipment.custom")
                    }
                    "identity" -> {
                        OsgbPicker("İşyeri", workplaces.map { it.first }, workplaceId, "osgb.equipment.workplace", workplaces.toMap()) { workplaceId = it }
                        NovaTextField("Seri / kod (isteğe bağlı)", serial, { serial = it }, identifier = "osgb.equipment.serial")
                        NovaTextField("Konum (isteğe bağlı)", location, { location = it }, identifier = "osgb.equipment.location")
                    }
                    "period" -> {
                        NovaDayField("Edinme tarihi", acquiredOn, { acquiredOn = minOf(it, osgbToday()) }, "osgb.equipment.acquired")
                        if (period != null) {
                            NovaFormValueRow("Başlangıç kontrol süresi", "hourglass") { NovaText("$period ay", style = NovaTypeToken.bodyStrong) }
                            NovaHelpHint(catalog.suggestions.firstOrNull { it.code == typeCode }?.defaultBasisNote
                                ?: "Süre firma kuralından gelir; uzman ekipman ayrıntısından değiştirebilir.")
                        } else NovaHelpHint("Bu tür için henüz süre tanımlı değil. Ekipmanı ekledikten sonra kontrol süresini belirleyin.")
                    }
                    else -> OsgbAttachmentField("Ekipman belgesi ekle (isteğe bağlı)", attachment, { attachment = it })
                }
            }
        }
        error?.let { NovaHelpHint(it) }
        NovaButton(if (saving) "Kaydediliyor…" else "Envantere ekle", ::save, symbol = "checkmark", enabled = !saving && steps.all(::complete))
    }
}

/**
 * Acil durum planı ekle (iOS `IsgWorkspaceEmergencyPlanCreateFlow`). A draft stays on the device, keyed by the
 * workplace so tenants never share it, until the plan is published.
 */
@Composable
fun NovaOsgbEmergencyPlanCreateFlow(scope: NovaOsgbScope, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    val android = androidx.compose.ui.platform.LocalContext.current
    val drafts = remember { android.getSharedPreferences("isg.workspace.emergency.drafts", Context.MODE_PRIVATE) }
    val steps = listOf("Kapsam", "Tarih ve geçerlilik", "Acil durum ekibi", "Plan dosyası", "Kontrol ve kaydet")
    var workplaces by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var employees by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var workplaceId by remember { mutableStateOf<String?>(null) }
    var planScope by remember { mutableStateOf("Acil Durum Planı") }
    var preparedOn by remember { mutableStateOf(osgbToday()) }
    var validUntil by remember { mutableStateOf(LocalDate.now().plusYears(1).toString()) }
    var overridesValidity by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }
    var roles by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var note by remember { mutableStateOf("") }
    var notesOpen by remember { mutableStateOf(false) }
    var attachment by remember { mutableStateOf<OsgbAttachment?>(null) }
    var step by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var validation by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmingExit by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf(false) }
    var draftSaved by remember { mutableStateOf(false) }
    val workflow = remember { OsgbWorkflowIds() }
    fun automaticValidity(from: String) = runCatching { LocalDate.parse(from).plusYears(1).toString() }.getOrDefault(validUntil)
    fun draftKey() = workplaceId?.let { "isg.workspace.emergency.draft.${it.lowercase()}" }
    LaunchedEffect(Unit) {
        try {
            coroutineScope {
                val places = async { scope.repository.directory(scope.context, scope.companyId, "workplaces") }
                val people = async { scope.repository.directory(scope.context, scope.companyId, "employees") }
                workplaces = places.await(); employees = people.await()
            }
            workplaceId = workplaces.firstOrNull()?.first
            validUntil = automaticValidity(preparedOn)
            draftKey()?.let { drafts.getString(it, null) }?.let { raw ->
                runCatching { Json.parseToJsonElement(raw).jsonObject }.getOrNull()?.let { draft ->
                    draft["scope"]?.jsonPrimitive?.contentOrNull?.let { planScope = it }
                    draft["preparedOn"]?.jsonPrimitive?.contentOrNull?.let { preparedOn = it }
                    draft["validUntil"]?.jsonPrimitive?.contentOrNull?.let { validUntil = it }
                    draft["note"]?.jsonPrimitive?.contentOrNull?.let { note = it }
                    selected = draft["selectedEmployees"]?.jsonArray?.map { it.jsonPrimitive.content.lowercase() }?.toSet().orEmpty()
                    roles = draft["roles"]?.jsonObject?.mapKeys { it.key.lowercase() }?.mapValues { it.value.jsonPrimitive.content }.orEmpty()
                    draftSaved = true
                }
            }
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
            error = "İşyeri veya personel bilgileri yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin."
        }
        loading = false
    }
    if (saved) {
        NovaTaskSuccessView("Acil durum planı kaydedildi", if (selected.isEmpty())
            "Plan ve geçerlilik tarihi firma kaydına eklendi. Acil durum ekibini daha sonra ekleyebilirsiniz."
            else "Plan, geçerlilik tarihi ve ${selected.size} kişilik ekip firma kaydına eklendi. Sıradaki mantıklı işlem bir tatbikat planlamaktır.",
            "Planlara dön", onDone)
        return
    }
    fun complete(index: Int): Boolean = when (index) {
        0 -> workplaceId != null && planScope.isNotBlank()
        1 -> validUntil > preparedOn
        4 -> complete(0) && complete(1)
        else -> true
    }
    fun toggle(id: String) {
        if (id in selected) { selected = selected - id; roles = roles - id } else { selected = selected + id; roles = roles + (id to (roles[id] ?: "coordinator")) }
    }
    fun save() {
        val place = workplaceId ?: return
        if (!complete(4) || saving) return
        val payload = buildJsonObject {
            put("entity", "plan"); put("action", "publish"); put("workplace_id", place); put("scope", planScope.trim())
            put("prepared_on", preparedOn); put("valid_until", validUntil); put("review_note", note.trim())
            put("team", JsonArray(selected.sorted().map { id ->
                buildJsonObject { put("employee_id", id); put("role", roles[id] ?: "coordinator"); put("contact", "") }
            }))
        }
        saving = true; error = null
        coroutines.launch {
            try {
                val uploaded = attachment?.let { file ->
                    scope.repository.uploadFile(scope.context, workflow.id("emergency.file.upload",
                        buildJsonObject { put("filename", file.filename); put("digest", file.digest) }), scope.companyId, file.title, file.filename,
                        "emergency_plan", file.data)
                }
                val created = scope.repository.mutateDomain(scope.context, workflow.id("emergency.create", payload), scope.companyId,
                    IsgWorkspaceDomain.EMERGENCY_PLAN, payload)
                val id = IsgWorkspaceMutations.recordId(created)
                if (uploaded != null && id != null) scope.repository.mutateDomain(scope.context, workflow.id("emergency.file.attach",
                    buildJsonObject { put("entry_id", uploaded.first); put("parent_id", id) }), scope.companyId, IsgWorkspaceDomain.FILES, buildJsonObject {
                    put("action", "attach"); put("entry_id", uploaded.first); put("parent_kind", "emergency_plan"); put("parent_id", id)
                    put("field_name", "attachment")
                })
                celebrate("Acil durum planı kaydedildi.")
                draftKey()?.let { drafts.edit().remove(it).apply() }
                saved = true
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                error = "Plan kaydedilemedi. İşyeri ve tarih bilgilerini kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }
    OsgbExitConfirm(confirmingExit, "Plan akışından çıkılsın mı?", onDone) { confirmingExit = false }
    NovaModuleTask("Acil durum planı ekle", step + 1, steps.size, steps[step], if (step == 4) "Yayımla" else "Devam",
        if (step == 4) "checkmark.seal" else "arrow.right", saving, { if (step > 0) { validation = null; step-- } else confirmingExit = true }, {
            validation = null
            when {
                !complete(step) -> validation = listOf("İşyeri ve plan kapsamını belirtin.", "Geçerlilik tarihi hazırlama tarihinden sonra olmalı.",
                    "", "", "Önceki adımlarda tamamlanmamış bilgi var.")[step]
                step < 4 -> step++
                else -> save()
            }
        }, error) {
        if (loading) { NovaLoadingView("İşyeri ve personel bilgileri hazırlanıyor…"); return@NovaModuleTask }
        validation?.let { NovaTaskErrorSummary(it) }
        when (step) {
            0 -> {
                NovaFormValueRow("Firma", "building.2") { NovaText(scope.companyName, style = NovaTypeToken.bodyStrong) }
                if (workplaces.size == 1) NovaFormValueRow("İşyeri", "mappin.and.ellipse") { NovaText(workplaces[0].second, style = NovaTypeToken.bodyStrong) }
                else OsgbPicker("İşyeri", workplaces.map { it.first }, workplaceId, "osgb.emergency.workplace", workplaces.toMap(),
                    placeholder = "İşyeri seçin") { workplaceId = it }
                NovaTextField("Plan kapsamı", planScope, { planScope = it }, identifier = "osgb.emergency.scope", multiline = true)
            }
            1 -> {
                NovaDayField("Hazırlama tarihi", preparedOn, { preparedOn = it; if (!overridesValidity) validUntil = automaticValidity(it) }, "osgb.emergency.prepared")
                if (overridesValidity) NovaDayField("Geçerlilik tarihi", validUntil, { validUntil = it }, "osgb.emergency.valid")
                else NovaFormValueRow("Geçerlilik", "calendar.badge.clock") {
                    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        NovaText(validUntil, style = NovaTypeToken.bodyStrong)
                        NovaText("Otomatik hesaplandı", style = NovaTypeToken.micro)
                    }
                }
                NovaCompanyToggleRow("Geçerlilik tarihini değiştir", overridesValidity, !saving) {
                    overridesValidity = it; if (!it) validUntil = automaticValidity(preparedOn)
                }
                NovaWhyDisclosure {
                    NovaText("Varsayılan tarih hazırlanma tarihinden bir yıl sonrası olarak hesaplanır. Yalnız istisna varsa değiştirin.",
                        style = NovaTypeToken.metaQuiet)
                }
            }
            2 -> {
                val needle = query.trim()
                val rows = if (needle.isEmpty()) employees else employees.filter { it.second.contains(needle, true) }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    NovaText("Acil durum ekibi", Modifier.weight(1f), NovaTypeToken.sectionTitle)
                    NovaText("${selected.size} seçili", style = NovaTypeToken.metaQuiet)
                }
                NovaHelpHint("Ekip eklemek isteğe bağlıdır. Şimdi kişi seçebilir veya bu adımı boş geçip ekibi daha sonra tamamlayabilirsiniz.")
                NovaSearchCapsule(query, "Personel ara", "osgb.emergency.search") { query = it }
                if (employees.isNotEmpty()) {
                    val all = selected.size == employees.size
                    NovaCompactActionButton(if (all) "Seçimi temizle" else "Tümünü seç", if (all) "xmark.circle" else "checkmark.circle",
                        Modifier.width(IntrinsicSize.Max)) {
                        if (all) { selected = emptySet(); roles = emptyMap() }
                        else { selected = employees.map { it.first }.toSet(); roles = employees.associate { it.first to (roles[it.first] ?: "other") } }
                    }
                }
                if (rows.isEmpty()) NovaEmptyState(if (employees.isEmpty()) "Firma personeli bulunmuyor" else "Eşleşen personel yok",
                    if (employees.isEmpty()) "Plan ekibine kişi seçmek için önce firma personeli ekleyin." else "Farklı bir ad veya personel kodu arayın.")
                rows.forEach { (id, name) ->
                    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).novaControlBackground(14.dp).padding(horizontal = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        NovaRadioRow(name, id in selected, identifier = "osgb.emergency.employee.$id") { toggle(id) }
                        if (id in selected) Box(Modifier.padding(start = 30.dp, bottom = 8.dp)) {
                            OsgbPicker("Ekip görevi", listOf("coordinator", "fire", "first_aid", "evacuation", "other"), roles[id] ?: "coordinator",
                                "osgb.emergency.employee.$id.role") { roles = roles + (id to it) }
                        }
                    }
                }
            }
            3 -> {
                NovaText("Plan dosyası", style = NovaTypeToken.sectionTitle)
                OsgbAttachmentField("PDF veya fotoğraf ekle (isteğe bağlı)", attachment, { attachment = it })
                NovaCompanyAccordion("Ek bilgiler", "note.text", notesOpen, { notesOpen = it }, identifier = "osgb.emergency.notes") {
                    NovaTextField("Plan notu (isteğe bağlı)", note, { note = it }, identifier = "osgb.emergency.note", multiline = true)
                }
            }
            else -> {
                NovaText("Kaydetmeden önce kontrol edin", style = NovaTypeToken.sectionTitle)
                NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        OsgbReview("Firma", scope.companyName)
                        OsgbReview("İşyeri", workplaces.firstOrNull { it.first == workplaceId }?.second.orEmpty())
                        OsgbReview("Kapsam", planScope.trim()); OsgbReview("Hazırlama", preparedOn); OsgbReview("Geçerlilik", validUntil)
                        OsgbReview("Ekip", "${selected.size} kişi"); OsgbReview("Dosya", attachment?.filename ?: "Daha sonra eklenebilir")
                    }
                }
                NovaButton(if (draftSaved) "Taslak kaydedildi" else "Taslak olarak kaydet", {
                    draftKey()?.let { key ->
                        drafts.edit().putString(key, buildJsonObject {
                            put("scope", planScope); put("preparedOn", preparedOn); put("validUntil", validUntil); put("note", note)
                            put("selectedEmployees", JsonArray(selected.map(::JsonPrimitive)))
                            put("roles", JsonObject(roles.mapValues { JsonPrimitive(it.value) }))
                        }.toString()).apply()
                        draftSaved = true
                    }
                    validation = null
                }, variant = NovaButtonVariant.Surface, symbol = if (draftSaved) "checkmark" else "tray.and.arrow.down", enabled = !draftSaved)
                NovaText("Taslak yayımlanmaz; yayımlamak için aşağıdaki ana aksiyonu kullanın.", style = NovaTypeToken.metaQuiet)
            }
        }
    }
}
