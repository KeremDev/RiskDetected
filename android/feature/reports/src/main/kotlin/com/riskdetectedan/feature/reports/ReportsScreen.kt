package com.riskdetectedan.feature.reports

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.History
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdListRow
import com.riskdetectedan.core.designsystem.RdRiskChip
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.riskLevelFromRaw
import com.riskdetectedan.core.designsystem.toTextStyle
import java.io.File

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
@Composable
fun ReportsScreen(onBack: (() -> Unit)? = null, viewModel: HistoryViewModel = hiltViewModel()) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val generatingId by viewModel.generatingReportForId.collectAsState()
    val generatingPdfId by viewModel.generatingPdfForId.collectAsState()
    val reportError by viewModel.reportError.collectAsState()
    val reportFile by viewModel.reportFile.collectAsState()
    val deletingId by viewModel.deletingId.collectAsState()
    val deleteError by viewModel.deleteError.collectAsState()
    var itemPendingDelete by remember { mutableStateOf<HistoryItem?>(null) }
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
        RdScreenHeader(title = "Geçmiş Analizler", onBack = onBack)

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.lg)) {
            when (val current = state) {
                is HistoryUiState.Loading -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.onyx)
                }
                is HistoryUiState.SignedOut -> RdEmptyState(
                    icon = Icons.Filled.History,
                    title = "Oturum yok",
                    subtitle = "Geçmiş analizlerini görmek için giriş yapmalısın.",
                )
                is HistoryUiState.Failed -> RdEmptyState(
                    icon = Icons.Filled.History,
                    title = "Geçmiş yüklenemedi",
                    subtitle = current.error.message,
                )
                is HistoryUiState.Loaded -> {
                    if (current.items.isEmpty()) {
                        RdEmptyState(
                            icon = Icons.Filled.History,
                            title = "Henüz analiz yok",
                            subtitle = "İlk fotoğrafını çekince analizlerin burada listelenecek.",
                        )
                    } else {
                        LazyColumn(
                            modifier = Modifier.padding(top = RdSpacing.sm),
                            verticalArrangement = Arrangement.spacedBy(RdSpacing.xs),
                        ) {
                            items(current.items, key = { it.id }) { item ->
                                HistoryRow(
                                    item = item,
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

    itemPendingDelete?.let { item ->
        AlertDialog(
            onDismissRequest = { itemPendingDelete = null },
            title = { Text("Analizi sil") },
            text = { Text("Bu analiz ve ona ait fotoğraf/rapor dosyaları kalıcı olarak silinecek. Bu işlem geri alınamaz.") },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteAnalysis(item)
                    itemPendingDelete = null
                }) { Text("Sil") }
            },
            dismissButton = {
                TextButton(onClick = { itemPendingDelete = null }) { Text("Vazgeç") }
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
private fun HistoryRow(
    item: HistoryItem,
    isGenerating: Boolean,
    isGeneratingPdf: Boolean,
    isDeleting: Boolean,
    onGenerateReport: () -> Unit,
    onGeneratePdf: () -> Unit,
    onDelete: () -> Unit,
) {
    val colors = RdTheme.colors
    val level = riskLevelFromRaw(item.riskBand)
    RdListRow(
        title = item.title,
        subtitle = "${item.findingCount} bulgu · ${item.historyStatus}",
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
                                contentDescription = "Analizi sil",
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
                            Text("PDF...", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                        } else {
                            TextButton(onClick = onGeneratePdf, enabled = !isGenerating) {
                                Text("PDF oluştur", style = RdFontStyle.Caption.toTextStyle())
                            }
                        }
                        if (isGenerating) {
                            Text("Oluşturuluyor...", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                        } else {
                            TextButton(onClick = onGenerateReport, enabled = !isGeneratingPdf) {
                                Text("Excel oluştur", style = RdFontStyle.Caption.toTextStyle())
                            }
                        }
                    }
                }
            }
        },
    )
}
