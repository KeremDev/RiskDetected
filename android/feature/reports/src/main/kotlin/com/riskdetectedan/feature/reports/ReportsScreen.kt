package com.riskdetectedan.feature.reports

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.content.Intent
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdListRow
import com.riskdetectedan.core.designsystem.RdRiskChip
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.RiskLevel
import com.riskdetectedan.core.designsystem.riskLevelFromRaw
import com.riskdetectedan.core.designsystem.toTextStyle
import java.io.File
import java.time.Instant
import java.time.OffsetDateTime
import java.time.temporal.ChronoUnit

/** Real port of `HistoryView.swift`'s search field + filter-chip row — was entirely missing on
 * Android before this (2026-08-09 gap sweep): tümü/bu hafta/kritik/KKD/genel, same semantics as
 * `filteredItems` (search matches title/kind, "bu hafta" = last 7 days same as iOS's
 * `isThisWeek`, "kritik" = highest risk band, KKD/genel match `item.kind`). iOS's advanced
 * `FilterSheet` (date range/risk-level/kind multi-select behind the funnel icon) is deliberately
 * NOT ported — checked its source: `onConfirm()` never reads back any of the sheet's own
 * `@State` (`dateFilter`/`selectedLevels`/`selectedKinds`), so it's decorative on iOS itself, not
 * a real feature to port faithfully. The company filter (`CompanyPickerSheet`, Plus/Pro-gated)
 * is also not ported this pass — real, but lower-priority than the chips/search that
 * `filteredItems` actually uses; a genuine follow-up, not silently dropped. */
private enum class HistoryFilterChip(@StringRes val labelRes: Int) {
    All(RdR.string.rd_tumu),
    ThisWeek(RdR.string.rd_bu_hafta),
    Critical(RdR.string.rd_kritik),
    Ppe(RdR.string.rd_kkd),
    General(RdR.string.rd_genel),
}

private fun isWithinLastWeek(createdAt: String?): Boolean {
    val raw = createdAt ?: return false
    return try {
        OffsetDateTime.parse(raw).toInstant().isAfter(Instant.now().minus(7, ChronoUnit.DAYS))
    } catch (t: Throwable) {
        false
    }
}

private fun matchesChip(item: HistoryItem, chip: HistoryFilterChip): Boolean = when (chip) {
    HistoryFilterChip.All -> true
    HistoryFilterChip.ThisWeek -> isWithinLastWeek(item.createdAt)
    HistoryFilterChip.Critical -> riskLevelFromRaw(item.riskBand) == RiskLevel.Critical
    HistoryFilterChip.Ppe -> item.kind.contains("KKD", ignoreCase = true)
    HistoryFilterChip.General -> item.kind.contains("Genel", ignoreCase = true)
}

/** Port of the analysis history list (2026-08-08 visual pass, Faz J of the core-flow redesign —
 * see [com.riskdetectedan.core.data.analysis.HistoryItem]'s doc comment for the mirrored iOS
 * mapping). Real structure ported: [RdListRow] + [RdRiskChip] for each row, [RdEmptyState] for
 * the empty-list case (none of the History/Reports/Company screens had one before this pass).
 * Report generation ("Excel oluştur"/"PDF oluştur") and the system-chooser hand-off are unchanged
 * — pure UI-layer pass, same as every other screen in this redesign.
 *
 * "PDF oluştur" (added 2026-08-08, DEC-09): real on-device PDF report generation, see
 * [HistoryViewModel.generatePdfReport]'s doc comment. Uses the same [LaunchedEffect]/FileProvider
 * hand-off as the Excel button — [HistoryViewModel.reportFile] doesn't distinguish the two, a
 * generated file is a generated file regardless of which flow produced it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportsScreen(
    onBack: (() -> Unit)? = null,
    focusedAnalysisId: String? = null,
    onOpenAnalysis: ((String) -> Unit)? = null,
    viewModel: HistoryViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val generatingId by viewModel.generatingReportForId.collectAsState()
    val generatingPdfId by viewModel.generatingPdfForId.collectAsState()
    val reportError by viewModel.reportError.collectAsState()
    val reportFile by viewModel.reportFile.collectAsState()
    val deletingId by viewModel.deletingId.collectAsState()
    val deleteError by viewModel.deleteError.collectAsState()
    var itemPendingDelete by remember { mutableStateOf<HistoryItem?>(null) }
    var search by remember { mutableStateOf("") }
    var activeChip by remember { mutableStateOf(HistoryFilterChip.All) }
    val companies by viewModel.companies.collectAsState()
    val userTier by viewModel.userTier.collectAsState()
    val selectedCompany by viewModel.selectedCompanyFilter.collectAsState()
    var showCompanyFilter by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val shareChooserTitle = stringResource(RdR.string.rd_raporu_paylas)

    LaunchedEffect(reportFile) {
        val file = reportFile ?: return@LaunchedEffect
        val dir = File(context.cacheDir, "reports").apply { mkdirs() }
        val target = File(dir, file.fileName)
        target.writeBytes(file.bytes)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", target)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = file.mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = android.content.ClipData.newRawUri(file.fileName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, shareChooserTitle))
        viewModel.clearReportFile()
    }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = stringResource(RdR.string.rd_gecmis_analizler), onBack = onBack)

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.lg)) {
            when (val current = state) {
                is HistoryUiState.Loading -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.onyx)
                }
                is HistoryUiState.SignedOut -> RdEmptyState(
                    icon = Icons.Filled.History,
                    title = stringResource(RdR.string.rd_oturum_yok),
                    subtitle = stringResource(RdR.string.rd_gecmis_analiz_giris),
                )
                is HistoryUiState.Failed -> RdEmptyState(
                    icon = Icons.Filled.History,
                    title = stringResource(RdR.string.rd_gecmis_yuklenemedi),
                    subtitle = current.error.message,
                )
                is HistoryUiState.Loaded -> {
                    if (current.items.isEmpty()) {
                        RdEmptyState(
                            icon = Icons.Filled.History,
                            title = stringResource(RdR.string.rd_henuz_analiz_yok),
                            subtitle = stringResource(RdR.string.rd_ilk_fotograf_analiz_aciklama),
                        )
                    } else {
                        val needle = search.trim().lowercase()
                        val filtered = current.items.filter { item ->
                            val matchesFocused = focusedAnalysisId == null || item.id == focusedAnalysisId
                            val matchesSearch = needle.isEmpty() ||
                                item.title.lowercase().contains(needle) ||
                                item.kind.lowercase().contains(needle)
                            val matchesCompany = selectedCompany == null || item.companyId == selectedCompany?.id
                            matchesFocused && matchesSearch && matchesChip(item, activeChip) && matchesCompany
                        }

                        HistoryFilterSurface(
                            showCompanyButton = userTier.isPaid,
                            companySelected = selectedCompany != null,
                            onCompanyButtonClick = { showCompanyFilter = true },
                            search = search,
                            onSearchChange = { search = it },
                            activeChip = activeChip,
                            onChipSelect = { activeChip = it },
                        )
                        Spacer(Modifier.height(RdSpacing.sm))

                        if (filtered.isEmpty()) {
                            RdEmptyState(
                                icon = Icons.Filled.History,
                                title = stringResource(RdR.string.rd_analiz_bulunamadi),
                                subtitle = stringResource(RdR.string.rd_analiz_filtre_bos_aciklama),
                            )
                        } else {
                        LazyColumn(
                            modifier = Modifier.padding(top = RdSpacing.sm),
                            verticalArrangement = Arrangement.spacedBy(RdSpacing.xs),
                        ) {
                            items(filtered, key = { it.id }) { item ->
                                HistoryRow(
                                    item = item,
                                    onOpen = { onOpenAnalysis?.invoke(item.id) },
                                    isGenerating = generatingId == item.id,
                                    isGeneratingPdf = generatingPdfId == item.id,
                                    isDeleting = deletingId == item.id,
                                    onGenerateReport = { viewModel.generateReport(item) },
                                    onGeneratePdf = { viewModel.generatePdfReport(item) },
                                    onDelete = { itemPendingDelete = item },
                                )
                            }
                        }
                        }
                    }
                }
            }
        }
    }

    reportError?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearReportError,
            title = { Text(error.title) },
            text = { Text(error.message) },
            confirmButton = {
                TextButton(onClick = viewModel::clearReportError) { Text(stringResource(RdR.string.rd_tamam)) }
            },
        )
    }

    itemPendingDelete?.let { item ->
        AlertDialog(
            onDismissRequest = { itemPendingDelete = null },
            title = { Text(stringResource(RdR.string.rd_analizi_sil)) },
            text = { Text(stringResource(RdR.string.rd_bu_analiz_ve_ona_ait_fotograf_rapor_dosyalari_kalici_ol)) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteAnalysis(item)
                    itemPendingDelete = null
                }) { Text(stringResource(RdR.string.rd_sil)) }
            },
            dismissButton = {
                TextButton(onClick = { itemPendingDelete = null }) { Text(stringResource(RdR.string.rd_vazgec)) }
            },
        )
    }

    deleteError?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearDeleteError,
            title = { Text(error.title) },
            text = { Text(error.message) },
            confirmButton = {
                TextButton(onClick = viewModel::clearDeleteError) { Text(stringResource(RdR.string.rd_tamam)) }
            },
        )
    }

    if (showCompanyFilter) {
        val sheetState = rememberModalBottomSheetState()
        ModalBottomSheet(onDismissRequest = { showCompanyFilter = false }, sheetState = sheetState) {
            CompanyFilterSheet(
                companies = companies,
                selected = selectedCompany,
                onSelect = { company ->
                    viewModel.setCompanyFilter(company)
                    showCompanyFilter = false
                },
            )
        }
    }
}

@Composable
private fun CompanyFilterSheet(
    companies: List<Company>,
    selected: Company?,
    onSelect: (Company?) -> Unit,
) {
    val colors = RdTheme.colors
    Column(modifier = Modifier.fillMaxWidth().padding(RdSpacing.lg)) {
        Text(stringResource(RdR.string.rd_analiz_firma_filtresi), style = RdFontStyle.Title3.toTextStyle(), color = colors.black)
        Spacer(Modifier.height(RdSpacing.sm))
        RdListRow(
            title = stringResource(RdR.string.rd_tumu),
            onClick = { onSelect(null) },
            trailing = if (selected == null) {
                { Icon(Icons.Filled.Check, contentDescription = null, tint = colors.green) }
            } else {
                null
            },
        )
        companies.forEach { company ->
            RdListRow(
                title = company.name,
                onClick = { onSelect(company) },
                trailing = if (selected?.id == company.id) {
                    { Icon(Icons.Filled.Check, contentDescription = null, tint = colors.green) }
                } else {
                    null
                },
            )
        }
        Spacer(Modifier.height(RdSpacing.lg))
    }
}

@Composable
private fun HistoryFilterSurface(
    showCompanyButton: Boolean,
    companySelected: Boolean,
    onCompanyButtonClick: () -> Unit,
    search: String,
    onSearchChange: (String) -> Unit,
    activeChip: HistoryFilterChip,
    onChipSelect: (HistoryFilterChip) -> Unit,
) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(colors.white)
            .padding(RdSpacing.sm),
        verticalArrangement = Arrangement.spacedBy(RdSpacing.sm),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .height(40.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(colors.fog)
                    .padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Search, contentDescription = null, tint = colors.slate, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(8.dp))
                Box(modifier = Modifier.fillMaxWidth()) {
                    if (search.isEmpty()) {
                        Text(stringResource(RdR.string.rd_analiz_ara), style = RdFontStyle.Callout.toTextStyle(), color = colors.slate)
                    }
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
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (companySelected) colors.greenSoft else colors.fog)
                        .clickable(onClick = onCompanyButtonClick),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.Business,
                        contentDescription = stringResource(RdR.string.rd_firma_filtresi),
                        tint = if (companySelected) colors.greenDark else colors.black,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
        }

        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(HistoryFilterChip.entries) { chip ->
                val active = chip == activeChip
                Box(
                    modifier = Modifier
                        .height(32.dp)
                        .clip(CircleShape)
                        .background(if (active) colors.selected else colors.fog)
                        .clickable { onChipSelect(chip) }
                        .padding(horizontal = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        stringResource(chip.labelRes),
                        style = RdFontStyle.Caption.toTextStyle(),
                        color = if (active) colors.white else colors.charcoal,
                    )
                }
            }
        }
    }
}

@Composable
private fun HistoryRow(
    item: HistoryItem,
    onOpen: () -> Unit,
    isGenerating: Boolean,
    isGeneratingPdf: Boolean,
    isDeleting: Boolean,
    onGenerateReport: () -> Unit,
    onGeneratePdf: () -> Unit,
    onDelete: () -> Unit,
) {
    val colors = RdTheme.colors
    val level = riskLevelFromRaw(item.riskBand)
    val statusLabel = if (item.historyStatus == "reviewed") {
        stringResource(RdR.string.rd_incelendi)
    } else {
        stringResource(RdR.string.rd_acik)
    }
    RdListRow(
        title = item.title,
        subtitle = stringResource(RdR.string.rd_bulgu_durum_format, item.findingCount, statusLabel),
        onClick = onOpen,
        trailing = {
            Column(horizontalAlignment = Alignment.End) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RdRiskChip(level = level)
                    if (isDeleting) {
                        CircularProgressIndicator(
                            color = colors.critical,
                            modifier = Modifier.size(16.dp).padding(start = RdSpacing.xs),
                        )
                    } else {
                        IconButton(onClick = onDelete, modifier = Modifier.size(28.dp)) {
                            Icon(
                                Icons.Filled.DeleteOutline,
                                contentDescription = stringResource(RdR.string.rd_analizi_sil),
                                tint = colors.critical,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                    }
                }
                // Report generation needs a completed, AI-scored analysis to read findings/photos
                // from — matches the edge function's own `analysis_not_completed`-style rejection
                // for non-terminal analyses (see generate-excel-report/index.ts and
                // register-report/index.ts, both real-checked, not assumed to be the same).
                if (item.status == "completed") {
                    Row {
                        if (isGeneratingPdf) {
                            Text(stringResource(RdR.string.rd_pdf), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                        } else {
                            TextButton(onClick = onGeneratePdf, enabled = !isGenerating) {
                                Text(stringResource(RdR.string.rd_pdf_olustur), style = RdFontStyle.Caption.toTextStyle())
                            }
                        }
                        if (isGenerating) {
                            Text(stringResource(RdR.string.rd_olusturuluyor), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                        } else {
                            TextButton(onClick = onGenerateReport, enabled = !isGeneratingPdf) {
                                Text(stringResource(RdR.string.rd_excel_olustur), style = RdFontStyle.Caption.toTextStyle())
                            }
                        }
                    }
                }
            }
        },
    )
}
