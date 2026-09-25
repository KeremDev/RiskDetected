package com.riskdetectedan.feature.nova

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** The module's calls bound to one identity (iOS `NovaRiskClient`); the design preview supplies its own. */
interface NovaRiskClient {
    val companies: suspend () -> List<NovaCompanyOption>
    val files: NovaFileClient
    suspend fun catalogue(company: String?): NovaRiskCatalogue
    suspend fun board(query: NovaRiskQuery): NovaRiskBoard
    suspend fun detail(id: String): NovaRiskRow
    suspend fun open(company: String, workplace: String?): NovaRiskRow?
    suspend fun draft(company: String, draft: NovaRiskVersionDraft): NovaRiskRow?
    suspend fun finalize(company: String, draft: NovaRiskFinalizeDraft): NovaRiskRow?
    suspend fun cancelDraft(company: String, row: NovaRiskRow, version: NovaRiskVersion, reason: String): NovaRiskRow?
}

class NovaServiceRiskClient(private val service: NovaRiskService, private val identity: IsgWorkspaceIdentity,
                            override val companies: suspend () -> List<NovaCompanyOption>, override val files: NovaFileClient) : NovaRiskClient {
    override suspend fun catalogue(company: String?) = service.catalogue(identity, company)
    override suspend fun board(query: NovaRiskQuery) = service.board(identity, query)
    override suspend fun detail(id: String) = service.detail(identity, id)
    override suspend fun open(company: String, workplace: String?) = service.open(identity, company, workplace)
    override suspend fun draft(company: String, draft: NovaRiskVersionDraft) = service.draft(identity, company, draft)
    override suspend fun finalize(company: String, draft: NovaRiskFinalizeDraft) = service.finalize(identity, company, draft)
    override suspend fun cancelDraft(company: String, row: NovaRiskRow, version: NovaRiskVersion, reason: String) =
        service.cancelDraft(identity, company, row, version, reason)
}

internal fun riskMessage(error: Throwable) = (error as? NovaRiskException)?.failure?.message ?: NovaRiskFailure.unavailable.message

@Composable
private fun NovaRiskGroup.statusInk() = when (this) {
    NovaRiskGroup.expired -> NovaColorToken.statusDangerInk.color()
    NovaRiskGroup.untracked -> NovaColorToken.statusNeutralInk.color()
    NovaRiskGroup.dueSoon -> NovaColorToken.statusWarningInk.color()
    NovaRiskGroup.current -> NovaColorToken.statusSuccessInk.color()
}

@Composable
private fun NovaRiskGroup.statusDot() = when (this) {
    NovaRiskGroup.expired -> NovaColorToken.statusDangerDot.color()
    NovaRiskGroup.untracked -> NovaColorToken.statusNeutralDot.color()
    NovaRiskGroup.dueSoon -> NovaColorToken.statusWarningDot.color()
    NovaRiskGroup.current -> NovaColorToken.statusSuccessDot.color()
}

@Composable
private fun RiskStatCard(group: NovaRiskGroup, value: Int, modifier: Modifier = Modifier,
                         selected: Boolean = false, onClick: () -> Unit) {
    val tone = when (group) {
        NovaRiskGroup.expired -> NovaStatus.Danger
        NovaRiskGroup.untracked -> NovaStatus.Neutral
        NovaRiskGroup.dueSoon -> NovaStatus.Warning
        NovaRiskGroup.current -> NovaStatus.Success
    }
    NovaListStat(group.title, group.symbol, value, modifier, selected, tone, onClick)
}

@Composable
private fun RiskFilterButton(label: String, value: String, identifier: String, modifier: Modifier = Modifier,
                             open: Boolean = false, selected: Boolean = false, onClick: () -> Unit) {
    val shape = RoundedCornerShape(13.dp)
    Row(modifier.heightIn(min = 44.dp).clip(shape).novaControlBackground(13.dp)
        .border(1.dp, if (selected || open) Color(0xFF0B2F53).copy(alpha = if (selected) 0.62f else 0.42f) else NovaColorToken.border.color(), shape)
        .novaRowPress(onClick = onClick).testTag(identifier)
        .semantics { contentDescription = "$label: $value"; stateDescription = value }
        .padding(horizontal = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaSizedText(value, 12f, if (selected) FontWeight.SemiBold else FontWeight.Medium,
            if (selected) Color(0xFF0B2F53) else NovaColorToken.text.color(), Modifier.weight(1f), maxLines = 1)
        NovaIcon(if (open) "chevron.up" else "chevron.down", 12.dp, tint = NovaColorToken.textTertiary.color())
    }
}

/** One workplace's record as a row; the state and its reason come from the server. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RiskRowCard(row: NovaRiskRow, modifier: Modifier, onClick: () -> Unit) {
    NovaCard(modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).novaRowPress(onClick = onClick).testTag("nova.risk.row.${row.id}"), padding = 14) {
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(row.companyName ?: row.workplaceName ?: "İşyeri", style = NovaTypeToken.cardTitle)
                    val workplace = row.workplaceName
                    if (workplace != null && novaFold(workplace) != novaFold(row.companyName.orEmpty())) NovaText(workplace, style = NovaTypeToken.metaQuiet)
                }
                Box(Modifier.size(8.dp).background(row.group.statusDot(), CircleShape)
                    .semantics { contentDescription = row.state.title })
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                val metadata = listOfNotNull(row.validUntil?.let { NovaDay.label(it) }, row.periodYears?.let { "$it yıl" },
                    row.currentVersion.takeIf { it > 0 }?.let { "v$it" })
                metadata.forEachIndexed { index, item ->
                    if (index > 0) NovaText("·", style = NovaTypeToken.metaQuiet)
                    NovaText(item, style = NovaTypeToken.metaQuiet, maxLines = 1)
                }
                Spacer(Modifier.weight(1f))
                NovaIcon("chevron.right", 12.dp, tint = NovaColorToken.textSubtle.color())
            }
            // Everything that needs the expert's eye, never folded into the state pill.
            if (row.hasOpenDraft || row.sourceDrift || row.dateNeedsReview) FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (row.hasOpenDraft) NovaTag("pencil.line", "Açık taslak var", NovaStatus.Info)
                if (row.sourceDrift) NovaTag("arrow.triangle.branch", "Kaynak analiz değişti", NovaStatus.Warning)
                if (row.dateNeedsReview) NovaTag("calendar.badge.exclamationmark", "Tarih çok eski · gözden geçirin", NovaStatus.Warning)
            }
        }
    }
}

@Composable
private fun RiskFact(symbol: String, label: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 11.dp, tint = NovaColorToken.textMuted.color())
        Column {
            NovaSizedText(label, 9f, FontWeight.Medium, NovaColorToken.textMuted.color())
            NovaSizedText(value, 11f, FontWeight.Bold)
        }
    }
}

/** Risk Değerlendirmesi: the whole account in one read, narrowed to a company on request. */
@Composable
fun NovaRiskScreen(client: NovaRiskClient, canWrite: Boolean, onBack: () -> Unit, initialCompany: String? = null,
                   headingOverride: String? = null, startInAddMode: Boolean = false, initialRecordId: String? = null,
                   /** Opened from a home suggestion: the wizard first, the list behind it. */
                   startWithWizard: Boolean = false) {
    if (startInAddMode) { RiskAddFlow(client, initialCompany, onBack); return }
    var showingWizard by remember { mutableStateOf(startWithWizard) }
    val coroutines = rememberCoroutineScope()
    var board by remember { mutableStateOf<NovaRiskBoard?>(null) }
    var catalogue by remember { mutableStateOf<NovaRiskCatalogue?>(null) }
    var companies by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var query by remember { mutableStateOf(NovaRiskQuery(company = initialCompany)) }
    var loading by remember { mutableStateOf(true) }
    var failure by remember { mutableStateOf<String?>(null) }
    var chooser by remember { mutableStateOf<String?>(null) }
    var showingPeriodInfo by remember { mutableStateOf(false) }
    var sortAscending by remember { mutableStateOf(true) }
    var detail by remember { mutableStateOf<NovaRiskRow?>(null) }
    var newVersion by remember { mutableStateOf<NovaRiskVersionDraft?>(null) }
    var cancelling by remember { mutableStateOf<NovaRiskRow?>(null) }
    var finalizing by remember { mutableStateOf<NovaRiskFinalizeDraft?>(null) }
    var creating by remember { mutableStateOf(false) }
    val headerContext = LocalNovaHeaderContext.current
    DisposableEffect(headerContext?.current) {
        if (headerContext?.current == NovaDestination.riskAssessments) headerContext.setPageBackAction(onBack)
        onDispose {
            if (headerContext?.current == NovaDestination.riskAssessments) headerContext.setPageBackAction(null)
        }
    }
    if (showingWizard) {
        NovaRiskWizardScreen(client.companies,
            { company -> client.catalogue(company).workplaces.map { NovaWizardWorkplace(it.id, it.name) } },
            { client.files }, query.company ?: initialCompany) { showingWizard = false }
        return
    }

    suspend fun load(reset: Boolean) {
        query = if (reset) query.copy(offset = 0) else query.copy(offset = query.offset + query.limit)
        loading = true; failure = null
        try {
            if (companies.isEmpty()) companies = client.companies()
            catalogue = client.catalogue(query.company)
            val answer = client.board(query)
            board = if (reset || board == null) answer else board!!.copy(rows = board!!.rows + answer.rows, counts = answer.counts,
                companies = answer.companies, total = answer.total, hasMore = answer.hasMore, offset = answer.offset)
            headerContext?.setPageSummary(NovaHeaderSummary(headingOverride ?: NovaDestination.riskAssessments.title,
                answer.total, answer.count(NovaRiskGroup.dueSoon)))
        } catch (error: Exception) { failure = riskMessage(error) }
        loading = false
    }
    fun reload() = coroutines.launch { load(true) }
    LaunchedEffect(Unit) { load(true) }
    LaunchedEffect(initialRecordId) {
        if (initialRecordId != null) detail = runCatching { client.detail(initialRecordId) }.getOrNull()
    }
    if (creating) { RiskAddFlow(client, null) { creating = false; reload() }; return }
    val companyOf: (String?) -> String? = { assessment -> query.company ?: board?.rows?.firstOrNull { it.id == assessment }?.companyId }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (headerContext?.current != NovaDestination.riskAssessments) NovaBackButton(onClick = onBack)
        if (canWrite) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaListActionButton("Kayıt Ekle", "plus", Modifier.weight(0.4f), identifier = "nova.risk.create") { creating = true }
            NovaListActionButton("Sihirbaz ile Oluştur", "sparkles", Modifier.weight(0.6f), discovery = true, identifier = "nova.risk.wizard") {
                showingWizard = true
            }
        }
        NovaListHint("Geçerlilik süresi kayıt bazında belirlenir.", actionTitle = "Detay",
            onAction = { showingPeriodInfo = true })
        board?.let { current ->
            val columns = if (novaFontScaleIsAccessibility()) 2 else 4
            NovaRiskGroup.entries.chunked(columns).forEach { chunk ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    chunk.forEach { group ->
                        RiskStatCard(group, current.count(group), Modifier.weight(1f).testTag("nova.risk.stat.${group.wire}"),
                            selected = query.state == group.wire) {
                            query = query.copy(state = if (query.state == group.wire) null else group.wire); reload()
                        }
                    }
                }
            }
        }
        NovaSearchCapsule(query.search, "Firma veya işyeri ara", "nova.risk.search") { query = query.copy(search = it) }
        LaunchedEffect(query.search) { if (board != null) { kotlinx.coroutines.delay(350); load(true) } }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            RiskFilterButton("Firma", companies.firstOrNull { it.id == query.company }?.name ?: "Tüm firmalar", "nova.risk.chooser.company",
                Modifier.weight(1f), open = chooser == "company") { chooser = if (chooser == "company") null else "company" }
            val stateTitle = query.state?.let { value -> NovaRiskGroup.ofWire(value)?.title ?: NovaRiskState.of(value)?.title } ?: "Tüm durumlar"
            RiskFilterButton("Durum", stateTitle, "nova.risk.chooser.state", Modifier.weight(1f),
                open = chooser == "state", selected = query.state != null) {
                chooser = if (chooser == "state") null else "state"
            }
            Row(Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(13.dp))
                .novaControlBackground(13.dp).border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(13.dp))
                .novaRowPress { sortAscending = !sortAscending }.testTag("nova.risk.sort")
                .semantics { contentDescription = "Geçerlilik tarihine göre sırala"; stateDescription = if (sortAscending) "En eski önce" else "En yeni önce" }
                .padding(horizontal = 9.dp), horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("arrow.up.arrow.down", 12.dp, tint = NovaColorToken.textSecondary.color())
                NovaSizedText("Sırala", 12f, FontWeight.Medium, NovaColorToken.textSecondary.color(), maxLines = 1)
            }
        }
        if (chooser == "company") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm firmalar")) + companies.map { NovaChooserOption(it.id, it.name) },
            query.company, "nova.risk.panel.company") { query = query.copy(company = it); chooser = null; reload() }
        if (chooser == "state") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm durumlar")) +
            NovaRiskGroup.entries.map { NovaChooserOption(it.wire, it.title, board?.count(it), it.symbol) } +
            NovaRiskState.entries.filter { state -> NovaRiskGroup.entries.none { it.wire == state.wire } }
                .map { NovaChooserOption(it.wire, it.title, board?.counts?.get(it.wire)) }, query.state, "nova.risk.panel.state") {
            query = query.copy(state = it); chooser = null; reload()
        }
        val current = board
        when {
            loading && current == null -> Box(Modifier.fillMaxWidth().padding(vertical = 30.dp), contentAlignment = Alignment.Center) {
                NovaSpinner(NovaColorToken.text.color(), size = 24.dp)
            }
            failure != null -> NovaCard(Modifier.fillMaxWidth(), padding = 16) { NovaText(failure!!, color = NovaColorToken.statusDangerInk.color()) }
            current != null -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                NovaListSectionHeading("Risk Değerlendirmeleri", "${current.total} kayıt")
                if (current.rows.isEmpty()) NovaEmptyState("Henüz risk değerlendirmesi kaydı yok",
                    "Risk değerlendirmesi ekleyerek sürümleri, geçerlilik tarihini ve bağlı dosyayı tek yerden takip edebilirsiniz.")
                else NovaListEntrance(current.rows.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        val sortedRows = current.rows.sortedWith { left, right ->
                            val leftDate = left.validUntil
                            val rightDate = right.validUntil
                            when {
                                leftDate == null && rightDate == null -> (left.companyName ?: left.workplaceName.orEmpty()).compareTo(right.companyName ?: right.workplaceName.orEmpty())
                                leftDate == null -> 1
                                rightDate == null -> -1
                                sortAscending -> leftDate.compareTo(rightDate)
                                else -> rightDate.compareTo(leftDate)
                            }
                        }
                        sortedRows.forEachIndexed { index, row ->
                            RiskRowCard(row, Modifier.novaRowEntrance(index)) {
                                coroutines.launch { detail = runCatching { client.detail(row.id) }.getOrDefault(row) }
                            }
                        }
                        if (current.hasMore) NovaButton("Daha fazla göster", { coroutines.launch { load(false) } }, variant = NovaButtonVariant.Surface,
                            symbol = "chevron.down")
                    }
                }
            }
        }
    }
    val openRow = detail
    NovaPopup(openRow != null, { detail = null }, identifier = "nova.risk.detail") {
        if (openRow != null) RiskDetail(openRow, canWrite,
            onNewVersion = {
                detail = null
                newVersion = NovaRiskVersionDraft(openRow.id, NovaRiskKind.full, NovaDay.today(), expectedCurrent = openRow.currentVersion)
            },
            onEdit = { version ->
                detail = null
                newVersion = NovaRiskVersionDraft(openRow.id, version.kind, version.assessmentOn, version.revisionOn.orEmpty(), version.scope,
                    version.reason.orEmpty(), openRow.currentVersion, version.version, version.editRevision)
            },
            onCancelDraft = { detail = null; cancelling = openRow },
            onFinalize = { version ->
                detail = null
                val suggested = openRow.workplaceSuggestedPeriodYears
                finalizing = NovaRiskFinalizeDraft(openRow.id, version, openRow.currentVersion, periodYears = suggested?.toString().orEmpty(),
                    kind = openRow.draftKind ?: NovaRiskKind.full, editRevision = openRow.versions.firstOrNull { it.version == version }?.editRevision ?: 0,
                    suggestedYears = suggested)
            })
    }
    val versionDraft = newVersion
    NovaPopup(versionDraft != null, { newVersion = null }, identifier = "nova.risk.version.sheet") {
        if (versionDraft != null) RiskVersionSheet(versionDraft, onClose = { newVersion = null }) { edited ->
            val company = companyOf(edited.assessmentId) ?: return@RiskVersionSheet NovaRiskFailure.validation.message
            try { client.draft(company, edited); newVersion = null; load(true); null } catch (error: Exception) { riskMessage(error) }
        }
    }
    val cancelRow = cancelling
    NovaPopup(cancelRow != null, { cancelling = null }) {
        if (cancelRow != null) RiskCancelDraft { reason ->
            val company = cancelRow.companyId
            val version = cancelRow.versions.firstOrNull { it.isDraft }
            if (company == null || version == null) return@RiskCancelDraft NovaRiskFailure.validation.message
            try { client.cancelDraft(company, cancelRow, version, reason); cancelling = null; load(true); null } catch (error: Exception) { riskMessage(error) }
        }
    }
    val finalizeDraft = finalizing
    NovaPopup(finalizeDraft != null, { finalizing = null }, identifier = "nova.risk.finalize.sheet") {
        if (finalizeDraft != null) RiskFinalizeSheet(finalizeDraft, catalogue, onClose = { finalizing = null }) { edited ->
            val company = companyOf(edited.assessmentId) ?: return@RiskFinalizeSheet NovaRiskFailure.validation.message
            try { client.finalize(company, edited); finalizing = null; load(true); null } catch (error: Exception) { riskMessage(error) }
        }
    }
    NovaPopup(showingPeriodInfo, { showingPeriodInfo = false }, identifier = "nova.risk.period.info") {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            NovaPopupHeading("Geçerlilik süresi", "info.circle")
            NovaText("Geçerlilik süresi her kayıt için ayrı belirlenir. Uzmanın belirlediği süre mevzuat gereği sabit bir süre olarak sunulmaz. Süre kaynağını ve tarihi kaydın detayında görebilirsiniz.",
                style = NovaTypeToken.body, color = NovaColorToken.textSecondary.color())
            NovaButton("Anladım", { showingPeriodInfo = false }, variant = NovaButtonVariant.Primary)
        }
    }
}

/** One workplace's whole record: the document that stands, what is open on it, every version behind it. */
@Composable
private fun RiskDetail(row: NovaRiskRow, canWrite: Boolean, onNewVersion: () -> Unit, onEdit: (NovaRiskVersion) -> Unit,
                       onCancelDraft: () -> Unit, onFinalize: (Int) -> Unit) {
    val unset = "Belirtilmedi"
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            NovaPopupHeading(row.workplaceName ?: "İşyeri", symbol = "checkmark.shield")
            row.companyName?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color()) }
            NovaText(row.explain, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    RiskCell("calendar", "Değerlendirme tarihi", row.currentAssessmentOn?.let(NovaDay::label) ?: unset, Modifier.weight(1f))
                    RiskCell("calendar.badge.clock", "Geçerlilik", row.validUntil?.let(NovaDay::label) ?: unset, Modifier.weight(1f))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    RiskCell("clock.arrow.circlepath", "Süre", row.periodYears?.let { "$it yıl" } ?: unset, Modifier.weight(1f), row.periodSource?.title.orEmpty())
                    RiskCell("number", "Yürürlükteki sürüm", if (row.currentVersion > 0) "v${row.currentVersion}" else unset, Modifier.weight(1f),
                        row.currentKind?.title.orEmpty())
                }
                NovaHelpHint(NovaRiskWords.periodAttribution)
                if (row.sourceDrift) NovaHelpHint(row.driftNote ?: "Kaynak analiz bu belge hazırlandıktan sonra değişti. Belge değiştirilmedi.")
            }
        }
        if (row.hasOpenDraft) NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                NovaText("Açık taslak", style = NovaTypeToken.cardTitle)
                NovaText("${row.draftKind?.title.orEmpty()} · v${row.draftVersion ?: 0}", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                row.draftReason?.takeIf { it.isNotEmpty() }?.let { NovaText(it) }
                NovaText("Taslak belge değildir. Tamamlanana kadar yürürlükteki sürüm değişmez.", style = NovaTypeToken.meta,
                    color = NovaColorToken.textSecondary.color())
                val version = row.draftVersion
                if (canWrite && version != null) {
                    row.versions.firstOrNull { it.version == version }?.let { draft ->
                        NovaButton("Taslağı düzenle", { onEdit(draft) }, variant = NovaButtonVariant.Surface, symbol = "pencil")
                    }
                    NovaButton("Taslağı iptal et", onCancelDraft, variant = NovaButtonVariant.Surface, symbol = "xmark")
                    NovaButton("Taslağı tamamla", { onFinalize(version) }, symbol = "checkmark.seal")
                }
            }
        }
        if (canWrite) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!row.hasOpenDraft) NovaButton("Yeni sürüm başlat", onNewVersion, symbol = "plus.circle")
            NovaText(NovaRiskWords.analysisNotAssessment, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaText("Sürüm geçmişi", style = NovaTypeToken.cardTitle)
            if (row.versions.isEmpty()) NovaText("Henüz sürüm yok.", style = NovaTypeToken.meta, color = NovaColorToken.textMuted.color())
            row.versions.forEach { version ->
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            NovaText("v${version.version} · ${version.kind.title}", Modifier.weight(1f), NovaTypeToken.cardTitle)
                            NovaStatusPill(when (version.state) { "cancelled" -> "İptal edildi"; "draft" -> "Taslak"; "final" -> "Yürürlükte"; else -> "Geçmiş" },
                                if (version.isFinal) NovaStatus.Success else if (version.isDraft) NovaStatus.Info else NovaStatus.Neutral)
                        }
                        NovaText(version.kind.explain, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            NovaSizedText("Değerlendirme tarihi: ${NovaDay.label(version.assessmentOn)}", 10.5f, FontWeight.Medium)
                            version.validUntil?.let { NovaSizedText("Geçerlilik: ${NovaDay.label(it)}", 10.5f, FontWeight.Medium) }
                        }
                        version.reason?.takeIf { it.isNotEmpty() }?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color()) }
                        version.cancellationNote?.takeIf { it.isNotEmpty() }?.let { NovaText("İptal gerekçesi: $it") }
                        if (version.scope.isNotEmpty()) NovaText("Kapsam: ${version.scope.joinToString(", ")}", style = NovaTypeToken.meta,
                            color = NovaColorToken.textSecondary.color())
                        if (version.sources.isNotEmpty()) NovaTag("arrow.down.doc", "${version.sources.size} analiz bulgusu aktarıldı", NovaStatus.Info)
                        version.impacts.forEach { NovaTag("arrow.triangle.branch", "${it.targetRef} · ${it.actionTitle}", NovaStatus.Warning) }
                        version.periodSource?.let {
                            NovaTag(if (it.needsReview) "exclamationmark.circle" else "checkmark.seal", it.title,
                                if (it.needsReview) NovaStatus.Warning else NovaStatus.Success)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RiskCell(symbol: String, label: String, value: String, modifier: Modifier, detail: String = "") {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        NovaIcon(symbol, 12.dp, Modifier.padding(top = 2.dp), tint = NovaColorToken.textMuted.color())
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            NovaSizedText(label, 9f, FontWeight.Medium, NovaColorToken.textMuted.color())
            NovaSizedText(value, 12f, FontWeight.Bold)
            if (detail.isNotEmpty()) NovaSizedText(detail, 9.5f, FontWeight.Medium, NovaColorToken.textSecondary.color())
        }
    }
}

@Composable
private fun ScopeField(scope: List<String>, onChange: (List<String>) -> Unit, identifier: String) {
    var entry by remember { mutableStateOf("") }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
            NovaTextField("Kapsam", entry, { entry = it }, Modifier.weight(1f), identifier = "$identifier.entry", placeholder = "Bölüm adı")
            NovaButton("Ekle", {
                val value = entry.trim()
                if (value.isNotEmpty() && scope.size < 50) { onChange(scope + value); entry = "" }
            }, variant = NovaButtonVariant.Surface, symbol = "plus", compact = true)
        }
        scope.forEach { item ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                NovaTag("square.dashed", item, NovaStatus.Info)
                Box(Modifier.size(32.dp).novaRowPress { onChange(scope - item) }.semantics { contentDescription = "Kaldır" },
                    contentAlignment = Alignment.Center) { NovaIcon("xmark.circle", 13.dp) }
            }
        }
    }
}

/** A years input inside a value row (iOS number-pad TextField + "yıl"). */
@Composable
private fun YearsRow(value: String, onChange: (String) -> Unit, identifier: String, symbol: String = "clock") {
    NovaFormValueRow("Geçerlilik süresi", symbol) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            val ink = NovaColorToken.text.color()
            BasicTextField(value, { onChange(it.filter(Char::isDigit).take(2)) }, Modifier.width(46.dp).testTag(identifier)
                .semantics { contentDescription = "Geçerlilik süresi, yıl" }, singleLine = true,
                textStyle = novaTextStyle(NovaTypeToken.body).copy(color = ink, textAlign = TextAlign.End),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), cursorBrush = SolidColor(ink))
            NovaText("yıl", style = NovaTypeToken.meta)
        }
    }
}

/** Opening a new version; the kind is chosen first because it decides which dates may be asked for. */
@Composable
private fun RiskVersionSheet(initial: NovaRiskVersionDraft, onClose: () -> Unit, onSave: suspend (NovaRiskVersionDraft) -> String?) {
    var draft by remember { mutableStateOf(initial) }
    var failure by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val busy = LocalNovaPopupBusy.current
    val coroutines = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPopupHeading(if (draft.versionToEdit != null) "Taslağı düzenle" else "Yeni sürüm", symbol = "checkmark.shield")
        // A rescan is never offered; it is listed only so an edited rescan still shows its kind.
        NovaChoiceField("Sürüm türü", "Sürüm türü seçin", "checkmark.shield",
            NovaRiskKind.entries.filter { it != NovaRiskKind.rescan || it == draft.kind }.map { NovaChoiceOption(it, it.title, it.explain) }, draft.kind,
            { value -> value?.let { draft = draft.copy(kind = it) } }, "nova.risk.version.kind", enabled = draft.versionToEdit == null, boxed = true)
        NovaHelpHint(draft.kind.explain)
        if (draft.kind.carriesAssessmentDate) NovaDayField("Değerlendirme tarihi", draft.assessmentOn, { draft = draft.copy(assessmentOn = it) }, "nova.risk.version.assessed")
        else NovaHelpHint("Bu tür, belgenin özgün değerlendirme tarihini korur.")
        NovaDayField("Revizyon tarihi", draft.revisionOn, { draft = draft.copy(revisionOn = it) }, "nova.risk.version.revised", clearable = true)
        if (draft.kind.needsScope) ScopeField(draft.scope, { draft = draft.copy(scope = it) }, "nova.risk.version.scope")
        if (draft.kind.needsReason) NovaTextField("Gerekçe", draft.reason, { draft = draft.copy(reason = it) }, identifier = "nova.risk.version.reason", multiline = true)
        failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaButton("Vazgeç", onClose, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "xmark")
            NovaButton("Taslağı aç", { coroutines.launch { saving = true; busy(true); failure = onSave(draft); saving = false; busy(false) } },
                Modifier.weight(1f), symbol = "checkmark", enabled = !saving, loading = saving)
        }
    }
}

/** Making a version the document that stands; only a renewal asks for a period. */
@Composable
private fun RiskFinalizeSheet(initial: NovaRiskFinalizeDraft, catalogue: NovaRiskCatalogue?, onClose: () -> Unit,
                              onSave: suspend (NovaRiskFinalizeDraft) -> String?) {
    var draft by remember { mutableStateOf(initial) }
    var failure by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    val busy = LocalNovaPopupBusy.current
    val coroutines = rememberCoroutineScope()
    val expertOption = "Kendi belirlediğim süre"
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPopupHeading("Sürümü tamamla", symbol = "checkmark.shield")
        NovaHelpHint("Tamamlanan sürüm yürürlüğe girer ve bir daha değiştirilemez. Doğrulama sizin beyanınızdır.")
        if (draft.kind == NovaRiskKind.full) {
            val rules = catalogue?.rules.orEmpty()
            when {
                rules.isNotEmpty() -> {
                    NovaChoiceField("Süre kaynağı", "Süre kaynağı seçin", "hourglass", rules.map { NovaChoiceOption(it.ruleCode, it.ruleCode) },
                        draft.ruleCode.ifEmpty { null }, { draft = draft.copy(ruleCode = it.orEmpty()) }, "nova.risk.finalize.rule",
                        noneTitle = expertOption, boxed = true)
                }
                draft.suggestedYears != null -> NovaHelpHint("İşyerinin tehlike sınıfına göre ${draft.suggestedYears} yıl otomatik dolduruldu. Gerekirse değiştirebilirsiniz.")
                else -> NovaHelpHint("Onaylanmış bir süre kataloğu yok. Gireceğiniz süre \"uzman tarafından belirlenen\" olarak kaydedilir.")
            }
            if (draft.ruleCode.isEmpty()) YearsRow(draft.periodYears, { draft = draft.copy(periodYears = it) }, "nova.risk.finalize.years")
        } else NovaHelpHint("Bu revizyon mevcut değerlendirme tarihini ve süre kaynağını korur.")
        failure?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            NovaButton("Vazgeç", onClose, Modifier.weight(1f), variant = NovaButtonVariant.Surface, symbol = "xmark")
            NovaButton("Tamamla", { coroutines.launch { saving = true; busy(true); failure = onSave(draft); saving = false; busy(false) } },
                Modifier.weight(1f), symbol = "checkmark.seal", enabled = !saving, loading = saving)
        }
    }
}

@Composable
private fun RiskCancelDraft(onConfirm: suspend (String) -> String?) {
    var reason by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    val busyReporter = LocalNovaPopupBusy.current
    val coroutines = rememberCoroutineScope()
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPopupHeading("Taslağı iptal et", symbol = "checkmark.shield")
        NovaText("Taslak geçmişte korunur. Yürürlükteki sürüm ve tarihleri değişmez.")
        NovaTextField("İptal gerekçesi (en az 10 karakter)", reason, { reason = it }, multiline = true)
        failure?.let { NovaText(it, style = NovaTypeToken.meta) }
        NovaButton("Taslağı iptal et", {
            coroutines.launch { busy = true; busyReporter(true); failure = onConfirm(reason.trim()); busy = false; busyReporter(false) }
        }, symbol = "xmark", enabled = !busy && reason.trim().length >= 10, loading = busy)
    }
}

private enum class RiskStep(val title: String) { details("Tarih ve geçerlilik"), file("Dosya"), review("Kontrol ve kaydet") }

/** Guided creation: company, then a three-step task with sticky actions (iOS `NovaRiskQuickCreateSheet`). */
@Composable
private fun RiskAddFlow(client: NovaRiskClient, fixedCompany: String?, onClose: () -> Unit) {
    NovaCompanyCreateFlow("Risk değerlendirmesi ekle", client.companies, { company -> client.catalogue(company) }, fixedCompany, onClose) { catalogue, company ->
        RiskQuickCreate(client, company, catalogue, onClose)
    }
}

@Composable
private fun RiskQuickCreate(client: NovaRiskClient, company: String, catalogue: NovaRiskCatalogue, onClose: () -> Unit) {
    val coroutines = rememberCoroutineScope()
    val workplaces = catalogue.workplaces
    var workplaceId by remember { mutableStateOf(workplaces.singleOrNull()?.id) }
    var row by remember { mutableStateOf<NovaRiskRow?>(null) }
    var opening by remember { mutableStateOf(false) }
    var openError by remember { mutableStateOf<String?>(null) }
    var kindChosen by remember { mutableStateOf(false) }
    var kind by remember { mutableStateOf(NovaRiskKind.full) }
    var assessmentOn by remember { mutableStateOf(NovaDay.today()) }
    var periodYears by remember { mutableStateOf("") }
    var scope by remember { mutableStateOf<List<String>>(emptyList()) }
    var reason by remember { mutableStateOf("") }
    var assetId by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    var saveError by remember { mutableStateOf<String?>(null) }
    var step by remember { mutableStateOf(RiskStep.details) }
    var didSave by remember { mutableStateOf(false) }
    var confirmingExit by remember { mutableStateOf(false) }
    val suggested = workplaces.firstOrNull { it.id == workplaceId }?.suggestedPeriodYears
    val hasOpenDraft = row?.hasOpenDraft ?: false
    fun primeSuggested() { if (periodYears.isEmpty()) periodYears = (suggested ?: 1).toString() }
    val detailsReady = (workplaces.isEmpty() || workplaceId != null) && row != null && kindChosen &&
        !(kind == NovaRiskKind.full && (periodYears.toIntOrNull() ?: 0) <= 0) &&
        !(kind.needsScope && scope.isEmpty()) && !(kind.needsReason && reason.isBlank())
    val validUntil = run {
        val years = periodYears.toIntOrNull()
        val date = NovaDay.parse(assessmentOn)
        if (kind == NovaRiskKind.full && years != null && years > 0 && date != null) NovaDay.label(date.plusYears(years.toLong()).toString())
        else null
    }
    val validity = validUntil ?: "Geçerlilik bilgisi daha sonra kesinleştirilecek"
    LaunchedEffect(workplaceId) {
        if (workplaces.isNotEmpty() && workplaceId == null) return@LaunchedEffect
        opening = true; openError = null
        try {
            val opened = client.open(company, workplaceId)
            row = opened
            val draft = opened?.versions?.firstOrNull { it.isDraft }
            if (draft != null) { kind = draft.kind; assessmentOn = draft.assessmentOn; scope = draft.scope; reason = draft.reason.orEmpty(); kindChosen = true }
            else if ((opened?.currentVersion ?: 0) == 0) { kind = NovaRiskKind.full; primeSuggested(); kindChosen = true }
        } catch (error: Exception) { openError = riskMessage(error) }
        opening = false
    }
    suspend fun save() {
        val current = row ?: return
        saving = true; saveError = null
        try {
            var afterDraft: NovaRiskRow = current
            if (!hasOpenDraft) {
                afterDraft = client.draft(company, NovaRiskVersionDraft(current.id, kind, if (kind.carriesAssessmentDate) assessmentOn else "",
                    scope = scope, reason = reason, expectedCurrent = current.currentVersion, fileAssetId = assetId.ifEmpty { null }))
                    ?: throw NovaRiskException(NovaRiskFailure.unavailable)
            }
            val draftVersion = afterDraft.versions.firstOrNull { it.isDraft } ?: throw NovaRiskException(NovaRiskFailure.unavailable)
            client.finalize(company, NovaRiskFinalizeDraft(current.id, draftVersion.version, afterDraft.currentVersion,
                periodYears = if (draftVersion.kind == NovaRiskKind.full) periodYears else "", kind = draftVersion.kind,
                editRevision = draftVersion.editRevision))
            didSave = true
        } catch (error: Exception) { saveError = riskMessage(error) }
        saving = false
    }
    if (didSave) {
        NovaTaskSuccessView("Risk değerlendirmesi kaydedildi",
            if (validUntil != null) "Kayıt $validUntil tarihine kadar geçerli olarak oluşturuldu. Firma detayından sürümleri ve dosyayı takip edebilirsiniz."
            else "Kayıt oluşturuldu. Geçerlilik tarihi daha sonra kesinleşecek; firma detayından sürümleri ve dosyayı takip edebilirsiniz.",
            "Risk değerlendirmelerine dön", onClose)
        return
    }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 18.dp).padding(top = 8.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)) {
            NovaTaskHeader("Risk değerlendirmesi ekle", step.ordinal + 1, RiskStep.entries.size, step.title) { confirmingExit = true }
            openError?.let { NovaTaskErrorSummary(it) }
            saveError?.let { NovaTaskErrorSummary(it) }
            when {
                workplaces.size > 1 && workplaceId == null -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaText("İşyeri seçin", style = NovaTypeToken.cardTitle)
                    workplaces.forEach { place ->
                        NovaPopupOption(place.name, "building.2", identifier = "risk.quick.workplace.${place.id.lowercase()}") { workplaceId = place.id }
                    }
                }
                opening || row == null -> NovaLoadingView("İşyeri ve risk sürümü hazırlanıyor…", Modifier.heightIn(max = 240.dp))
                else -> AnimatedContent(step, transitionSpec = { fadeIn(NovaMotion.easeInOut(0.2)) togetherWith fadeOut(NovaMotion.easeInOut(0.2)) },
                    label = "riskStep") { current ->
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        when (current) {
                            RiskStep.details -> when {
                                (row?.currentVersion ?: 0) > 0 && !hasOpenDraft && !kindChosen -> {
                                    NovaText("Bu işyerinde kayıtlı bir değerlendirme var.", style = NovaTypeToken.metaQuiet)
                                    NovaPopupOption("Yeni değerlendirme", "doc.badge.plus", "Yeni dönem için kayıt oluşturun.",
                                        identifier = "risk.quick.kind.new") { kind = NovaRiskKind.full; primeSuggested(); kindChosen = true }
                                    NovaPopupOption("Revize et", "square.and.pencil", "Mevcut değerlendirmeyi güncelleyin.",
                                        identifier = "risk.quick.kind.revise") { kind = NovaRiskKind.partial; kindChosen = true }
                                }
                                else -> {
                                    if (kind.carriesAssessmentDate) NovaDayField("Değerlendirme tarihi", assessmentOn, { assessmentOn = it }, "risk.quick.date")
                                    else NovaFormValueRow("Değerlendirme tarihi", "calendar") { NovaText("İlk değerlendirme tarihi korunur", style = NovaTypeToken.bodyStrong) }
                                    if (kind == NovaRiskKind.full) {
                                        YearsRow(periodYears, { periodYears = it }, "risk.quick.years", "calendar.badge.clock")
                                        NovaHelpHint("İşyerinin tehlike sınıfına göre otomatik dolduruldu. Gerekirse değiştirebilirsiniz. Geçerlilik: $validity")
                                    }
                                    if (kind.needsScope) ScopeField(scope, { scope = it }, "risk.quick.scope")
                                    if (kind.needsReason) NovaTextField("Değişiklik gerekçesi", reason, { reason = it }, identifier = "risk.quick.reason", multiline = true)
                                    if (hasOpenDraft) NovaHelpHint("Bu işyerinde açık bir taslak var. Bilgileri kontrol ederek tamamlayabilirsiniz.")
                                }
                            }
                            RiskStep.file -> {
                                NovaText("Dosya", style = NovaTypeToken.sectionTitle)
                                NovaInlineFileField("risk_assessment", company, client.files, assetId, { assetId = it })
                                NovaHelpHint("Dosya eklemek zorunlu değil; değerlendirmeyi şimdi kaydedip belgeyi daha sonra bağlayabilirsiniz.")
                            }
                            RiskStep.review -> {
                                NovaText("Kontrol et", style = NovaTypeToken.sectionTitle)
                                NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                                        ReviewRow("İşyeri", workplaces.firstOrNull { it.id == workplaceId }?.name ?: "Belirtilmedi")
                                        ReviewRow("Değerlendirme", if (kind.carriesAssessmentDate) NovaDay.label(assessmentOn) else "İlk tarih korunuyor")
                                        ReviewRow("Geçerlilik", validity)
                                        if (scope.isNotEmpty()) ReviewRow("Kapsam", scope.joinToString(", "))
                                        ReviewRow("Dosya", if (assetId.isEmpty()) "Daha sonra eklenebilir" else "Dosya eklendi")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        if (!opening && row != null) NovaTaskStickyActions(
            if (step == RiskStep.review) "Kaydet" else "Devam", onBack = {
                saveError = null
                if (step.ordinal > 0) step = RiskStep.entries[step.ordinal - 1]
            }, onPrimary = {
                saveError = null
                when {
                    step == RiskStep.review -> coroutines.launch { save() }
                    step == RiskStep.details && !detailsReady -> saveError = "İşyeri, değerlendirme türü ve gerekli kapsam bilgilerini kontrol edin."
                    else -> step = RiskStep.entries[step.ordinal + 1]
                }
            }, primarySymbol = if (step == RiskStep.review) "checkmark" else "arrow.right", working = saving, canGoBack = step != RiskStep.details,
            modifier = Modifier.navigationBarsPadding().padding(bottom = novaTabBarClearance))
    }
    NovaPopup(confirmingExit, { confirmingExit = false }) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            NovaPopupHeading("Risk değerlendirmesi akışından çıkılsın mı?", symbol = "exclamationmark.triangle")
            NovaText("Henüz kaydedilmemiş bilgiler silinir.")
            NovaButton("Çık", { confirmingExit = false; onClose() }, variant = NovaButtonVariant.Danger)
            NovaButton("Devam et", { confirmingExit = false }, variant = NovaButtonVariant.Surface)
        }
    }
}

@Composable
internal fun ReviewRow(label: String, value: String) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        NovaText(label, style = NovaTypeToken.metaQuiet)
        NovaText(value, style = NovaTypeToken.bodyStrong)
    }
}
