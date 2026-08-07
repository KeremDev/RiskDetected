package com.riskdetectedan.feature.analysis

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
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FindingPatch
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.backgroundColor
import com.riskdetectedan.core.designsystem.color
import com.riskdetectedan.core.designsystem.riskLevelFromRaw

/**
 * Sector picker + full submit flow: create `analyses` row -> upload photo -> call `analyze`
 * -> poll -> fetch+display findings. First real render of AI output, not just a "completed"
 * status string.
 */
@Composable
fun AnalysisScreen(photoPath: String? = null, viewModel: AnalysisViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsState()
    var selectedSector by remember { mutableStateOf<AnalysisSector?>(null) }

    val completed = state as? CreateAnalysisUiState.Completed
    if (completed != null) {
        val findings by viewModel.findings.collectAsState()
        val deleteError by viewModel.deleteError.collectAsState()
        val updateError by viewModel.updateError.collectAsState()
        FindingsList(
            analysisId = completed.analysisId,
            findings = findings,
            onDelete = { finding -> viewModel.deleteFinding(completed.analysisId, finding) },
            onUpdate = { finding, patch -> viewModel.updateFinding(completed.analysisId, finding, patch) },
        )
        deleteError?.let { message ->
            AlertDialog(
                onDismissRequest = viewModel::clearDeleteError,
                title = { Text("Bulgu silinemedi") },
                text = { Text(message) },
                confirmButton = {
                    TextButton(onClick = viewModel::clearDeleteError) { Text("Tamam") }
                },
            )
        }
        updateError?.let { message ->
            AlertDialog(
                onDismissRequest = viewModel::clearUpdateError,
                title = { Text("Bulgu kaydedilemedi") },
                text = { Text(message) },
                confirmButton = {
                    TextButton(onClick = viewModel::clearUpdateError) { Text("Tamam") }
                },
            )
        }
        return
    }

    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        if (photoPath != null) {
            Text("Fotoğraf hazır — sektör seçince analiz başlatılacak")
        }
        Text("Sektör seç")
        LazyColumn(modifier = Modifier.padding(top = RdSpacing.sm)) {
            items(AnalysisSector.entries) { sector ->
                val isSelected = selectedSector == sector
                ListItem(
                    headlineContent = {
                        Text(if (isSelected) "✓ ${sector.titleTr}" else sector.titleTr)
                    },
                    modifier = Modifier.clickable {
                        selectedSector = sector
                        viewModel.createAnalysis(sector, photoPath)
                    },
                )
            }
        }

        when (val current = state) {
            is CreateAnalysisUiState.Idle -> Unit
            is CreateAnalysisUiState.Creating -> LabeledProgress("Analiz kaydı oluşturuluyor...")
            is CreateAnalysisUiState.UploadingPhoto -> LabeledProgress("Fotoğraf yükleniyor...")
            is CreateAnalysisUiState.Submitting -> LabeledProgress("Analiz gönderiliyor...")
            is CreateAnalysisUiState.Polling -> LabeledProgress("AI analiz ediyor...")
            is CreateAnalysisUiState.Completed -> Unit // handled above, returns early
            is CreateAnalysisUiState.CreatedWithoutPhoto ->
                Text("Analiz oluşturuldu (fotoğrafsız): ${current.analysisId}")
            is CreateAnalysisUiState.Failed ->
                Text("Analiz başarısız: ${current.message}")
        }
    }
}

@Composable
private fun FindingsList(
    analysisId: String,
    findings: List<Finding>,
    onDelete: (Finding) -> Unit,
    onUpdate: (Finding, FindingPatch) -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text(
            if (findings.isEmpty()) {
                "Analiz tamamlandı, bulgu bulunamadı."
            } else {
                "${findings.size} bulgu — analiz $analysisId"
            },
        )
        LazyColumn(modifier = Modifier.padding(top = RdSpacing.sm)) {
            items(findings, key = { it.id }) { finding -> FindingRow(finding, onDelete, onUpdate) }
        }
    }
}

@Composable
private fun FindingRow(finding: Finding, onDelete: (Finding) -> Unit, onUpdate: (Finding, FindingPatch) -> Unit) {
    var showConfirm by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }
    val level = riskLevelFromRaw(finding.fkBand)
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
            Text(finding.title)
            finding.description?.let { Text(it) }
            Text("FK: ${finding.fkScore ?: "—"}  ·  M5: ${finding.m5Score ?: "—"}")
            Row {
                Text("Düzenle", modifier = Modifier.clickable { showEdit = true })
                Text("Sil", modifier = Modifier.padding(start = RdSpacing.md).clickable { showConfirm = true })
            }
        }
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text("Bulguyu sil") },
            text = { Text("\"${finding.title}\" bulgusu silinsin mi? Bu işlem geri alınamaz.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showConfirm = false
                        onDelete(finding)
                    },
                ) { Text("Evet, sil") }
            },
            dismissButton = {
                TextButton(onClick = { showConfirm = false }) { Text("Vazgeç") }
            },
        )
    }

    if (showEdit) {
        FindingEditDialog(
            finding = finding,
            onDismiss = { showEdit = false },
            onSave = { patch ->
                showEdit = false
                onUpdate(finding, patch)
            },
        )
    }
}

/** Text-field-only edit surface, matching what [FindingPatch]/`FindingsRepository.updateFinding`
 * actually sends — no fk_/m5_ risk-rescoring controls (see those doc comments for why). */
@Composable
private fun FindingEditDialog(finding: Finding, onDismiss: () -> Unit, onSave: (FindingPatch) -> Unit) {
    var title by remember { mutableStateOf(finding.title) }
    var category by remember { mutableStateOf(finding.category ?: "") }
    var description by remember { mutableStateOf(finding.description ?: "") }
    var recommendedAction by remember { mutableStateOf(finding.recommendedAction ?: "") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Bulguyu düzenle") },
        text = {
            Column {
                OutlinedTextField(title, { title = it }, label = { Text("Başlık") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(category, { category = it }, label = { Text("Kategori") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    description,
                    { description = it },
                    label = { Text("Açıklama") },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    recommendedAction,
                    { recommendedAction = it },
                    label = { Text("Önerilen aksiyon") },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    onSave(
                        FindingPatch(
                            title = title,
                            category = category,
                            description = description,
                            recommendedAction = recommendedAction,
                        ),
                    )
                },
            ) { Text("Kaydet") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Vazgeç") }
        },
    )
}

@Composable
private fun LabeledProgress(label: String) {
    Column {
        CircularProgressIndicator()
        Text(label)
    }
}
