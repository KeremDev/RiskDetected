package com.riskdetectedan.feature.reports

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.FileProvider
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.backgroundColor
import com.riskdetectedan.core.designsystem.color
import com.riskdetectedan.core.designsystem.riskLevelFromRaw
import java.io.File

/** Port of the analysis history list (App/Models/HistoryItem.swift's `init(row:)` mapping —
 * not a port of App/Views/History/HistoryView.swift's layout, which wasn't read; this reuses
 * the same functional-list pattern as every other screen built this session). Each completed
 * analysis row now also offers "Excel oluştur" (generate-excel-report), same as iOS's report
 * generation entry point — the actual file is opened via a system chooser rather than an
 * in-app viewer (no XLSX renderer built, this hands off to whatever's installed).
 */
@Composable
fun ReportsScreen(viewModel: HistoryViewModel = hiltViewModel()) {
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

    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Geçmiş analizler")
        when (val current = state) {
            is HistoryUiState.Loading -> CircularProgressIndicator()
            is HistoryUiState.SignedOut -> Text("Oturum yok")
            is HistoryUiState.Failed -> Text("Geçmiş yüklenemedi: ${current.message}")
            is HistoryUiState.Loaded -> {
                if (current.items.isEmpty()) {
                    Text("Henüz analiz yok")
                } else {
                    LazyColumn(modifier = Modifier.padding(top = RdSpacing.sm)) {
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

    if (reportError != null) {
        AlertDialog(
            onDismissRequest = viewModel::clearReportError,
            title = { Text("Rapor oluşturulamadı") },
            text = { Text(reportError ?: "") },
            confirmButton = {
                TextButton(onClick = viewModel::clearReportError) { Text("Tamam") }
            },
        )
    }
}

@Composable
private fun HistoryRow(item: HistoryItem, isGenerating: Boolean, onGenerateReport: () -> Unit) {
    val level = riskLevelFromRaw(item.riskBand)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = RdSpacing.xs),
    ) {
        Text(
            text = level.name,
            modifier = Modifier
                .background(level.backgroundColor(), RoundedCornerShape(RdRadius.xs))
                .padding(horizontal = RdSpacing.xs, vertical = RdSpacing.xxs),
            color = level.color(),
        )
        Column(modifier = Modifier.padding(start = RdSpacing.sm)) {
            Text(item.title)
            Text("${item.findingCount} bulgu · ${item.historyStatus}")
            // Report generation needs a completed, AI-scored analysis to read findings/photos
            // from — matches the edge function's own `analysis_not_completed`-style rejection
            // for non-terminal analyses (see generate-excel-report/index.ts).
            if (item.status == "completed") {
                if (isGenerating) {
                    Text("Rapor oluşturuluyor...")
                } else {
                    Text("Excel oluştur", modifier = Modifier.clickable(onClick = onGenerateReport))
                }
            }
        }
    }
}
