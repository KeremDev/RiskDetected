package com.riskdetectedan.feature.reports

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
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
 * Report generation ("Excel oluştur") behavior and the system-chooser hand-off are unchanged —
 * pure UI-layer pass, same as every other screen in this redesign.
 */
@Composable
fun ReportsScreen(onBack: (() -> Unit)? = null, viewModel: HistoryViewModel = hiltViewModel()) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val generatingId by viewModel.generatingReportForId.collectAsState()
    val reportError by viewModel.reportError.collectAsState()
    val reportFile by viewModel.reportFile.collectAsState()
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
                                    onGenerateReport = { viewModel.generateReport(item) },
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
}

@Composable
private fun HistoryRow(item: HistoryItem, isGenerating: Boolean, onGenerateReport: () -> Unit) {
    val colors = RdTheme.colors
    val level = riskLevelFromRaw(item.riskBand)
    RdListRow(
        title = item.title,
        subtitle = "${item.findingCount} bulgu · ${item.historyStatus}",
        trailing = {
            Column(horizontalAlignment = Alignment.End) {
                RdRiskChip(level = level)
                // Report generation needs a completed, AI-scored analysis to read findings/photos
                // from — matches the edge function's own `analysis_not_completed`-style rejection
                // for non-terminal analyses (see generate-excel-report/index.ts).
                if (item.status == "completed") {
                    if (isGenerating) {
                        Text("Oluşturuluyor...", style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                    } else {
                        TextButton(onClick = onGenerateReport) {
                            Text("Excel oluştur", style = RdFontStyle.Caption.toTextStyle())
                        }
                    }
                }
            }
        },
    )
}
