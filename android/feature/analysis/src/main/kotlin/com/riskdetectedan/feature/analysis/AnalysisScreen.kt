package com.riskdetectedan.feature.analysis

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FindingMeasure
import com.riskdetectedan.core.data.analysis.FindingPatch
import com.riskdetectedan.core.data.analysis.FineKinneyValues
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
            is CreateAnalysisUiState.Failed -> Column {
                Text(current.error.title)
                Text(current.error.message)
                if (current.error.action.isNotEmpty()) Text(current.error.action)
                Text(current.error.supportID)
            }
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

/** Text fields plus fk_/m5_ risk-rescoring pickers, matching the full [FindingPatch] shape
 * `FindingsRepository.updateFinding` sends. Both method's numbers stay editable regardless of
 * the profile's preferredMethod — the finding row always carries both fk_* and m5_* columns
 * (see [Finding]'s doc comment), and the existing read-only display already shows both scores. */
@Composable
private fun FindingEditDialog(finding: Finding, onDismiss: () -> Unit, onSave: (FindingPatch) -> Unit) {
    var title by remember { mutableStateOf(finding.title) }
    var category by remember { mutableStateOf(finding.category ?: "") }
    var description by remember { mutableStateOf(finding.description ?: "") }
    var recommendedAction by remember { mutableStateOf(finding.recommendedAction ?: "") }
    var fkProbability by remember { mutableStateOf(finding.fkProbability) }
    var fkFrequency by remember { mutableStateOf(finding.fkFrequency) }
    var fkSeverity by remember { mutableStateOf(finding.fkSeverity) }
    var m5Probability by remember { mutableStateOf(finding.m5Probability) }
    var m5Severity by remember { mutableStateOf(finding.m5Severity) }
    val measures = remember {
        androidx.compose.runtime.mutableStateListOf(*(finding.recommendedMeasures ?: emptyList()).toTypedArray())
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Bulguyu düzenle") },
        text = {
            Column(modifier = Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState())) {
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

                Text("Fine-Kinney — Olasılık (O)", modifier = Modifier.padding(top = RdSpacing.md))
                NumberOptionRow(FineKinneyValues.PROBABILITY, fkProbability) { fkProbability = it }
                Text("Fine-Kinney — Frekans (F)", modifier = Modifier.padding(top = RdSpacing.sm))
                NumberOptionRow(FineKinneyValues.FREQUENCY, fkFrequency) { fkFrequency = it }
                Text("Fine-Kinney — Şiddet (Ş)", modifier = Modifier.padding(top = RdSpacing.sm))
                NumberOptionRow(FineKinneyValues.SEVERITY, fkSeverity) { fkSeverity = it }

                Text("5x5 Matris — Olasılık", modifier = Modifier.padding(top = RdSpacing.md))
                NumberOptionRow((1..5).map { it.toDouble() }, m5Probability?.toDouble()) {
                    m5Probability = it.toInt()
                }
                Text("5x5 Matris — Şiddet", modifier = Modifier.padding(top = RdSpacing.sm))
                NumberOptionRow((1..5).map { it.toDouble() }, m5Severity?.toDouble()) {
                    m5Severity = it.toInt()
                }

                Text(
                    "Yapılandırılmış önlemler (varsa \"Önerilen aksiyon\"ın yerine geçer)",
                    modifier = Modifier.padding(top = RdSpacing.md),
                )
                measures.forEachIndexed { index, measure ->
                    MeasureEditor(
                        measure = measure,
                        onChange = { measures[index] = it },
                        onRemove = { measures.removeAt(index) },
                    )
                }
                if (measures.size < 8) {
                    TextButton(onClick = { measures.add(FindingMeasure()) }) { Text("+ Önlem ekle") }
                }
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
                            recommendedMeasures = measures.ifEmpty { null },
                            fkProbability = fkProbability,
                            fkFrequency = fkFrequency,
                            fkSeverity = fkSeverity,
                            m5Probability = m5Probability,
                            m5Severity = m5Severity,
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

/** A row of tappable chips for a fixed set of allowed numeric values — matches the discrete
 * option sets both Fine-Kinney (6 values each) and the 5x5 matrix (1-5) actually allow; there's
 * no free-text entry here on purpose, an out-of-set value is guaranteed a server 400. */
@Composable
private fun NumberOptionRow(options: List<Double>, selected: Double?, onSelect: (Double) -> Unit) {
    Row(modifier = Modifier.horizontalScroll(rememberScrollState())) {
        options.forEach { value ->
            val label = if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()
            val isSelected = selected == value
            Text(
                text = label,
                modifier = Modifier
                    .padding(end = RdSpacing.xs)
                    .background(
                        if (isSelected) {
                            androidx.compose.material3.MaterialTheme.colorScheme.primaryContainer
                        } else {
                            androidx.compose.ui.graphics.Color.Transparent
                        },
                        RoundedCornerShape(RdRadius.xs),
                    )
                    .clickable { onSelect(value) }
                    .padding(horizontal = RdSpacing.sm, vertical = RdSpacing.xxs),
            )
        }
    }
}

/** One `recommended_measures` entry — kind toggle (corrective/preventive, the only two values
 * the server accepts, everything else coerced to "corrective"), title, text. Mirrors
 * normalizeMeasures()'s 80/900-char limits only insofar as the server will trim silently past
 * them; not enforced client-side (not worth a counter UI for a limit that fails soft). */
@Composable
private fun MeasureEditor(measure: FindingMeasure, onChange: (FindingMeasure) -> Unit, onRemove: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = RdSpacing.xs)
            .background(
                androidx.compose.material3.MaterialTheme.colorScheme.surfaceVariant,
                RoundedCornerShape(RdRadius.xs),
            )
            .padding(RdSpacing.sm),
    ) {
        Row {
            listOf("corrective" to "Düzeltici", "preventive" to "Önleyici").forEach { (kind, label) ->
                val isSelected = measure.kind == kind
                Text(
                    text = label,
                    modifier = Modifier
                        .padding(end = RdSpacing.xs)
                        .background(
                            if (isSelected) {
                                androidx.compose.material3.MaterialTheme.colorScheme.primaryContainer
                            } else {
                                androidx.compose.ui.graphics.Color.Transparent
                            },
                            RoundedCornerShape(RdRadius.xs),
                        )
                        .clickable { onChange(measure.copy(kind = kind)) }
                        .padding(horizontal = RdSpacing.sm, vertical = RdSpacing.xxs),
                )
            }
            Text("Kaldır", modifier = Modifier.padding(start = RdSpacing.md).clickable(onClick = onRemove))
        }
        OutlinedTextField(
            measure.title,
            { onChange(measure.copy(title = it)) },
            label = { Text("Başlık") },
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            measure.text,
            { onChange(measure.copy(text = it)) },
            label = { Text("Metin") },
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun LabeledProgress(label: String) {
    Column {
        CircularProgressIndicator()
        Text(label)
    }
}
