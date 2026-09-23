package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID

/** Everything an OSGB create flow needs: the workspace, the company and the repository. */
class NovaOsgbScope(val context: IsgWorkspaceContext, val repository: IsgWorkspaceRepository, val companyId: String,
                    val companyName: String, val companyHazardClass: String)

/** Keeps one mutation id per workflow step and content, so a retried save replays each step it already wrote. */
internal class OsgbWorkflowIds {
    private val ids = mutableMapOf<String, String>()
    fun id(namespace: String, payload: JsonObject): String = ids.getOrPut("$namespace:$payload") { UUID.randomUUID().toString() }
}

internal fun osgbInstant(day: String, time: LocalTime = LocalTime.MIDNIGHT): String =
    runCatching { LocalDate.parse(day).atTime(time).atZone(ZoneId.systemDefault()).toInstant().truncatedTo(ChronoUnit.SECONDS).toString() }
        .getOrDefault(day)

private fun lineValues(text: String) = text.lines().map { it.trim() }.filter { it.isNotEmpty() }

/** A stable equipment type code from its label (iOS `slug`). */
internal fun osgbEquipmentSlug(text: String): String {
    val folded = java.text.Normalizer.normalize(text.lowercase(Locale.forLanguageTag("tr-TR")).replace('ı', 'i'), java.text.Normalizer.Form.NFD)
        .replace(Regex("\\p{M}+"), "")
    val value = folded.replace(Regex("[^a-z0-9]+"), "_").trim('_')
    return if (value.length >= 3) value.take(40) else "equipment"
}

/** A searchable employee list for one or many choices, with an optional team role per chosen person. */
@Composable
internal fun OsgbEmployeeSelector(title: String, employees: List<Pair<String, String>>, selected: Set<String>, single: Boolean,
                                  onToggle: (String) -> Unit, roles: Map<String, String>? = null, onRole: ((String, String) -> Unit)? = null) {
    var query by remember { mutableStateOf("") }
    val needle = query.trim()
    val rows = if (needle.isEmpty()) employees else employees.filter { it.second.contains(needle, true) }
    NovaCard(Modifier.fillMaxWidth(), padding = 14) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                NovaText(title, Modifier.weight(1f), NovaTypeToken.bodyStrong)
                if (selected.isNotEmpty()) NovaText("${selected.size} seçili", style = NovaTypeToken.metaQuiet)
            }
            NovaSearchCapsule(query, "Personel ara", "osgb.employee.search") { query = it }
            if (rows.isEmpty()) NovaHelpHint(if (employees.isEmpty()) "Önce firma personeli ekleyin." else "Aramanızla eşleşen personel bulunamadı.")
            rows.forEach { (id, name) ->
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(Modifier.fillMaxWidth().heightIn(min = 42.dp).novaRowPress { onToggle(id) }.testTag("osgb.employee.$id"),
                        horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon(if (id in selected) "checkmark.circle.fill" else "circle", 18.dp)
                        NovaText(name, Modifier.weight(1f))
                    }
                    if (!single && roles != null && onRole != null && id in selected) Box(Modifier.padding(start = 30.dp)) {
                        OsgbPicker("Ekip görevi", listOf("coordinator", "fire", "first_aid", "evacuation", "other"), roles[id] ?: "coordinator",
                            "osgb.employee.$id.role") { onRole(id, it) }
                    }
                }
            }
        }
    }
}

@Composable
private fun OsgbReviewRow(label: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        NovaText(label, style = NovaTypeToken.metaQuiet)
        Spacer(Modifier.weight(1f))
        NovaText(value.ifEmpty { "—" }, style = NovaTypeToken.bodyStrong, maxLines = 3)
    }
}

/**
 * The step-by-step create flow of the remaining D2-D6 records (iOS `IsgWorkspaceDomainCreateEditor`): checklist,
 * drill, appointment, PPE, İSG-KATİP, annual plan, board, work permit and visit. Training, risk, findings,
 * equipment, emergency plans and files have their own flows.
 */
@Composable
fun NovaOsgbDomainCreateEditor(scope: NovaOsgbScope, domain: IsgWorkspaceDomain, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    val (context, repository, companyId) = Triple(scope.context, scope.repository, scope.companyId)
    val needsWorkplace = domain != IsgWorkspaceDomain.PPE
    val needsEmployee = domain == IsgWorkspaceDomain.PPE
    var workplaces by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var employees by remember { mutableStateOf<List<Pair<String, String>>>(emptyList()) }
    var plans by remember { mutableStateOf<List<IsgWorkspaceRecord>>(emptyList()) }
    var templates by remember { mutableStateOf<List<IsgWorkspaceChecklistTemplate>>(emptyList()) }
    var templateId by remember { mutableStateOf<String?>(null) }
    var workplaceId by remember { mutableStateOf<String?>(null) }
    var employeeId by remember { mutableStateOf<String?>(null) }
    var selectedEmployees by remember { mutableStateOf<Set<String>>(emptySet()) }
    var planId by remember { mutableStateOf<String?>(null) }
    var primary by remember { mutableStateOf("") }
    var secondary by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var option by remember { mutableStateOf("") }
    var hasEndDate by remember { mutableStateOf(false) }
    var boardState by remember { mutableStateOf("held") }
    var decisions by remember { mutableStateOf("") }
    var number by remember { mutableIntStateOf(if (domain == IsgWorkspaceDomain.VISIT) 60 else 1) }
    var firstDate by remember { mutableStateOf(osgbToday()) }
    var firstTime by remember { mutableStateOf(LocalTime.now().withSecond(0).withNano(0)) }
    var secondDate by remember { mutableStateOf(LocalDate.now().plusYears(1).toString()) }
    var secondTime by remember { mutableStateOf(LocalTime.now().withSecond(0).withNano(0)) }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var attachment by remember { mutableStateOf<OsgbAttachment?>(null) }
    var step by remember { mutableIntStateOf(0) }
    var saved by remember { mutableStateOf(false) }
    val workflow = remember { OsgbWorkflowIds() }
    val scopeNeedsInput = (needsWorkplace && workplaces.size != 1) || needsEmployee || domain == IsgWorkspaceDomain.DRILL
    val minimumStep = if (scopeNeedsInput) 0 else 1
    val total = if (domain == IsgWorkspaceDomain.VISIT) 5 else 4
    LaunchedEffect(Unit) {
        loading = true; error = null
        try {
            if (needsWorkplace) {
                workplaces = repository.ensuredWorkplaces(context, companyId)
                workplaceId = workplaces.singleOrNull()?.first
            }
            if (needsEmployee || domain in setOf(IsgWorkspaceDomain.APPOINTMENT, IsgWorkspaceDomain.BOARD)) {
                employees = repository.directory(context, companyId, "employees")
                if (needsEmployee) employeeId = employees.firstOrNull()?.first
            }
            if (domain == IsgWorkspaceDomain.DRILL) {
                plans = repository.snapshot(context, companyId, IsgWorkspaceDomain.EMERGENCY_PLAN).rows; planId = plans.firstOrNull()?.id
            }
            if (domain == IsgWorkspaceDomain.CHECKLIST) {
                templates = repository.checklistTemplates(context, companyId); templateId = templates.firstOrNull()?.id
            }
            option = when (domain) { IsgWorkspaceDomain.APPOINTMENT -> "representative"; IsgWorkspaceDomain.PPE -> "piece"
                IsgWorkspaceDomain.BOARD -> "mandatory"; else -> "" }
            val needsInput = (needsWorkplace && workplaces.size != 1) || needsEmployee || domain == IsgWorkspaceDomain.DRILL
            if (!needsInput) step = 1
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = "Bağlantınızı kontrol edip yeniden deneyin." }
        loading = false
    }
    if (saved) {
        NovaTaskSuccessView("${domain.title} kaydedildi", if (domain == IsgWorkspaceDomain.VISIT)
            "Ziyaret bilgileri ve eklediğiniz kanıtlar firma kaydına işlendi." else "Kayıt firma kapsamına eklendi ve ilgili listelerde kullanıma hazır.",
            "Listeye dön", onDone)
        return
    }
    val template = templates.firstOrNull { it.id == templateId }
    val canSave = when {
        needsWorkplace && workplaceId == null -> false
        needsEmployee && employeeId == null -> false
        domain == IsgWorkspaceDomain.DRILL && planId == null -> false
        else -> when (domain) {
            IsgWorkspaceDomain.PPE, IsgWorkspaceDomain.WORK_PERMIT, IsgWorkspaceDomain.VISIT -> primary.isNotBlank()
            IsgWorkspaceDomain.APPOINTMENT -> employeeId != null && (!hasEndDate || secondDate > firstDate)
            IsgWorkspaceDomain.BOARD -> lineValues(primary).isNotEmpty() &&
                (if (boardState == "held") selectedEmployees.isNotEmpty() else notes.trim().length >= 5)
            IsgWorkspaceDomain.KATIP -> primary.isNotEmpty() && secondary.isNotEmpty() && notes.isNotEmpty()
            IsgWorkspaceDomain.CHECKLIST -> template != null
            else -> true
        }
    }
    val stepValid = when {
        step == 0 -> !(needsWorkplace && workplaceId == null) && !(needsEmployee && employeeId == null) &&
            !(domain == IsgWorkspaceDomain.DRILL && planId == null)
        domain == IsgWorkspaceDomain.VISIT && step == 2 -> primary.isNotBlank()
        step == total - 1 -> canSave
        else -> true
    }
    val category = when (domain) {
        IsgWorkspaceDomain.DRILL -> "emergency_plan"; IsgWorkspaceDomain.PPE -> "handover_form"; IsgWorkspaceDomain.KATIP -> "contract"
        IsgWorkspaceDomain.BOARD -> "board_document"; IsgWorkspaceDomain.WORK_PERMIT -> "permit_form"; IsgWorkspaceDomain.VISIT -> "visit_evidence"
        else -> "other"
    }
    val parentKind = when (domain) {
        IsgWorkspaceDomain.CHECKLIST -> "checklist"; IsgWorkspaceDomain.DRILL -> "drill"; IsgWorkspaceDomain.APPOINTMENT -> "appointment"
        IsgWorkspaceDomain.PPE -> "ppe"; IsgWorkspaceDomain.KATIP -> "katip_contract"; IsgWorkspaceDomain.ANNUAL_PLAN -> "annual_plan"
        IsgWorkspaceDomain.BOARD -> "board"; IsgWorkspaceDomain.WORK_PERMIT -> "work_permit"; IsgWorkspaceDomain.VISIT -> "site_visit"
        else -> null
    }
    val fieldName = when (domain) {
        IsgWorkspaceDomain.PPE -> "handover_form"; IsgWorkspaceDomain.BOARD -> "minutes"; IsgWorkspaceDomain.WORK_PERMIT -> "permit_form"
        IsgWorkspaceDomain.VISIT -> "evidence"; else -> "attachment"
    }
    fun payload(assetId: String?): JsonObject {
        fun id(value: String?) = value?.let(::JsonPrimitive) ?: JsonNull
        val asset = assetId?.let(::JsonPrimitive) ?: JsonNull
        return when (domain) {
            IsgWorkspaceDomain.CHECKLIST -> buildJsonObject {
                put("action", "create"); put("workplace_id", id(workplaceId)); put("template_code", template!!.code)
                put("template_version", template.version); put("started_on", firstDate)
            }
            IsgWorkspaceDomain.DRILL -> buildJsonObject {
                put("entity", "drill"); put("action", "create"); put("workplace_id", id(workplaceId)); put("plan_id", id(planId))
                put("plan_version", plans.firstOrNull { it.id == planId }?.version ?: 1); put("planned_on", firstDate)
            }
            IsgWorkspaceDomain.APPOINTMENT -> buildJsonObject {
                put("entity", "appointment"); put("action", "create"); put("employee_id", id(employeeId)); put("workplace_id", id(workplaceId))
                put("kind", option); put("starts_on", firstDate); put("ends_before", if (hasEndDate) JsonPrimitive(secondDate) else JsonNull)
            }
            IsgWorkspaceDomain.PPE -> buildJsonObject {
                put("entity", "ppe"); put("action", "handover"); put("employee_id", id(employeeId)); put("item", primary); put("quantity", number)
                put("unit", option); put("handed_on", firstDate); put("signed_copy", false); put("external_ref", secondary)
            }
            IsgWorkspaceDomain.KATIP -> buildJsonObject {
                put("kind", "katip_contract"); put("action", "create"); put("workplace_id", id(workplaceId)); put("counterparty", primary)
                put("expert_contact", secondary); put("scope", notes); put("starts_on", firstDate); put("ends_before", secondDate)
                put("declared_monthly_minutes", number); put("declared_note", ""); put("contract_location", ""); put("workspace_asset_id", asset)
            }
            IsgWorkspaceDomain.ANNUAL_PLAN -> buildJsonObject {
                put("kind", "annual_plan"); put("action", "create"); put("workplace_id", id(workplaceId))
                put("plan_year", runCatching { LocalDate.parse(firstDate).year }.getOrDefault(LocalDate.now().year))
            }
            IsgWorkspaceDomain.BOARD -> buildJsonObject {
                put("kind", "board"); put("action", "create"); put("workplace_id", id(workplaceId)); put("applicability", "mandatory")
                put("planned_on", firstDate); put("agenda", JsonArray(lineValues(primary).map(::JsonPrimitive)))
            }
            IsgWorkspaceDomain.WORK_PERMIT -> buildJsonObject {
                put("kind", "work_permit"); put("action", "create"); put("workplace_id", id(workplaceId)); put("template_code", "general")
                put("job_description", primary); put("parties", JsonArray(listOf(JsonPrimitive(secondary.ifEmpty { primary }))))
                put("planned_on", firstDate); put("work_location", secondary); put("starts_at", osgbInstant(firstDate, firstTime))
                put("ends_at", osgbInstant(secondDate, secondTime)); put("risk_precautions", notes); put("workspace_asset_id", asset)
            }
            else -> buildJsonObject {
                put("kind", "site_visit"); put("action", "create"); put("workplace_id", id(workplaceId)); put("visited_on", firstDate)
                put("duration_minutes", number); put("location_note", secondary); put("expert_note", primary); put("responsible_contact", notes)
            }
        }
    }
    suspend fun upload(): Pair<String, String>? = attachment?.let { file ->
        repository.uploadFile(context, workflow.id("${domain.name.lowercase()}.file.upload",
            buildJsonObject { put("filename", file.filename); put("digest", file.digest) }), companyId, file.title, file.filename, category, file.data)
    }
    suspend fun attach(uploaded: Pair<String, String>?, parent: String?) {
        if (uploaded == null || parent == null || parentKind == null) return
        val signature = buildJsonObject { put("entry_id", uploaded.first); put("parent_id", parent); put("parent_kind", parentKind) }
        repository.mutateDomain(context, workflow.id("${domain.name.lowercase()}.file.attach", signature), companyId, IsgWorkspaceDomain.FILES,
            buildJsonObject {
                put("action", "attach"); put("entry_id", uploaded.first); put("parent_kind", parentKind); put("parent_id", parent)
                put("field_name", fieldName)
            })
    }
    fun save() {
        if (!canSave || saving) return
        saving = true; error = null
        coroutines.launch {
            try {
                val uploaded = upload()
                val create = payload(uploaded?.second)
                val created = repository.mutateDomain(context, workflow.id(if (domain == IsgWorkspaceDomain.BOARD) "board.create"
                    else "domain.${domain.name.lowercase()}", create), companyId, domain, create)
                val recordId = IsgWorkspaceMutations.recordId(created)
                if (domain == IsgWorkspaceDomain.BOARD) {
                    val meeting = recordId ?: error("meeting")
                    val version = IsgWorkspaceMutations.version(created) ?: error("version")
                    val outcome = if (boardState == "held") buildJsonObject {
                        put("kind", "board"); put("action", "hold"); put("id", meeting); put("expected_version", version); put("held_on", firstDate)
                        put("attendance", JsonArray(selectedEmployees.sorted().map(::JsonPrimitive)))
                        put("workspace_asset_id", uploaded?.second?.let(::JsonPrimitive) ?: JsonNull)
                    } else buildJsonObject {
                        put("kind", "board"); put("action", "cancel"); put("id", meeting); put("expected_version", version); put("reason", notes.trim())
                    }
                    repository.mutateDomain(context, workflow.id("board.outcome", outcome), companyId, domain, outcome)
                    if (boardState == "held") lineValues(decisions).forEachIndexed { offset, text ->
                        val command = buildJsonObject {
                            put("kind", "board_decision"); put("action", "create"); put("meeting_id", meeting); put("decision_no", offset + 1)
                            put("decision_text", text); put("responsible_contact", JsonNull); put("due_on", JsonNull)
                        }
                        repository.mutateDomain(context, workflow.id("board.decision.${offset + 1}", command), companyId, domain, command)
                    }
                }
                attach(uploaded, recordId)
                celebrate(if (domain == IsgWorkspaceDomain.BOARD) "Kurul toplantısı kaydedildi." else "${domain.title} kaydedildi.")
                saved = true
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                error = if (domain == IsgWorkspaceDomain.BOARD) "Toplantı kaydı tamamlanamadı. Gündem, katılımcı ve tarih bilgilerini kontrol edip yeniden deneyin."
                    else "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }
    val stepTitle = if (domain == IsgWorkspaceDomain.VISIT) listOf("İşyeri", "Tarih ve süre", "Ziyaret ayrıntıları", "Dosya", "Kontrol")[step]
        else listOf("Kapsam", "Kayıt bilgileri", "Dosya", "Kontrol")[step]
    val saveTitle = when (domain) {
        IsgWorkspaceDomain.CHECKLIST -> "Kontrol listesini başlat"; IsgWorkspaceDomain.DRILL -> "Tatbikatı planla"
        IsgWorkspaceDomain.APPOINTMENT -> "Atamayı kaydet"; IsgWorkspaceDomain.PPE -> "Teslimi kaydet"
        IsgWorkspaceDomain.KATIP -> "Sözleşmeyi kaydet"; IsgWorkspaceDomain.BOARD -> "Toplantıyı kaydet"; else -> "Kaydı oluştur"
    }
    val goBack: () -> Unit = { if (!saving) { error = null; if (step > minimumStep) step-- else onDone() } }
    if (loading) {
        NovaModuleTask("${domain.title} ekle", 1, total - minimumStep, stepTitle, "Devam", "arrow.right", false, onDone, {}, null) {
            NovaLoadingView("Form hazırlanıyor…")
        }
        return
    }
    @Composable fun field(title: String, value: String, id: String, onChange: (String) -> Unit) =
        NovaTextField(title, value, onChange, identifier = "osgb.create.$id", multiline = true)
    @Composable fun stepper(label: String) = OsgbStepper("$label: $number", number, 1..100_000, "osgb.create.number") { number = it }
    NovaModuleTask("${domain.title} ekle", step - minimumStep + 1, total - minimumStep, stepTitle,
        if (step == total - 1) saveTitle else "Devam", if (step == total - 1) "checkmark" else "arrow.right", saving, goBack, {
            error = null
            when {
                !stepValid -> error = when {
                    step == 0 -> "İşyeri, personel veya bağlı plan seçimini tamamlayın."
                    domain == IsgWorkspaceDomain.VISIT && step == 2 -> "Ziyaret notunu yazın."
                    else -> "Zorunlu alanları ve tarihleri kontrol edin."
                }
                step < total - 1 -> step++
                else -> save()
            }
        }, error) {
        val attachmentStep = if (domain == IsgWorkspaceDomain.VISIT) 3 else 2
        when {
            step == 0 -> {
                NovaText("Kapsam", style = NovaTypeToken.sectionTitle)
                NovaHelpHint("Firma bilgisi korunur; işyeri ve ilgili kayıt seçimi sonraki adımlara otomatik taşınır.")
                if (needsWorkplace) when {
                    workplaces.isEmpty() -> NovaTaskErrorSummary("Firma için işyeri kaydı hazırlanamadı. Yeniden deneyin veya firma ayrıntılarından işyeri ekleyin.")
                    workplaces.size == 1 -> NovaFormValueRow("İşyeri", "building") { NovaText(workplaces[0].second, style = NovaTypeToken.bodyStrong) }
                    else -> OsgbPicker("İşyeri", workplaces.map { it.first }, workplaceId, "osgb.create.workplace", workplaces.toMap(),
                        placeholder = "İşyeri seçin") { workplaceId = it }
                }
                if (needsEmployee) OsgbPicker("Personel", employees.map { it.first }, employeeId, "osgb.create.employee", employees.toMap()) { employeeId = it }
                if (domain == IsgWorkspaceDomain.DRILL) {
                    if (plans.isEmpty()) NovaHelpHint("Tatbikat planlamak için önce acil durum planı ekleyin.")
                    else OsgbPicker("Acil durum planı", plans.map { it.id }, planId, "osgb.create.plan", plans.associate { it.id to it.title }) { planId = it }
                }
            }
            domain == IsgWorkspaceDomain.VISIT && step == 1 -> {
                NovaText("Tarih, saat ve süre", style = NovaTypeToken.sectionTitle)
                NovaDayField("Ziyaret tarihi", firstDate, { firstDate = it }, "osgb.create.date")
                NovaTimeField("Ziyaret saati", firstTime, "osgb.create.time") { firstTime = it }
                stepper("Ziyaret süresi (dakika)")
            }
            domain == IsgWorkspaceDomain.VISIT && step == 2 -> {
                NovaText("Ziyaret ayrıntıları", style = NovaTypeToken.sectionTitle)
                field("Ziyaret notu *", primary, "note") { primary = it }
                field("Ziyaret yeri", secondary, "location") { secondary = it }
                field("Görüşülen kişi", notes, "contact") { notes = it }
            }
            step == 1 -> {
                NovaText("Kayıt bilgileri", style = NovaTypeToken.sectionTitle)
                when (domain) {
                    IsgWorkspaceDomain.CHECKLIST -> {
                        if (templates.isEmpty()) NovaEmptyState("Yayımlanmış şablon yok", "Kontrol listesi oluşturmak için önce onaylı bir şablon yayımlanmalıdır.")
                        else OsgbPicker("Kontrol listesi şablonu", templates.map { it.id }, templateId, "osgb.create.template",
                            templates.associate { it.id to "${it.title} · ${it.itemCount} madde" }) { templateId = it }
                        NovaDayField("Başlangıç / kayıt tarihi", firstDate, { firstDate = it }, "osgb.create.date")
                    }
                    IsgWorkspaceDomain.DRILL, IsgWorkspaceDomain.ANNUAL_PLAN ->
                        NovaDayField("Başlangıç / kayıt tarihi", firstDate, { firstDate = it }, "osgb.create.date")
                    IsgWorkspaceDomain.APPOINTMENT -> {
                        OsgbEmployeeSelector("Personel", employees, setOfNotNull(employeeId), single = true, onToggle = { employeeId = it })
                        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                NovaText("Görev", style = NovaTypeToken.bodyStrong)
                                OsgbPicker("Görev türü", listOf("representative", "support_staff", "team_member", "first_aid", "fire_team"), option,
                                    "osgb.create.kind") { option = it }
                                NovaDayField("Başlangıç", firstDate, { firstDate = it }, "osgb.create.start")
                                NovaCompanyToggleRow("Bitiş tarihi belirle", hasEndDate, !saving) { hasEndDate = it }
                                if (hasEndDate) NovaDayField("Bitiş", secondDate, { secondDate = it }, "osgb.create.end")
                            }
                        }
                        NovaHelpHint("Çalışan temsilcisi ve destek elemanı kayıtları beyana dayanır; uygulama yeterlilik veya zorunlu kişi sayısı doğrulaması yapmaz.")
                    }
                    IsgWorkspaceDomain.PPE -> {
                        field("KKD ürünü", primary, "item") { primary = it }
                        stepper("Adet")
                        OsgbPicker("Tür / durum", listOf("piece", "pair", "set", "metre", "litre"), option, "osgb.create.unit") { option = it }
                        NovaDayField("Başlangıç / kayıt tarihi", firstDate, { firstDate = it }, "osgb.create.date")
                        field("Referans", secondary, "reference") { secondary = it }
                    }
                    IsgWorkspaceDomain.KATIP -> {
                        field("Sözleşme tarafı", primary, "counterparty") { primary = it }
                        field("Uzman / iletişim", secondary, "expert") { secondary = it }
                        field("Hizmet kapsamı", notes, "scope") { notes = it }
                        NovaDayField("Başlangıç / kayıt tarihi", firstDate, { firstDate = it }, "osgb.create.start")
                        NovaDayField("Bitiş / termin tarihi", secondDate, { secondDate = it }, "osgb.create.end")
                        stepper("Aylık dakika")
                    }
                    IsgWorkspaceDomain.BOARD -> {
                        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                NovaText("Toplantı", style = NovaTypeToken.bodyStrong)
                                NovaDayField("Toplantı tarihi", firstDate, { firstDate = it }, "osgb.create.date")
                                NovaSegmentedControl(listOf("Gerçekleşti", "İptal edildi"), if (boardState == "held") 0 else 1) {
                                    boardState = if (it == 0) "held" else "cancelled"
                                }
                                field("Gündem maddeleri · her satıra bir madde", primary, "agenda") { primary = it }
                            }
                        }
                        if (boardState == "held") {
                            OsgbEmployeeSelector("Katılımcılar", employees, selectedEmployees, single = false,
                                onToggle = { selectedEmployees = if (it in selectedEmployees) selectedEmployees - it else selectedEmployees + it })
                            field("Alınan kararlar · her satıra bir karar", decisions, "decisions") { decisions = it }
                        } else field("İptal gerekçesi", notes, "reason") { notes = it }
                        NovaHelpHint("Kurul toplantısı mevzuat kapsamındaki gerçekleşen kayıt olarak saklanır; kararlar toplantıya bağlı ayrı takip maddelerine dönüşür.")
                    }
                    IsgWorkspaceDomain.WORK_PERMIT -> {
                        field("İş tanımı", primary, "job") { primary = it }
                        field("Çalışma yeri / taraf", secondary, "location") { secondary = it }
                        field("Not", notes, "note") { notes = it }
                        NovaDayField("Başlangıç / kayıt tarihi", firstDate, { firstDate = it }, "osgb.create.start")
                        NovaTimeField("Başlangıç saati", firstTime, "osgb.create.start.time") { firstTime = it }
                        NovaDayField("Bitiş / termin tarihi", secondDate, { secondDate = it }, "osgb.create.end")
                        NovaTimeField("Bitiş saati", secondTime, "osgb.create.end.time") { secondTime = it }
                    }
                    else -> Unit
                }
            }
            step == attachmentStep -> {
                NovaText("Dosya ve kanıt", style = NovaTypeToken.sectionTitle)
                NovaHelpHint("Dosya veya fotoğraf eklemek isteğe bağlıdır; kaydı dosyasız da tamamlayabilirsiniz.")
                OsgbAttachmentField("Bu kayda dosya ekle (isteğe bağlı)", attachment, { attachment = it })
            }
            else -> {
                NovaText("Kontrol", style = NovaTypeToken.sectionTitle)
                NovaHelpHint("Bilgileri doğrulayın. Değişiklik gerekiyorsa Geri ile ilgili adıma dönebilirsiniz.")
                NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                        OsgbReviewRow("Modül", domain.title)
                        if (needsWorkplace) OsgbReviewRow("İşyeri", workplaces.firstOrNull { it.first == workplaceId }?.second ?: "Seçilmedi")
                        if (domain == IsgWorkspaceDomain.VISIT) {
                            OsgbReviewRow("Ziyaret tarihi", firstDate); OsgbReviewRow("Süre", "$number dakika"); OsgbReviewRow("Ziyaret notu", primary)
                        }
                        OsgbReviewRow("Dosya", if (attachment == null) "Eklenmedi" else "Eklendi")
                    }
                }
            }
        }
    }
}

private val fileCategories = listOf("company_logo", "risk_assessment", "emergency_plan", "training_material", "inspection_report",
    "measurement_report", "accident_record", "board_document", "handover_form", "personnel_document", "contract", "permit_form",
    "visit_evidence", "notebook_archive", "other")

private val fileCategoryTitles = mapOf("company_logo" to "Firma logosu", "risk_assessment" to "Risk değerlendirmesi",
    "emergency_plan" to "Acil durum planı", "training_material" to "Eğitim belgesi", "inspection_report" to "Kontrol raporu",
    "measurement_report" to "Ölçüm raporu", "accident_record" to "Kaza kaydı", "board_document" to "Kurul belgesi",
    "handover_form" to "Teslim formu", "personnel_document" to "Personel belgesi", "contract" to "Sözleşme", "permit_form" to "İzin formu",
    "visit_evidence" to "Ziyaret kanıtı", "notebook_archive" to "Defter arşivi", "other" to "Diğer")

/** Dosya ekle (iOS `IsgWorkspaceFileCreateEditor`): bytes go to the server-owned intent flow of the selected company. */
@Composable
fun NovaOsgbFileCreateEditor(scope: NovaOsgbScope, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    var file by remember { mutableStateOf<OsgbAttachment?>(null) }
    var title by remember { mutableStateOf("") }
    var category by remember { mutableStateOf("other") }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val attempt = remember { IsgWorkspaceMutationAttempt() }
    androidx.activity.compose.BackHandler(enabled = !saving, onBack = onDone)
    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp).padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPageHeading("Dosya ekle", onBack = onDone)
        NovaHelpHint("Dosya doğrulandıktan sonra seçili firmanın arşivine eklenir.")
        OsgbAttachmentField("Dosya seç", file, {
            file = it
            if (it != null && title.isBlank()) title = it.title
        }, help = "PDF, Office, CSV ve görsel · en fazla 50 MB", identifier = "osgb.file.pick")
        if (file != null) {
            NovaTextField("Dosya başlığı", title, { title = it }, identifier = "osgb.file.title")
            OsgbPicker("Kategori", fileCategories, category, "osgb.file.category", fileCategoryTitles) { category = it }
        }
        error?.let { NovaHelpHint(it) }
        NovaCompactActionButton(if (saving) "Dosya doğrulanıyor…" else "Dosyayı ekle", "arrow.up.doc", Modifier.width(IntrinsicSize.Max),
            prominent = true, enabled = file != null && title.isNotBlank() && !saving, identifier = "osgb.file.save") {
            val chosen = file ?: return@NovaCompactActionButton
            val mutation = attempt.id("files.create", title.trim(), chosen.filename, category, chosen.digest)
            saving = true; error = null
            coroutines.launch {
                try {
                    scope.repository.uploadFile(scope.context, mutation, scope.companyId, title, chosen.filename, category, chosen.data)
                    celebrate("Dosya kaydedildi.")
                    onDone()
                } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                    error = "Dosya eklenemedi. Dosya türünü ve bağlantınızı kontrol edip yeniden deneyin."
                }
                saving = false
            }
        }
    }
}
