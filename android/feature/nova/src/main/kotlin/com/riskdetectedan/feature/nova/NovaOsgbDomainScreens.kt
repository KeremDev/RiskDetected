package com.riskdetectedan.feature.nova

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate

/** The OSGB title and symbol of each workspace domain (iOS `IsgWorkspaceDomain.title/symbol`). */
internal val IsgWorkspaceDomain.destination: NovaDestination get() = when (this) {
    IsgWorkspaceDomain.PERSONNEL -> NovaDestination.companies; IsgWorkspaceDomain.TRAINING -> NovaDestination.training
    IsgWorkspaceDomain.RISK -> NovaDestination.riskAssessments; IsgWorkspaceDomain.NONCONFORMITY -> NovaDestination.findings
    IsgWorkspaceDomain.CHECKLIST -> NovaDestination.checklists; IsgWorkspaceDomain.EMERGENCY_PLAN -> NovaDestination.emergencyPlans
    IsgWorkspaceDomain.DRILL -> NovaDestination.drills; IsgWorkspaceDomain.APPOINTMENT -> NovaDestination.appointments
    IsgWorkspaceDomain.PPE -> NovaDestination.ppeHandovers; IsgWorkspaceDomain.EQUIPMENT -> NovaDestination.periodicChecks
    IsgWorkspaceDomain.KATIP -> NovaDestination.katipContracts; IsgWorkspaceDomain.ANNUAL_PLAN -> NovaDestination.annualWorkPlans
    IsgWorkspaceDomain.BOARD -> NovaDestination.boardMeetings; IsgWorkspaceDomain.WORK_PERMIT -> NovaDestination.workPermits
    IsgWorkspaceDomain.VISIT -> NovaDestination.visits; IsgWorkspaceDomain.FILES -> NovaDestination.documents
}
internal val IsgWorkspaceDomain.title: String get() = if (this == IsgWorkspaceDomain.PERSONNEL) "Personel" else destination.title
internal val IsgWorkspaceDomain.symbol: String get() = if (this == IsgWorkspaceDomain.PERSONNEL) "person.2" else destination.symbol

/** The workspace calls one domain page needs, bound to the selected workspace and company. */
class NovaOsgbDomainClient(
    val snapshot: suspend (IsgWorkspaceDomain) -> IsgWorkspaceSnapshot,
    val detail: suspend (IsgWorkspaceDomain, String) -> IsgWorkspaceRecord,
    val workplaces: suspend () -> Map<String, String>,
    val employees: suspend () -> Map<String, String>,
)

private fun today() = LocalDate.now().toString()
private fun inDays(days: Long) = LocalDate.now().plusDays(days).toString()

private fun statusTone(value: String) = when (value) {
    "closed", "completed", "performed", "valid", "active", "held" -> NovaStatus.Success
    "overdue", "expired", "failed", "critical" -> NovaStatus.Danger
    "due_soon", "planned", "draft", "open", "upcoming", "untracked", "never_inspected", "period_unknown" -> NovaStatus.Warning
    else -> NovaStatus.Neutral
}

private fun metricSymbol(domain: IsgWorkspaceDomain, key: String) = when {
    key.contains("overdue") || key.contains("expired") -> "exclamationmark.triangle"
    key.contains("completed") || key.contains("valid") -> "checkmark.circle"
    key.contains("people") || key.contains("employee") -> "person.2"
    key.contains("minute") -> "clock"
    key.contains("untracked") -> "questionmark.circle"
    key.contains("upcoming") || key.contains("due_soon") -> "clock"
    key.contains("held") -> "person.3"
    key.contains("decision") -> "checklist"
    else -> domain.symbol
}

private fun metricStatus(key: String) = when {
    key.contains("overdue") || key.contains("expired") || key.contains("failed") -> NovaStatus.Danger
    key.contains("untracked") || key.contains("due_soon") || key.contains("upcoming") || key.contains("open") -> NovaStatus.Warning
    key.contains("valid") || key.contains("completed") || key.contains("active") || key.contains("held") -> NovaStatus.Success
    else -> NovaStatus.Neutral
}

/** The status a row shows; appointments and emergency plans derive theirs from their dates. */
internal fun osgbRecordStatus(domain: IsgWorkspaceDomain, row: IsgWorkspaceRecord): String? {
    val today = today()
    return when (domain) {
        IsgWorkspaceDomain.APPOINTMENT -> when {
            row.fact("starts_on")?.let { it > today } == true -> "upcoming"
            row.fact("ends_before")?.let { it <= today } == true -> "ended"
            else -> "active"
        }
        IsgWorkspaceDomain.EMERGENCY_PLAN -> row.fact("valid_until")?.let { valid ->
            when { valid < today -> "expired"; valid <= inDays(60) -> "due_soon"; else -> "valid" }
        } ?: "untracked"
        else -> row.status
    }
}

private fun priority(domain: IsgWorkspaceDomain, row: IsgWorkspaceRecord) = when (osgbRecordStatus(domain, row).orEmpty()) {
    "overdue", "expired", "failed", "critical" -> 0
    "open", "in_progress", "pending_verification", "untracked", "never_inspected", "period_unknown" -> 1
    "due_soon", "upcoming", "draft", "planned" -> 2
    "valid", "active", "completed", "closed", "held", "performed" -> 4
    else -> 3
}

/** Counters in the order each domain reads them; four domains derive theirs from the rows when the server has none. */
private fun displayMetrics(domain: IsgWorkspaceDomain, snapshot: IsgWorkspaceSnapshot): List<IsgWorkspaceMetric> {
    val rows = snapshot.rows; val values = snapshot.metrics; val today = today(); val due = inDays(60)
    fun keyed(keys: List<String>, fallback: Map<String, Long>) = keys.map { key -> IsgWorkspaceMetric(key, values.firstOrNull { it.id == key }?.value ?: fallback[key] ?: 0) }
    return when (domain) {
        IsgWorkspaceDomain.EMERGENCY_PLAN -> {
            val dates = rows.map { it.fact("valid_until") }
            keyed(listOf("plans.expired", "plans.untracked", "plans.due_soon", "plans.valid"), mapOf(
                "plans.expired" to dates.count { (it ?: today) < today }.toLong(), "plans.untracked" to dates.count { it == null }.toLong(),
                "plans.due_soon" to dates.filterNotNull().count { it in today..due }.toLong(), "plans.valid" to dates.filterNotNull().count { it > due }.toLong()))
        }
        IsgWorkspaceDomain.APPOINTMENT -> {
            val states = rows.map { osgbRecordStatus(domain, it) }
            keyed(listOf("appointments.active", "appointments.upcoming", "appointments.ended", "appointments.total"), mapOf(
                "appointments.active" to states.count { it == "active" }.toLong(), "appointments.upcoming" to states.count { it == "upcoming" }.toLong(),
                "appointments.ended" to states.count { it == "ended" }.toLong(), "appointments.total" to rows.size.toLong()))
        }
        IsgWorkspaceDomain.RISK -> {
            val expired = rows.count { (it.fact("valid_until") ?: today) < today }
            val untracked = rows.count { (it.fact("current_version")?.toIntOrNull() ?: 0) == 0 }
            val dueSoon = rows.count { row -> row.fact("valid_until")?.let { it in today..due } == true }
            keyed(listOf("risk.expired", "risk.untracked", "risk.valid", "risk.due_soon"), mapOf("risk.expired" to expired.toLong(),
                "risk.untracked" to untracked.toLong(), "risk.valid" to maxOf(0, rows.size - expired - untracked - dueSoon).toLong(),
                "risk.due_soon" to dueSoon.toLong()))
        }
        IsgWorkspaceDomain.BOARD -> keyed(listOf("board.planned", "board.held", "board.open_decisions", "board.cancelled"), mapOf(
            "board.planned" to rows.count { it.status == "planned" }.toLong(), "board.held" to rows.count { it.status == "held" }.toLong(),
            "board.open_decisions" to rows.sumOf { it.fact("open_decision_count")?.toIntOrNull() ?: 0 }.toLong(),
            "board.cancelled" to rows.count { it.status == "cancelled" }.toLong()))
        else -> {
            val preferred = when (domain) {
                IsgWorkspaceDomain.TRAINING -> listOf("completed_minutes", "trained_people", "person_minutes", "people_without_completed_training")
                IsgWorkspaceDomain.EQUIPMENT -> listOf("overdue", "failed", "untracked", "due_soon", "current")
                IsgWorkspaceDomain.NONCONFORMITY -> listOf("open", "assigned", "pending_verification", "closed")
                else -> listOf("total", "active", "planned", "completed", "open", "overdue", "archived")
            }
            fun rank(metric: IsgWorkspaceMetric) = preferred.indexOfFirst { metric.id == it || metric.id.endsWith(".$it") }.let { if (it < 0) Int.MAX_VALUE else it }
            values.sortedWith(compareBy<IsgWorkspaceMetric> { rank(it) }.thenBy { it.id }).take(if (domain == IsgWorkspaceDomain.EQUIPMENT) 5 else 4)
        }
    }
}

private fun recordTitle(domain: IsgWorkspaceDomain, row: IsgWorkspaceRecord, workplaces: Map<String, String>, employees: Map<String, String>): String {
    if (domain == IsgWorkspaceDomain.APPOINTMENT) row.fact("employee_id")?.let { employees[it.lowercase()] }?.let { return it }
    if (domain == IsgWorkspaceDomain.RISK) row.fact("workplace_id")?.let { workplaces[it.lowercase()] }?.let { return it }
    if (domain == IsgWorkspaceDomain.BOARD) (row.fact("held_on") ?: row.fact("planned_on"))?.let { return "Kurul toplantısı · $it" }
    return row.title
}

private fun recordSubtitle(domain: IsgWorkspaceDomain, row: IsgWorkspaceRecord, workplaces: Map<String, String>): String? {
    val values = mutableListOf<String>()
    if (domain == IsgWorkspaceDomain.APPOINTMENT) values += IsgWorkspaceDisplayText.value(row.title)
    row.fact("workplace_id")?.let { workplaces[it.lowercase()] }?.let { values += it }
    if (domain == IsgWorkspaceDomain.BOARD) row.fact("agenda_summary")?.let { values += it }
    if (values.isEmpty()) row.subtitle?.let { values += it }
    return values.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

private fun recordHighlights(domain: IsgWorkspaceDomain, row: IsgWorkspaceRecord): List<String> = when (domain) {
    IsgWorkspaceDomain.EMERGENCY_PLAN -> listOfNotNull(row.fact("prepared_on")?.let { "Hazırlanma: $it" }, row.fact("valid_until")?.let { "Geçerlilik: $it" },
        row.fact("team_size")?.let { "$it kişilik ekip" })
    IsgWorkspaceDomain.APPOINTMENT -> listOfNotNull(row.fact("starts_on")?.let { "Başlangıç: $it" }, row.fact("ends_before")?.let { "Bitiş: $it" })
    IsgWorkspaceDomain.RISK -> listOfNotNull(row.fact("base_assessment_on")?.let { "Değerlendirme: $it" }, row.fact("valid_until")?.let { "Geçerlilik: $it" },
        row.fact("current_version")?.let { "Sürüm: $it" })
    IsgWorkspaceDomain.TRAINING -> listOfNotNull(row.fact("duration_minutes")?.let { "$it dk" }, row.fact("participant_count")?.let { "$it katılımcı" },
        row.fact("method")?.let(IsgWorkspaceDisplayText::value))
    IsgWorkspaceDomain.EQUIPMENT -> listOfNotNull(row.fact("serial_tag")?.let { "Kod: $it" }, row.fact("last_performed_on")?.let { "Son kontrol: $it" },
        row.fact("next_due_on")?.let { "Sonraki: $it" })
    IsgWorkspaceDomain.BOARD -> listOfNotNull(row.fact("attendance_count")?.let { "$it katılımcı" }, row.fact("decision_count")?.let { "$it karar" },
        row.fact("open_decision_count")?.let { "$it açık" })
    else -> emptyList()
}

private fun emptyTitle(domain: IsgWorkspaceDomain) = when (domain) {
    IsgWorkspaceDomain.EMERGENCY_PLAN -> "Henüz acil durum planı yok"; IsgWorkspaceDomain.APPOINTMENT -> "Henüz atama kaydı yok"
    IsgWorkspaceDomain.BOARD -> "Henüz kurul toplantısı kaydı yok"; IsgWorkspaceDomain.RISK -> "Henüz risk değerlendirmesi yok"
    IsgWorkspaceDomain.TRAINING -> "Henüz gerçekleşen eğitim kaydı yok"; IsgWorkspaceDomain.EQUIPMENT -> "Henüz ekipman kaydı yok"
    else -> "Henüz ${domain.title.lowercase(java.util.Locale.forLanguageTag("tr-TR"))} kaydı yok"
}

private fun emptyMessage(domain: IsgWorkspaceDomain) = when (domain) {
    IsgWorkspaceDomain.EMERGENCY_PLAN -> "Planı ve görevli ekibi ekleyerek geçerlilik süresini dijital ortamda takip edebilirsiniz."
    IsgWorkspaceDomain.APPOINTMENT -> "Firma personeline görev vererek çalışan temsilcisi ve destek elemanı kayıtlarını tek yerden izleyebilirsiniz."
    IsgWorkspaceDomain.BOARD -> "Toplantıyı ekleyerek gündemi, katılımcıları ve alınan kararları birlikte takip edebilirsiniz."
    IsgWorkspaceDomain.RISK -> "İlk değerlendirmeyi ekleyerek geçerlilik süresini ve sonraki revizyonları takip edebilirsiniz."
    IsgWorkspaceDomain.TRAINING -> "Gerçekleşen eğitimi ve katılımcıları ekleyerek eğitim saatlerini ve eksik personeli takip edebilirsiniz."
    IsgWorkspaceDomain.EQUIPMENT -> "Periyodik kontrole giren ekipmanları ekleyerek kontrol tarihlerini ve raporlarını takip edebilirsiniz."
    else -> "Yeni kayıtlar bu firmaya ve yetkili çalışma alanına bağlı olarak burada görünür."
}

private fun addTitle(domain: IsgWorkspaceDomain) = when (domain) {
    IsgWorkspaceDomain.EMERGENCY_PLAN -> "Plan Ekle"; IsgWorkspaceDomain.APPOINTMENT -> "Atama Ekle"; IsgWorkspaceDomain.BOARD -> "Toplantı Ekle"
    IsgWorkspaceDomain.RISK -> "Kayıt Ekle"; IsgWorkspaceDomain.TRAINING -> "Eğitim Ekle"; IsgWorkspaceDomain.EQUIPMENT -> "Ekipman Ekle"
    else -> "Ekle"
}

/**
 * A workspace-only operational browser (iOS `IsgWorkspaceDomainScreen`): it reads through the workspace API alone,
 * so an OSGB route can never fall back to a personal owner boundary. [create] is the domain's create flow, shown
 * full screen; [actions] is the operable part of a record's detail.
 */
@Composable
fun NovaOsgbDomainScreen(client: NovaOsgbDomainClient, domain: IsgWorkspaceDomain, companyName: String, onBack: () -> Unit,
                         startInAddMode: Boolean = false, create: (@Composable (onClose: () -> Unit) -> Unit)? = null,
                         actions: (@Composable (IsgWorkspaceRecord, workplaces: Map<String, String>, onChanged: () -> Unit) -> Unit)? = null) {
    var snapshot by remember { mutableStateOf<IsgWorkspaceSnapshot?>(null) }
    var query by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    var workplaces by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var employees by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var selected by remember { mutableStateOf<IsgWorkspaceRecord?>(null) }
    var detailLoading by remember { mutableStateOf<String?>(null) }
    var creating by rememberSaveable { mutableStateOf(startInAddMode && create != null) }
    val coroutines = rememberCoroutineScope()
    if (creating && create != null) {
        create { creating = false; reload++ }
        return
    }
    BackHandler(onBack = onBack)
    fun open(row: IsgWorkspaceRecord) {
        if (detailLoading != null) return
        detailLoading = row.id
        coroutines.launch {
            selected = try { client.detail(domain, row.id) } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                error = "Kayıt geçmişinin tamamı yüklenemedi. Özet bilgiler gösteriliyor."; row
            }
            detailLoading = null
        }
    }
    LaunchedEffect(reload) {
        loading = true; error = null
        try {
            snapshot = client.snapshot(domain)
            if (domain in setOf(IsgWorkspaceDomain.EMERGENCY_PLAN, IsgWorkspaceDomain.APPOINTMENT, IsgWorkspaceDomain.RISK, IsgWorkspaceDomain.BOARD))
                workplaces = runCatching { client.workplaces() }.getOrDefault(emptyMap())
            if (domain in setOf(IsgWorkspaceDomain.EMERGENCY_PLAN, IsgWorkspaceDomain.APPOINTMENT, IsgWorkspaceDomain.BOARD))
                employees = runCatching { client.employees() }.getOrDefault(emptyMap())
        } catch (_: Exception) { snapshot = null; error = "Bağlantınızı kontrol edip yeniden deneyin." }
        loading = false
    }
    val needle = query.trim()
    val rows = snapshot?.rows.orEmpty().filter { row ->
        needle.isEmpty() || (listOfNotNull(row.title, row.subtitle, row.status) + row.facts.map { it.second }).any { it.contains(needle, true) }
    }.sortedWith(compareBy<IsgWorkspaceRecord> { priority(domain, it) }.thenBy { recordTitle(domain, it, workplaces, employees) })
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset)
        .testTag("osgb.domain.${domain.name.lowercase()}"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaListHeading(domain.title, onBack) {
            if (create != null) NovaButton(addTitle(domain), { creating = true }, symbol = "plus", compact = true)
        }
        NovaSearchCapsule(query, "Kayıtlarda ara", "osgb.domain.search") { query = it }
        snapshot?.let { value ->
            val metrics = displayMetrics(domain, value)
            if (metrics.isNotEmpty()) NovaMetricStrip(metrics.map {
                NovaMetricStripItem(it.id, IsgWorkspaceDisplayText.metricValue(it.id, it.value), IsgWorkspaceDisplayText.metric(it.id),
                    metricSymbol(domain, it.id), metricStatus(it.id))
            })
        }
        when {
            loading -> NovaLoadingView("Kayıtlar yükleniyor…")
            error != null && snapshot == null -> {
                NovaEmptyState("Kayıtlar yüklenemedi", error!!)
                NovaCompactActionButton("Tekrar dene", "arrow.clockwise", Modifier.width(IntrinsicSize.Max)) { reload++ }
            }
            rows.isEmpty() -> NovaEmptyState(emptyTitle(domain), emptyMessage(domain))
            else -> NovaListEntrance(true) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    rows.forEachIndexed { index, row ->
                        NovaCard(Modifier.fillMaxWidth().novaRowEntrance(index).clip(RoundedCornerShape(22.dp)).novaRowPress(enabled = detailLoading == null) { open(row) }
                            .testTag("osgb.record.${row.id}"), padding = 14) {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                NovaIcon(domain.symbol, 19.dp)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    NovaText(recordTitle(domain, row, workplaces, employees), style = NovaTypeToken.bodyStrong)
                                    recordSubtitle(domain, row, workplaces)?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                                    osgbRecordStatus(domain, row)?.let { NovaStatusPill(IsgWorkspaceDisplayText.value(it), statusTone(it)) }
                                    recordHighlights(domain, row).takeIf { it.isNotEmpty() }?.let {
                                        NovaText(it.joinToString(" · "), style = NovaTypeToken.metaQuiet)
                                    }
                                }
                                if (detailLoading == row.id) NovaSpinner(NovaColorToken.text.color(), size = 14.dp)
                                else NovaIcon("chevron.right", 12.dp)
                            }
                        }
                    }
                }
            }
        }
        if (snapshot != null) error?.let { NovaHelpHint(it) }
    }
    val open = selected
    NovaPopup(open != null, { selected = null }, identifier = "osgb.record.detail") {
        if (open != null) NovaOsgbRecordDetail(domain, open, recordTitle(domain, open, workplaces, employees), workplaces, employees) {
            actions?.invoke(open, workplaces) { selected = null; reload++ }
        }
    }
}

/** One record's facts and history (iOS `IsgWorkspaceDomainDetail`). [extra] carries the record's actions. */
@Composable
private fun NovaOsgbRecordDetail(domain: IsgWorkspaceDomain, row: IsgWorkspaceRecord, title: String, workplaces: Map<String, String>,
                                 employees: Map<String, String>, extra: @Composable () -> Unit) {
    fun factValue(fact: Pair<String, String>) = when (fact.first) {
        "employee_id" -> employees[fact.second.lowercase()] ?: IsgWorkspaceDisplayText.value(fact.second)
        "workplace_id" -> workplaces[fact.second.lowercase()] ?: IsgWorkspaceDisplayText.value(fact.second)
        else -> IsgWorkspaceDisplayText.value(fact.second)
    }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaIcon(domain.symbol, 22.dp)
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                NovaText(title, style = NovaTypeToken.sectionTitle)
                row.subtitle?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
            }
        }
        row.status?.let { NovaStatusPill(IsgWorkspaceDisplayText.value(it), NovaStatus.Neutral) }
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                row.facts.forEach { fact ->
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        NovaText(IsgWorkspaceDisplayText.field(fact.first), style = NovaTypeToken.metaQuiet)
                        NovaText(factValue(fact), style = NovaTypeToken.bodyStrong)
                    }
                }
            }
        }
        if (domain == IsgWorkspaceDomain.RISK) {
            NovaText("Sürüm geçmişi", style = NovaTypeToken.cardTitle)
            if (row.riskVersions.isEmpty()) NovaEmptyState("Henüz sürüm yok", "İlk değerlendirme taslağı eklendiğinde sürüm geçmişi burada oluşur.")
            row.riskVersions.sortedByDescending { it.number }.forEach { version ->
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            NovaText("v${version.number} · ${IsgWorkspaceDisplayText.value(version.kind)}", Modifier.weight(1f), NovaTypeToken.bodyStrong)
                            NovaStatusPill(IsgWorkspaceDisplayText.value(version.state), when (version.state) {
                                "final" -> NovaStatus.Success; "draft" -> NovaStatus.Warning; else -> NovaStatus.Neutral })
                        }
                        NovaText(listOfNotNull("Değerlendirme: ${version.assessmentOn}", version.revisionOn?.let { "Revizyon: $it" }).joinToString("   "),
                            style = NovaTypeToken.metaQuiet)
                        version.validUntil?.let { NovaText("Geçerlilik: $it", style = NovaTypeToken.metaQuiet) }
                        version.periodYears?.let { NovaText("Süre: $it yıl" + (version.periodSource?.let { " · ${IsgWorkspaceDisplayText.value(it)}" } ?: ""),
                            style = NovaTypeToken.metaQuiet) }
                        version.scopeSummary?.takeIf { it.isNotEmpty() }?.let { NovaText("Kapsam: $it", style = NovaTypeToken.meta) }
                        version.reason?.takeIf { it.isNotEmpty() }?.let { NovaText("Gerekçe: $it", style = NovaTypeToken.meta) }
                        version.cancellationNote?.takeIf { it.isNotEmpty() }?.let { NovaText("İptal gerekçesi: $it", style = NovaTypeToken.meta) }
                        if (version.periodNeedsReview) NovaHelpHint("Süre uzman tarafından belirlenmiştir; kaynak ve geçerlilik bilgisi gözden geçirilmelidir.")
                        if (version.sourceDrift) NovaHelpHint("Kaynak analiz bu sürümden sonra değişmiştir; kayıt otomatik değiştirilmedi.")
                    }
                }
            }
        }
        if (domain == IsgWorkspaceDomain.EQUIPMENT) {
            NovaText("Kontrol ve rapor geçmişi", style = NovaTypeToken.cardTitle)
            if (row.equipmentInspections.isEmpty()) NovaEmptyState("Henüz kontrol kaydı yok",
                "İlk periyodik kontrolü eklediğinizde tarih, sonuç ve rapor bilgileri burada görünür.")
            row.equipmentInspections.forEach { inspection ->
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            NovaText(inspection.performedOn, Modifier.weight(1f), NovaTypeToken.bodyStrong)
                            NovaStatusPill(IsgWorkspaceDisplayText.value(inspection.result), when (inspection.result) {
                                "pass" -> NovaStatus.Success; "fail" -> NovaStatus.Danger; else -> NovaStatus.Warning })
                        }
                        inspection.nextDueOn?.let { NovaText("Sonraki kontrol: $it", style = NovaTypeToken.metaQuiet) }
                        inspection.inspector?.takeIf { it.isNotEmpty() }?.let { NovaText("Kontrolü yapan: $it", style = NovaTypeToken.meta) }
                        inspection.externalRef?.takeIf { it.isNotEmpty() }?.let { NovaText("Rapor no: $it", style = NovaTypeToken.meta) }
                        inspection.note?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.meta) }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (inspection.assetId != null) NovaStatusPill("Rapor arşivde", NovaStatus.Success)
                            if (inspection.katipDeclared) NovaStatusPill("İSG-KATİP beyanı", NovaStatus.Neutral)
                        }
                    }
                }
            }
        }
        if (domain == IsgWorkspaceDomain.TRAINING && row.trainingParticipants.isNotEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaText("Katılımcılar", style = NovaTypeToken.bodyStrong)
                row.trainingParticipants.forEach { person ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon(if (person.attended) "checkmark.circle.fill" else "circle", 15.dp)
                        NovaText(person.name, Modifier.weight(1f))
                        NovaText(when { person.attended -> "Katıldı"; row.status == "planned" -> "Tamamlanmayı bekliyor"; else -> "Katılmadı" },
                            style = NovaTypeToken.metaQuiet)
                    }
                }
            }
        }
        if (domain == IsgWorkspaceDomain.CHECKLIST && row.checklistItems.isNotEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                NovaText("Kontrol maddeleri", style = NovaTypeToken.bodyStrong)
                row.checklistItems.forEach { item ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        NovaIcon(when (item.result) { null -> "circle"; "conform" -> "checkmark.circle"; "nonconform" -> "exclamationmark.triangle"
                            else -> "minus.circle" }, 15.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            NovaText(item.prompt)
                            NovaText(when (item.result) { "conform" -> "Uygun"; "nonconform" -> "Uygunsuz"; "not_applicable" -> "Uygulanamaz"
                                else -> "Yanıt bekliyor" }, style = NovaTypeToken.metaQuiet)
                            item.note?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.metaQuiet) }
                        }
                    }
                }
            }
        }
        extra()
    }
}

/** Bildirimler for the workspace (iOS `IsgWorkspaceChangeScreen`): the record changes, refreshed every thirty seconds. */
@Composable
fun NovaOsgbChangeScreen(load: suspend () -> List<Triple<Long, String, String>>, companyName: String?, onBack: () -> Unit) {
    var rows by remember { mutableStateOf<List<Triple<Long, String, String>>?>(null) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    BackHandler(onBack = onBack)
    LaunchedEffect(Unit) {
        var first = true
        while (true) {
            if (first) loading = true
            error = null
            try { rows = load() } catch (_: Exception) { rows = null; error = "Bağlantınızı kontrol edip yeniden deneyin." }
            if (first) { loading = false; first = false }
            delay(30_000)
        }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPageHeading(NovaDestination.notifications.title, onBack = onBack)
        companyName?.let { NovaHelpHint("$it firmasındaki yetkili değişiklikler gösteriliyor.") }
        when {
            loading -> NovaLoadingView("Değişiklikler yükleniyor…")
            error != null -> NovaEmptyState("Değişiklikler yüklenemedi", error!!)
            rows.isNullOrEmpty() -> NovaEmptyState("Henüz değişiklik yok", "Bu çalışma alanındaki kayıt hareketleri burada görünür.")
            else -> rows!!.forEach { (sequence, aggregate, event) ->
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon("arrow.triangle.2.circlepath", 18.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            NovaText(IsgWorkspaceDisplayText.field(aggregate), style = NovaTypeToken.bodyStrong)
                            NovaText(IsgWorkspaceDisplayText.event(event), style = NovaTypeToken.metaQuiet)
                        }
                        NovaText("#$sequence", style = NovaTypeToken.metaQuiet)
                    }
                }
            }
        }
    }
}
