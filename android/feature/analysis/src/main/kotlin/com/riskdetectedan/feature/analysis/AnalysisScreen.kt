package com.riskdetectedan.feature.analysis

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.graphics.BitmapFactory
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
import androidx.compose.foundation.layout.size
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
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.Warehouse
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.foundation.Image
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.analysis.AnalysisCanvas
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.AnalysisResultSummary
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FindingMeasure
import com.riskdetectedan.core.data.analysis.FindingPatch
import com.riskdetectedan.core.data.analysis.FineKinneyValues
import com.riskdetectedan.core.data.analysis.PlanCapabilities
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.designsystem.RdCard
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdRiskChip
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.RiskLevel
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
    resume: Boolean = false,
    completedAnalysisId: String? = null,
    preSelectedSectorId: String? = null,
    onBack: (() -> Unit)? = null,
    onOpenCompanies: () -> Unit = {},
    onUpgrade: () -> Unit = {},
    onUpgradeTier: (SubscriptionTier) -> Unit = { onUpgrade() },
    viewModel: AnalysisViewModel = hiltViewModel(),
    reportViewModel: ResultReportViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val capabilities by viewModel.capabilities.collectAsState()
    val resultSummary by viewModel.resultSummary.collectAsState()
    val resultPhotoBytes by viewModel.resultPhotoBytes.collectAsState()
    val reportState by reportViewModel.state.collectAsState()
    val preSelectedSector = remember(preSelectedSectorId) { preSelectedSectorId?.let(AnalysisSector::fromId) }
    var selectedSector by remember { mutableStateOf(preSelectedSector) }

    // Real port of resumeInFlightAnalysisIfNeeded's trigger (Home-driven on iOS; here the caller
    // navigates straight into this screen with resume=true once it's found an in-flight record —
    // see MainShell/HomeScreen's onResumeAnalysis wiring). Runs once per composition entry, not
    // per recomposition — resumeIfInFlight is itself idempotent-safe (a second call just finds no
    // record once the first has consumed/cleared it), but there's no reason to call it twice.
    LaunchedEffect(resume, preSelectedSector, completedAnalysisId) {
        if (completedAnalysisId != null) {
            viewModel.openCompletedAnalysis(completedAnalysisId)
            return@LaunchedEffect
        }
        // Always reconcile the persisted in-flight record before creating anything. This matters
        // when Android restores the Analysis navigation entry after process death: the route still
        // contains the original photos/sector, but the server-side analysis may already be queued.
        // Resuming first prevents that restored route from creating a second analysis row.
        val resumedInFlight = viewModel.resumeIfInFlight()
        if (
            !resumedInFlight &&
            preSelectedSector != null &&
            !resume &&
            state is CreateAnalysisUiState.Idle
        ) {
            viewModel.createAnalysis(preSelectedSector, photoPaths, canvasIds, analysisMode)
        }
    }

    val completed = state as? CreateAnalysisUiState.Completed
    if (completed != null) {
        val findings by viewModel.findings.collectAsState()
        val deleteError by viewModel.deleteError.collectAsState()
        val updateError by viewModel.updateError.collectAsState()
        IosParityResultView(
            analysisId = completed.analysisId,
            findings = findings,
            summary = resultSummary,
            photoBytes = resultPhotoBytes,
            capabilities = capabilities,
            reportState = reportState,
            onGenerateReport = reportViewModel::generate,
            onReportFileConsumed = reportViewModel::clearReadyFile,
            onReportErrorDismiss = reportViewModel::clearError,
            onBack = onBack,
            onDelete = { finding -> viewModel.deleteFinding(completed.analysisId, finding) },
            onUpdate = { finding, patch -> viewModel.updateFinding(completed.analysisId, finding, patch) },
            onOpenCompanies = onOpenCompanies,
            onUpgradeTier = onUpgradeTier,
        )
        deleteError?.let { error ->
            AlertDialog(
                onDismissRequest = viewModel::clearDeleteError,
                title = { Text(stringResource(RdR.string.rd_bulgu_silinemedi)) },
                text = { Text(error.message) },
                confirmButton = {
                    TextButton(onClick = viewModel::clearDeleteError) { Text(stringResource(RdR.string.rd_tamam)) }
                },
            )
        }
        updateError?.let { error ->
            AlertDialog(
                onDismissRequest = viewModel::clearUpdateError,
                title = { Text(stringResource(RdR.string.rd_bulgu_kaydedilemedi)) },
                text = { Text(error.message) },
                confirmButton = {
                    TextButton(onClick = viewModel::clearUpdateError) { Text(stringResource(RdR.string.rd_tamam)) }
                },
            )
        }
        return
    }

    if (
        state is CreateAnalysisUiState.Creating ||
        state is CreateAnalysisUiState.UploadingPhoto ||
        state is CreateAnalysisUiState.Submitting ||
        state is CreateAnalysisUiState.Polling ||
        state is CreateAnalysisUiState.Finalizing
    ) {
        IosParityAnalyzingView(
            state = state,
            previewPhotoPath = photoPaths.firstOrNull(),
            previewPhotoBytes = resultPhotoBytes.firstOrNull(),
            photoCount = photoPaths.size,
        )
        return
    }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(
            title = stringResource(if (resume) RdR.string.rd_analiz_devam_ediyor else RdR.string.rd_yeni_analiz),
            onBack = onBack,
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RdSpacing.lg),
        ) {
            // Resume mode skips the sector picker entirely — there's no new analysis to
            // configure, this screen is just re-showing progress for one the server is already
            // working on (real port of resumeAnalysis's straight-to-polling behavior). A
            // pre-selected sector (real Home-embedded SectorPickerSheet path) also skips this —
            // the LaunchedEffect above already kicked off createAnalysis with it.
            if (
                !resume &&
                completedAnalysisId == null &&
                preSelectedSector == null &&
                (state is CreateAnalysisUiState.Idle ||
                    state is CreateAnalysisUiState.Failed ||
                    state is CreateAnalysisUiState.CreatedWithoutPhoto)
            ) {
                if (photoPaths.isNotEmpty()) {
                    Text(
                        if (photoPaths.size == 1) {
                            stringResource(RdR.string.rd_tek_fotograf_hazir)
                        } else {
                            stringResource(RdR.string.rd_coklu_fotograf_hazir_format, photoPaths.size)
                        },
                        style = RdFontStyle.Footnote.toTextStyle(),
                        color = colors.slate,
                        modifier = Modifier.padding(bottom = RdSpacing.sm),
                    )
                }
                Text(stringResource(RdR.string.rd_sektor_sec), style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx)
                Column(
                    modifier = Modifier.padding(top = RdSpacing.sm, bottom = RdSpacing.md),
                    verticalArrangement = Arrangement.spacedBy(RdSpacing.xs),
                ) {
                    AnalysisSector.entries.forEach { sector ->
                        RdCard(
                            title = analysisSectorTitle(sector),
                            icon = analysisSectorIcon(sector),
                            selected = selectedSector == sector,
                            onClick = {
                                selectedSector = sector
                                viewModel.createAnalysis(sector, photoPaths, canvasIds, analysisMode)
                            },
                        )
                    }
                }
            }

            when (val current = state) {
                is CreateAnalysisUiState.Idle -> Unit
                is CreateAnalysisUiState.Creating -> LabeledProgress(stringResource(RdR.string.rd_analiz_kaydi_olusturuluyor))
                is CreateAnalysisUiState.UploadingPhoto -> LabeledProgress(stringResource(RdR.string.rd_fotograf_yukleniyor))
                is CreateAnalysisUiState.Submitting -> LabeledProgress(stringResource(RdR.string.rd_analiz_gonderiliyor))
                is CreateAnalysisUiState.Polling -> LabeledProgress(stringResource(RdR.string.rd_ai_analiz_ediyor))
                is CreateAnalysisUiState.Finalizing -> LabeledProgress(stringResource(RdR.string.rd_sonuc_hazirlaniyor))
                is CreateAnalysisUiState.Completed -> Unit // handled above, returns early
                is CreateAnalysisUiState.CreatedWithoutPhoto ->
                    Text(
                        stringResource(RdR.string.rd_fotografsiz_analiz_format, current.analysisId),
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
private fun analysisSectorTitle(sector: AnalysisSector): String = stringResource(
    when (sector) {
        AnalysisSector.General -> RdR.string.rd_genel
        AnalysisSector.Construction -> RdR.string.rd_sector_construction
        AnalysisSector.Manufacturing -> RdR.string.rd_sector_manufacturing
        AnalysisSector.Mining -> RdR.string.rd_sector_mining
        AnalysisSector.Energy -> RdR.string.rd_sector_energy
        AnalysisSector.Office -> RdR.string.rd_sector_office
        AnalysisSector.LogisticsWarehouse -> RdR.string.rd_sector_logistics
        AnalysisSector.ChemicalLaboratory -> RdR.string.rd_sector_chemical
        AnalysisSector.Healthcare -> RdR.string.rd_sector_healthcare
        AnalysisSector.FoodProduction -> RdR.string.rd_sector_food
        AnalysisSector.AgricultureLivestock -> RdR.string.rd_sector_agriculture
        AnalysisSector.Retail -> RdR.string.rd_sector_retail
        AnalysisSector.MunicipalFieldServices -> RdR.string.rd_sector_municipal
        AnalysisSector.Education -> RdR.string.rd_sector_education
        AnalysisSector.Hospitality -> RdR.string.rd_sector_hospitality
    },
)

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
    summary: AnalysisResultSummary?,
    photoBytes: List<ByteArray>,
    capabilities: PlanCapabilities,
    onBack: (() -> Unit)?,
    canEdit: Boolean,
    onDelete: (Finding) -> Unit,
    onUpdate: (Finding, FindingPatch) -> Unit,
    onOpenReports: () -> Unit,
    onOpenCompanies: () -> Unit,
    onUpgrade: () -> Unit,
) {
    val colors = RdTheme.colors
    var method by remember { mutableStateOf(ResultRiskMethod.FineKinney) }
    val sortedFindings = remember(findings, method) {
        findings.sortedWith(
            compareByDescending<Finding> { riskRank(resultRiskLevel(it, method)) }
                .thenByDescending { resultScore(it, method) }
                .thenByDescending { it.confidence },
        )
    }
    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = stringResource(RdR.string.rd_analiz_sonuclari), onBack = onBack)

        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(horizontal = RdSpacing.lg),
            verticalArrangement = Arrangement.spacedBy(RdSpacing.sm),
        ) {
            item {
                ResultMetaCard(
                    summary = summary,
                    photoBytes = photoBytes,
                    findings = findings,
                    capabilities = capabilities,
                    onUpgrade = onUpgrade,
                )
            }
            item {
                ResultMethodSelector(method = method, onSelect = { method = it })
            }
            item {
                ResultDistributionCard(findings = findings, method = method)
            }

            if (findings.isEmpty()) {
                item {
                    RdEmptyState(
                        icon = Icons.Filled.VerifiedUser,
                        title = stringResource(RdR.string.rd_tehlike_tespit_edilmedi),
                        subtitle = stringResource(RdR.string.rd_tehlike_tespit_edilmedi_aciklama),
                    )
                }
            } else {
                item {
                    Text(
                        stringResource(RdR.string.rd_tespit_tehlikeler_risk),
                        style = RdFontStyle.Caption.toTextStyle(),
                        color = colors.slate,
                        modifier = Modifier.padding(start = RdSpacing.xxs, top = RdSpacing.xs),
                    )
                }
                items(sortedFindings, key = { it.id }) { finding ->
                    FindingRow(finding, method, canEdit, onDelete, onUpdate)
                }
            }

            item {
                Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.xs)) {
                    Button(onClick = onOpenReports, modifier = Modifier.fillMaxWidth().height(56.dp)) {
                        Text(stringResource(RdR.string.rd_rapor_olustur), style = RdFontStyle.Title3.toTextStyle())
                    }
                    TextButton(onClick = onOpenCompanies, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(RdR.string.rd_sirket_bilgilerini_yonet))
                    }
                    Spacer(Modifier.height(84.dp))
                }
            }
        }
    }
}

private enum class ResultRiskMethod { FineKinney, Matrix5x5 }

private fun resultRiskLevel(finding: Finding, method: ResultRiskMethod): RiskLevel = riskLevelFromRaw(
    if (method == ResultRiskMethod.FineKinney) finding.fkBand else finding.m5Band,
)

private fun resultScore(finding: Finding, method: ResultRiskMethod): Double = when (method) {
    ResultRiskMethod.FineKinney -> finding.fkScore ?: 0.0
    ResultRiskMethod.Matrix5x5 -> finding.m5Score?.toDouble() ?: 0.0
}

private fun riskRank(level: RiskLevel): Int = when (level) {
    RiskLevel.Critical -> 4
    RiskLevel.High -> 3
    RiskLevel.Medium -> 2
    RiskLevel.Low -> 1
    RiskLevel.Unknown -> 0
}

@Composable
private fun ResultMetaCard(
    summary: AnalysisResultSummary?,
    photoBytes: List<ByteArray>,
    findings: List<Finding>,
    capabilities: PlanCapabilities,
    onUpgrade: () -> Unit,
) {
    val colors = RdTheme.colors
    val averageConfidence = if (findings.isEmpty()) 0 else (findings.map(Finding::confidence).average() * 100).toInt()
    val sector = summary?.analysisSector?.let(AnalysisSector::fromId)?.let { analysisSectorTitle(it) }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.white)
            .border(1.dp, colors.onyx.copy(alpha = 0.06f), RoundedCornerShape(RdRadius.lg))
            .padding(RdSpacing.md),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
            if (photoBytes.isEmpty()) {
                Box(
                    modifier = Modifier.size(88.dp).clip(RoundedCornerShape(14.dp)).background(colors.fog),
                    contentAlignment = Alignment.Center,
                ) {
                    androidx.compose.material3.Icon(Icons.Filled.PhotoLibrary, contentDescription = null, tint = colors.slate)
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    photoBytes.take(3).forEach { bytes ->
                        val bitmap = remember(bytes) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }
                        if (bitmap != null) {
                            Image(
                                bitmap = bitmap,
                                contentDescription = stringResource(RdR.string.rd_kaynak_fotograf),
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.size(if (photoBytes.size == 1) 88.dp else 42.dp)
                                    .clip(RoundedCornerShape(12.dp)),
                            )
                        }
                    }
                }
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(summary?.title ?: stringResource(RdR.string.rd_analiz_sonucu), style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx)
                val canvasLabel = summary?.canvas?.let { canvasId ->
                    AnalysisCanvas.all.firstOrNull { it.id == canvasId }?.title ?: canvasId
                }
                Text(
                    listOfNotNull(summary?.createdAt?.take(16)?.replace('T', ' '), canvasLabel).joinToString(" · "),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                )
                if (sector != null) {
                    Text(stringResource(RdR.string.rd_analiz_kapsami_format, sector), style = RdFontStyle.Caption.toTextStyle(), color = colors.graphite)
                }
                Text(stringResource(RdR.string.rd_bulgu_ai_guveni_format, findings.size, averageConfidence), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }
        }
        if (photoBytes.size > 1) {
            val coverageLabels = mutableListOf<String>()
            for (index in 1..photoBytes.size) {
                val count = findings.count { it.sourcePhotoIndices.ifEmpty { listOf(1) }.contains(index) }
                coverageLabels += stringResource(RdR.string.rd_fotograf_bulgu_coverage_format, index, count)
            }
            val coverage = coverageLabels.joinToString(" · ")
            Text(
                coverage,
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
                modifier = Modifier.padding(top = RdSpacing.xs),
            )
        }
        if (capabilities.tier.name != "Pro") {
            TextButton(onClick = onUpgrade, modifier = Modifier.fillMaxWidth()) {
                Text(
                    stringResource(
                        if (capabilities.tier.name == "Plus") RdR.string.rd_pro_upsell_analiz
                        else RdR.string.rd_plus_upsell_analiz,
                    ),
                )
            }
        }
    }
}

@Composable
private fun ResultMethodSelector(method: ResultRiskMethod, onSelect: (ResultRiskMethod) -> Unit) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(colors.fog).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        ResultRiskMethod.entries.forEach { option ->
            val selected = method == option
            Column(
                modifier = Modifier.weight(1f).clip(RoundedCornerShape(9.dp))
                    .background(if (selected) colors.white else colors.fog)
                    .clickable { onSelect(option) }.padding(vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(stringResource(if (option == ResultRiskMethod.FineKinney) RdR.string.rd_fine_kinney else RdR.string.rd_bes_carp_bes_matris), style = RdFontStyle.Callout.toTextStyle(), color = colors.onyx)
                Text(stringResource(if (option == ResultRiskMethod.FineKinney) RdR.string.rd_fk_formula else RdR.string.rd_matrix_formula), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }
        }
    }
}

@Composable
private fun ResultDistributionCard(findings: List<Finding>, method: ResultRiskMethod) {
    val colors = RdTheme.colors
    val levels = listOf(RiskLevel.Critical, RiskLevel.High, RiskLevel.Medium, RiskLevel.Low)
    val counts = levels.associateWith { level -> findings.count { resultRiskLevel(it, method) == level } }
    val top = findings.maxByOrNull { resultScore(it, method) }
    val topLevel = top?.let { resultRiskLevel(it, method) } ?: RiskLevel.Unknown
    val topScore = top?.let { resultScore(it, method) } ?: 0.0
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(RdRadius.lg)).background(colors.white)
            .border(1.dp, colors.onyx.copy(alpha = 0.06f), RoundedCornerShape(RdRadius.lg)).padding(RdSpacing.md),
    ) {
        Text(stringResource(if (method == ResultRiskMethod.FineKinney) RdR.string.rd_fk_upper else RdR.string.rd_matrix_upper), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
            Column(modifier = Modifier.weight(1f)) {
                Text(topScore.let { if (it % 1.0 == 0.0) it.toInt().toString() else "%.1f".format(it) }, style = RdFontStyle.LargeTitle.toTextStyle(), color = colors.onyx)
                Text(stringResource(RdR.string.rd_en_yuksek_risk), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                RdRiskChip(topLevel)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
                levels.forEach { level ->
                    val count = counts[level] ?: 0
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(modifier = Modifier.width(22.dp).height(50.dp).clip(RoundedCornerShape(4.dp)).background(colors.fog), contentAlignment = Alignment.BottomCenter) {
                            Box(modifier = Modifier.fillMaxWidth().height((count.coerceAtMost(5) * 10).coerceAtLeast(2).dp).background(riskColor(level)))
                        }
                        Text(count.toString(), style = RdFontStyle.Caption.toTextStyle(), color = colors.onyx)
                        Text(riskShortLabel(level), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                    }
                }
            }
        }
    }
}

@Composable
private fun riskColor(level: RiskLevel) = when (level) {
    RiskLevel.Critical -> RdTheme.colors.critical
    RiskLevel.High -> RdTheme.colors.high
    RiskLevel.Medium -> RdTheme.colors.medium
    RiskLevel.Low -> RdTheme.colors.low
    RiskLevel.Unknown -> RdTheme.colors.unknown
}

@Composable
private fun riskShortLabel(level: RiskLevel): String = when (level) {
    RiskLevel.Critical -> stringResource(RdR.string.rd_risk_critical_short)
    RiskLevel.High -> stringResource(RdR.string.rd_risk_high_short)
    RiskLevel.Medium -> stringResource(RdR.string.rd_risk_medium_short)
    RiskLevel.Low -> stringResource(RdR.string.rd_risk_low_short)
    RiskLevel.Unknown -> "—"
}

@Composable
private fun FindingRow(
    finding: Finding,
    method: ResultRiskMethod,
    canEdit: Boolean,
    onDelete: (Finding) -> Unit,
    onUpdate: (Finding, FindingPatch) -> Unit,
) {
    var showConfirm by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }
    var showDetail by remember { mutableStateOf(false) }
    val colors = RdTheme.colors
    val level = resultRiskLevel(finding, method)
    val score = resultScore(finding, method)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.white)
            .border(1.dp, colors.onyx.copy(alpha = 0.06f), RoundedCornerShape(RdRadius.lg))
            .clickable { showDetail = true }
            .padding(RdSpacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                finding.ordinal.toString(),
                style = RdFontStyle.Data.toTextStyle(),
                color = colors.onyx,
                modifier = Modifier.size(25.dp).clip(RoundedCornerShape(8.dp)).background(colors.fog)
                    .padding(top = 5.dp),
            )
            Spacer(Modifier.width(RdSpacing.xs))
            RdRiskChip(level = level)
            Spacer(Modifier.width(RdSpacing.xs))
            Text(finding.title, style = RdFontStyle.Callout.toTextStyle(), color = colors.onyx, modifier = Modifier.weight(1f))
        }
        finding.description?.let {
            Text(it, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate, modifier = Modifier.padding(top = RdSpacing.xxs))
        }
        Text(
            stringResource(
                RdR.string.rd_risk_score_format,
                stringResource(if (method == ResultRiskMethod.FineKinney) RdR.string.rd_fine_kinney else RdR.string.rd_bes_carp_bes_matris),
                if (score % 1.0 == 0.0) score.toInt().toString() else score.toString(),
            ),
            style = RdFontStyle.Caption.toTextStyle(),
            color = colors.slate,
            modifier = Modifier.padding(top = RdSpacing.xs),
        )
        if (finding.needsFieldVerification || finding.sourcePhotoIndices.isNotEmpty()) {
            Row(
                modifier = Modifier.padding(top = RdSpacing.xs),
                horizontalArrangement = Arrangement.spacedBy(RdSpacing.xs),
            ) {
                if (finding.needsFieldVerification) {
                    Text(
                        stringResource(RdR.string.rd_saha_teyidi),
                        style = RdFontStyle.Caption.toTextStyle(),
                        color = colors.slate,
                        modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(colors.fog)
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    )
                }
                if (finding.sourcePhotoIndices.isNotEmpty()) {
                    Text(
                        stringResource(RdR.string.rd_foto_indeks_format, finding.sourcePhotoIndices.joinToString(", ")),
                        style = RdFontStyle.Caption.toTextStyle(),
                        color = colors.slate,
                        modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(colors.fog)
                            .padding(horizontal = 8.dp, vertical = 3.dp),
                    )
                }
            }
        }
        if (canEdit) {
            Row(modifier = Modifier.padding(top = RdSpacing.xs)) {
                TextButton(onClick = { showEdit = true }) { Text(stringResource(RdR.string.rd_duzenle), style = RdFontStyle.Caption.toTextStyle()) }
                TextButton(onClick = { showConfirm = true }) {
                    Text(stringResource(RdR.string.rd_sil), style = RdFontStyle.Caption.toTextStyle(), color = colors.critical)
                }
            }
        }
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text(stringResource(RdR.string.rd_bulguyu_sil)) },
            text = { Text(stringResource(RdR.string.rd_bulgu_silme_onayi_format, finding.title)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showConfirm = false
                        onDelete(finding)
                    },
                ) { Text(stringResource(RdR.string.rd_evet_sil)) }
            },
            dismissButton = {
                TextButton(onClick = { showConfirm = false }) { Text(stringResource(RdR.string.rd_vazgec)) }
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

    if (showDetail) {
        AlertDialog(
            onDismissRequest = { showDetail = false },
            title = { Text(finding.title) },
            text = {
                Column(modifier = Modifier.heightIn(max = 520.dp).verticalScroll(rememberScrollState())) {
                    finding.description?.takeIf(String::isNotBlank)?.let {
                        Text(stringResource(RdR.string.rd_gozlenen_durum), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.onyx)
                        Text(it, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
                    }
                    finding.rootCauseText?.takeIf(String::isNotBlank)?.let {
                        Text(stringResource(RdR.string.rd_kok_neden), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.onyx, modifier = Modifier.padding(top = RdSpacing.sm))
                        Text(it, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
                    }
                    finding.recommendedMeasures.orEmpty().forEach { measure ->
                        Text(measure.title.ifBlank { stringResource(RdR.string.rd_onerilen_tedbir) }, style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.onyx, modifier = Modifier.padding(top = RdSpacing.sm))
                        Text(measure.text, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
                    }
                    finding.referencesText?.takeIf(String::isNotBlank)?.let {
                        Text(stringResource(RdR.string.rd_kaynak_ve_standartlar), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.onyx, modifier = Modifier.padding(top = RdSpacing.sm))
                        Text(it, style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
                    }
                }
            },
            confirmButton = { TextButton(onClick = { showDetail = false }) { Text(stringResource(RdR.string.rd_kapat)) } },
        )
    }
}

/** Text fields plus fk_/m5_ risk-rescoring pickers, matching the full [FindingPatch] shape
 * `FindingsRepository.updateFinding` sends. Both method's numbers stay editable regardless of
 * the profile's preferredMethod — the finding row always carries both fk_* and m5_* columns
 * (see [Finding]'s doc comment), and the existing read-only display already shows both scores. */
@Composable
internal fun FindingEditDialog(finding: Finding, onDismiss: () -> Unit, onSave: (FindingPatch) -> Unit) {
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
        title = { Text(stringResource(RdR.string.rd_bulguyu_duzenle)) },
        text = {
            Column(modifier = Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState())) {
                OutlinedTextField(title, { title = it }, label = { Text(stringResource(RdR.string.rd_baslik)) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(category, { category = it }, label = { Text(stringResource(RdR.string.rd_kategori)) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    description,
                    { description = it },
                    label = { Text(stringResource(RdR.string.rd_aciklama)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    recommendedAction,
                    { recommendedAction = it },
                    label = { Text(stringResource(RdR.string.rd_onerilen_aksiyon)) },
                    modifier = Modifier.fillMaxWidth(),
                )

                Text(stringResource(RdR.string.rd_fine_kinney_olasilik_o), modifier = Modifier.padding(top = RdSpacing.md))
                NumberOptionRow(FineKinneyValues.PROBABILITY, fkProbability) { fkProbability = it }
                Text(stringResource(RdR.string.rd_fine_kinney_frekans_f), modifier = Modifier.padding(top = RdSpacing.sm))
                NumberOptionRow(FineKinneyValues.FREQUENCY, fkFrequency) { fkFrequency = it }
                Text(stringResource(RdR.string.rd_fine_kinney_siddet_s), modifier = Modifier.padding(top = RdSpacing.sm))
                NumberOptionRow(FineKinneyValues.SEVERITY, fkSeverity) { fkSeverity = it }

                Text(stringResource(RdR.string.rd_5x5_matris_olasilik), modifier = Modifier.padding(top = RdSpacing.md))
                NumberOptionRow((1..5).map { it.toDouble() }, m5Probability?.toDouble()) {
                    m5Probability = it.toInt()
                }
                Text(stringResource(RdR.string.rd_5x5_matris_siddet), modifier = Modifier.padding(top = RdSpacing.sm))
                NumberOptionRow((1..5).map { it.toDouble() }, m5Severity?.toDouble()) {
                    m5Severity = it.toInt()
                }

                Text(
                    stringResource(RdR.string.rd_yapilandirilmis_onlemler),
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
                    TextButton(onClick = { measures.add(FindingMeasure()) }) { Text(stringResource(RdR.string.rd_plus_onlem_ekle)) }
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
            ) { Text(stringResource(RdR.string.rd_kaydet)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(RdR.string.rd_vazgec)) }
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
            listOf(
                "corrective" to stringResource(RdR.string.rd_duzeltici),
                "preventive" to stringResource(RdR.string.rd_onleyici),
            ).forEach { (kind, label) ->
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
                stringResource(RdR.string.rd_kaldir_button),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.critical,
                modifier = Modifier.padding(start = RdSpacing.md).clickable(onClick = onRemove),
            )
        }
        OutlinedTextField(
            measure.title,
            { onChange(measure.copy(title = it)) },
            label = { Text(stringResource(RdR.string.rd_baslik)) },
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            measure.text,
            { onChange(measure.copy(text = it)) },
            label = { Text(stringResource(RdR.string.rd_metin)) },
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
