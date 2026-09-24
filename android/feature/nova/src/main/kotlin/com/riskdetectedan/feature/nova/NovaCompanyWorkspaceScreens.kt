package com.riskdetectedan.feature.nova

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.data.company.CompanyDraft
import com.riskdetectedan.core.data.company.CompanyHazardClass
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Everything the company page reads and writes for one company, bound by the root to one identity. */
class NovaCompanyWorkspaceClient(
    val summary: suspend () -> NovaCompanySummary?,
    val record: suspend () -> Company?,
    val logo: suspend (String) -> ByteArray?,
    /** Uploads a JPEG as the company logo and saves it on the record; returns the saved record. */
    val saveLogo: suspend (Company, ByteArray) -> Company,
    val saveCompany: suspend (CompanyDraft) -> Company,
    val nonconformities: suspend () -> List<NovaNonconformityRow>,
    val completedTrainings: suspend () -> Int,
    val tracking: suspend () -> NovaModuleTrackingSnapshot,
    val equipment: suspend () -> NovaEquipmentBoard,
    val risk: suspend () -> NovaRiskBoard,
    val appointments: suspend (NovaAppointmentKind) -> NovaAppointmentBoard,
    val fileCategories: suspend () -> List<NovaFileCategory>,
    val files: suspend () -> NovaFileLibraryPage,
    val changes: Flow<Unit> = emptyFlow(),
)

/** The pages the company page opens, each over its own module for this company. */
sealed interface NovaCompanyPage {
    data object Personnel : NovaCompanyPage
    data class Directory(val kind: NovaDirectoryKind) : NovaCompanyPage
    data object Training : NovaCompanyPage
    /** A module list (risk, appointment, emergency_plan, drill, board, ppe or equipment), optionally straight into its add form. */
    data class Module(val kind: String, val adding: Boolean = false, val heading: String? = null) : NovaCompanyPage
    data class Files(val categories: List<String>?, val heading: String, val adding: Boolean = false) : NovaCompanyPage
    data object Editor : NovaCompanyPage
}

private data class NextAction(val id: String, val title: String, val detail: String, val symbol: String, val status: NovaStatus, val page: NovaCompanyPage?)

/** The pilot is Turkish-only, like iOS; the shared enum's title follows the legacy app language. */
private fun companyHazardTitle(id: String) = when (id) { "low" -> "Az Tehlikeli"; "high" -> "Çok Tehlikeli"; else -> "Tehlikeli" }

private fun trackingSummary(snapshot: NovaModuleTrackingSnapshot?, kind: String) = snapshot?.summaries?.firstOrNull { it.id == kind }

private fun sectionKind(section: NovaCompanySection) = when (section) {
    NovaCompanySection.representative, NovaCompanySection.support -> "appointment"
    NovaCompanySection.emergency -> "emergency_plan"; NovaCompanySection.board -> "board"; NovaCompanySection.handover -> "ppe"
    else -> null
}

/**
 * Firma Detayı (iOS `NovaCompanyWorkspace`): the company's overview, its readiness ring, logo, the
 * next work it needs and every record heading, each opening its own module for this company.
 * [open] renders a module page; [onOpenFindings] leaves for the nonconformity board.
 */
@Composable
fun NovaCompanyWorkspaceScreen(client: NovaCompanyWorkspaceClient, companyId: String, companyName: String, canWrite: Boolean, canManageCompany: Boolean,
                               onBack: () -> Unit, onOpenFindings: () -> Unit,
                               open: @Composable (page: NovaCompanyPage, onBack: () -> Unit) -> Unit) {
    val context = LocalContext.current
    val coroutines = rememberCoroutineScope()
    val celebrate = rememberNovaCelebrate()
    var revision by remember { mutableIntStateOf(0) }
    var summary by remember { mutableStateOf<NovaCompanySummary?>(null) }
    var summaryFailed by remember { mutableStateOf(false) }
    var record by remember { mutableStateOf<Company?>(null) }
    var recordLoaded by remember { mutableStateOf(false) }
    var logo by remember { mutableStateOf<Bitmap?>(null) }
    var logoSaving by remember { mutableStateOf(false) }
    var logoError by remember { mutableStateOf<String?>(null) }
    var nonconformities by remember { mutableStateOf<List<NovaNonconformityRow>?>(null) }
    var completedTrainings by remember { mutableStateOf<Int?>(null) }
    var tracking by remember { mutableStateOf<NovaModuleTrackingSnapshot?>(null) }
    var equipment by remember { mutableStateOf<NovaEquipmentBoard?>(null) }
    var risk by remember { mutableStateOf<NovaRiskBoard?>(null) }
    var representative by remember { mutableStateOf<NovaAppointmentBoard?>(null) }
    var support by remember { mutableStateOf<NovaAppointmentBoard?>(null) }
    var categories by remember { mutableStateOf<List<NovaFileCategory>>(emptyList()) }
    var files by remember { mutableStateOf<NovaFileLibraryPage?>(null) }
    var page by remember { mutableStateOf<NovaCompanyPage?>(null) }

    suspend fun loadLogo(path: String?) {
        logo = null
        if (path.isNullOrEmpty()) return
        logo = client.logo(path)?.let { bytes -> withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) } }
    }
    LaunchedEffect(client) { client.changes.collect { revision++ } }
    LaunchedEffect(revision) {
        summaryFailed = false
        launch { try { summary = client.summary() } catch (_: Exception) { summaryFailed = true } }
        launch { completedTrainings = runCatching { client.completedTrainings() }.getOrNull() }
        launch { nonconformities = runCatching { client.nonconformities() }.getOrNull() }
        launch { tracking = runCatching { client.tracking() }.getOrNull() }
        launch { equipment = runCatching { client.equipment() }.getOrNull() }
        launch { risk = runCatching { client.risk() }.getOrNull() }
        launch { representative = runCatching { client.appointments(NovaAppointmentKind.representative) }.getOrNull() }
        launch { support = runCatching { client.appointments(NovaAppointmentKind.supportStaff) }.getOrNull() }
        launch { runCatching { client.fileCategories() }.getOrNull()?.let { categories = it }; files = runCatching { client.files() }.getOrNull() }
        launch {
            recordLoaded = false
            record = runCatching { client.record() }.getOrNull()
            recordLoaded = record != null
            runCatching { loadLogo(record?.logoPath) }
        }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        val company = record
        if (uri == null) return@rememberLauncherForActivityResult
        if (!canManageCompany || company == null) { logoError = "Firma kaydı yüklenmeden logo eklenemez."; return@rememberLauncherForActivityResult }
        coroutines.launch {
            logoSaving = true; logoError = null
            try {
                val (jpeg, bitmap) = withContext(Dispatchers.IO) {
                    val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: error("empty")
                    val image = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: error("image")
                    java.io.ByteArrayOutputStream().also { image.compress(Bitmap.CompressFormat.JPEG, 90, it) }.toByteArray() to image
                }
                record = client.saveLogo(company, jpeg); recordLoaded = true; logo = bitmap
                celebrate("Firma logosu başarıyla eklendi!")
            } catch (_: Exception) { logoError = "Logo eklenemedi. Bağlantınızı kontrol edip tekrar deneyin." }
            logoSaving = false
        }
    }

    val shown = page
    if (shown != null) {
        val close: () -> Unit = { page = null; revision++ }
        BackHandler(onBack = close)
        when (shown) {
            NovaCompanyPage.Editor -> CompanyEditor(record, companyId, summary?.name ?: companyName, summary?.hazardClass ?: "medium", client.saveCompany,
                onClose = close) { saved ->
                record = saved; recordLoaded = true; celebrate("Firma bilgileri başarıyla güncellendi!"); close()
            }
            else -> open(shown, close)
        }
        return
    }

    val nonconformityRows = nonconformities?.filter { it.kind == NovaNonconformityRecordKind.nonconformity }
    val openFindings = nonconformityRows.orEmpty().count { it.state !in setOf("closed", "cancelled") }
    val accidentCategories = categories.filter { it.section == NovaCompanySection.accidents.name }.map { it.code }
    val accidentFiles = files?.counts(accidentCategories)?.values?.sum()
    val next = buildList {
        if (openFindings > 0) add(NextAction("nonconformities", "Açık uygunsuzlukları incele", "$openFindings kayıt takip bekliyor",
            "exclamationmark.triangle", NovaStatus.Danger, null))
        if (risk?.total == 0) add(NextAction("risk", "Risk değerlendirmesi oluştur", "Henüz değerlendirme kaydı yok", "checkmark.shield",
            NovaStatus.Warning, NovaCompanyPage.Module("risk", adding = true)))
        if (trackingSummary(tracking, "emergency_plan")?.total == 0) add(NextAction("emergency", "Acil durum planı oluştur",
            "Henüz yürürlükte bir plan yok", "light.beacon.max", NovaStatus.Warning, NovaCompanyPage.Module("emergency_plan", adding = true)))
        if (equipment?.total == 0) add(NextAction("equipment", "Ekipman ve kontrol takibini başlat", "Henüz ekipman kaydı yok",
            "wrench.and.screwdriver", NovaStatus.Warning, NovaCompanyPage.Module("equipment", adding = true, heading = NovaCompanySection.inspections.title)))
        if (summary?.personnelCount == 0) add(NextAction("personnel", "İlk personeli ekle", "Firma personeli bulunmuyor", "person.badge.plus",
            NovaStatus.Warning, NovaCompanyPage.Personnel))
        if (completedTrainings == 0) add(NextAction("training", "İlk eğitim kaydını oluştur", "Henüz gerçekleşen eğitim yok", "graduationcap",
            NovaStatus.Warning, NovaCompanyPage.Training))
    }
    fun openAction(action: NextAction) { if (action.page == null) onOpenFindings() else page = action.page }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset)
        .testTag("company.workspace"), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaPageHeading("Firma Detayı", onBack = onBack)
        BackHandler(onBack = onBack)
        // Overview: mark, name, hazard and people, plus the two figures that decide what to do next.
        NovaCard(Modifier.fillMaxWidth(), padding = 16) {
            Column(verticalArrangement = Arrangement.spacedBy(13.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    NovaCompanyMark(logo)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        NovaText(summary?.name ?: companyName, style = NovaTypeToken.cardTitle)
                        NovaText(listOfNotNull(summary?.hazardClass?.let(::companyHazardTitle),
                            summary?.let { "${it.personnelCount} personel" }).joinToString(" · "), style = NovaTypeToken.metaQuiet)
                    }
                    if (canManageCompany) Box(Modifier.size(44.dp).clip(CircleShape).novaRowPress { page = NovaCompanyPage.Editor }
                        .semantics { contentDescription = "Firmayı düzenle" }.testTag("company.edit"), contentAlignment = Alignment.Center) {
                        NovaIcon("pencil", 16.dp)
                    }
                }
                NovaMetricStrip(listOf(
                    NovaMetricStripItem("open", openFindings.toString(), "açık uygunsuzluk", "exclamationmark.triangle",
                        if (openFindings > 0) NovaStatus.Danger else NovaStatus.Success),
                    NovaMetricStripItem("next", next.size.toString(), "işlem gerekli", "checklist", if (next.isEmpty()) NovaStatus.Success else NovaStatus.Warning),
                ))
                if (summaryFailed) NovaButton("Özeti tekrar yükle", { revision++ }, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
            }
        }
        NovaCompanyReadinessCard(readiness(summary, record, recordLoaded, logo != null, completedTrainings, nonconformityRows, openFindings, risk,
            equipment, tracking))
        // The logo belongs to the company profile and stays visible even when another capability is unavailable.
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            NovaCard(Modifier.fillMaxWidth(), padding = 10) {
                Row(Modifier.heightIn(min = 52.dp), horizontalArrangement = Arrangement.spacedBy(11.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaCompanyMark(logo)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        NovaText(if (!record?.logoPath.isNullOrEmpty()) "Firma logosu" else "Logo ekleyin", style = NovaTypeToken.bodyStrong)
                        NovaText(if (logoSaving) "Logo yükleniyor…" else "Firma kartında ve raporlarda kullanılır.", style = NovaTypeToken.micro,
                            color = NovaColorToken.textMuted.color())
                    }
                    if (logoSaving) NovaSpinner(NovaColorToken.text.color(), size = 18.dp)
                    else NovaCompactActionButton(if (logo == null) "Logo seç" else "Değiştir", if (logo == null) "plus" else "arrow.triangle.2.circlepath",
                        Modifier.width(IntrinsicSize.Max),
                        enabled = canManageCompany && record != null, identifier = "company.logo.picker") {
                        picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }
                }
            }
            logoError?.let { NovaText(it, style = NovaTypeToken.micro, color = NovaColorToken.statusDangerInk.color()) }
        }
        NovaText("Sıradaki işler", style = NovaTypeToken.sectionTitle)
        if (next.isEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 14, tint = NovaColorToken.statusSuccessBg.color()) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("checkmark.circle.fill", 18.dp, tint = NovaColorToken.statusSuccessInk.color())
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText("Şu anda kritik iş görünmüyor", style = NovaTypeToken.bodyStrong)
                    NovaText("Kayıt kategorilerinden ayrıntıları inceleyebilirsiniz.", style = NovaTypeToken.metaQuiet)
                }
            }
        } else next.take(3).forEach { action ->
            NovaCard(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress { openAction(action) }.testTag("company.next.${action.id}"), padding = 13) {
                Row(Modifier.heightIn(min = 44.dp), horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                    Box(Modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(action.status.background.color()), contentAlignment = Alignment.Center) {
                        NovaIcon(action.symbol, 18.dp, tint = action.status.ink.color())
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        NovaText(action.title, style = NovaTypeToken.bodyStrong)
                        NovaText(action.detail, style = NovaTypeToken.metaQuiet)
                    }
                    NovaIcon("chevron.right", 11.dp, Modifier.padding(top = 5.dp))
                }
            }
        }
        val loading = "Yükleniyor…"
        fun status(section: NovaCompanySection): Pair<String, NovaStatus>? {
            if (section == NovaCompanySection.handover) return null
            sectionKind(section)?.let { kind ->
                trackingSummary(tracking, kind)?.let { row ->
                    return when {
                        row.overdue > 0 -> "Dikkat" to NovaStatus.Danger
                        row.upcoming > 0 -> "Yaklaşıyor" to NovaStatus.Warning
                        row.pending > 0 || row.review > 0 -> "Takip gerekli" to NovaStatus.Warning
                        row.total > 0 -> "Güncel" to NovaStatus.Success
                        else -> "Başlanmadı" to NovaStatus.Warning
                    }
                }
            }
            val board = risk
            if (section == NovaCompanySection.risk && board != null) return when {
                board.count(NovaRiskGroup.expired) > 0 -> "Dikkat" to NovaStatus.Danger
                board.count(NovaRiskGroup.dueSoon) > 0 -> "Yaklaşıyor" to NovaStatus.Warning
                board.count(NovaRiskGroup.untracked) > 0 -> "Takip gerekli" to NovaStatus.Warning
                board.total > 0 -> "Güncel" to NovaStatus.Success
                else -> "Başlanmadı" to NovaStatus.Warning
            }
            val inventory = equipment
            if (section == NovaCompanySection.inspections && inventory != null) return when {
                (inventory.counts[NovaEquipmentState.overdue] ?: 0) + (inventory.counts[NovaEquipmentState.failed] ?: 0) > 0 -> "Dikkat" to NovaStatus.Danger
                (inventory.counts[NovaEquipmentState.dueSoon] ?: 0) > 0 -> "Yaklaşıyor" to NovaStatus.Warning
                (inventory.counts[NovaEquipmentState.neverInspected] ?: 0) + (inventory.counts[NovaEquipmentState.periodUnknown] ?: 0) > 0 ->
                    "Takip gerekli" to NovaStatus.Warning
                inventory.total > 0 -> "Güncel" to NovaStatus.Success
                else -> "Başlanmadı" to NovaStatus.Warning
            }
            if (section == NovaCompanySection.training) completedTrainings?.let { return if (it > 0) "Güncel" to NovaStatus.Success else "Başlanmadı" to NovaStatus.Warning }
            if (section == NovaCompanySection.accidents) accidentFiles?.let { return if (it > 0) "Güncel" to NovaStatus.Success else "Başlanmadı" to NovaStatus.Warning }
            if (section == NovaCompanySection.personnel) summary?.let { return if (it.personnelCount > 0) "Güncel" to NovaStatus.Success else "Başlanmadı" to NovaStatus.Warning }
            return null
        }
        fun detail(section: NovaCompanySection): String = when {
            section == NovaCompanySection.handover -> "Düzenlenebilir Word örneği"
            section == NovaCompanySection.risk -> risk?.let { "${it.total} kayıt" } ?: loading
            section == NovaCompanySection.inspections -> equipment?.let { "${it.total} ekipman" } ?: loading
            section == NovaCompanySection.training -> completedTrainings?.let { "$it tamamlanan eğitim" } ?: loading
            sectionKind(section) != null && trackingSummary(tracking, sectionKind(section)!!) != null -> "${trackingSummary(tracking, sectionKind(section)!!)!!.total} kayıt"
            section == NovaCompanySection.accidents && accidentFiles != null -> "$accidentFiles dosya"
            else -> "Kayıtları görüntüle"
        }
        fun openSection(section: NovaCompanySection) {
            page = when (section) {
                NovaCompanySection.personnel -> NovaCompanyPage.Personnel
                NovaCompanySection.representative, NovaCompanySection.support -> NovaCompanyPage.Module("appointment")
                NovaCompanySection.risk -> NovaCompanyPage.Module("risk")
                NovaCompanySection.emergency, NovaCompanySection.board, NovaCompanySection.handover -> NovaCompanyPage.Module(sectionKind(section)!!)
                NovaCompanySection.inspections -> NovaCompanyPage.Module("equipment", heading = section.title)
                NovaCompanySection.accidents, NovaCompanySection.files -> NovaCompanyPage.Files(
                    categories.filter { it.section == section.name }.map { it.code }.ifEmpty { null }, section.title)
                NovaCompanySection.training -> NovaCompanyPage.Training
                NovaCompanySection.logo -> if (canManageCompany) NovaCompanyPage.Editor else null
            }
        }
        @Composable
        fun sectionRow(section: NovaCompanySection) = CompanyRow(section.title, detail(section), section.symbol, status(section),
            "company.section.${section.name}") { openSection(section) }
        @Composable
        fun directoryRow(kind: NovaDirectoryKind, symbol: String) = CompanyRow(kind.title, "Kayıtları görüntüle", symbol, null,
            "company.directory.${kind.name}") { page = NovaCompanyPage.Directory(kind) }
        fun appointmentDetail(board: NovaAppointmentBoard?) = board?.rows?.firstOrNull()?.employeeName ?: if (board == null) loading else "Henüz atama yok"

        CompanyCategory("Firma ve kadro") {
            CompanyRow("Firma bilgileri", summary?.sector ?: "Profil bilgileri", "building.2", if (recordLoaded) "Güncel" to NovaStatus.Success else null,
                "company.section.info", if (canManageCompany) ({ page = NovaCompanyPage.Editor }) else null)
            CompanyRow("Personel", "${summary?.personnelCount ?: 0} kişi", "person.2", status(NovaCompanySection.personnel),
                "company.section.personnel") { page = NovaCompanyPage.Personnel }
            directoryRow(NovaDirectoryKind.workplaces, "building")
            directoryRow(NovaDirectoryKind.departments, "square.grid.2x2")
            CompanyRow(NovaCompanySection.representative.title, appointmentDetail(representative), NovaCompanySection.representative.symbol,
                status(NovaCompanySection.representative), "company.section.representative") { page = NovaCompanyPage.Module("appointment") }
            CompanyRow(NovaCompanySection.support.title, appointmentDetail(support), NovaCompanySection.support.symbol,
                status(NovaCompanySection.support), "company.section.support") { page = NovaCompanyPage.Module("appointment") }
        }
        CompanyCategory("Risk ve acil durum") { sectionRow(NovaCompanySection.risk); sectionRow(NovaCompanySection.emergency) }
        CompanyCategory("Kontrol ve olaylar") {
            sectionRow(NovaCompanySection.inspections)
            CompanyRow("Uygunsuzluklar", "${nonconformityRows?.size ?: 0} kayıt", "exclamationmark.triangle",
                if (openFindings > 0) "Takip gerekli" to NovaStatus.Warning else "Güncel" to NovaStatus.Success, "company.section.nonconformities", onOpenFindings)
            sectionRow(NovaCompanySection.accidents)
        }
        CompanyCategory("Eğitim ve organizasyon") { sectionRow(NovaCompanySection.training); sectionRow(NovaCompanySection.board) }
        CompanyCategory("Diğer kayıtlar") {
            sectionRow(NovaCompanySection.files)
            directoryRow(NovaDirectoryKind.jobs, "briefcase")
            directoryRow(NovaDirectoryKind.contractors, "building.2")
        }
        CompanyCategory("Örnek formlar") { sectionRow(NovaCompanySection.handover) }
        if (!canWrite) NovaHelpHint("Salt okunur · kayıtlarınız korunuyor. Yeni kayıt ve düzenleme şu anda kullanılamıyor.")
    }
}

private fun readiness(summary: NovaCompanySummary?, record: Company?, recordLoaded: Boolean, hasLogo: Boolean, completedTrainings: Int?,
                      nonconformities: List<NovaNonconformityRow>?, openFindings: Int, risk: NovaRiskBoard?, equipment: NovaEquipmentBoard?,
                      tracking: NovaModuleTrackingSnapshot?): List<NovaCompanyReadinessItem> {
    val complete = NovaCompanyReadinessStatus.complete; val missing = NovaCompanyReadinessStatus.missing
    val review = NovaCompanyReadinessStatus.needsReview; val unknown = NovaCompanyReadinessStatus.unknown
    fun tracked(id: String, title: String, kind: String): NovaCompanyReadinessItem {
        val row = trackingSummary(tracking, kind)?.takeIf { it.available } ?: return NovaCompanyReadinessItem(id, title, "Durum bilgisi yükleniyor.", unknown)
        if (row.total == 0) return NovaCompanyReadinessItem(id, title, "Henüz kayıt yok.", missing)
        val attention = row.overdue + row.upcoming + row.review + row.pending
        return NovaCompanyReadinessItem(id, title, if (attention > 0) "$attention kayıt tarih veya durum kontrolü bekliyor." else "${row.total} kayıt güncel.",
            if (attention > 0) review else complete)
    }
    val companyKnown = recordLoaded || summary != null
    val responsible = listOf(record?.defaultResponsible, record?.contactPerson).mapNotNull { it?.trim() }.firstOrNull { it.isNotEmpty() }
    val logoStatus = if (!recordLoaded) unknown else if (!record?.logoPath.isNullOrEmpty() || hasLogo) complete else missing
    return listOf(
        NovaCompanyReadinessItem("company", "Firma Bilgileri", if (companyKnown) "Temel firma bilgileri kayıtlı." else "Firma bilgileri yükleniyor.",
            if (companyKnown) complete else unknown),
        when {
            risk == null -> NovaCompanyReadinessItem("risk", "Risk Analizi", "Risk durumu yükleniyor.", unknown)
            risk.total == 0 -> NovaCompanyReadinessItem("risk", "Risk Analizi", "Henüz kayıt yok.", missing)
            risk.needsAttention > 0 -> NovaCompanyReadinessItem("risk", "Risk Analizi", "${risk.needsAttention} kayıt tarih veya durum kontrolü bekliyor.", review)
            else -> NovaCompanyReadinessItem("risk", "Risk Analizi", "Risk analizi güncel.", complete)
        },
        tracked("emergency", "Acil Durum Planı", "emergency_plan"),
        NovaCompanyReadinessItem("training", "Eğitim", completedTrainings?.let { "$it tamamlanan eğitim kayıtlı." } ?: "Eğitim durumu yükleniyor.",
            completedTrainings?.let { if (it > 0) complete else missing } ?: unknown),
        NovaCompanyReadinessItem("personnel", "Personel", summary?.let { "${it.personnelCount} aktif personel kayıtlı." } ?: "Personel durumu yükleniyor.",
            summary?.let { if (it.personnelCount > 0) complete else missing } ?: unknown),
        when {
            nonconformities == null -> NovaCompanyReadinessItem("nonconformity", "Uygunsuzluk", "Uygunsuzluk durumu yükleniyor.", unknown)
            nonconformities.isEmpty() -> NovaCompanyReadinessItem("nonconformity", "Uygunsuzluk", "Henüz kayıt yok.", missing)
            openFindings > 0 -> NovaCompanyReadinessItem("nonconformity", "Uygunsuzluk", "$openFindings açık kayıt takip bekliyor.", review)
            else -> NovaCompanyReadinessItem("nonconformity", "Uygunsuzluk", "Tüm uygunsuzluk kayıtları kapalı.", complete)
        },
        when {
            equipment == null -> NovaCompanyReadinessItem("equipment", "Periyodik Kontrol", "Kontrol durumu yükleniyor.", unknown)
            equipment.total == 0 -> NovaCompanyReadinessItem("equipment", "Periyodik Kontrol", "Henüz ekipman kaydı yok.", missing)
            else -> {
                val attention = equipment.count(NovaEquipmentGroup.overdue) + equipment.count(NovaEquipmentGroup.failed) +
                    equipment.count(NovaEquipmentGroup.untracked) + equipment.count(NovaEquipmentGroup.dueSoon)
                NovaCompanyReadinessItem("equipment", "Periyodik Kontrol",
                    if (attention > 0) "$attention kayıt tarih veya durum kontrolü bekliyor." else "Periyodik kontroller güncel.", if (attention > 0) review else complete)
            }
        },
        NovaCompanyReadinessItem("logo", "Logo", if (logoStatus == complete) "Firma logosu kayıtlı." else "Firma logosu eklenmemiş.", logoStatus),
        NovaCompanyReadinessItem("responsible", "Sorumlu Kişi",
            responsible ?: if (recordLoaded) "Sorumlu kişi tanımlanmamış." else "Sorumlu kişi yükleniyor.",
            if (responsible != null) complete else if (recordLoaded) missing else unknown),
        tracked("visits", "Ziyaretler", "site_visit"),
    )
}

@Composable
internal fun NovaCompanyMark(logo: Bitmap?) {
    Box(Modifier.size(42.dp).clip(RoundedCornerShape(11.dp)).background(NovaColorToken.surfaceMuted.color())
        .border(if (logo != null) 1.dp else 0.dp, NovaColorToken.border.color(), RoundedCornerShape(11.dp)), contentAlignment = Alignment.Center) {
        if (logo != null) Image(logo.asImageBitmap(), "Firma logosu", Modifier.fillMaxSize().padding(5.dp), contentScale = ContentScale.Fit)
        else NovaIcon("building.2", 22.dp)
    }
}

@Composable
private fun CompanyCategory(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        NovaText(title, style = NovaTypeToken.sectionTitle)
        NovaCard(Modifier.fillMaxWidth(), padding = 0, content = content)
    }
}

@Composable
private fun CompanyRow(title: String, detail: String, symbol: String, status: Pair<String, NovaStatus>?, identifier: String, action: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().heightIn(min = 58.dp).novaRowPress(enabled = action != null) { action?.invoke() }.testTag(identifier)
        .padding(horizontal = 13.dp), horizontalArrangement = Arrangement.spacedBy(11.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 17.dp, Modifier.width(28.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            NovaText(title, style = NovaTypeToken.bodyStrong)
            NovaText(detail, style = NovaTypeToken.metaQuiet)
        }
        status?.let { NovaStatusPill(it.first, it.second) }
        if (action != null) NovaIcon("chevron.right", 11.dp)
    }
}

/** Firma Bilgilerini Güncelle (iOS `NovaCompanyLiveEditor`): writes through the company record. */
@Composable
private fun CompanyEditor(company: Company?, fallbackId: String, fallbackName: String, fallbackHazard: String, save: suspend (CompanyDraft) -> Company,
                          onClose: () -> Unit, onSaved: (Company) -> Unit) {
    val coroutines = rememberCoroutineScope()
    var draft by remember {
        mutableStateOf(CompanyDraft(id = company?.id ?: fallbackId, name = company?.name ?: fallbackName,
            hazardClass = company?.hazardClass ?: CompanyHazardClass.entries.firstOrNull { it.id == fallbackHazard } ?: CompanyHazardClass.Medium,
            logoPath = company?.logoPath, address = company?.address.orEmpty(), contactPerson = company?.contactPerson.orEmpty(),
            department = company?.department.orEmpty(), defaultResponsible = company?.defaultResponsible.orEmpty(),
            defaultDueDaysText = company?.defaultDueDays?.toString().orEmpty()))
    }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPageHeading("Firma Bilgilerini Güncelle", backEnabled = !saving, onBack = onClose)
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                NovaTextField("Firma adı", draft.name, { draft = draft.copy(name = it) }, identifier = "company.editor.name")
                NovaText("Tehlike sınıfı", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
                NovaSegmentedControl(CompanyHazardClass.entries.map { companyHazardTitle(it.id) }, CompanyHazardClass.entries.indexOf(draft.hazardClass)) {
                    draft = draft.copy(hazardClass = CompanyHazardClass.entries[it])
                }
                NovaTextField("Adres", draft.address, { draft = draft.copy(address = it) }, identifier = "company.editor.address")
                NovaTextField("İlgili kişi", draft.contactPerson, { draft = draft.copy(contactPerson = it) }, identifier = "company.editor.contact")
                NovaTextField("Departman / ekip", draft.department, { draft = draft.copy(department = it) }, identifier = "company.editor.department")
            }
        }
        error?.let { NovaHelpHint(it) }
        NovaButton(if (saving) "Kaydediliyor…" else "Kaydet", {
            coroutines.launch {
                saving = true; error = null
                try { onSaved(save(draft)) } catch (failure: Exception) { error = failure.message ?: "Firma kaydedilemedi."; saving = false }
            }
        }, Modifier.fillMaxWidth().testTag("company.editor.save"), enabled = !saving && draft.isValid, loading = saving, symbol = "checkmark")
    }
}
