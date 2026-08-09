package com.riskdetectedan.app.reports

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.reports.Report
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdListRow
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import java.io.File
import java.time.OffsetDateTime
import java.time.temporal.WeekFields
import java.util.Locale

/** Mirrors `ReportRow.isExcelReport` (AnalysisService.swift extension). */
private val Report.isExcel: Boolean
    get() = format == "xlsx" || mimeType == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

/** Mirrors `ReportRow.isRiskAnalysisReport`. */
private val Report.isRiskAnalysis: Boolean
    get() = kind == "risk_analysis" || kind == "riskAnalysis"

/** Real port of `ReportView.swift`'s `ReportArchiveFilter` chip row + `reportSearch` — was
 * entirely missing on Android before this (2026-08-09 gap sweep). `riskAnalysis` matching
 * `isRiskAnalysis || isExcel` looks odd in isolation but is intentional on iOS: it mirrors
 * `usesRiskAnalysisTrial` (same predicate, named for what it actually tracks — anything that
 * drew from the risk-analysis trial allowance, which Excel exports do too), not a copy-paste
 * bug to "fix" while porting. `thisWeek` here is a real ISO calendar-week boundary
 * (`Calendar.current.isDate(_:equalTo:toGranularity:.weekOfYear)`) — deliberately different from
 * [com.riskdetectedan.feature.reports.HistoryFilterChip]'s "last 7 days", matching each screen's
 * own iOS source exactly rather than reusing one semantic for both. */
private enum class ReportArchiveFilter(val label: String) {
    All("Tümü"),
    Pdf("PDF"),
    Excel("Excel"),
    Standard("Standart"),
    RiskAnalysis("Risk analizi"),
    ThisWeek("Bu hafta"),
}

private fun isSameIsoWeek(createdAt: String?): Boolean {
    val raw = createdAt ?: return false
    return try {
        val date = OffsetDateTime.parse(raw)
        val now = OffsetDateTime.now()
        val weekFields = WeekFields.of(Locale.getDefault())
        date.get(weekFields.weekBasedYear()) == now.get(weekFields.weekBasedYear()) &&
            date.get(weekFields.weekOfWeekBasedYear()) == now.get(weekFields.weekOfWeekBasedYear())
    } catch (t: Throwable) {
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
    report.title, report.fileName, report.kind, report.method,
    report.format, report.mimeType, report.createdAt,
).joinToString(" ").lowercase()

/**
 * Faz R — real "Raporlar" tab (port of `HomeView.swift`'s `generatedReportsSection`'s data source,
 * as a full tab rather than a Home-embedded card — matches `MainTabView.swift`'s real `.reports`
 * tab being a full screen). Distinct from Analizler's [com.riskdetectedan.feature.reports.ReportsScreen]
 * (that one is the `analyses` history + "Excel oluştur" generation action) — this lists
 * already-generated `reports` rows (`GeneratedReportsViewModel.listReports`) and opens them,
 * mirroring iOS's real tab split. Replaces `MainShell.kt`'s honest stub.
 *
 * Simplified vs iOS's `generatedReportsSection`/`HomeReportRow`: no per-kind tinted icon chip
 * (Excel green vs. PDF red vs. risk-analysis accent) — a single icon keyed off `isExcel`, reusing
 * the same [RdListRow]/[RdEmptyState] structure as every other list screen in this pass, not a
 * hand-painted custom row. Real data/behavior (list, open, error) is not simplified.
 */
@Composable
fun GeneratedReportsScreen(viewModel: GeneratedReportsViewModel = hiltViewModel()) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val openingId by viewModel.openingReportId.collectAsState()
    val reportError by viewModel.reportError.collectAsState()
    val reportFile by viewModel.reportFile.collectAsState()
    val deletingReportId by viewModel.deletingReportId.collectAsState()
    val deleteError by viewModel.deleteError.collectAsState()
    var reportPendingDelete by remember { mutableStateOf<Report?>(null) }
    var search by remember { mutableStateOf("") }
    var activeFilter by remember { mutableStateOf(ReportArchiveFilter.All) }
    val context = LocalContext.current

    LaunchedEffect(reportFile) {
        val file = reportFile ?: return@LaunchedEffect
        val dir = File(context.cacheDir, "reports").apply { mkdirs() }
        val target = File(dir, file.fileName)
        target.writeBytes(file.bytes)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", target)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, file.mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "Raporu aç"))
        viewModel.clearReportFile()
    }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = "Raporlar")

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.lg)) {
            when (val current = state) {
                is GeneratedReportsUiState.Loading -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.onyx)
                }
                is GeneratedReportsUiState.SignedOut -> RdEmptyState(
                    icon = Icons.Filled.Description,
                    title = "Oturum yok",
                    subtitle = "Raporlarını görmek için giriş yapmalısın.",
                )
                is GeneratedReportsUiState.Failed -> RdEmptyState(
                    icon = Icons.Filled.Description,
                    title = "Raporlar yüklenemedi",
                    subtitle = current.error.message,
                )
                is GeneratedReportsUiState.Loaded -> {
                    if (current.items.isEmpty()) {
                        RdEmptyState(
                            icon = Icons.Filled.Description,
                            title = "Henüz rapor yok",
                            subtitle = "Oluşturduğun raporların listesi burada görünecek.",
                        )
                    } else {
                        val needle = search.trim().lowercase()
                        val filtered = current.items.filter { report ->
                            (needle.isEmpty() || reportSearchText(report).contains(needle)) &&
                                matchesReportFilter(report, activeFilter)
                        }

                        ReportArchiveFilterSurface(
                            search = search,
                            onSearchChange = { search = it },
                            activeFilter = activeFilter,
                            onFilterSelect = { activeFilter = it },
                        )
                        Spacer(Modifier.height(RdSpacing.sm))

                        if (filtered.isEmpty()) {
                            RdEmptyState(
                                icon = Icons.Filled.Description,
                                title = "Rapor bulunamadı",
                                subtitle = "Filtreyi değiştir veya farklı bir arama dene.",
                            )
                        } else {
                            LazyColumn(
                                modifier = Modifier.padding(top = RdSpacing.sm),
                                verticalArrangement = Arrangement.spacedBy(RdSpacing.xs),
                            ) {
                                items(filtered, key = { it.id }) { report ->
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
        }
    }

    reportError?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearReportError,
            title = { Text(error.title) },
            text = { Text(error.message) },
            confirmButton = {
                TextButton(onClick = viewModel::clearReportError) { Text("Tamam") }
            },
        )
    }

    reportPendingDelete?.let { report ->
        AlertDialog(
            onDismissRequest = { reportPendingDelete = null },
            title = { Text("Raporu sil") },
            text = { Text("Bu rapor dosyası kalıcı olarak silinecek. Bu işlem geri alınamaz.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteReport(report)
                    reportPendingDelete = null
                }) { Text("Sil") }
            },
            dismissButton = {
                TextButton(onClick = { reportPendingDelete = null }) { Text("Vazgeç") }
            },
        )
    }

    deleteError?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearDeleteError,
            title = { Text(error.title) },
            text = { Text(error.message) },
            confirmButton = {
                TextButton(onClick = viewModel::clearDeleteError) { Text("Tamam") }
            },
        )
    }
}

@Composable
private fun ReportArchiveFilterSurface(
    search: String,
    onSearchChange: (String) -> Unit,
    activeFilter: ReportArchiveFilter,
    onFilterSelect: (ReportArchiveFilter) -> Unit,
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
        Row(
            modifier = Modifier
                .fillMaxWidth()
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
                    Text("Rapor ara", style = RdFontStyle.Callout.toTextStyle(), color = colors.slate)
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

        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(ReportArchiveFilter.entries) { filter ->
                val active = filter == activeFilter
                Box(
                    modifier = Modifier
                        .height(32.dp)
                        .clip(CircleShape)
                        .background(if (active) colors.selected else colors.fog)
                        .clickable { onFilterSelect(filter) }
                        .padding(horizontal = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        filter.label,
                        style = RdFontStyle.Caption.toTextStyle(),
                        color = if (active) colors.white else colors.charcoal,
                    )
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
    val isExcel = report.format == "xlsx" ||
        report.mimeType == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    RdListRow(
        title = report.title ?: report.fileName ?: "Rapor",
        subtitle = report.createdAt?.take(10),
        icon = if (isExcel) Icons.Filled.TableChart else Icons.Filled.Description,
        iconBackground = colors.fog,
        onClick = if (isOpening) null else onClick,
        trailing = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (isOpening) {
                    Text("Açılıyor...", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                }
                if (isDeleting) {
                    CircularProgressIndicator(color = colors.critical, modifier = Modifier.size(16.dp))
                } else {
                    IconButton(onClick = onDelete, modifier = Modifier.size(28.dp)) {
                        Icon(
                            Icons.Filled.DeleteOutline,
                            contentDescription = "Raporu sil",
                            tint = colors.critical,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
        },
    )
}
