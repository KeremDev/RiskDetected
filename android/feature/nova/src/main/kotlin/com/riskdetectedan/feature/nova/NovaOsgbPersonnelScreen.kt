package com.riskdetectedan.feature.nova

import androidx.activity.compose.BackHandler
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
import com.riskdetectedan.core.data.isg.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.*

/** The organisation tabs of a workspace company (iOS `IsgPersonnelSection`). */
enum class NovaOsgbPersonnelSection(val title: String, val symbol: String) {
    employee("Personel", "person"), workplace("İşyerleri", "building.2"), department("Departmanlar", "square.grid.2x2"),
    jobRole("Görevler", "briefcase"), contractor("Dış firmalar", "building.2.crop.circle"), engagement("Sözleşmeler", "doc.text"),
    assignment("Atama geçmişi", "arrow.triangle.branch")
}

private sealed interface PersonnelRoute {
    data class Directory(val entity: String, val entry: IsgWorkspaceDirectoryEntry?) : PersonnelRoute
    data class Employee(val entry: IsgWorkspaceDirectoryEntry?) : PersonnelRoute
    data class Advanced(val section: NovaOsgbPersonnelSection, val entry: IsgWorkspaceAdvancedRecord?) : PersonnelRoute
}

private const val personnelSaveFailed = "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin."

/**
 * Personel for a workspace company (iOS `IsgWorkspacePersonnelScreen`): employees, the workplace and department
 * directory, job roles, contractors with their engagements, and the assignment history.
 */
@Composable
fun NovaOsgbPersonnelScreen(scope: NovaOsgbScope, canManageDirectory: Boolean, onBack: () -> Unit,
                            initialSection: NovaOsgbPersonnelSection = NovaOsgbPersonnelSection.employee) {
    BackHandler(onBack = onBack)
    val (context, repository, companyId) = Triple(scope.context, scope.repository, scope.companyId)
    var section by remember { mutableStateOf(initialSection) }
    var workplaces by remember { mutableStateOf<List<IsgWorkspaceDirectoryEntry>>(emptyList()) }
    var departments by remember { mutableStateOf<List<IsgWorkspaceDirectoryEntry>>(emptyList()) }
    var employees by remember { mutableStateOf<List<IsgWorkspaceDirectoryEntry>>(emptyList()) }
    var advanced by remember { mutableStateOf<Map<NovaOsgbPersonnelSection, List<IsgWorkspaceAdvancedRecord>>>(emptyMap()) }
    var counts by remember { mutableStateOf<Map<String, Long>?>(null) }
    var route by remember { mutableStateOf<PersonnelRoute?>(null) }
    var query by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    LaunchedEffect(revision) {
        loading = true; error = null
        try {
            coroutineScope {
                val places = async { repository.directoryEntries(context, companyId, "workplaces") }
                val units = async { repository.directoryEntries(context, companyId, "departments") }
                val people = async { repository.directoryEntries(context, companyId, "employees") }
                val metrics = async { repository.personnelCounts(context, companyId) }
                val kinds = mapOf(NovaOsgbPersonnelSection.jobRole to IsgWorkspacePersonnelAdvancedKind.JOB_ROLES,
                    NovaOsgbPersonnelSection.contractor to IsgWorkspacePersonnelAdvancedKind.CONTRACTORS,
                    NovaOsgbPersonnelSection.engagement to IsgWorkspacePersonnelAdvancedKind.ENGAGEMENTS,
                    NovaOsgbPersonnelSection.assignment to IsgWorkspacePersonnelAdvancedKind.ASSIGNMENTS)
                    .mapValues { (_, kind) -> async { repository.personnelRecords(context, companyId, kind) } }
                workplaces = places.await(); departments = units.await(); employees = people.await(); counts = metrics.await()
                advanced = kinds.mapValues { it.value.await() }
            }
        } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = "Bağlantınızı kontrol edip yeniden deneyin." }
        loading = false
    }
    val needle = query.trim()
    fun matches(vararg values: String?) = needle.isEmpty() || values.any { it?.contains(needle, true) == true }
    val rows: List<Triple<String, String, () -> Unit>> = when (section) {
        NovaOsgbPersonnelSection.employee -> employees.filter { matches(it.code, it.name) }.map { Triple(it.name, it.code) { route = PersonnelRoute.Employee(it) } }
        NovaOsgbPersonnelSection.workplace -> workplaces.filter { matches(it.code, it.name) }
            .map { Triple(it.name, it.code) { route = PersonnelRoute.Directory("workplace", it) } }
        NovaOsgbPersonnelSection.department -> departments.filter { matches(it.code, it.name) }
            .map { Triple(it.name, it.code) { route = PersonnelRoute.Directory("department", it) } }
        else -> advanced[section].orEmpty().filter { matches(it.title, it.subtitle, it.status) }.map { row ->
            Triple(row.title, listOfNotNull(row.subtitle, row.status?.let(IsgWorkspaceDisplayText::value)).joinToString(" · ")) {
                route = PersonnelRoute.Advanced(section, row)
            }
        }
    }
    val canAdd = when (section) {
        NovaOsgbPersonnelSection.employee, NovaOsgbPersonnelSection.assignment -> context.canOperate
        else -> canManageDirectory
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset)
        .testTag("osgb.personnel"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaListHeading(IsgWorkspaceDomain.PERSONNEL.title, onBack, actionBelow = true) {
            if (canAdd) NovaListActionButton("${section.title} ekle", "plus", identifier = "osgb.personnel.add") {
                route = when (section) {
                    NovaOsgbPersonnelSection.employee -> PersonnelRoute.Employee(null)
                    NovaOsgbPersonnelSection.workplace -> PersonnelRoute.Directory("workplace", null)
                    NovaOsgbPersonnelSection.department -> PersonnelRoute.Directory("department", null)
                    else -> PersonnelRoute.Advanced(section, null)
                }
            }
        }
        NovaListHint("${scope.companyName} firmasına ait yetkili OSGB kayıtları gösteriliyor.")
        counts?.let { values ->
            NovaMetricStrip(listOf(
                NovaMetricStripItem("employees", (values["employees"] ?: 0).toString(), NovaOsgbPersonnelSection.employee.title, "person.2", NovaStatus.Neutral),
                NovaMetricStripItem("workplaces", (values["workplaces"] ?: 0).toString(), NovaOsgbPersonnelSection.workplace.title, "building.2", NovaStatus.Neutral),
                NovaMetricStripItem("departments", (values["departments"] ?: 0).toString(), NovaOsgbPersonnelSection.department.title, "square.grid.2x2", NovaStatus.Neutral),
                NovaMetricStripItem("job_roles", (values["job_roles"] ?: 0).toString(), NovaOsgbPersonnelSection.jobRole.title, "briefcase", NovaStatus.Neutral),
                NovaMetricStripItem("contractors", (values["contractors"] ?: 0).toString(), NovaOsgbPersonnelSection.contractor.title, "building.2.crop.circle", NovaStatus.Neutral),
                NovaMetricStripItem("assignments", (values["assignments"] ?: 0).toString(), NovaOsgbPersonnelSection.assignment.title, "arrow.triangle.branch", NovaStatus.Neutral),
            ))
        }
        NovaSearchCapsule(query, "Kayıtlarda ara", "osgb.personnel.search") { query = it }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaOsgbPersonnelSection.entries.forEach { item ->
                NovaChoiceChip(item.title, section == item, identifier = "osgb.personnel.section.${item.name}", inverse = true) { section = item }
            }
        }
        NovaListSectionHeading(section.title, "${rows.size} kayıt")
        when {
            loading -> NovaLoadingView("Kayıtlar yükleniyor…")
            error != null -> {
                NovaEmptyState("Kayıtlar yüklenemedi", error!!)
                NovaCompactActionButton("Tekrar dene", "arrow.clockwise", Modifier.width(IntrinsicSize.Max)) { revision++ }
            }
            rows.isEmpty() -> NovaEmptyState("Henüz ${section.title} kaydı yok.", "Kayıt ekleyerek firmanın personel organizasyonunu güvenli biçimde yönetin.")
            else -> NovaListEntrance(true) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    rows.forEachIndexed { index, (title, subtitle, open) ->
                        NovaCard(Modifier.fillMaxWidth().novaRowEntrance(index).clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = open), padding = 14) {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                                NovaIcon(if (section == NovaOsgbPersonnelSection.employee) "person" else section.symbol, 19.dp)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    NovaText(title, style = NovaTypeToken.bodyStrong)
                                    NovaText(subtitle, style = NovaTypeToken.metaQuiet)
                                }
                                NovaIcon("chevron.right", 12.dp)
                            }
                        }
                    }
                }
            }
        }
    }
    val open = route
    NovaPopup(open != null, { route = null }, identifier = "osgb.personnel.editor") {
        val done: () -> Unit = { route = null; revision++ }
        when (open) {
            is PersonnelRoute.Directory -> key(open) { DirectoryEditor(scope, open, workplaces, done) }
            is PersonnelRoute.Employee -> key(open) { EmployeeEditor(scope, open.entry, departments, done) }
            is PersonnelRoute.Advanced -> key(open) {
                AdvancedEditor(scope, open, workplaces, departments, employees, advanced[NovaOsgbPersonnelSection.jobRole].orEmpty(),
                    advanced[NovaOsgbPersonnelSection.contractor].orEmpty(), advanced[NovaOsgbPersonnelSection.engagement].orEmpty(), done)
            }
            null -> Unit
        }
    }
}

@Composable
private fun DirectoryEditor(scope: NovaOsgbScope, route: PersonnelRoute.Directory, workplaces: List<IsgWorkspaceDirectoryEntry>, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    val entry = route.entry
    val title = if (route.entity == "workplace") "İşyerleri" else "Departmanlar"
    var code by remember { mutableStateOf(entry?.code.orEmpty()) }
    var name by remember { mutableStateOf(entry?.name.orEmpty()) }
    var workplaceId by remember { mutableStateOf(entry?.workplaceId ?: workplaces.firstOrNull()?.id) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val attempt = remember { IsgWorkspaceMutationAttempt() }
    fun mutate(action: String) {
        val mutation = attempt.id("directory.${route.entity}.$action", entry?.id.orEmpty(), (entry?.version ?: 0).toString(), workplaceId.orEmpty(), code, name)
        working = true; error = null
        coroutines.launch {
            try {
                scope.repository.mutateDirectory(scope.context, mutation, scope.companyId, route.entity, action, entry,
                    if (route.entity == "department") workplaceId else null, code, name)
                celebrate("$title kaydedildi.")
                onDone()
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = personnelSaveFailed }
            working = false
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPopupHeading(if (entry == null) "$title ekle" else "Kaydı düzenle", if (route.entity == "workplace") "building.2" else "square.grid.2x2")
        NovaTextField("Kod", code, { code = it }, identifier = "osgb.directory.code")
        NovaTextField("Ad", name, { name = it }, identifier = "osgb.directory.name")
        if (route.entity == "department" && workplaces.isNotEmpty()) OsgbPicker("İşyerleri", workplaces.map { it.id }, workplaceId, "osgb.directory.workplace",
            workplaces.associate { it.id to it.name }) { workplaceId = it }
        error?.let { NovaHelpHint(it) }
        NovaCompactActionButton(if (working) "Kaydediliyor…" else "Kaydet", "checkmark", prominent = true,
            enabled = !working && code.isNotBlank() && name.isNotBlank() && (route.entity == "workplace" || workplaces.isEmpty() || workplaceId != null)) {
            mutate(if (entry == null) "create" else "edit")
        }
        if (entry != null) NovaCompactActionButton("Arşivle", "archivebox", enabled = !working) { mutate("archive") }
    }
}

@Composable
private fun EmployeeEditor(scope: NovaOsgbScope, entry: IsgWorkspaceDirectoryEntry?, departments: List<IsgWorkspaceDirectoryEntry>, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    var code by remember { mutableStateOf(entry?.code.orEmpty()) }
    var name by remember { mutableStateOf(entry?.name.orEmpty()) }
    var departmentId by remember { mutableStateOf(entry?.departmentId ?: departments.firstOrNull()?.id) }
    var hiredOn by remember { mutableStateOf(entry?.hiredOn ?: osgbToday()) }
    var hasEnd by remember { mutableStateOf(entry?.endsBefore != null) }
    var endsBefore by remember { mutableStateOf(entry?.endsBefore ?: java.time.LocalDate.now().plusYears(1).toString()) }
    var attachment by remember { mutableStateOf<OsgbAttachment?>(null) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val attempt = remember { IsgWorkspaceMutationAttempt() }
    fun mutate(action: String) {
        val hired = if (action == "archive") null else hiredOn
        val ending = if (action == "archive" || !hasEnd) null else endsBefore
        val mutation = attempt.id("employee.$action", entry?.id.orEmpty(), (entry?.version ?: 0).toString(), code, name, departmentId.orEmpty(),
            hired.orEmpty(), ending.orEmpty())
        working = true; error = null
        coroutines.launch {
            try {
                val uploaded = attachment?.takeIf { action != "archive" }?.let {
                    osgbUploadAttachment(scope.repository, scope.context, scope.companyId, attempt, "employee", it, "personnel_document")
                }
                val id = scope.repository.mutateEmployee(scope.context, mutation, scope.companyId, action, entry, code, name, departmentId, hired, ending)
                    ?: entry?.id
                if (uploaded != null && id != null)
                    osgbAttachFile(scope.repository, scope.context, scope.companyId, attempt, "employee", uploaded.first, "employee", id, "personnel_document")
                celebrate(when { action == "archive" -> "Personel arşivlendi."; entry == null -> "Personel eklendi!"; else -> "Personel bilgileri güncellendi." })
                onDone()
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) { error = personnelSaveFailed }
            working = false
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPopupHeading(if (entry == null) "Personel ekle" else "Personeli düzenle", "person")
        NovaTextField("Kod", code, { code = it }, identifier = "osgb.employee.code")
        NovaTextField("Ad soyad", name, { name = it }, identifier = "osgb.employee.name")
        if (departments.isNotEmpty()) OsgbPicker("Departmanlar", departments.map { it.id }, departmentId, "osgb.employee.department",
            departments.associate { it.id to it.name }, placeholder = "Departman seçilmedi") { departmentId = it }
        NovaDayField("İşe giriş", hiredOn, { hiredOn = it }, "osgb.employee.hired")
        NovaCompanyToggleRow("Bitiş tarihi var", hasEnd, !working) { hasEnd = it }
        if (hasEnd) NovaDayField("Bitiş", endsBefore, { endsBefore = maxOf(it, osgbDay(1, hiredOn)) }, "osgb.employee.ends")
        OsgbAttachmentField("Personel belgesi ekle (isteğe bağlı)", attachment, { attachment = it })
        error?.let { NovaHelpHint(it) }
        NovaCompactActionButton(if (working) "Kaydediliyor…" else "Kaydet", "checkmark", prominent = true,
            enabled = !working && code.isNotEmpty() && name.isNotEmpty()) { mutate(if (entry == null) "create" else "edit") }
        if (entry != null) NovaCompactActionButton("Arşivle", "archivebox", enabled = !working) { mutate("archive") }
    }
}

@Composable
private fun AdvancedEditor(scope: NovaOsgbScope, route: PersonnelRoute.Advanced, workplaces: List<IsgWorkspaceDirectoryEntry>,
                           departments: List<IsgWorkspaceDirectoryEntry>, employees: List<IsgWorkspaceDirectoryEntry>,
                           jobRoles: List<IsgWorkspaceAdvancedRecord>, contractors: List<IsgWorkspaceAdvancedRecord>,
                           engagements: List<IsgWorkspaceAdvancedRecord>, onDone: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    val (section, entry) = route.section to route.entry
    var code by remember { mutableStateOf(entry?.text("code").orEmpty()) }
    var name by remember { mutableStateOf(entry?.text("name").orEmpty()) }
    var details by remember { mutableStateOf(entry?.text("description") ?: entry?.text("scope").orEmpty()) }
    var relation by remember { mutableStateOf(entry?.text("relation_kind") ?: "contractor") }
    var taxIdentifier by remember { mutableStateOf(entry?.text("tax_identifier").orEmpty()) }
    var contactName by remember { mutableStateOf(entry?.text("contact_name").orEmpty()) }
    var contactValue by remember { mutableStateOf(entry?.text("contact_value").orEmpty()) }
    var workplaceId by remember { mutableStateOf(entry?.text("workplace_id")?.lowercase() ?: workplaces.firstOrNull()?.id) }
    var contractorId by remember { mutableStateOf(entry?.text("contractor_id")?.lowercase() ?: contractors.firstOrNull()?.id?.lowercase()) }
    var employeeId by remember { mutableStateOf(entry?.text("employee_id")?.lowercase() ?: employees.firstOrNull()?.id) }
    var departmentId by remember { mutableStateOf(entry?.text("department_id")?.lowercase() ?: departments.firstOrNull()?.id) }
    var jobRoleId by remember { mutableStateOf(entry?.text("job_role_id")?.lowercase() ?: jobRoles.firstOrNull()?.id?.lowercase()) }
    var engagementId by remember { mutableStateOf(entry?.text("contractor_engagement_id")?.lowercase()) }
    val start = entry?.text(if (section == NovaOsgbPersonnelSection.engagement) "starts_on" else "effective_from") ?: osgbToday()
    var startsOn by remember { mutableStateOf(start) }
    var endsOn by remember { mutableStateOf(osgbDay(1, start)) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val attempt = remember { IsgWorkspaceMutationAttempt() }
    val symbol = when (section) { NovaOsgbPersonnelSection.jobRole -> "briefcase"; NovaOsgbPersonnelSection.contractor -> "building.2.crop.circle"
        NovaOsgbPersonnelSection.engagement -> "doc.text"; else -> "arrow.triangle.branch" }
    val canSave = when (section) {
        NovaOsgbPersonnelSection.jobRole -> code.isNotBlank() && name.isNotBlank()
        NovaOsgbPersonnelSection.contractor -> name.isNotBlank()
        NovaOsgbPersonnelSection.engagement -> contractorId != null && (workplaces.isEmpty() || workplaceId != null) && details.isNotBlank()
        NovaOsgbPersonnelSection.assignment -> employeeId != null && (departmentId != null || jobRoleId != null || engagementId != null)
        else -> false
    }
    val editable = section in setOf(NovaOsgbPersonnelSection.jobRole, NovaOsgbPersonnelSection.contractor)
    fun mutate(action: String) {
        fun id(value: String?) = value?.let(::JsonPrimitive) ?: JsonNull
        val payload = buildJsonObject {
            put("action", action); put("id", id(entry?.id)); put("expected_version", entry?.version ?: 0)
            when (action) {
                "job_role_save" -> { put("code", code); put("name", name); put("description", details) }
                "contractor_save" -> { put("name", name); put("relation_kind", relation); put("tax_identifier", taxIdentifier)
                    put("contact_name", contactName); put("contact_value", contactValue) }
                "engagement_create" -> { put("contractor_id", id(contractorId)); put("workplace_id", id(workplaceId)); put("scope", details)
                    put("starts_on", startsOn); put("ends_before", JsonNull) }
                "engagement_end" -> put("ends_before", endsOn)
                "assignment_create" -> { put("employee_id", id(employeeId)); put("department_id", id(departmentId)); put("job_role_id", id(jobRoleId))
                    put("engagement_id", id(engagementId)); put("effective_from", startsOn); put("effective_before", JsonNull) }
                "assignment_end" -> put("effective_before", endsOn)
            }
        }
        val mutation = attempt.id("personnel.advanced.$action", payload.toString())
        working = true; error = null
        coroutines.launch {
            try {
                scope.repository.mutatePersonnelAdvanced(scope.context, mutation, scope.companyId, payload)
                celebrate("${section.title} kaydedildi.")
                onDone()
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                error = "İşlem tamamlanamadı. Kapsam, tarih ve sürüm bilgilerini kontrol edin."
            }
            working = false
        }
    }
    @Composable fun picker(label: String, icon: String, values: List<Pair<String, String>>, selected: String?, id: String, optional: Boolean = false,
                           searchable: Boolean = false, onPick: (String?) -> Unit) {
        NovaChoiceField(label, "$label seçin", icon, values.map { NovaChoiceOption(it.first, it.second) }, selected,
            { if (optional || it != null) onPick(it) }, id, noneTitle = if (optional) "Seçilmedi" else null,
            searchable = searchable || values.size > 8, boxed = true)
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPopupHeading(if (entry == null) "${section.title} ekle" else section.title, symbol,
            subtitle = "Kayıt seçili firma kapsamında tutulur; geçmiş satırları korunur.")
        when {
            section == NovaOsgbPersonnelSection.jobRole -> {
                NovaTextField("Görev kodu", code, { code = it }, identifier = "osgb.role.code")
                NovaTextField("Görev adı", name, { name = it }, identifier = "osgb.role.name")
                NovaTextField("Açıklama", details, { details = it }, identifier = "osgb.role.description", multiline = true)
            }
            section == NovaOsgbPersonnelSection.contractor -> {
                NovaTextField("Firma adı", name, { name = it }, identifier = "osgb.contractor.name")
                OsgbPicker("İlişki", listOf("subcontractor", "contractor", "supplier", "other"), relation, "osgb.contractor.relation") { relation = it }
                NovaTextField("Vergi / kayıt no", taxIdentifier, { taxIdentifier = it }, identifier = "osgb.contractor.tax")
                NovaTextField("İletişim kişisi", contactName, { contactName = it }, identifier = "osgb.contractor.contact")
                NovaTextField("Telefon veya e-posta", contactValue, { contactValue = it }, identifier = "osgb.contractor.value")
            }
            section == NovaOsgbPersonnelSection.engagement && entry == null -> {
                picker("Dış firma", "briefcase", contractors.map { it.id.lowercase() to it.title }, contractorId, "osgb.engagement.contractor",
                    searchable = true) { contractorId = it }
                if (workplaces.isNotEmpty()) picker("İşyeri", "building.2", workplaces.map { it.id to it.name }, workplaceId, "osgb.engagement.workplace",
                    searchable = true) { workplaceId = it }
                NovaTextField("İşin kapsamı", details, { details = it }, identifier = "osgb.engagement.scope", multiline = true)
                NovaDayField("Başlangıç", startsOn, { startsOn = it }, "osgb.engagement.start")
            }
            section == NovaOsgbPersonnelSection.assignment && entry == null -> {
                picker("Personel", "person", employees.map { it.id to it.name }, employeeId, "osgb.history.employee", searchable = true) { employeeId = it }
                picker("Departman", "person.3", departments.map { it.id to it.name }, departmentId, "osgb.history.department", optional = true) { departmentId = it }
                picker("Görev", "person.text.rectangle", jobRoles.map { it.id.lowercase() to it.title }, jobRoleId, "osgb.history.role", optional = true) { jobRoleId = it }
                picker("Dış firma sözleşmesi", "doc.text", engagements.filter { it.status == "active" }.map { it.id.lowercase() to it.title }, engagementId,
                    "osgb.history.engagement", optional = true) { engagementId = it }
                NovaDayField("Başlangıç", startsOn, { startsOn = it }, "osgb.history.start")
            }
        }
        error?.let { NovaHelpHint(it) }
        if (entry == null || editable) NovaCompactActionButton(if (working) "Kaydediliyor…" else "Kaydet", "checkmark", prominent = true,
            enabled = canSave && !working, identifier = "osgb.advanced.save") {
            mutate(when (section) {
                NovaOsgbPersonnelSection.jobRole -> "job_role_save"; NovaOsgbPersonnelSection.contractor -> "contractor_save"
                NovaOsgbPersonnelSection.engagement -> "engagement_create"; else -> "assignment_create"
            })
        }
        if (entry != null) {
            if (editable) NovaCompactActionButton("Arşivle", "archivebox", enabled = !working) {
                mutate(if (section == NovaOsgbPersonnelSection.jobRole) "job_role_archive" else "contractor_archive")
            } else {
                val ongoing = if (section == NovaOsgbPersonnelSection.engagement) entry.text("state") == "active" else entry.text("effective_before") == null
                if (ongoing) {
                    NovaDayField("Bitiş tarihi", endsOn, { endsOn = maxOf(it, osgbDay(1, startsOn)) }, "osgb.advanced.end")
                    NovaCompactActionButton("Kaydı sonlandır", "calendar.badge.minus", enabled = !working) {
                        mutate(if (section == NovaOsgbPersonnelSection.engagement) "engagement_end" else "assignment_end")
                    }
                }
            }
        }
    }
}
