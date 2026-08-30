package com.riskdetectedan.app.reports

import android.content.ClipData
import android.content.Intent
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.data.reports.Report
import com.riskdetectedan.core.designsystem.R as RdR
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRiskChip
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.riskLevelFromRaw
import com.riskdetectedan.core.designsystem.toTextStyle
import com.riskdetectedan.feature.reports.HistoryUiState
import com.riskdetectedan.feature.reports.HistoryViewModel
import com.riskdetectedan.feature.reports.ReportPreviewUiState
import java.io.File
import java.time.OffsetDateTime
import java.time.temporal.WeekFields
import java.text.Normalizer
import java.util.Locale

private val Report.isExcel: Boolean
    get() = format == "xlsx" || mimeType == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

private val Report.isRiskAnalysis: Boolean
    get() = kind == "risk_analysis" || kind == "riskAnalysis"

private enum class ReportArchiveFilter(@StringRes val labelRes: Int) {
    All(RdR.string.rd_tumu),
    Pdf(RdR.string.rd_pdf_label),
    Excel(RdR.string.rd_excel_label),
    Standard(RdR.string.rd_standart),
    RiskAnalysis(RdR.string.rd_risk_analizi),
    ThisWeek(RdR.string.rd_bu_hafta),
}

private enum class ReportKind { Standard, RiskAnalysis }
private enum class ReportFormat { Pdf, Excel }
private enum class ReportMethod(val wire: String, @StringRes val titleRes: Int) {
    FineKinney("fine_kinney", RdR.string.rd_fine_kinney),
    Matrix5x5("matrix_5x5", RdR.string.rd_bes_carp_bes_matris),
}

private fun isSameIsoWeek(createdAt: String?): Boolean {
    val raw = createdAt ?: return false
    return try {
        val date = OffsetDateTime.parse(raw)
        val now = OffsetDateTime.now()
        val weekFields = WeekFields.of(Locale.getDefault())
        date.get(weekFields.weekBasedYear()) == now.get(weekFields.weekBasedYear()) &&
            date.get(weekFields.weekOfWeekBasedYear()) == now.get(weekFields.weekOfWeekBasedYear())
    } catch (_: Throwable) {
        false
    }
}

private fun matchesReportFilter(report: Report, filter: ReportArchiveFilter): Boolean = when (filter) {
    ReportArchiveFilter.All -> true
    ReportArchiveFilter.Pdf -> !report.isExcel
    ReportArchiveFilter.Excel -> report.isExcel
    ReportArchiveFilter.Standard -> !report.isExcel && !report.isRiskAnalysis
    ReportArchiveFilter.RiskAnalysis -> report.isRiskAnalysis || report.isExcel
    ReportArchiveFilter.ThisWeek -> isSameIsoWeek(report.createdAt)
}

private fun reportSearchText(report: Report): String = listOfNotNull(
    report.title,
    report.fileName,
    report.kind,
    report.method,
    report.format,
    report.mimeType,
    report.createdAt,
).joinToString(" ").let(::normalizeReportSearch)

private fun normalizeReportSearch(value: String): String = Normalizer
    .normalize(value.trim().lowercase(Locale.getDefault()).replace('ı', 'i'), Normalizer.Form.NFD)
    .replace(Regex("\\p{Mn}+"), "")

/**
 * Android port of iOS build-81 `ReportView`: overview, Plus value card, collapsible archive and
 * analysis-source selector live in one tab. Analizler no longer owns report-generation buttons.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GeneratedReportsScreen(
    focusedReportId: String? = null,
    onUpgrade: (entryPoint: String) -> Unit = {},
    embeddedInMainShell: Boolean = false,
    viewModel: GeneratedReportsViewModel = hiltViewModel(),
    historyViewModel: HistoryViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val historyState by historyViewModel.state.collectAsState()
    val userTier by historyViewModel.userTier.collectAsState()
    val profile by historyViewModel.profile.collectAsState()
    val reportPreview by historyViewModel.reportPreview.collectAsState()
    val reportQuotaUsage by historyViewModel.reportQuotaUsage.collectAsState()
    val companies by historyViewModel.companies.collectAsState()
    val openingId by viewModel.openingReportId.collectAsState()
    val reportError by viewModel.reportError.collectAsState()
    val reportFile by viewModel.reportFile.collectAsState()
    val deletingReportId by viewModel.deletingReportId.collectAsState()
    val deleteError by viewModel.deleteError.collectAsState()
    val generatedFile by historyViewModel.reportFile.collectAsState()
    val generationError by historyViewModel.reportError.collectAsState()
    val generatingExcelId by historyViewModel.generatingReportForId.collectAsState()
    val generatingPdfId by historyViewModel.generatingPdfForId.collectAsState()
    var reportPendingDelete by remember { mutableStateOf<Report?>(null) }
    var selectedAnalysis by remember { mutableStateOf<HistoryItem?>(null) }
    var search by remember { mutableStateOf("") }
    var activeFilter by remember { mutableStateOf(ReportArchiveFilter.All) }
    var archiveExpanded by remember { mutableStateOf(focusedReportId != null) }
    var analysesExpanded by remember { mutableStateOf(false) }
    var selectedArchiveCompany by remember { mutableStateOf<Company?>(null) }
    var showArchiveCompanyFilter by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val openChooserTitle = stringResource(RdR.string.rd_raporu_ac)
    val shareChooserTitle = stringResource(RdR.string.rd_raporu_paylas)

    val reports = (state as? GeneratedReportsUiState.Loaded)?.items.orEmpty()
    val analyses = (historyState as? HistoryUiState.Loaded)?.items.orEmpty()
        .filter { it.status == "completed" }
    val needle = normalizeReportSearch(search)
    val filteredReports = reports.filter { report ->
        (focusedReportId == null || report.id == focusedReportId) &&
            (needle.isEmpty() || reportSearchText(report).contains(needle)) &&
            matchesReportFilter(report, activeFilter) &&
            (selectedArchiveCompany == null || report.companyId == selectedArchiveCompany?.id)
    }
    val freeRiskTrialUsedFromArchive = reports.any { it.isRiskAnalysis || it.isExcel }
    val freeRiskTrialAvailable = userTier == SubscriptionTier.Free &&
        !(reportQuotaUsage?.riskTrialUsed ?: freeRiskTrialUsedFromArchive)
    val isGenerating = generatingExcelId != null || generatingPdfId != null

    // Both ViewModels survive tab changes in MainShell; refresh the archive and its analysis
    // sources on each real entry so newly generated items appear without relaunching the app.
    LaunchedEffect(Unit) {
        viewModel.load()
        historyViewModel.load()
    }

    LaunchedEffect(focusedReportId) {
        if (focusedReportId != null) archiveExpanded = true
    }

    LaunchedEffect(selectedAnalysis?.id) {
        selectedAnalysis?.let(historyViewModel::loadReportPreview)
    }

    LaunchedEffect(reportFile) {
        val file = reportFile ?: return@LaunchedEffect
        val dir = File(context.cacheDir, "reports").apply { mkdirs() }
        val target = File(dir, File(file.fileName).name)
        target.writeBytes(file.bytes)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", target)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, file.mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, openChooserTitle))
        viewModel.clearReportFile()
    }

    LaunchedEffect(generatedFile) {
        val file = generatedFile ?: return@LaunchedEffect
        val dir = File(context.cacheDir, "reports").apply { mkdirs() }
        val target = File(dir, File(file.fileName).name)
        target.writeBytes(file.bytes)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", target)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = file.mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri(file.fileName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, shareChooserTitle))
        historyViewModel.clearReportFile()
        viewModel.load()
        historyViewModel.load()
        archiveExpanded = true
    }

    Box(modifier = Modifier.fillMaxSize().background(colors.cloud)) {
        Column(modifier = Modifier.fillMaxSize()) {
            if (!embeddedInMainShell) {
                RdScreenHeader(title = stringResource(RdR.string.rd_raporlar))
            }

            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = RdSpacing.lg,
                    end = RdSpacing.lg,
                    bottom = 120.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                item {
                    ReportOverview(
                        reportCount = reports.size,
                        analysisCount = analyses.size,
                        riskReportCount = reports.count { it.isRiskAnalysis || it.isExcel },
                    )
                }

                if (userTier == SubscriptionTier.Free) {
                    item { ReportPlanUpsell { onUpgrade("reports_upsell_card") } }
                }

                when {
                    state is GeneratedReportsUiState.SignedOut -> item {
                        RdEmptyState(
                            icon = Icons.Filled.Description,
                            title = stringResource(RdR.string.rd_oturum_yok),
                            subtitle = stringResource(RdR.string.rd_rapor_giris),
                        )
                    }
                    state is GeneratedReportsUiState.Failed -> item {
                        val failure = state as GeneratedReportsUiState.Failed
                        RdEmptyState(
                            icon = Icons.Filled.Description,
                            title = stringResource(RdR.string.rd_raporlar_yuklenemedi),
                            subtitle = failure.error.message,
                        )
                    }
                    state is GeneratedReportsUiState.Loading && historyState is HistoryUiState.Loading -> item {
                        Box(Modifier.fillMaxWidth().height(140.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = colors.black)
                        }
                    }
                    reports.isEmpty() && analyses.isEmpty() -> item {
                        RdEmptyState(
                            icon = Icons.Filled.Description,
                            title = stringResource(RdR.string.rd_henuz_raporlanacak_analiz_yok),
                            subtitle = stringResource(RdR.string.rd_rapor_kaynagi_bos_aciklama),
                        )
                    }
                    else -> {
                        item {
                            ReportSectionCard(
                                title = stringResource(RdR.string.rd_kayitli_rapor_dosyalari),
                                meta = stringResource(RdR.string.rd_dosya_sayisi_format, reports.size),
                                icon = Icons.Filled.Archive,
                                expanded = archiveExpanded,
                                onToggle = { archiveExpanded = !archiveExpanded },
                            ) {
                                if (reports.isEmpty()) {
                                    InlineStateCard(
                                        title = stringResource(RdR.string.rd_henuz_kayitli_rapor_yok),
                                        subtitle = stringResource(RdR.string.rd_kayitli_rapor_bos_aciklama),
                                    )
                                } else {
                                    ReportArchiveFilterSurface(
                                        search = search,
                                        onSearchChange = { search = it },
                                        activeFilter = activeFilter,
                                        onFilterSelect = { activeFilter = it },
                                        showCompanyButton = userTier != SubscriptionTier.Free,
                                        companySelected = selectedArchiveCompany != null,
                                        onCompanyClick = { showArchiveCompanyFilter = true },
                                    )
                                    Spacer(Modifier.height(7.dp))
                                    if (filteredReports.isEmpty()) {
                                        InlineStateCard(
                                            title = stringResource(RdR.string.rd_rapor_bulunamadi),
                                            subtitle = stringResource(RdR.string.rd_rapor_filtre_bos_aciklama),
                                        )
                                    } else {
                                        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                            filteredReports.forEach { report ->
                                                ReportRow(
                                                    report = report,
                                                    isOpening = openingId == report.id,
                                                    isDeleting = deletingReportId == report.id,
                                                    onClick = { viewModel.openReport(report) },
                                                    onDelete = { reportPendingDelete = report },
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        item {
                            ReportSectionCard(
                                title = stringResource(RdR.string.rd_rapora_donustur),
                                meta = stringResource(RdR.string.rd_analiz_sayisi_format, analyses.size),
                                icon = Icons.Filled.Tune,
                                expanded = analysesExpanded,
                                onToggle = { analysesExpanded = !analysesExpanded },
                            ) {
                                if (analyses.isEmpty()) {
                                    InlineStateCard(
                                        title = stringResource(RdR.string.rd_rapor_kaynagi_bekleniyor),
                                        subtitle = stringResource(RdR.string.rd_rapor_kaynagi_bos_aciklama),
                                    )
                                } else {
                                    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                                        analyses.forEach { item ->
                                            ReportAnalysisRow(
                                                item = item,
                                                isLoading = generatingExcelId == item.id || generatingPdfId == item.id,
                                                onClick = { selectedAnalysis = item },
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        if (isGenerating) {
            ReportGenerationOverlay(
                isExcel = generatingExcelId != null,
                modifier = Modifier.align(Alignment.Center),
            )
        }
    }

    selectedAnalysis?.let { item ->
        ReportSourceSheet(
            item = item,
            tier = userTier,
            companies = companies,
            profile = profile,
            previewState = reportPreview,
            freeRiskTrialAvailable = freeRiskTrialAvailable,
            reportQuotaExhausted = reportQuotaUsage?.isStandardQuotaExhausted == true,
            onDismiss = {
                selectedAnalysis = null
                historyViewModel.clearReportPreview()
            },
            onUpgrade = { entryPoint ->
                selectedAnalysis = null
                onUpgrade(entryPoint)
            },
            onGenerate = { kind, method, format, companyId, preparedBy, preparedTitle, certificateNumber ->
                selectedAnalysis = null
                historyViewModel.clearReportPreview()
                when (format) {
                    ReportFormat.Pdf -> historyViewModel.generatePdfReport(
                        item = item,
                        method = method.wire,
                        kind = if (kind == ReportKind.Standard) "standard" else "risk_analysis",
                        companyId = companyId,
                        preparedByName = preparedBy,
                        preparedByTitle = preparedTitle,
                        certificateNumber = certificateNumber,
                    )
                    ReportFormat.Excel -> historyViewModel.generateReport(item, method.wire, companyId)
                }
            },
        )
    }

    if (showArchiveCompanyFilter) {
        ModalBottomSheet(
            onDismissRequest = { showArchiveCompanyFilter = false },
            containerColor = colors.paper,
        ) {
            ReportCompanyFilterSheet(
                companies = companies,
                selected = selectedArchiveCompany,
                onSelect = { company ->
                    selectedArchiveCompany = company
                    showArchiveCompanyFilter = false
                },
            )
        }
    }

    reportError?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearReportError,
            title = { Text(error.title) },
            text = { Text(error.message) },
            confirmButton = { TextButton(onClick = viewModel::clearReportError) { Text(stringResource(RdR.string.rd_tamam)) } },
        )
    }

    generationError?.let { error ->
        AlertDialog(
            onDismissRequest = historyViewModel::clearReportError,
            title = { Text(error.title) },
            text = { Text(error.message) },
            confirmButton = { TextButton(onClick = historyViewModel::clearReportError) { Text(stringResource(RdR.string.rd_tamam)) } },
        )
    }

    reportPendingDelete?.let { report ->
        AlertDialog(
            onDismissRequest = { reportPendingDelete = null },
            title = { Text(stringResource(RdR.string.rd_raporu_sil)) },
            text = { Text(stringResource(RdR.string.rd_bu_rapor_dosyasi_kalici_olarak_silinecek_bu_islem_geri)) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteReport(report)
                    reportPendingDelete = null
                }) { Text(stringResource(RdR.string.rd_sil)) }
            },
            dismissButton = { TextButton(onClick = { reportPendingDelete = null }) { Text(stringResource(RdR.string.rd_vazgec)) } },
        )
    }

    deleteError?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearDeleteError,
            title = { Text(error.title) },
            text = { Text(error.message) },
            confirmButton = { TextButton(onClick = viewModel::clearDeleteError) { Text(stringResource(RdR.string.rd_tamam)) } },
        )
    }
}

@Composable
private fun ReportOverview(reportCount: Int, analysisCount: Int, riskReportCount: Int) {
    val colors = RdTheme.colors
    // Use the resolved in-app preference, not the device setting. These can intentionally differ.
    val dark = RdTheme.isDark
    val metricBackground = if (dark) Color(0xFF17231B) else colors.onyx
    val metricBorder = if (dark) colors.green.copy(alpha = .34f) else colors.onyx
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(6.dp, RoundedCornerShape(20.dp), ambientColor = colors.green.copy(.16f), spotColor = colors.onyx.copy(.14f))
            .clip(RoundedCornerShape(20.dp))
            .background(
                Brush.linearGradient(
                    if (dark) listOf(Color(0xFF151A18), Color(0xFF111615), Color(0xFF0F1D14))
                    else listOf(Color(0xFFF7FBFF), Color(0xFFF2F7FA), Color(0xFFEEF8F2)),
                ),
            )
            .border(1.4.dp, if (dark) colors.white.copy(.10f) else colors.onyx, RoundedCornerShape(20.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(42.dp).clip(RoundedCornerShape(13.dp)).background(colors.greenSoft), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Description, null, tint = colors.greenDark, modifier = Modifier.size(18.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text(stringResource(RdR.string.rd_denetime_hazir_ciktilar), style = RdFontStyle.Title3.toTextStyle(), color = colors.black)
                Text(stringResource(RdR.string.rd_denetime_hazir_ciktilar_aciklama), style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
            }
            Column(
                Modifier.size(width = 58.dp, height = 54.dp).clip(RoundedCornerShape(16.dp)).background(metricBackground)
                    .border(1.dp, metricBorder, RoundedCornerShape(16.dp)),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(reportCount.toString(), style = RdFontStyle.Title2.toTextStyle(), color = Color.White)
                Text(stringResource(RdR.string.rd_dosya_kucuk), style = RdFontStyle.Caption.toTextStyle(), color = Color.White.copy(.72f))
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OverviewMetric(Icons.Filled.BarChart, stringResource(RdR.string.rd_analiz), analysisCount, metricBackground, metricBorder, Modifier.weight(1f))
            OverviewMetric(Icons.Filled.TableChart, stringResource(RdR.string.rd_risk_tablosu), riskReportCount, metricBackground, metricBorder, Modifier.weight(1f))
            OverviewMetric(Icons.Filled.Archive, stringResource(RdR.string.rd_arsiv), reportCount, metricBackground, metricBorder, Modifier.weight(1f))
        }
    }
}

@Composable
private fun OverviewMetric(
    icon: ImageVector,
    label: String,
    value: Int,
    background: Color,
    border: Color,
    modifier: Modifier,
) {
    Row(
        modifier.height(48.dp).clip(RoundedCornerShape(14.dp)).background(background)
            .border(1.dp, border, RoundedCornerShape(14.dp)).padding(9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.size(26.dp).clip(RoundedCornerShape(8.dp)).background(Color.White.copy(.14f)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(13.dp))
        }
        Column {
            Text(value.toString(), style = RdFontStyle.Data.toTextStyle(), color = Color.White)
            Text(label, style = RdFontStyle.Caption.toTextStyle(), color = Color.White.copy(.70f), maxLines = 1)
        }
    }
}

@Composable
private fun ReportPlanUpsell(onClick: () -> Unit) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
            .background(Brush.linearGradient(listOf(colors.planPlusSoft, colors.white)))
            .border(1.dp, colors.planPlus.copy(.38f), RoundedCornerShape(18.dp))
            .clickable(onClick = onClick).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(42.dp).clip(RoundedCornerShape(13.dp)).background(colors.planPlus), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.TableChart, null, tint = Color.White, modifier = Modifier.size(20.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(stringResource(RdR.string.rd_detayli_risk_tablolarini_ac), style = RdFontStyle.Callout.toTextStyle(), color = colors.planPlusDark)
            Text(stringResource(RdR.string.rd_plus_rapor_deger_aciklama), style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = colors.planPlusDark)
    }
}

@Composable
private fun ReportSectionCard(
    title: String,
    meta: String,
    icon: ImageVector,
    expanded: Boolean,
    onToggle: () -> Unit,
    content: @Composable () -> Unit,
) {
    val colors = RdTheme.colors
    Column(
        Modifier.fillMaxWidth().shadow(4.dp, RoundedCornerShape(18.dp)).clip(RoundedCornerShape(18.dp))
            .background(colors.white).border(1.dp, colors.line, RoundedCornerShape(18.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().clickable(onClick = onToggle).padding(2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(Modifier.size(30.dp).clip(RoundedCornerShape(9.dp)).background(colors.greenSoft), contentAlignment = Alignment.Center) {
                Icon(icon, null, tint = colors.green, modifier = Modifier.size(14.dp))
            }
            Text(title, style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.black, modifier = Modifier.weight(1f))
            Text(meta, style = RdFontStyle.Data.toTextStyle(), color = colors.slate, modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(colors.fog).padding(horizontal = 8.dp, vertical = 5.dp))
            Box(Modifier.size(28.dp).clip(RoundedCornerShape(9.dp)).background(colors.fog), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.ExpandMore, null, tint = colors.slate, modifier = Modifier.size(16.dp).rotate(if (expanded) 0f else -90f))
            }
        }
        if (expanded) content()
    }
}

@Composable
private fun InlineStateCard(title: String, subtitle: String) {
    val colors = RdTheme.colors
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.fog).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title, style = RdFontStyle.Callout.toTextStyle(), color = colors.black)
        Text(subtitle, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
    }
}

@Composable
private fun ReportArchiveFilterSurface(
    search: String,
    onSearchChange: (String) -> Unit,
    activeFilter: ReportArchiveFilter,
    onFilterSelect: (ReportArchiveFilter) -> Unit,
    showCompanyButton: Boolean,
    companySelected: Boolean,
    onCompanyClick: () -> Unit,
) {
    val colors = RdTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                Modifier.weight(1f).height(40.dp).clip(RoundedCornerShape(12.dp)).background(colors.fog)
                    .border(1.dp, colors.line, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Search, null, tint = colors.slate, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(8.dp))
                Box(Modifier.fillMaxWidth()) {
                    if (search.isEmpty()) Text(stringResource(RdR.string.rd_rapor_ara), style = RdFontStyle.Callout.toTextStyle(), color = colors.slate)
                    BasicTextField(
                        value = search,
                        onValueChange = onSearchChange,
                        singleLine = true,
                        textStyle = RdFontStyle.Callout.toTextStyle().copy(color = colors.black),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            if (showCompanyButton) {
                IconButton(
                    onClick = onCompanyClick,
                    modifier = Modifier.size(40.dp).clip(RoundedCornerShape(12.dp))
                        .background(if (companySelected) colors.greenSoft else colors.fog)
                        .border(1.dp, if (companySelected) colors.green.copy(.34f) else colors.line, RoundedCornerShape(12.dp)),
                ) {
                    Icon(Icons.Filled.Business, stringResource(RdR.string.rd_rapor_firma_filtresi), tint = if (companySelected) colors.greenDark else colors.black, modifier = Modifier.size(18.dp))
                }
            }
        }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(ReportArchiveFilter.entries) { filter ->
                val active = filter == activeFilter
                Box(
                    Modifier.height(32.dp).clip(CircleShape).background(if (active) colors.selected else colors.fog)
                        .clickable { onFilterSelect(filter) }.padding(horizontal = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(stringResource(filter.labelRes), style = RdFontStyle.Caption.toTextStyle(), color = if (active) colors.white else colors.charcoal)
                }
            }
        }
    }
}

@Composable
private fun ReportRow(
    report: Report,
    isOpening: Boolean,
    isDeleting: Boolean,
    onClick: () -> Unit,
    onDelete: () -> Unit,
) {
    val colors = RdTheme.colors
    val iconTint = when {
        report.isExcel -> Color(0xFF2563EB)
        report.isRiskAnalysis -> colors.green
        else -> colors.charcoal
    }
    val iconBackground = when {
        report.isExcel -> Color(0xFFEAF1FF)
        report.isRiskAnalysis -> colors.greenSoft
        else -> colors.fog
    }
    Row(
        Modifier.fillMaxWidth().shadow(2.dp, RoundedCornerShape(14.dp)).clip(RoundedCornerShape(14.dp))
            .background(colors.white).border(1.dp, if (report.isRiskAnalysis) colors.green.copy(.24f) else colors.line, RoundedCornerShape(14.dp))
            .clickable(enabled = !isOpening, onClick = onClick).padding(horizontal = 10.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Box(Modifier.size(36.dp).clip(RoundedCornerShape(11.dp)).background(iconBackground), contentAlignment = Alignment.Center) {
            Icon(if (report.isExcel) Icons.Filled.TableChart else Icons.Filled.Description, null, tint = iconTint, modifier = Modifier.size(17.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(report.title ?: report.fileName ?: stringResource(RdR.string.rd_rapor), style = RdFontStyle.Footnote.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.black, maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                ReportMetaChip(if (report.isExcel) stringResource(RdR.string.rd_excel_label) else stringResource(RdR.string.rd_pdf_label), iconTint, iconBackground)
                report.method?.let { ReportMetaChip(if (it == "matrix_5x5") "5×5" else "FK", colors.charcoal, colors.fog) }
                report.createdAt?.let { Text(it.take(10), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate) }
            }
        }
        when {
            isOpening || isDeleting -> CircularProgressIndicator(color = if (isDeleting) colors.critical else colors.green, modifier = Modifier.size(18.dp))
            else -> {
                IconButton(onClick = onDelete, modifier = Modifier.size(32.dp).clip(RoundedCornerShape(10.dp)).background(colors.fog)) {
                    Icon(Icons.Filled.DeleteOutline, stringResource(RdR.string.rd_raporu_sil), tint = colors.critical, modifier = Modifier.size(17.dp))
                }
            }
        }
    }
}

@Composable
private fun ReportMetaChip(text: String, foreground: Color, background: Color) {
    Text(text, style = RdFontStyle.Caption.toTextStyle(), color = foreground, modifier = Modifier.clip(RoundedCornerShape(7.dp)).background(background).padding(horizontal = 7.dp, vertical = 3.dp))
}

@Composable
private fun ReportAnalysisRow(item: HistoryItem, isLoading: Boolean, onClick: () -> Unit) {
    val colors = RdTheme.colors
    val level = riskLevelFromRaw(item.riskBand)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(18.dp)).clickable(enabled = !isLoading, onClick = onClick).padding(14.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(44.dp).clip(RoundedCornerShape(13.dp)).background(colors.greenSoft), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.PhotoCamera, null, tint = colors.greenDark, modifier = Modifier.size(19.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(item.title, style = RdFontStyle.Subheadline.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.black, modifier = Modifier.weight(1f), maxLines = 2)
                RdRiskChip(level)
            }
            Text(
                listOfNotNull(item.createdAt?.take(10), item.kind, stringResource(RdR.string.rd_bulgu_sayisi_format, item.findingCount)).joinToString(" · "),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
                maxLines = 1,
            )
        }
        if (isLoading) CircularProgressIndicator(color = colors.green, modifier = Modifier.size(18.dp))
        else Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = colors.slate, modifier = Modifier.size(20.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReportSourceSheet(
    item: HistoryItem,
    tier: SubscriptionTier,
    companies: List<Company>,
    profile: UserProfile?,
    previewState: ReportPreviewUiState,
    freeRiskTrialAvailable: Boolean,
    reportQuotaExhausted: Boolean,
    onDismiss: () -> Unit,
    onUpgrade: (entryPoint: String) -> Unit,
    onGenerate: (ReportKind, ReportMethod, ReportFormat, String?, String, String, String) -> Unit,
) {
    val colors = RdTheme.colors
    var kind by remember { mutableStateOf(ReportKind.Standard) }
    var method by remember { mutableStateOf(ReportMethod.FineKinney) }
    var format by remember { mutableStateOf(ReportFormat.Pdf) }
    var selectedCompanyId by remember(item.id) { mutableStateOf(item.companyId) }
    var showCompanyPicker by remember { mutableStateOf(false) }
    var showSettings by remember(item.id) { mutableStateOf(false) }
    var preparedBy by remember(item.id, profile?.id) { mutableStateOf(profile?.displayName.orEmpty()) }
    var preparedTitle by remember(item.id, profile?.id) { mutableStateOf(profile?.title.orEmpty()) }
    var certificateNumber by remember(item.id, profile?.id) { mutableStateOf(profile?.certificateNumber.orEmpty()) }
    val selectedCompany = companies.firstOrNull { it.id == selectedCompanyId }
    val riskAnalysisLocked = tier == SubscriptionTier.Free && !freeRiskTrialAvailable
    val riskOptionLocked = riskAnalysisLocked || (reportQuotaExhausted && !freeRiskTrialAvailable)
    val selectedOptionLocked = when (kind) {
        ReportKind.Standard -> reportQuotaExhausted
        ReportKind.RiskAnalysis -> riskOptionLocked
    }
    val handleLockedAction: () -> Unit = {
        if (tier == SubscriptionTier.Pro) onDismiss() else onUpgrade("reports_locked_report_options")
    }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = colors.paper,
        dragHandle = { Box(Modifier.padding(top = 8.dp).size(width = 38.dp, height = 5.dp).clip(CircleShape).background(colors.line)) },
    ) {
        Column(Modifier.fillMaxWidth().heightIn(min = 430.dp, max = 700.dp).padding(horizontal = 14.dp)) {
            Box(Modifier.fillMaxWidth().height(48.dp)) {
                Text(stringResource(RdR.string.rd_rapor_olustur), style = RdFontStyle.Callout.toTextStyle(), color = colors.black, modifier = Modifier.align(Alignment.Center))
                IconButton(onClick = onDismiss, modifier = Modifier.align(Alignment.CenterEnd).size(34.dp).clip(CircleShape).background(colors.fog)) {
                    Icon(Icons.Filled.Close, stringResource(RdR.string.rd_kapat), tint = colors.black, modifier = Modifier.size(18.dp))
                }
            }
            Text(item.title, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate, modifier = Modifier.padding(bottom = 10.dp))
            LazyColumn(
                Modifier.weight(1f).testTag("report-settings-list"),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (!showSettings) {
                    item {
                        ReportDocumentPreview(item = item, previewState = previewState, profile = profile)
                    }
                } else {
                    item {
                        ReportOptionCard(
                            selected = kind == ReportKind.Standard,
                            icon = Icons.Filled.Description,
                            title = stringResource(RdR.string.rd_standart_rapor),
                            subtitle = stringResource(RdR.string.rd_standart_rapor_aciklama),
                            locked = reportQuotaExhausted,
                        ) {
                            if (reportQuotaExhausted) handleLockedAction() else {
                                kind = ReportKind.Standard
                                format = ReportFormat.Pdf
                            }
                        }
                    }
                    item {
                        if (tier == SubscriptionTier.Free && freeRiskTrialAvailable) FreeTrialRibbon()
                        ReportOptionCard(
                            selected = kind == ReportKind.RiskAnalysis,
                            icon = Icons.Filled.TableChart,
                            title = stringResource(RdR.string.rd_risk_analizi_tablosu),
                            subtitle = stringResource(
                                if (riskAnalysisLocked) RdR.string.rd_risk_analizi_deneme_kullanildi
                                else RdR.string.rd_risk_analizi_tablosu_aciklama,
                            ),
                            locked = riskOptionLocked,
                        ) {
                            if (riskOptionLocked) handleLockedAction() else kind = ReportKind.RiskAnalysis
                        }
                    }
                    if (kind == ReportKind.RiskAnalysis) {
                        item {
                            Text(stringResource(RdR.string.rd_rapor_firmasi), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.slate)
                            Spacer(Modifier.height(7.dp))
                            ReportCompanyChoice(
                                selectedCompany = selectedCompany,
                                onClick = {
                                    if (tier == SubscriptionTier.Free) onUpgrade("reports_company_picker") else showCompanyPicker = true
                                },
                            )
                        }
                        item {
                            Text(stringResource(RdR.string.rd_risk_yontemi), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.slate)
                            Spacer(Modifier.height(7.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                ReportChoiceChip(stringResource(ReportMethod.FineKinney.titleRes), method == ReportMethod.FineKinney, Modifier.weight(1f)) { method = ReportMethod.FineKinney }
                                ReportChoiceChip(stringResource(ReportMethod.Matrix5x5.titleRes), method == ReportMethod.Matrix5x5, Modifier.weight(1f)) { method = ReportMethod.Matrix5x5 }
                            }
                        }
                        item {
                            Text(stringResource(RdR.string.rd_cikti_formati), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.slate)
                            Spacer(Modifier.height(7.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                ReportChoiceChip(stringResource(RdR.string.rd_pdf_rapor), format == ReportFormat.Pdf, Modifier.weight(1f)) { format = ReportFormat.Pdf }
                                ReportChoiceChip(stringResource(RdR.string.rd_excel_tablo), format == ReportFormat.Excel, Modifier.weight(1f)) { format = ReportFormat.Excel }
                            }
                        }
                        item {
                            ReportIdentityFields(
                                preparedBy = preparedBy,
                                onPreparedByChange = { preparedBy = it },
                                preparedTitle = preparedTitle,
                                onPreparedTitleChange = { preparedTitle = it },
                                certificateNumber = certificateNumber,
                                onCertificateNumberChange = { certificateNumber = it },
                            )
                        }
                        item {
                            Text(stringResource(RdR.string.rd_rapor_dili), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.slate)
                            Spacer(Modifier.height(7.dp))
                            InlineStateCard(
                                title = stringResource(RdR.string.rd_turkce),
                                subtitle = stringResource(RdR.string.rd_rapor_dili_aciklama),
                            )
                        }
                    }
                }
            }
            Button(
                onClick = {
                    if (!showSettings) {
                        showSettings = true
                    } else if (selectedOptionLocked) {
                        handleLockedAction()
                    } else {
                        onGenerate(
                            kind,
                            method,
                            format,
                            selectedCompanyId,
                            preparedBy,
                            preparedTitle,
                            certificateNumber,
                        )
                    }
                },
                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp).height(56.dp).testTag("report-source-primary"),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = colors.onyx, contentColor = Color.White),
            ) {
                Icon(if (format == ReportFormat.Pdf) Icons.Filled.Description else Icons.Filled.TableChart, null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Text(
                    when {
                        !showSettings -> stringResource(RdR.string.rd_rapor_olustur)
                        selectedOptionLocked && tier == SubscriptionTier.Free -> stringResource(RdR.string.rd_yukselt)
                        selectedOptionLocked && tier == SubscriptionTier.Plus -> stringResource(RdR.string.rd_proya_yukselt)
                        selectedOptionLocked -> stringResource(RdR.string.rd_tamam)
                        kind == ReportKind.Standard -> stringResource(RdR.string.rd_rapor_olustur)
                        format == ReportFormat.Excel -> stringResource(RdR.string.rd_excel_risk_tablosu_olustur)
                        else -> stringResource(RdR.string.rd_risk_analizi_pdf_olustur)
                    },
                    style = RdFontStyle.Callout.toTextStyle(),
                    modifier = Modifier.weight(1f),
                )
                Box(Modifier.size(34.dp).clip(CircleShape).background(Color.White), contentAlignment = Alignment.Center) {
                    Icon(Icons.AutoMirrored.Filled.Send, null, tint = colors.black, modifier = Modifier.size(17.dp))
                }
            }
        }
    }

    if (showCompanyPicker) {
        val companyPickerSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { showCompanyPicker = false },
            sheetState = companyPickerSheetState,
            containerColor = colors.paper,
            dragHandle = {
                Box(
                    Modifier.padding(top = 8.dp).size(width = 38.dp, height = 5.dp)
                        .clip(CircleShape).background(colors.line),
                )
            },
        ) {
            ReportCompanySearchSheet(
                companies = companies,
                selected = selectedCompany,
                onSelect = { company ->
                    selectedCompanyId = company?.id
                    showCompanyPicker = false
                },
                onClose = { showCompanyPicker = false },
            )
        }
    }
}

@Composable
private fun ReportDocumentPreview(
    item: HistoryItem,
    previewState: ReportPreviewUiState,
    profile: UserProfile?,
) {
    val colors = RdTheme.colors
    val findings = (previewState as? ReportPreviewUiState.Loaded)
        ?.takeIf { it.analysisId == item.id }
        ?.findings
        .orEmpty()
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(18.dp)).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    stringResource(RdR.string.rd_rapor_onizleme),
                    style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.Bold),
                    color = colors.greenDark,
                )
                Text(
                    stringResource(RdR.string.rd_is_guvenligi_risk_analizi),
                    style = RdFontStyle.Title3.toTextStyle().copy(fontWeight = FontWeight.Bold),
                    color = colors.black,
                )
            }
            Text(item.createdAt?.take(10).orEmpty(), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
        }
        Box(Modifier.fillMaxWidth().height(2.dp).background(colors.green))
        Text(item.title, style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.black)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ReportPreviewStat(stringResource(RdR.string.rd_bulgu_sayisi_format, item.findingCount), Modifier.weight(1f))
            Box(
                Modifier.weight(1f).height(52.dp).clip(RoundedCornerShape(13.dp)).background(colors.fog),
                contentAlignment = Alignment.Center,
            ) {
                RdRiskChip(riskLevelFromRaw(item.riskBand))
            }
        }
        when (previewState) {
            ReportPreviewUiState.Idle,
            ReportPreviewUiState.Loading -> Box(Modifier.fillMaxWidth().height(72.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.green, modifier = Modifier.size(24.dp))
            }
            is ReportPreviewUiState.Failed -> InlineStateCard(
                title = stringResource(RdR.string.rd_onizleme_detayi_alinamadi),
                subtitle = stringResource(RdR.string.rd_rapor_onizleme_devam_aciklama),
            )
            is ReportPreviewUiState.Loaded -> {
                if (findings.isEmpty()) {
                    InlineStateCard(
                        title = stringResource(RdR.string.rd_bulgu_yok),
                        subtitle = stringResource(RdR.string.rd_rapor_onizleme_devam_aciklama),
                    )
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        findings.take(3).forEach { finding -> ReportPreviewFindingRow(finding) }
                    }
                }
            }
        }
        Text(
            stringResource(RdR.string.rd_hazirlayan_format, profile?.displayName ?: stringResource(RdR.string.rd_emdash)),
            style = RdFontStyle.Caption.toTextStyle(),
            color = colors.slate,
        )
    }
}

@Composable
private fun ReportPreviewStat(text: String, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    Box(modifier.height(52.dp).clip(RoundedCornerShape(13.dp)).background(colors.fog), contentAlignment = Alignment.Center) {
        Text(text, style = RdFontStyle.Footnote.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.black)
    }
}

@Composable
private fun ReportPreviewFindingRow(finding: Finding) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(colors.fog).padding(horizontal = 11.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Text(
            finding.ordinal.toString(),
            style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.Bold),
            color = colors.greenDark,
        )
        Text(
            finding.title,
            style = RdFontStyle.Footnote.toTextStyle(),
            color = colors.black,
            modifier = Modifier.weight(1f),
            maxLines = 2,
        )
        RdRiskChip(riskLevelFromRaw(finding.fkBand))
    }
}

@Composable
private fun ReportIdentityFields(
    preparedBy: String,
    onPreparedByChange: (String) -> Unit,
    preparedTitle: String,
    onPreparedTitleChange: (String) -> Unit,
    certificateNumber: String,
    onCertificateNumberChange: (String) -> Unit,
) {
    val colors = RdTheme.colors
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(18.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(stringResource(RdR.string.rd_hazirlayan_bilgileri), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.slate)
        ReportTextField(stringResource(RdR.string.rd_hazirlayan), preparedBy, onPreparedByChange)
        ReportTextField(stringResource(RdR.string.rd_unvan), preparedTitle, onPreparedTitleChange)
        ReportTextField(stringResource(RdR.string.rd_belge_no), certificateNumber, onCertificateNumberChange)
    }
}

@Composable
private fun ReportTextField(label: String, value: String, onValueChange: (String) -> Unit) {
    val colors = RdTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(label, style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.slate)
        BasicTextField(
            value = value,
            onValueChange = { onValueChange(it.take(120)) },
            textStyle = RdFontStyle.Footnote.toTextStyle().copy(color = colors.black),
            cursorBrush = SolidColor(colors.green),
            modifier = Modifier.fillMaxWidth().heightIn(min = 46.dp).clip(RoundedCornerShape(12.dp))
                .background(colors.fog).border(1.dp, colors.line, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 13.dp),
        )
    }
}

@Composable
private fun ReportOptionCard(
    selected: Boolean,
    icon: ImageVector,
    title: String,
    subtitle: String,
    locked: Boolean = false,
    onClick: () -> Unit,
) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 104.dp).clip(RoundedCornerShape(20.dp))
            .background(if (selected) colors.greenSoft.copy(.65f) else colors.white)
            .border(if (selected) 1.4.dp else 1.dp, if (selected) colors.green.copy(.55f) else colors.line, RoundedCornerShape(20.dp))
            .clickable(onClick = onClick).padding(horizontal = 18.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(58.dp).clip(RoundedCornerShape(15.dp)).background(if (selected) colors.green else colors.greenSoft), contentAlignment = Alignment.Center) {
            Icon(if (locked) Icons.Filled.Lock else icon, null, tint = if (selected) Color.White else if (locked) colors.planPlusDark else colors.greenDark, modifier = Modifier.size(25.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.black)
            Text(subtitle, style = RdFontStyle.Footnote.toTextStyle(), color = if (locked) colors.planPlusDark else colors.slate, maxLines = 3)
        }
        Box(Modifier.size(24.dp).clip(CircleShape).border(2.dp, if (selected) colors.green else colors.slate.copy(.32f), CircleShape).background(if (selected) colors.green else Color.Transparent), contentAlignment = Alignment.Center) {
            if (selected) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(15.dp))
        }
    }
}

@Composable
private fun ReportCompanyChoice(selectedCompany: Company?, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 58.dp).clip(RoundedCornerShape(16.dp))
            .background(colors.white).border(1.dp, colors.line, RoundedCornerShape(16.dp))
            .clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        Box(Modifier.size(38.dp).clip(RoundedCornerShape(11.dp)).background(colors.greenSoft), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Business, null, tint = colors.greenDark, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(selectedCompany?.name ?: stringResource(RdR.string.rd_firma_yok), style = RdFontStyle.Footnote.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.black)
            Text(
                selectedCompany?.let(::reportCompanySubtitle)
                    ?: stringResource(RdR.string.rd_kayitli_firmalarindan_sec),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
                maxLines = 1,
            )
        }
        Icon(Icons.Filled.ExpandMore, null, tint = colors.slate, modifier = Modifier.size(20.dp))
    }
}

internal fun filterReportCompanies(
    companies: List<Company>,
    query: String,
    selectedCompanyId: String? = null,
): List<Company> {
    val needle = normalizeReportSearch(query)
    return companies
        .asSequence()
        .filter { company ->
            needle.isEmpty() || normalizeReportSearch(
                listOfNotNull(
                    company.name,
                    company.hazardClass.title,
                    company.address,
                    company.contactPerson,
                    company.department,
                    company.defaultResponsible,
                ).joinToString(" "),
            ).contains(needle)
        }
        .sortedWith(
            compareByDescending<Company> { it.id == selectedCompanyId }
                .thenBy { normalizeReportSearch(it.name) },
        )
        .toList()
}

private fun reportCompanySubtitle(company: Company): String = listOfNotNull(
    company.hazardClass.title,
    company.department?.trim()?.takeIf(String::isNotEmpty)
        ?: company.address?.trim()?.takeIf(String::isNotEmpty),
).joinToString(" · ")

@Composable
internal fun ReportCompanySearchSheet(
    companies: List<Company>,
    selected: Company?,
    onSelect: (Company?) -> Unit,
    onClose: () -> Unit,
) {
    val colors = RdTheme.colors
    var query by remember { mutableStateOf("") }
    val filteredCompanies = remember(companies, query, selected?.id) {
        filterReportCompanies(companies, query, selected?.id)
    }

    Column(
        Modifier.fillMaxWidth().heightIn(min = 430.dp, max = 680.dp)
            .padding(horizontal = 18.dp).padding(bottom = 22.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(colors.greenSoft),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Business, null, tint = colors.greenDark, modifier = Modifier.size(21.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    stringResource(RdR.string.rd_rapor_firmasi),
                    style = RdFontStyle.Title3.toTextStyle().copy(fontWeight = FontWeight.Bold),
                    color = colors.black,
                )
                Text(
                    stringResource(RdR.string.rd_rapor_firmasi_sec_aciklama),
                    style = RdFontStyle.Footnote.toTextStyle(),
                    color = colors.slate,
                )
            }
            IconButton(
                onClick = onClose,
                modifier = Modifier.size(38.dp).clip(CircleShape).background(colors.fog),
            ) {
                Icon(Icons.Filled.Close, stringResource(RdR.string.rd_kapat), tint = colors.black, modifier = Modifier.size(18.dp))
            }
        }

        ReportCompanySearchField(query = query, onQueryChange = { query = it })

        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(RdR.string.rd_firma_sonuc_sayisi_format, filteredCompanies.size),
                style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.Bold),
                color = colors.slate,
                modifier = Modifier.weight(1f),
            )
            if (query.isNotBlank()) {
                Text(
                    stringResource(RdR.string.rd_aramayi_temizle),
                    style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.Bold),
                    color = colors.greenDark,
                    modifier = Modifier.clip(CircleShape).clickable { query = "" }
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
        }

        ReportCompanySearchRow(
            company = null,
            selected = selected == null,
            onClick = { onSelect(null) },
        )

        if (filteredCompanies.isEmpty()) {
            Column(
                Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(18.dp))
                    .background(colors.fog).padding(22.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(Icons.Filled.Search, null, tint = colors.slate, modifier = Modifier.size(28.dp))
                Spacer(Modifier.height(9.dp))
                Text(
                    stringResource(if (companies.isEmpty()) RdR.string.rd_henuz_firma_yok else RdR.string.rd_firma_arama_sonuc_yok),
                    style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.Bold),
                    color = colors.black,
                )
                if (query.isNotBlank()) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        stringResource(RdR.string.rd_firma_arama_sonuc_yok_aciklama),
                        style = RdFontStyle.Footnote.toTextStyle(),
                        color = colors.slate,
                    )
                }
            }
        } else {
            LazyColumn(
                Modifier.fillMaxWidth().weight(1f).testTag("report-company-results"),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(filteredCompanies, key = { it.id }) { company ->
                    ReportCompanySearchRow(
                        company = company,
                        selected = selected?.id == company.id,
                        onClick = { onSelect(company) },
                    )
                }
            }
        }
    }
}

@Composable
private fun ReportCompanySearchField(query: String, onQueryChange: (String) -> Unit) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().height(50.dp).clip(RoundedCornerShape(15.dp))
            .background(colors.white).border(1.dp, colors.line, RoundedCornerShape(15.dp))
            .padding(start = 14.dp, end = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Search, null, tint = colors.slate, modifier = Modifier.size(19.dp))
        Spacer(Modifier.width(9.dp))
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (query.isEmpty()) {
                Text(stringResource(RdR.string.rd_firma_ara), style = RdFontStyle.Callout.toTextStyle(), color = colors.slate)
            }
            BasicTextField(
                value = query,
                onValueChange = onQueryChange,
                singleLine = true,
                textStyle = RdFontStyle.Callout.toTextStyle().copy(color = colors.black),
                cursorBrush = SolidColor(colors.green),
                modifier = Modifier.fillMaxWidth().testTag("report-company-search"),
            )
        }
        if (query.isNotEmpty()) {
            IconButton(onClick = { onQueryChange("") }, modifier = Modifier.size(36.dp)) {
                Icon(Icons.Filled.Close, stringResource(RdR.string.rd_aramayi_temizle), tint = colors.slate, modifier = Modifier.size(17.dp))
            }
        }
    }
}

@Composable
private fun ReportCompanySearchRow(company: Company?, selected: Boolean, onClick: () -> Unit) {
    val colors = RdTheme.colors
    val title = company?.name ?: stringResource(RdR.string.rd_firma_secmeden_devam_et)
    val subtitle = company?.let(::reportCompanySubtitle)
        ?: stringResource(RdR.string.rd_firma_bilgisi_rapora_eklenmez)
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
            .background(if (selected) colors.greenSoft.copy(.72f) else colors.white)
            .border(
                if (selected) 1.4.dp else 1.dp,
                if (selected) colors.green.copy(.52f) else colors.line,
                RoundedCornerShape(16.dp),
            )
            .clickable(onClick = onClick)
            .then(if (company != null) Modifier.testTag("report-company-${company.id}") else Modifier)
            .padding(horizontal = 12.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        Box(
            Modifier.size(40.dp).clip(RoundedCornerShape(12.dp))
                .background(if (selected) colors.green else colors.fog),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (company == null) Icons.Filled.Close else Icons.Filled.Business,
                null,
                tint = if (selected) Color.White else colors.slate,
                modifier = Modifier.size(18.dp),
            )
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                title,
                style = RdFontStyle.Footnote.toTextStyle().copy(fontWeight = FontWeight.Bold),
                color = colors.black,
                maxLines = 1,
            )
            Text(subtitle, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate, maxLines = 1)
        }
        Box(
            Modifier.size(24.dp).clip(CircleShape)
                .border(2.dp, if (selected) colors.green else colors.slate.copy(.30f), CircleShape)
                .background(if (selected) colors.green else Color.Transparent),
            contentAlignment = Alignment.Center,
        ) {
            if (selected) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(15.dp))
        }
    }
}

@Composable
private fun ReportCompanyPickerList(
    companies: List<Company>,
    selected: Company?,
    onSelect: (Company?) -> Unit,
) {
    val colors = RdTheme.colors
    LazyColumn(Modifier.fillMaxWidth().heightIn(max = 360.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        item {
            ReportCompanyPickerRow(
                title = stringResource(RdR.string.rd_firma_yok),
                selected = selected == null,
                onClick = { onSelect(null) },
            )
        }
        items(companies, key = { it.id }) { company ->
            ReportCompanyPickerRow(
                title = company.name,
                selected = selected?.id == company.id,
                onClick = { onSelect(company) },
            )
        }
        if (companies.isEmpty()) {
            item {
                Text(stringResource(RdR.string.rd_henuz_firma_yok), style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate, modifier = Modifier.padding(10.dp))
            }
        }
    }
}

@Composable
private fun ReportCompanyPickerRow(title: String, selected: Boolean, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(13.dp))
            .background(if (selected) colors.greenSoft else colors.fog)
            .clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = RdFontStyle.Footnote.toTextStyle(), color = colors.black, modifier = Modifier.weight(1f))
        if (selected) Icon(Icons.Filled.Check, null, tint = colors.green, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun ReportCompanyFilterSheet(
    companies: List<Company>,
    selected: Company?,
    onSelect: (Company?) -> Unit,
) {
    val colors = RdTheme.colors
    Column(Modifier.fillMaxWidth().padding(horizontal = RdSpacing.lg, vertical = 12.dp)) {
        Text(stringResource(RdR.string.rd_rapor_firma_filtresi), style = RdFontStyle.Title3.toTextStyle(), color = colors.black)
        Spacer(Modifier.height(12.dp))
        ReportCompanyPickerList(companies, selected, onSelect)
        Spacer(Modifier.height(20.dp))
    }
}

@Composable
private fun FreeTrialRibbon() {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().padding(bottom = 6.dp).clip(RoundedCornerShape(16.dp))
            .background(Brush.linearGradient(listOf(colors.planPlusSoft, colors.white)))
            .border(1.dp, colors.planPlus.copy(.34f), RoundedCornerShape(16.dp))
            .padding(horizontal = 14.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Icon(Icons.Filled.TableChart, null, tint = colors.planPlusDark, modifier = Modifier.size(18.dp))
        Text(stringResource(RdR.string.rd_tek_seferlik_deneme_aciklama), style = RdFontStyle.Footnote.toTextStyle().copy(fontWeight = FontWeight.Bold), color = colors.planPlusDark, modifier = Modifier.weight(1f))
        Text(stringResource(RdR.string.rd_plus), style = RdFontStyle.Caption.toTextStyle(), color = colors.planPlusDark)
    }
}

@Composable
private fun ReportChoiceChip(text: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Box(
        modifier.height(48.dp).clip(RoundedCornerShape(14.dp)).background(if (selected) colors.greenSoft else colors.white)
            .border(1.dp, if (selected) colors.green else colors.line, RoundedCornerShape(14.dp)).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = RdFontStyle.Footnote.toTextStyle(), color = if (selected) colors.greenDark else colors.black)
    }
}

@Composable
private fun ReportGenerationOverlay(isExcel: Boolean, modifier: Modifier = Modifier) {
    val colors = RdTheme.colors
    Box(modifier.fillMaxSize().background(Color.Black.copy(.42f)), contentAlignment = Alignment.Center) {
        Column(
            modifier.width(300.dp).clip(RoundedCornerShape(24.dp)).background(colors.paper).border(1.dp, colors.line, RoundedCornerShape(24.dp)).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CircularProgressIndicator(color = if (isExcel) Color(0xFF2563EB) else colors.green, modifier = Modifier.size(44.dp))
            Text(
                stringResource(if (isExcel) RdR.string.rd_excel_hazirlaniyor else RdR.string.rd_pdf_hazirlaniyor),
                style = RdFontStyle.Title3.toTextStyle(),
                color = colors.black,
            )
            Text(stringResource(RdR.string.rd_uygulamayi_acik_tut), style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
        }
    }
}

/** Deterministic live-component golden surface for the expanded archive + source hierarchy. */
@Composable
internal fun GeneratedReportsParityPreviewSurface() {
    val colors = RdTheme.colors
    val pdfReport = Report(
        id = "preview-pdf",
        documentNo = "RD-2026-0810",
        format = "pdf",
        kind = "risk_analysis",
        method = "fine_kinney",
        title = "İskele Risk Analizi",
        storagePath = "preview/report.pdf",
        fileName = "iskele-risk-analizi.pdf",
        mimeType = "application/pdf",
        createdAt = "2026-08-10T12:00:00+03:00",
    )
    val excelReport = Report(
        id = "preview-xlsx",
        documentNo = "RD-2026-0809",
        format = "xlsx",
        kind = "standard",
        method = "matrix_5x5",
        title = "Üretim Hattı Bulguları",
        storagePath = "preview/report.xlsx",
        fileName = "uretim-hatti-bulgulari.xlsx",
        mimeType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        createdAt = "2026-08-09T15:45:00+03:00",
    )
    val analysis = HistoryItem(
        id = "preview-analysis",
        title = "İskele çalışma alanı",
        canvas = "general",
        status = "completed",
        kind = "Genel",
        findingCount = 8,
        highestBandFk = "critical",
        createdAt = "2026-08-10T10:30:00+03:00",
    )
    Column(Modifier.fillMaxSize().background(colors.cloud)) {
        RdScreenHeader(title = stringResource(RdR.string.rd_raporlar))
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = RdSpacing.lg, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item { ReportOverview(1, 1, 1) }
            item { ReportPlanUpsell {} }
            item {
                ReportSectionCard(stringResource(RdR.string.rd_kayitli_rapor_dosyalari), "1 dosya", Icons.Filled.Archive, true, {}) {
                    ReportArchiveFilterSurface("", {}, ReportArchiveFilter.All, {}, true, false, {})
                    Spacer(Modifier.height(7.dp))
                    ReportRow(pdfReport, false, false, {}, {})
                    Spacer(Modifier.height(7.dp))
                    ReportRow(excelReport, false, false, {}, {})
                }
            }
            item {
                ReportSectionCard(stringResource(RdR.string.rd_rapora_donustur), "1 analiz", Icons.Filled.Tune, true, {}) {
                    ReportAnalysisRow(analysis, false, {})
                }
            }
        }
    }
}

/** Deterministic golden surface for iOS build-81's source-selection sheet. */
@Composable
internal fun ReportSourceSheetParityPreviewSurface(
    tier: SubscriptionTier = SubscriptionTier.Free,
    freeRiskTrialAvailable: Boolean = true,
) {
    val previewItem = HistoryItem(
        id = "preview-source",
        title = "İskele çalışma alanı",
        canvas = "general",
        status = "completed",
        kind = "Genel",
        findingCount = 2,
        highestBandFk = "critical",
        createdAt = "2026-08-10T10:30:00+03:00",
    )
    ReportSourceSheet(
        item = previewItem,
        tier = tier,
        companies = emptyList(),
        profile = null,
        previewState = ReportPreviewUiState.Loaded(
            analysisId = previewItem.id,
            findings = listOf(
                Finding(
                    id = "finding-1",
                    ordinal = 1,
                    title = "Platform kenarında düşmeye karşı koruma yok",
                    fkBand = "critical",
                    m5Band = "high",
                ),
                Finding(
                    id = "finding-2",
                    ordinal = 2,
                    title = "Geçiş yolunda dağınık malzeme bulunuyor",
                    fkBand = "medium",
                    m5Band = "medium",
                ),
            ),
        ),
        freeRiskTrialAvailable = freeRiskTrialAvailable,
        reportQuotaExhausted = false,
        onDismiss = {},
        onUpgrade = {},
        onGenerate = { _, _, _, _, _, _, _ -> },
    )
}

/** Deterministic golden surface for the server-side Excel generation state. */
@Composable
internal fun ExcelGenerationOverlayParityPreviewSurface() {
    val colors = RdTheme.colors
    Box(Modifier.fillMaxSize().background(colors.cloud)) {
        GeneratedReportsParityPreviewSurface()
        ReportGenerationOverlay(isExcel = true)
    }
}
