package com.riskdetectedan.feature.profile

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.isg.IsgWorkspaceContext
import com.riskdetectedan.core.data.isg.IsgWorkspaceDomain
import com.riskdetectedan.core.data.isg.IsgWorkspacePersonnelAdvancedKind
import com.riskdetectedan.core.data.isg.IsgWorkspaceTrainingAdvancedKind
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.serialization.json.*
import java.util.Locale

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun OsgbWorkspaceScreen(
    onBack: () -> Unit,
    viewModel: OsgbWorkspaceViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val handleBack = { if (!viewModel.back()) onBack() }
    BackHandler(onBack = handleBack)
    NovaTheme {
        NovaPageSurface {
            Column(Modifier.fillMaxSize()) {
                OsgbHeader(titleFor(state), handleBack) {
                    when (val page = state.page) {
                        OsgbWorkspacePage.Workspaces -> viewModel.refreshWorkspaces()
                        OsgbWorkspacePage.Companies -> viewModel.refreshCompanies()
                        OsgbWorkspacePage.Company -> state.company?.let(viewModel::selectCompany)
                        is OsgbWorkspacePage.Domain -> viewModel.openDomain(page.domain)
                        is OsgbWorkspacePage.PersonnelAdvanced -> viewModel.openPersonnelAdvanced(page.kind)
                        is OsgbWorkspacePage.TrainingAdvanced -> viewModel.openTrainingAdvanced(page.kind)
                        OsgbWorkspacePage.Analyses -> viewModel.openAnalyses()
                    }
                }
                Box(Modifier.weight(1f)) {
                    when (state.page) {
                        OsgbWorkspacePage.Workspaces -> WorkspaceList(state.workspaces, viewModel::selectWorkspace)
                        OsgbWorkspacePage.Companies -> CompanyList(state, viewModel::selectCompany)
                        OsgbWorkspacePage.Company -> CompanyHub(state, viewModel)
                        is OsgbWorkspacePage.Domain,
                        is OsgbWorkspacePage.PersonnelAdvanced,
                        is OsgbWorkspacePage.TrainingAdvanced -> RecordList(state, viewModel::selectRow)
                        OsgbWorkspacePage.Analyses -> RecordList(state, viewModel::openAnalysis)
                    }
                    if (state.loading) CircularProgressIndicator(Modifier.align(Alignment.Center))
                }
            }
            state.selectedRow?.let { row ->
                androidx.compose.material3.ModalBottomSheet(onDismissRequest = { viewModel.selectRow(null) }) {
                    if (state.page == OsgbWorkspacePage.Analyses && row["analysis"] is JsonObject) {
                        AnalysisDetail(row, state.notice, { viewModel.createExport("pdf") },
                            { viewModel.createExport("xlsx") }) { viewModel.selectRow(null) }
                    } else RecordDetail(row) { viewModel.selectRow(null) }
                }
            }
        }
    }
}

@Composable
private fun OsgbHeader(title: String, onBack: () -> Unit, onRefresh: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        IconButton(onClick = onBack) { NovaGlyph(Icons.Outlined.ChevronLeft, "Geri") }
        Column(Modifier.weight(1f)) {
            NovaText(title, style = NovaTypeToken.screenTitle)
            NovaText("OSGB çalışma alanı", style = NovaTypeToken.metaQuiet)
        }
        IconButton(onClick = onRefresh) { NovaGlyph(Icons.Outlined.Refresh, "Yenile") }
    }
}

@Composable
private fun WorkspaceList(workspaces: List<IsgWorkspaceContext>, onSelect: (IsgWorkspaceContext) -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (workspaces.isEmpty()) EmptyState("OSGB çalışma alanı bulunamadı.",
            "Bireysel hesabınız ve mevcut firma kayıtlarınız değişmeden kullanılmaya devam eder.")
        workspaces.forEach { workspace ->
            ActionCard(workspace.name, "${workspace.membership.role.roleLabel()} · ${workspace.status.statusLabel()}",
                Icons.Outlined.Domain) { onSelect(workspace) }
        }
    }
}

@Composable
private fun CompanyList(state: OsgbWorkspaceUiState, onSelect: (OsgbCompanyItem) -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        state.error?.let { ErrorCard(it) }
        DashboardMetrics(state.dashboard)
        if (!state.loading && state.companies.isEmpty()) EmptyState("Atanmış firma yok.",
            "OSGB yöneticisi firma ataması yaptığında kayıtlar burada görünür.")
        state.companies.forEach { company ->
            ActionCard(company.name, company.hazardClass.hazardLabel(), Icons.Outlined.Business) { onSelect(company) }
        }
    }
}

@Composable
private fun CompanyHub(state: OsgbWorkspaceUiState, viewModel: OsgbWorkspaceViewModel) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
        .padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        state.error?.let { ErrorCard(it) }
        DashboardMetrics(state.dashboard)
        NovaText("Operasyonlar", style = NovaTypeToken.sectionTitle)
        domainSpecs.forEach { spec ->
            ActionCard(spec.title, spec.subtitle, spec.icon) { viewModel.openDomain(spec.domain) }
        }
        NovaText("Personel ve eğitim gelişmiş kayıtları", style = NovaTypeToken.sectionTitle)
        IsgWorkspacePersonnelAdvancedKind.entries.forEach { kind ->
            ActionCard(kind.personnelTitle(), "Görev, dış firma ve atama geçmişi", Icons.Outlined.Badge) {
                viewModel.openPersonnelAdvanced(kind)
            }
        }
        IsgWorkspaceTrainingAdvancedKind.entries.forEach { kind ->
            ActionCard(kind.trainingTitle(), "Müfredat, plan, sınav ve sertifika", Icons.Outlined.School) {
                viewModel.openTrainingAdvanced(kind)
            }
        }
        NovaText("Analiz ve raporlama", style = NovaTypeToken.sectionTitle)
        ActionCard("Analizler ve raporlar", "Risk bulguları, uzman görüşü ve dışa aktarımlar",
            Icons.Outlined.Analytics) { viewModel.openAnalyses() }
    }
}

@Composable
private fun RecordList(state: OsgbWorkspaceUiState, onSelect: (JsonObject) -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
        .padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        state.error?.let { ErrorCard(it) }
        MetricStrip(state.metrics)
        if (!state.loading && state.rows.isEmpty()) EmptyState("Henüz kayıt yok.",
            "İlgili kayıt oluşturulduğunda tenant kapsamı korunarak burada listelenir.")
        state.rows.forEach { row ->
            val title = rowTitle(row)
            val detail = rowDetail(row)
            ActionCard(title, detail, iconFor(state.page)) { onSelect(row) }
        }
    }
}

@Composable
private fun DashboardMetrics(payload: JsonObject?) {
    if (payload == null) return
    val metrics = numericLeaves(payload).filterNot { it.first in setOf("schema_version", "version") }.take(6)
    if (metrics.isEmpty()) return
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        metrics.forEach { (label, value) -> MetricCard(value, label.labelize()) }
    }
}

@Composable
private fun MetricStrip(payload: JsonObject?) {
    if (payload == null) return
    val metrics = numericLeaves(payload).filterNot { it.first in setOf("schema_version", "version") }.take(5)
    if (metrics.isEmpty()) return
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        metrics.forEach { (label, value) -> MetricCard(value, label.labelize()) }
    }
}

@Composable
private fun MetricCard(value: String, label: String) {
    NovaCard(Modifier.width(112.dp).heightIn(min = 86.dp), padding = 12) {
        NovaText(value, style = NovaTypeToken.screenTitle)
        NovaText(label, Modifier.padding(top = 4.dp), NovaTypeToken.metaQuiet)
    }
}

@Composable
private fun ActionCard(title: String, detail: String, icon: ImageVector, onClick: () -> Unit) {
    NovaCard(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick), padding = 14) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            NovaGlyph(icon, null, Modifier.size(22.dp))
            Column(Modifier.weight(1f)) {
                NovaText(title, style = NovaTypeToken.cardTitle)
                NovaText(detail, Modifier.padding(top = 3.dp), NovaTypeToken.metaQuiet)
            }
            NovaGlyph(Icons.Outlined.ChevronRight, null, Modifier.size(18.dp))
        }
    }
}

@Composable
private fun EmptyState(title: String, message: String) {
    NovaCard(Modifier.fillMaxWidth(), padding = 18) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
            NovaGlyph(Icons.Outlined.Lightbulb, null, Modifier.size(20.dp))
            Column(Modifier.weight(1f)) {
                NovaText(title, style = NovaTypeToken.cardTitle)
                NovaText(message, Modifier.padding(top = 6.dp), NovaTypeToken.metaQuiet)
            }
        }
    }
}

@Composable
private fun ErrorCard(message: String) {
    NovaCard(Modifier.fillMaxWidth(), padding = 14) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaGlyph(Icons.Outlined.ErrorOutline, null, Modifier.size(20.dp))
            NovaText(message, Modifier.weight(1f), NovaTypeToken.body)
        }
    }
}

@Composable
private fun RecordDetail(row: JsonObject, onClose: () -> Unit) {
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
        .padding(bottom = 36.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            NovaText(rowTitle(row), Modifier.weight(1f), NovaTypeToken.sheetTitle)
            IconButton(onClick = onClose) { NovaGlyph(Icons.Outlined.Close, "Kapat") }
        }
        row.entries.filterNot { it.value is JsonNull || it.key.endsWith("_id") || it.key == "id" }
            .take(24).forEach { (key, value) ->
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    NovaText(key.labelize(), style = NovaTypeToken.meta)
                    NovaText(value.displayValue(), Modifier.padding(top = 4.dp), NovaTypeToken.body)
                }
            }
        NovaButton("Kapat", onClose, variant = NovaButtonVariant.Muted)
    }
}

@Composable
private fun AnalysisDetail(row: JsonObject, notice: String?, onPdf: () -> Unit,
                           onXlsx: () -> Unit, onClose: () -> Unit) {
    val analysis = row["analysis"]?.jsonObject ?: return
    val counts = row["counts"]?.jsonObject
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp)
        .padding(bottom = 36.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                NovaText(analysis["title"]?.jsonPrimitive?.contentOrNull ?: "Analiz", style = NovaTypeToken.sheetTitle)
                NovaText("Risk, uzman görüşü ve eğitim önerileri", style = NovaTypeToken.metaQuiet)
            }
            IconButton(onClick = onClose) { NovaGlyph(Icons.Outlined.Close, "Kapat") }
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("risk" to "Risk", "expert" to "Uzman görüşü", "training" to "Eğitim").forEach { (key, label) ->
                MetricCard(counts?.get(key)?.jsonPrimitive?.contentOrNull ?: "0", label)
            }
        }
        notice?.let { EmptyState("Rapor sıraya alındı", it) }
        NovaButton("PDF raporu hazırla", onPdf)
        NovaButton("Excel raporu hazırla", onXlsx, variant = NovaButtonVariant.Muted)
        NovaButton("Kapat", onClose, variant = NovaButtonVariant.Muted)
    }
}

private data class DomainSpec(val domain: IsgWorkspaceDomain, val title: String,
                              val subtitle: String, val icon: ImageVector)

private val domainSpecs = listOf(
    DomainSpec(IsgWorkspaceDomain.PERSONNEL, "Personel", "Çalışanlar ve organizasyon", Icons.Outlined.PeopleOutline),
    DomainSpec(IsgWorkspaceDomain.TRAINING, "Eğitimler", "Katılım ve eğitim kayıtları", Icons.Outlined.School),
    DomainSpec(IsgWorkspaceDomain.RISK, "Risk değerlendirmeleri", "Risk analizleri ve geçerlilik", Icons.Outlined.WarningAmber),
    DomainSpec(IsgWorkspaceDomain.NONCONFORMITY, "Uygunsuzluklar", "Aksiyon ve termin takibi", Icons.Outlined.FactCheck),
    DomainSpec(IsgWorkspaceDomain.CHECKLIST, "Kontrol listeleri", "Saha kontrol kayıtları", Icons.Outlined.Checklist),
    DomainSpec(IsgWorkspaceDomain.EMERGENCY_PLAN, "Acil durum planları", "Plan ve ekip kayıtları", Icons.Outlined.HealthAndSafety),
    DomainSpec(IsgWorkspaceDomain.DRILL, "Tatbikatlar", "Tatbikat planı ve sonuçları", Icons.Outlined.Campaign),
    DomainSpec(IsgWorkspaceDomain.APPOINTMENT, "Atamalar", "Uzman ve hekim atamaları", Icons.Outlined.AssignmentInd),
    DomainSpec(IsgWorkspaceDomain.PPE, "KKD teslimleri", "İmzalı teslim kayıtları", Icons.Outlined.Inventory2),
    DomainSpec(IsgWorkspaceDomain.EQUIPMENT, "Periyodik kontroller", "Ekipman ve kontrol tarihleri", Icons.Outlined.Build),
    DomainSpec(IsgWorkspaceDomain.KATIP, "İSG-KATİP sözleşmeleri", "Sözleşme ve süre takibi", Icons.Outlined.Description),
    DomainSpec(IsgWorkspaceDomain.ANNUAL_PLAN, "Yıllık çalışma planı", "Plan ve gerçekleşmeler", Icons.Outlined.CalendarMonth),
    DomainSpec(IsgWorkspaceDomain.BOARD, "İSG kurulu", "Toplantı ve kararlar", Icons.Outlined.Groups),
    DomainSpec(IsgWorkspaceDomain.WORK_PERMIT, "Çalışma izinleri", "İzin formu kayıtları", Icons.Outlined.Approval),
    DomainSpec(IsgWorkspaceDomain.VISIT, "Saha ziyaretleri", "Ziyaret notları ve bulgular", Icons.Outlined.LocationOn),
    DomainSpec(IsgWorkspaceDomain.FILES, "Dosyalar", "Tenant kapsamlı belge arşivi", Icons.Outlined.FolderOpen),
)

private fun titleFor(state: OsgbWorkspaceUiState): String = when (val page = state.page) {
    OsgbWorkspacePage.Workspaces -> "Çalışma Alanları"
    OsgbWorkspacePage.Companies -> state.workspace?.name ?: "Firmalar"
    OsgbWorkspacePage.Company -> state.company?.name ?: "Firma"
    is OsgbWorkspacePage.Domain -> domainSpecs.first { it.domain == page.domain }.title
    is OsgbWorkspacePage.PersonnelAdvanced -> page.kind.personnelTitle()
    is OsgbWorkspacePage.TrainingAdvanced -> page.kind.trainingTitle()
    OsgbWorkspacePage.Analyses -> "Analizler ve Raporlar"
}

private fun iconFor(page: OsgbWorkspacePage): ImageVector = when (page) {
    is OsgbWorkspacePage.Domain -> domainSpecs.first { it.domain == page.domain }.icon
    is OsgbWorkspacePage.PersonnelAdvanced -> Icons.Outlined.Badge
    is OsgbWorkspacePage.TrainingAdvanced -> Icons.Outlined.School
    OsgbWorkspacePage.Analyses -> Icons.Outlined.Analytics
    else -> Icons.Outlined.Description
}

private fun IsgWorkspacePersonnelAdvancedKind.personnelTitle() = when (this) {
    IsgWorkspacePersonnelAdvancedKind.JOB_ROLES -> "Görev ve unvanlar"
    IsgWorkspacePersonnelAdvancedKind.CONTRACTORS -> "Dış firmalar"
    IsgWorkspacePersonnelAdvancedKind.ENGAGEMENTS -> "Çalışma ilişkileri"
    IsgWorkspacePersonnelAdvancedKind.ASSIGNMENTS -> "Personel atamaları"
}

private fun IsgWorkspaceTrainingAdvancedKind.trainingTitle() = when (this) {
    IsgWorkspaceTrainingAdvancedKind.CURRICULA -> "Eğitim müfredatları"
    IsgWorkspaceTrainingAdvancedKind.ANNUAL_PLANS -> "Yıllık eğitim planları"
    IsgWorkspaceTrainingAdvancedKind.ANNUAL_ITEMS -> "Plan kalemleri"
    IsgWorkspaceTrainingAdvancedKind.ATTEMPTS -> "Sınav denemeleri"
    IsgWorkspaceTrainingAdvancedKind.CERTIFICATES -> "Sertifikalar"
}

private fun String.roleLabel() = when (this) { "owner" -> "Sahip"; "admin" -> "Yönetici"; else -> "Uzman" }
private fun String.statusLabel() = when (this) { "active" -> "Aktif"; "pending_purchase" -> "Satın alma bekliyor"; "suspended" -> "Askıda"; else -> this.labelize() }
private fun String.hazardLabel() = when (this) { "low" -> "Az tehlikeli"; "medium" -> "Tehlikeli"; "high" -> "Çok tehlikeli"; else -> this }

private fun rowTitle(row: JsonObject): String = listOf("name", "full_name", "title", "code", "item",
    "notebook_ref", "kind", "state").firstNotNullOfOrNull { key ->
    row[key]?.jsonPrimitive?.takeIf { it.isString }?.content?.takeIf(String::isNotBlank)
} ?: "Kayıt"

private fun rowDetail(row: JsonObject): String = listOf("status", "state", "role", "hazard_class",
    "held_on", "planned_on", "opened_on", "created_at").firstNotNullOfOrNull { key ->
    row[key]?.jsonPrimitive?.contentOrNull?.let { "${key.labelize()}: $it" }
} ?: "Detayları görüntüle"

private fun numericLeaves(root: JsonObject): List<Pair<String, String>> {
    val result = mutableListOf<Pair<String, String>>()
    fun visit(prefix: String, element: JsonElement) {
        when (element) {
            is JsonObject -> element.forEach { (key, value) -> visit(if (prefix.isEmpty()) key else "$prefix · $key", value) }
            is JsonPrimitive -> if (!element.isString && element.longOrNull != null) result += prefix to element.content
            else -> Unit
        }
    }
    visit("", root)
    return result
}

private fun String.labelize(): String = replace('_', ' ').split(' ').joinToString(" ") { word ->
    word.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.forLanguageTag("tr-TR")) else it.toString() }
}

private fun JsonElement.displayValue(): String = when (this) {
    is JsonPrimitive -> content
    is JsonArray -> joinToString(" · ") { it.displayValue() }.take(500)
    is JsonObject -> entries.joinToString(" · ") { (key, value) -> "${key.labelize()}: ${value.displayValue()}" }.take(500)
    JsonNull -> "—"
}
