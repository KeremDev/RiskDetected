package com.riskdetectedan.feature.analysis

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Agriculture
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Construction
import androidx.compose.material.icons.filled.Factory
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.SecurityUpdateWarning
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.Warehouse
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FindingMeasure
import com.riskdetectedan.core.data.analysis.FindingPatch
import com.riskdetectedan.core.data.analysis.FineKinneyValues
import com.riskdetectedan.core.designsystem.RdCard
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdRiskChip
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.riskLevelFromRaw
import com.riskdetectedan.core.designsystem.toTextStyle

/**
 * Sector picker + full submit flow: create `analyses` row -> upload photo -> call `analyze`
 * -> poll -> fetch+display findings (2026-08-08 visual pass, Faz I of the core-flow redesign).
 * All ViewModel/state logic is unchanged — pure UI-layer pass over the real findings CRUD flow.
 *
 * Sector picker reuses [RdCard] (core:designsystem, built for onboarding's Certificate/Hazard
 * pickers but a genuinely shared component — not feature-scoped) rather than a bare `ListItem`
 * list, same selection-indicator language as onboarding. Findings render as real cards
 * ([RdRiskChip] + title/description/scores), replacing the plain colored-text-label rows. Dialog
 * chip pickers (Fine-Kinney/5x5/measure-kind) now use the app's real onyx/fog token pair instead
 * of `MaterialTheme.colorScheme.primaryContainer` (a real inconsistency this pass fixes — that
 * default Material color was never part of the app's actual design system).
 */
@Composable
fun AnalysisScreen(
    photoPaths: List<String> = emptyList(),
    canvasIds: List<String> = listOf("general"),
    analysisMode: String = "standard",
    onBack: (() -> Unit)? = null,
    viewModel: AnalysisViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
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
            onBack = onBack,
            onDelete = { finding -> viewModel.deleteFinding(completed.analysisId, finding) },
            onUpdate = { finding, patch -> viewModel.updateFinding(completed.analysisId, finding, patch) },
        )
        deleteError?.let { error ->
            AlertDialog(
                onDismissRequest = viewModel::clearDeleteError,
                title = { Text("Bulgu silinemedi") },
                text = { Text(error.message) },
                confirmButton = {
                    TextButton(onClick = viewModel::clearDeleteError) { Text("Tamam") }
                },
            )
        }
        updateError?.let { error ->
            AlertDialog(
                onDismissRequest = viewModel::clearUpdateError,
                title = { Text("Bulgu kaydedilemedi") },
                text = { Text(error.message) },
                confirmButton = {
                    TextButton(onClick = viewModel::clearUpdateError) { Text("Tamam") }
                },
            )
        }
        return
    }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = "Yeni Analiz", onBack = onBack)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RdSpacing.lg),
        ) {
            if (photoPaths.isNotEmpty()) {
                Text(
                    if (photoPaths.size == 1) {
                        "Fotoğraf hazır — sektör seçince analiz başlatılacak"
                    } else {
                        "${photoPaths.size} fotoğraf hazır — sektör seçince analiz başlatılacak"
                    },
                    style = RdFontStyle.Footnote.toTextStyle(),
                    color = colors.slate,
                    modifier = Modifier.padding(bottom = RdSpacing.sm),
                )
            }
            Text("Sektör seç", style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx)
            Column(
                modifier = Modifier.padding(top = RdSpacing.sm, bottom = RdSpacing.md),
                verticalArrangement = Arrangement.spacedBy(RdSpacing.xs),
            ) {
                AnalysisSector.entries.forEach { sector ->
                    RdCard(
                        title = sector.titleTr,
                        icon = analysisSectorIcon(sector),
                        selected = selectedSector == sector,
                        onClick = {
                            selectedSector = sector
                            viewModel.createAnalysis(sector, photoPaths, canvasIds, analysisMode)
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
                    Text(
                        "Analiz oluşturuldu (fotoğrafsız): ${current.analysisId}",
                        style = RdFontStyle.Footnote.toTextStyle(),
                        color = colors.slate,
                        modifier = Modifier.padding(top = RdSpacing.md),
                    )
                is CreateAnalysisUiState.Failed -> AnalysisErrorCard(current.error)
            }
        }
    }
}

private fun analysisSectorIcon(sector: AnalysisSector): ImageVector = when (sector) {
    AnalysisSector.General -> Icons.Filled.Business
    AnalysisSector.Construction -> Icons.Filled.Construction
    AnalysisSector.Manufacturing -> Icons.Filled.Factory
    AnalysisSector.Mining -> Icons.Filled.Terrain
    AnalysisSector.Energy -> Icons.Filled.Bolt
    AnalysisSector.Office -> Icons.Filled.Business
    AnalysisSector.LogisticsWarehouse -> Icons.Filled.Warehouse
    AnalysisSector.ChemicalLaboratory -> Icons.Filled.Science
    AnalysisSector.Healthcare -> Icons.Filled.LocalHospital
    AnalysisSector.FoodProduction -> Icons.Filled.Restaurant
    AnalysisSector.AgricultureLivestock -> Icons.Filled.Agriculture
    AnalysisSector.Retail -> Icons.Filled.Storefront
    AnalysisSector.MunicipalFieldServices -> Icons.Filled.AccountBalance
    AnalysisSector.Education -> Icons.Filled.School
    AnalysisSector.Hospitality -> Icons.Filled.Hotel
}

@Composable
private fun LabeledProgress(label: String) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator(color = colors.onyx)
        Spacer(Modifier.height(RdSpacing.sm))
        Text(label, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
    }
}

@Composable
private fun AnalysisErrorCard(error: com.riskdetectedan.core.data.error.AppErrorMessage) {
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = RdSpacing.md)
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.criticalBg.copy(alpha = 0.70f))
            .border(1.dp, colors.critical.copy(alpha = 0.22f), RoundedCornerShape(RdRadius.lg))
            .padding(RdSpacing.md),
    ) {
        Text(error.title, style = RdFontStyle.Callout.toTextStyle(), color = colors.criticalText)
        Text(error.message, style = RdFontStyle.Footnote.toTextStyle(), color = colors.criticalText)
        if (error.action.isNotEmpty()) {
            Text(error.action, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
        }
        Text(error.supportID, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
    }
}

@Composable
private fun FindingsList(
    analysisId: String,
    findings: List<Finding>,
    onBack: (() -> Unit)?,
    onDelete: (Finding) -> Unit,
    onUpdate: (Finding, FindingPatch) -> Unit,
) {
    val colors = RdTheme.colors
    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = "Analiz Sonuçları", onBack = onBack)

        Column(modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.lg)) {
            if (findings.isEmpty()) {
                RdEmptyState(
                    icon = Icons.Filled.SecurityUpdateWarning,
                    title = "Bulgu bulunamadı",
                    subtitle = "Analiz tamamlandı, herhangi bir tehlike tespit edilmedi.",
                )
            } else {
                Text(
                    "${findings.size} bulgu",
                    style = RdFontStyle.Footnote.toTextStyle(),
                    color = colors.slate,
                    modifier = Modifier.padding(vertical = RdSpacing.sm),
                )
                LazyColumn(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                    items(findings, key = { it.id }) { finding -> FindingRow(finding, onDelete, onUpdate) }
                }
            }
        }
    }
}

@Composable
private fun FindingRow(finding: Finding, onDelete: (Finding) -> Unit, onUpdate: (Finding, FindingPatch) -> Unit) {
    var showConfirm by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }
    val colors = RdTheme.colors
    val level = riskLevelFromRaw(finding.fkBand)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.white)
            .border(1.dp, colors.onyx.copy(alpha = 0.06f), RoundedCornerShape(RdRadius.lg))
            .padding(RdSpacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            RdRiskChip(level = level)
            Spacer(Modifier.width(RdSpacing.xs))
            Text(finding.title, style = RdFontStyle.Callout.toTextStyle(), color = colors.onyx, modifier = Modifier.weight(1f))
        }
        finding.description?.let {
            Text(it, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate, modifier = Modifier.padding(top = RdSpacing.xxs))
        }
        Text(
            "FK: ${finding.fkScore ?: "—"}  ·  M5: ${finding.m5Score ?: "—"}",
            style = RdFontStyle.Caption.toTextStyle(),
            color = colors.slate,
            modifier = Modifier.padding(top = RdSpacing.xs),
        )
        Row(modifier = Modifier.padding(top = RdSpacing.xs)) {
            TextButton(onClick = { showEdit = true }) { Text("Düzenle", style = RdFontStyle.Caption.toTextStyle()) }
            TextButton(onClick = { showConfirm = true }) {
                Text("Sil", style = RdFontStyle.Caption.toTextStyle(), color = colors.critical)
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
 * no free-text entry here on purpose, an out-of-set value is guaranteed a server 400. Uses the
 * app's real onyx/fog token pair (was `MaterialTheme.colorScheme.primaryContainer`, a stray
 * default-Material color never part of the actual design system — fixed in this pass). */
@Composable
private fun NumberOptionRow(options: List<Double>, selected: Double?, onSelect: (Double) -> Unit) {
    val colors = RdTheme.colors
    Row(modifier = Modifier.horizontalScroll(rememberScrollState())) {
        options.forEach { value ->
            val label = if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()
            val isSelected = selected == value
            Text(
                text = label,
                color = if (isSelected) colors.white else colors.onyx,
                style = RdFontStyle.Caption.toTextStyle(),
                modifier = Modifier
                    .padding(end = RdSpacing.xs)
                    .clip(RoundedCornerShape(RdRadius.xs))
                    .background(if (isSelected) colors.onyx else colors.fog)
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
    val colors = RdTheme.colors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = RdSpacing.xs)
            .clip(RoundedCornerShape(RdRadius.xs))
            .background(colors.fog)
            .padding(RdSpacing.sm),
    ) {
        Row {
            listOf("corrective" to "Düzeltici", "preventive" to "Önleyici").forEach { (kind, label) ->
                val isSelected = measure.kind == kind
                Text(
                    text = label,
                    color = if (isSelected) colors.white else colors.onyx,
                    style = RdFontStyle.Caption.toTextStyle(),
                    modifier = Modifier
                        .padding(end = RdSpacing.xs)
                        .clip(RoundedCornerShape(RdRadius.xs))
                        .background(if (isSelected) colors.onyx else colors.white)
                        .clickable { onChange(measure.copy(kind = kind)) }
                        .padding(horizontal = RdSpacing.sm, vertical = RdSpacing.xxs),
                )
            }
            Text(
                "Kaldır",
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.critical,
                modifier = Modifier.padding(start = RdSpacing.md).clickable(onClick = onRemove),
            )
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
