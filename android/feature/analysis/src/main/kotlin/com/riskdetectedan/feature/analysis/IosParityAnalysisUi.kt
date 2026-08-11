package com.riskdetectedan.feature.analysis

import android.content.ClipData
import android.content.Intent
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FactCheck
import androidx.compose.material.icons.filled.FindInPage
import androidx.compose.material.icons.filled.GppGood
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.IosShare
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.riskdetectedan.core.data.analysis.AnalysisCanvas
import com.riskdetectedan.core.data.analysis.AnalysisResultSummary
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FindingPatch
import com.riskdetectedan.core.data.analysis.PlanCapabilities
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.designsystem.R as RdR
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.RiskLevel
import com.riskdetectedan.core.designsystem.backgroundColor
import com.riskdetectedan.core.designsystem.color
import com.riskdetectedan.core.designsystem.rdFontScale
import com.riskdetectedan.core.designsystem.riskLevelFromRaw
import com.riskdetectedan.core.designsystem.toTextStyle
import java.io.File
import java.text.NumberFormat
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

private enum class ParityRiskMethod(val wire: String) { FineKinney("fine_kinney"), Matrix5x5("matrix_5x5") }
private enum class ParityReportKind { Standard, RiskAnalysis }

/**
 * Screen-specific mirror of SwiftUI's `.system(size:weight:design:.rounded)` calls.
 * SF Pro Rounded is not redistributed; the Android system sans family is tuned to the exact
 * iOS point-size curve, tracking and vertical metrics instead.
 */
private fun iosRounded(
    size: Float,
    weight: FontWeight = FontWeight.Normal,
    tracking: Float = 0f,
    lineHeightMultiplier: Float = 1.18f,
): TextStyle {
    val scaled = rdFontScale(size)
    return TextStyle(
        fontSize = scaled.sp,
        lineHeight = (scaled * lineHeightMultiplier).sp,
        fontWeight = weight,
        fontFamily = FontFamily.SansSerif,
        letterSpacing = tracking.sp,
        platformStyle = PlatformTextStyle(includeFontPadding = false),
    )
}

private fun iosMono(
    size: Float,
    weight: FontWeight = FontWeight.Medium,
    tracking: Float = 0f,
): TextStyle {
    val scaled = rdFontScale(size)
    return TextStyle(
        fontSize = scaled.sp,
        lineHeight = (scaled * 1.14f).sp,
        fontWeight = weight,
        // SF Mono is not bundled on Android. Tabular numerals preserve its score/formula
        // rhythm without the visibly wider glyph spacing of Android's default monospace.
        fontFamily = FontFamily.SansSerif,
        fontFeatureSettings = "tnum",
        letterSpacing = tracking.sp,
        platformStyle = PlatformTextStyle(includeFontPadding = false),
    )
}

@Composable
internal fun IosParityAnalyzingView(
    state: CreateAnalysisUiState,
    previewPhotoPath: String?,
    previewPhotoBytes: ByteArray?,
    photoCount: Int,
) {
    val colors = RdTheme.colors
    val target = when (state) {
        is CreateAnalysisUiState.Creating -> .18f
        is CreateAnalysisUiState.UploadingPhoto -> .52f
        is CreateAnalysisUiState.Submitting -> .62f
        is CreateAnalysisUiState.Polling -> .94f
        is CreateAnalysisUiState.Finalizing -> .99f
        else -> .03f
    }
    val progress by animateFloatAsState(target, tween(780, easing = FastOutSlowInEasing), label = "analysisProgress")
    val percent = (progress * 100).toInt().coerceIn(3, 99)
    val bitmap = remember(previewPhotoPath, previewPhotoBytes) {
        previewPhotoPath?.let { runCatching { BitmapFactory.decodeFile(it)?.asImageBitmap() }.getOrNull() }
            ?: previewPhotoBytes?.let { bytes ->
                runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }.getOrNull()
            }
    }
    val transition = rememberInfiniteTransition(label = "analysisMotion")
    val pulse by transition.animateFloat(
        initialValue = .96f,
        targetValue = 1.04f,
        animationSpec = infiniteRepeatable(tween(1250), RepeatMode.Reverse),
        label = "analysisPulseScale",
    )
    val scanPosition by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1550), RepeatMode.Restart),
        label = "analysisScanPosition",
    )

    Box(Modifier.fillMaxSize().background(colors.paper)) {
        Column(
            modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(Modifier.size(296.dp, 286.dp).scale(pulse), contentAlignment = Alignment.Center) {
                Box(
                    Modifier.size(246.dp)
                        .shadow(20.dp, RoundedCornerShape(24.dp), ambientColor = colors.onyx.copy(.12f), spotColor = colors.onyx.copy(.14f))
                        .clip(RoundedCornerShape(24.dp))
                        .background(Brush.linearGradient(listOf(colors.graphite, colors.onyx)))
                        .border(2.dp, colors.green.copy(.75f), RoundedCornerShape(24.dp)),
                ) {
                    if (bitmap != null) {
                        Image(bitmap, null, Modifier.fillMaxSize().blur(7.dp), contentScale = ContentScale.Crop)
                        Box(Modifier.fillMaxSize().background(colors.onyx.copy(.24f)))
                    }
                    Box(
                        Modifier.fillMaxWidth().height(64.dp)
                            .offset(y = (-80 + scanPosition * 342).dp)
                            .background(
                                Brush.verticalGradient(
                                    listOf(Color.Transparent, colors.green.copy(.62f), colors.green.copy(.22f), Color.Transparent),
                                ),
                            ),
                    )

                    Column(
                        Modifier.align(Alignment.Center).width(210.dp)
                            .clip(RoundedCornerShape(22.dp))
                            .background(colors.onyx.copy(.58f))
                            .border(1.dp, colors.white.copy(.14f), RoundedCornerShape(22.dp))
                            .padding(horizontal = 18.dp, vertical = 18.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(9.dp),
                    ) {
                        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text("$percent", style = iosRounded(64f, FontWeight.Black, tracking = -0.5f, lineHeightMultiplier = 1f), color = colors.white)
                            Text("%", style = iosRounded(28f, FontWeight.Black, lineHeightMultiplier = 1f), color = colors.white.copy(.92f), modifier = Modifier.padding(bottom = 5.dp))
                        }
                        if (photoCount > 1) {
                            Text(
                                stringResource(RdR.string.rd_fotograf_sayisi_format, photoCount),
                                style = iosRounded(11f, FontWeight.Bold),
                                color = colors.white,
                                modifier = Modifier.clip(CircleShape).background(colors.white.copy(.16f)).padding(horizontal = 10.dp, vertical = 5.dp),
                            )
                        }
                        LinearProgressIndicator(
                            progress = { progress },
                            modifier = Modifier.width(156.dp).height(7.dp).clip(CircleShape),
                            color = colors.green,
                            trackColor = colors.white.copy(.24f),
                        )
                    }
                }

                ScanSignal(Icons.Filled.GppGood, stringResource(RdR.string.rd_kkd), Alignment.TopStart, Modifier.offset(x = (-18).dp, y = (-12).dp))
                ScanSignal(Icons.Filled.AutoAwesome, stringResource(RdR.string.rd_risk), Alignment.TopEnd, Modifier.offset(x = 18.dp, y = 26.dp))
                ScanSignal(Icons.Filled.FactCheck, stringResource(RdR.string.rd_kontrol), Alignment.BottomStart, Modifier.offset(x = (-16).dp, y = 16.dp))
            }

            Spacer(Modifier.height(22.dp))
            Text(stringResource(RdR.string.rd_analiz_devam_ediyor), style = iosRounded(22f, FontWeight.Bold, tracking = -0.4f), color = colors.onyx)
            Spacer(Modifier.height(6.dp))
            Text(
                stringResource(RdR.string.rd_analiz_hazirlaniyor_alt),
                style = iosRounded(12.5f, FontWeight.Medium),
                color = colors.slate,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(18.dp))

            val steps = listOf(
                Triple(RdR.string.rd_goruntu_kalitesi_okunuyor, .03f, .25f),
                Triple(RdR.string.rd_risk_sinyalleri_tanimlaniyor, .25f, .55f),
                Triple(RdR.string.rd_kkd_cevresel_kontroller, .55f, .82f),
                Triple(RdR.string.rd_bulgular_yapilandiriliyor, .82f, 1f),
            )
            Column(Modifier.width(320.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                steps.forEach { (label, start, end) ->
                    val fill = ((progress - start) / (end - start)).coerceIn(0f, 1f)
                    ProgressStep(stringResource(label), fill)
                }
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.BoxScope.ScanSignal(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    alignment: Alignment,
    modifier: Modifier = Modifier,
) {
    val colors = RdTheme.colors
    Row(
        modifier.align(alignment).height(28.dp).clip(CircleShape)
            .background(colors.white.copy(.92f)).border(1.dp, colors.green.copy(.26f), CircleShape)
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(icon, null, tint = colors.greenDark, modifier = Modifier.size(12.dp))
        Text(text, color = colors.greenDark, style = iosRounded(10f, FontWeight.Bold))
    }
}

@Composable
private fun ProgressStep(label: String, fill: Float) {
    val colors = RdTheme.colors
    val complete = fill >= .995f
    val active = !complete && fill > 0f
    Row(
        Modifier.fillMaxWidth().height(50.dp).clip(RoundedCornerShape(15.dp))
            .background(if (complete || active) colors.white else colors.fog.copy(.62f))
            .border(1.dp, if (active) colors.green.copy(.42f) else colors.line.copy(.75f), RoundedCornerShape(15.dp))
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(22.dp).clip(CircleShape).background(if (complete) colors.green else colors.fog)
                .border(if (active) 2.dp else 0.dp, if (active) colors.selected else Color.Transparent, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (complete) Icon(Icons.Filled.Check, null, tint = colors.white, modifier = Modifier.size(13.dp))
            else if (active) Box(Modifier.size(7.dp).clip(CircleShape).background(colors.selected))
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(label, style = iosRounded(13.5f, FontWeight.SemiBold), color = colors.onyx, maxLines = 1)
            LinearProgressIndicator(
                progress = { fill },
                modifier = Modifier.fillMaxWidth().height(5.dp).clip(CircleShape),
                color = colors.green,
                trackColor = colors.line.copy(.70f),
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun IosParityResultView(
    analysisId: String,
    findings: List<Finding>,
    summary: AnalysisResultSummary?,
    photoBytes: List<ByteArray>,
    capabilities: PlanCapabilities,
    reportState: ResultReportUiState,
    reportSetup: ResultReportSetup,
    onGenerateReport: (ResultReportRequest, String, String, ResultReportFormat) -> Unit,
    onReportFileConsumed: () -> Unit,
    onReportErrorDismiss: () -> Unit,
    onBack: (() -> Unit)?,
    onDelete: (Finding) -> Unit,
    onUpdate: (Finding, FindingPatch) -> Unit,
    onOpenCompanies: () -> Unit,
    onUpgradeTier: (SubscriptionTier) -> Unit,
) {
    val colors = RdTheme.colors
    var method by remember { mutableStateOf(ParityRiskMethod.FineKinney) }
    var showReportSheet by remember { mutableStateOf(false) }
    var editingFinding by remember { mutableStateOf<Finding?>(null) }
    var deletingFinding by remember { mutableStateOf<Finding?>(null) }
    var selectedFinding by remember { mutableStateOf<Finding?>(null) }
    val context = LocalContext.current
    val chooserTitle = stringResource(RdR.string.rd_raporu_paylas)
    val fallbackAnalysisTitle = stringResource(RdR.string.rd_adsiz_analiz)
    val canvasLabel = summary?.canvas?.let { id -> AnalysisCanvas.all.firstOrNull { it.id == id }?.title ?: id } ?: stringResource(RdR.string.rd_genel)

    LaunchedEffect(reportState) {
        val ready = reportState as? ResultReportUiState.Ready ?: return@LaunchedEffect
        val dir = File(context.cacheDir, "reports").apply { mkdirs() }
        val target = File(dir, ready.file.fileName)
        target.writeBytes(ready.file.bytes)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", target)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = ready.file.mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri(ready.file.fileName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, chooserTitle))
        onReportFileConsumed()
    }

    Box(Modifier.fillMaxSize().background(colors.paper)) {
        Column(Modifier.fillMaxSize()) {
            ParityResultHeader(onBack, onReport = { showReportSheet = true })
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 20.dp, end = 20.dp, bottom = 108.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item { ResultMetaSurface(summary, canvasLabel, photoBytes, findings, capabilities, onUpgradeTier) }
                item { ResultMethodSelector(method) { method = it } }
                item { MethodologySurface(findings, method) }
                if (findings.isEmpty()) {
                    item { EmptyResultSurface() }
                } else {
                    item {
                        Text(
                            stringResource(RdR.string.rd_tespit_tehlikeler_risk),
                            style = RdFontStyle.SectionHeader.toTextStyle(),
                            color = colors.slate,
                            modifier = Modifier.padding(top = 6.dp, start = 2.dp),
                        )
                    }
                    itemsIndexed(findings.sortedByDescending { parityScore(it, method) }, key = { _, item -> item.id }) { index, finding ->
                        Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                            RichFindingCard(
                                finding = finding,
                                displayIndex = index + 1,
                                method = method,
                                canEdit = capabilities.canEditAIFindings,
                                tier = capabilities.tier,
                                onEdit = { editingFinding = finding },
                                onDelete = { deletingFinding = finding },
                                onUpgrade = onUpgradeTier,
                                onOpenDetail = { selectedFinding = finding },
                            )
                            if (capabilities.tier == SubscriptionTier.Free && index < 2) {
                                LockedFindingPreviewCard(
                                    number = findings.size + index + 1,
                                    requiredTier = if (index == 0) SubscriptionTier.Pro else SubscriptionTier.Plus,
                                    level = if (index == 0) RiskLevel.High else RiskLevel.Medium,
                                    onUpgrade = onUpgradeTier,
                                )
                            }
                        }
                    }
                }
            }
        }

        Box(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, colors.paper, colors.paper)))
                .padding(horizontal = 20.dp, vertical = 14.dp),
        ) {
            Button(
                onClick = { showReportSheet = true },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = colors.onyx, contentColor = colors.white),
            ) {
                Icon(Icons.Filled.Tune, null, Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Text(stringResource(RdR.string.rd_rapor_olustur), style = RdFontStyle.Callout.toTextStyle(), modifier = Modifier.weight(1f))
                Box(Modifier.size(34.dp).clip(CircleShape).background(colors.white), contentAlignment = Alignment.Center) {
                    Icon(Icons.AutoMirrored.Filled.Send, null, tint = colors.onyx, modifier = Modifier.size(17.dp))
                }
            }
        }

        selectedFinding?.let { finding ->
            FindingDetailSurface(
                finding = finding,
                method = method,
                photos = photoBytes,
                tier = capabilities.tier,
                onMethodChange = { method = it },
                onClose = { selectedFinding = null },
                onUpgrade = onUpgradeTier,
            )
        }
    }

    BackHandler(enabled = selectedFinding != null) { selectedFinding = null }

    if (showReportSheet) {
        ResultReportSettingsSheet(
            tier = capabilities.tier,
            method = method,
            onMethodChange = { method = it },
            onClose = { showReportSheet = false },
            onOpenCompanies = onOpenCompanies,
            onUpgrade = { onUpgradeTier(SubscriptionTier.Plus) },
            companies = reportSetup.companies,
            profile = reportSetup.profile,
            initialCompanyId = summary?.companyId,
            onGenerate = { kind, output, customization ->
                showReportSheet = false
                val request = ResultReportRequest(
                    analysisId = analysisId,
                    title = summary?.title ?: fallbackAnalysisTitle,
                    canvasLabel = canvasLabel,
                    createdAt = summary?.createdAt,
                    companyId = customization.companyId,
                    findings = findings,
                    coverPhotoBytes = photoBytes.firstOrNull(),
                    companyNameOverride = customization.companyName,
                    companyInfoOverride = customization.companyInfo,
                    companyLogoOverrideBytes = customization.companyLogoBytes,
                    preparedByOverride = customization.preparedBy,
                    preparedTitleOverride = customization.preparedTitle,
                    certificateNumberOverride = customization.certificateNumber,
                )
                onGenerateReport(
                    request,
                    if (kind == ParityReportKind.Standard) "standard" else "risk_analysis",
                    method.wire,
                    output,
                )
            },
        )
    }

    editingFinding?.let { finding ->
        FindingEditDialog(finding, onDismiss = { editingFinding = null }) { patch ->
            editingFinding = null
            onUpdate(finding, patch)
        }
    }
    deletingFinding?.let { finding ->
        AlertDialog(
            onDismissRequest = { deletingFinding = null },
            title = { Text(stringResource(RdR.string.rd_bulguyu_sil)) },
            text = { Text(stringResource(RdR.string.rd_bulgu_silme_onayi_format, finding.title)) },
            confirmButton = { TextButton(onClick = { deletingFinding = null; onDelete(finding) }) { Text(stringResource(RdR.string.rd_sil)) } },
            dismissButton = { TextButton(onClick = { deletingFinding = null }) { Text(stringResource(RdR.string.rd_vazgec)) } },
        )
    }
    (reportState as? ResultReportUiState.Failed)?.let { failed ->
        AlertDialog(
            onDismissRequest = onReportErrorDismiss,
            title = { Text(failed.error.title) },
            text = { Text(failed.error.message) },
            confirmButton = { TextButton(onClick = onReportErrorDismiss) { Text(stringResource(RdR.string.rd_tamam)) } },
        )
    }
    (reportState as? ResultReportUiState.Generating)?.let { generating ->
        ReportGenerationOverlay(generating.format, generating.progress)
    }
}

@Composable
private fun ParityResultHeader(onBack: (() -> Unit)?, onReport: () -> Unit) {
    val colors = RdTheme.colors
    Row(Modifier.fillMaxWidth().height(56.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        RoundHeaderButton(onBack) { Icon(Icons.Filled.KeyboardArrowLeft, stringResource(RdR.string.rd_geri), tint = colors.onyx, modifier = Modifier.size(23.dp)) }
        Text(stringResource(RdR.string.rd_analiz_sonucu), style = iosRounded(15f, FontWeight.SemiBold), color = colors.onyx, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
        RoundHeaderButton(onReport) { Icon(Icons.Filled.Download, stringResource(RdR.string.rd_rapor_olustur), tint = colors.onyx, modifier = Modifier.size(19.dp)) }
        Spacer(Modifier.width(8.dp))
        RoundHeaderButton(onReport) { Icon(Icons.Filled.IosShare, stringResource(RdR.string.rd_raporu_paylas), tint = colors.onyx, modifier = Modifier.size(18.dp)) }
    }
}

@Composable
private fun RoundHeaderButton(onClick: (() -> Unit)?, content: @Composable () -> Unit) {
    val colors = RdTheme.colors
    Box(
        Modifier.size(36.dp).clip(RoundedCornerShape(10.dp)).background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(10.dp))
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        contentAlignment = Alignment.Center,
    ) { content() }
}

@Composable
private fun ResultMetaSurface(
    summary: AnalysisResultSummary?,
    canvasLabel: String,
    photos: List<ByteArray>,
    findings: List<Finding>,
    capabilities: PlanCapabilities,
    onUpgrade: (SubscriptionTier) -> Unit,
) {
    val colors = RdTheme.colors
    val confidence = if (findings.isEmpty()) 0 else (findings.map { it.confidence }.average() * 100).toInt()
    Row(
        Modifier.fillMaxWidth().shadow(10.dp, RoundedCornerShape(16.dp), ambientColor = colors.onyx.copy(.04f), spotColor = colors.onyx.copy(.04f))
            .clip(RoundedCornerShape(16.dp)).background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(16.dp)).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        PhotoMosaic(photos)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(summary?.title ?: stringResource(RdR.string.rd_adsiz_analiz), style = iosRounded(15f, FontWeight.SemiBold), color = colors.onyx, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(formatResultDate(summary?.createdAt) + " · " + canvasLabel, style = iosRounded(12f), color = colors.slate, maxLines = 1)
            summary?.analysisSector?.takeIf(String::isNotBlank)?.let { sector ->
                Text(
                    stringResource(RdR.string.rd_analiz_kapsami_format, analysisSectorLabel(sector, canvasLabel)),
                    style = iosRounded(12f, FontWeight.Medium),
                    color = colors.charcoal,
                    maxLines = 1,
                )
            }
            Text(stringResource(RdR.string.rd_analiz_odagi_format, canvasLabel), style = iosRounded(12f), color = colors.slate, maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                MetaChip(stringResource(RdR.string.rd_bulgu_sayisi_format, findings.size), colors.fog, colors.onyx)
                MetaChip(stringResource(RdR.string.rd_ai_guveni_yuzde_format, confidence), if (capabilities.tier == SubscriptionTier.Pro) colors.greenSoft else colors.highBg, if (capabilities.tier == SubscriptionTier.Pro) colors.greenDark else colors.highText)
            }
            if (photos.isNotEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.PhotoLibrary, null, tint = colors.slate, modifier = Modifier.size(12.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(stringResource(RdR.string.rd_fotograf_sayisi_format, photos.size), style = iosMono(9.5f), color = colors.slate)
                }
            }
            if (capabilities.tier != SubscriptionTier.Pro) {
                val destinationTier = if (capabilities.tier == SubscriptionTier.Free) SubscriptionTier.Plus else SubscriptionTier.Pro
                val accentText = if (destinationTier == SubscriptionTier.Plus) colors.planPlusDark else colors.greenDark
                val accentSoft = if (destinationTier == SubscriptionTier.Plus) colors.planPlusSoft else colors.greenSoft
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(accentSoft.copy(.78f))
                        .clickable { onUpgrade(destinationTier) }.padding(horizontal = 8.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(if (destinationTier == SubscriptionTier.Plus) Icons.Filled.WorkspacePremium else Icons.Filled.Star, null, tint = accentText, modifier = Modifier.padding(top = 1.dp).size(11.dp))
                    Text(
                        stringResource(if (destinationTier == SubscriptionTier.Plus) RdR.string.rd_plus_upsell_analiz else RdR.string.rd_pro_upsell_analiz),
                        style = iosRounded(10.5f, FontWeight.SemiBold),
                        color = accentText,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun PhotoMosaic(photos: List<ByteArray>) {
    val colors = RdTheme.colors
    val images = remember(photos) { photos.mapNotNull { bytes -> runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }.getOrNull() } }
    Box(Modifier.size(78.dp).clip(RoundedCornerShape(13.dp)).background(colors.fog)) {
        if (images.isEmpty()) {
            Icon(Icons.Filled.PhotoLibrary, null, tint = colors.slate, modifier = Modifier.align(Alignment.Center).size(26.dp))
        } else if (images.size == 1) {
            Image(images.first(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        } else {
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Image(images.first(), null, Modifier.weight(1f).fillMaxHeight(), contentScale = ContentScale.Crop)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Image(images[1], null, Modifier.weight(1f).fillMaxWidth(), contentScale = ContentScale.Crop)
                    if (images.size > 2) Image(images[2], null, Modifier.weight(1f).fillMaxWidth(), contentScale = ContentScale.Crop)
                    else Box(Modifier.weight(1f).fillMaxWidth().background(colors.fog))
                }
            }
        }
    }
}

@Composable
private fun MetaChip(text: String, bg: Color, fg: Color) {
    Text(text, style = iosMono(11f, FontWeight.SemiBold), color = fg, modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(bg).padding(horizontal = 8.dp, vertical = 2.dp))
}

@Composable
private fun ResultMethodSelector(method: ParityRiskMethod, onChange: (ParityRiskMethod) -> Unit) {
    val colors = RdTheme.colors
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(colors.fog).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        ParityRiskMethod.entries.forEach { item ->
            val active = item == method
            Box(
                Modifier.weight(1f)
                    .shadow(if (active) 3.dp else 0.dp, RoundedCornerShape(9.dp))
                    .clip(RoundedCornerShape(9.dp))
                    .background(if (active) colors.white else Color.Transparent)
                    .clickable { onChange(item) }.padding(vertical = 8.dp),
            ) {
                Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(stringResource(if (item == ParityRiskMethod.FineKinney) RdR.string.rd_fine_kinney else RdR.string.rd_bes_carp_bes_matris), style = iosRounded(13f, FontWeight.Bold), color = if (active) colors.onyx else colors.slate)
                    Text(stringResource(if (item == ParityRiskMethod.FineKinney) RdR.string.rd_fk_formula else RdR.string.rd_matrix_formula), style = iosMono(10f), color = colors.slate)
                }
                if (active) Icon(Icons.Filled.CheckCircle, null, tint = colors.green, modifier = Modifier.align(Alignment.TopEnd).padding(end = 6.dp).size(15.dp))
            }
        }
    }
}

@Composable
private fun MethodologySurface(findings: List<Finding>, method: ParityRiskMethod) {
    val colors = RdTheme.colors
    val top = findings.maxByOrNull { parityScore(it, method) }
    val level = top?.let { parityLevel(it, method) } ?: RiskLevel.Unknown
    val score = top?.let { parityScore(it, method) } ?: 0.0
    val counts = RiskLevel.entries.associateWith { candidate -> findings.count { parityLevel(it, method) == candidate } }
    Row(
        Modifier.fillMaxWidth().shadow(10.dp, RoundedCornerShape(16.dp), ambientColor = colors.onyx.copy(.04f), spotColor = colors.onyx.copy(.04f))
            .clip(RoundedCornerShape(16.dp)).background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(16.dp)).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(stringResource(if (method == ParityRiskMethod.FineKinney) RdR.string.rd_fk_upper else RdR.string.rd_matrix_upper), style = iosRounded(11f, FontWeight.Bold, tracking = .8f), color = colors.slate)
            Text(formatScore(score), style = iosMono(30f, FontWeight.Black, tracking = -.5f), color = level.color())
            Text(stringResource(RdR.string.rd_en_yuksek_risk), style = iosMono(11f, FontWeight.SemiBold), color = colors.slate)
            Row(
                Modifier.clip(RoundedCornerShape(6.dp)).background(level.color().copy(.13f)).padding(horizontal = 8.dp, vertical = 3.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Icon(Icons.Filled.Warning, null, tint = level.color(), modifier = Modifier.size(11.dp))
                Text(parityBandLabel(level), style = iosRounded(11f, FontWeight.Bold), color = level.color())
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(stringResource(RdR.string.rd_dagilim).uppercase(Locale.forLanguageTag("tr-TR")), style = iosRounded(9f, FontWeight.Bold, tracking = .45f), color = colors.slate)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Bottom) {
                listOf(RiskLevel.Critical, RiskLevel.High, RiskLevel.Medium, RiskLevel.Low).forEach { item ->
                    RiskCountBar(item, counts[item].orEmpty())
                }
            }
        }
    }
}

@Composable
private fun RiskCountBar(level: RiskLevel, count: Int) {
    val colors = RdTheme.colors
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Box(Modifier.width(22.dp).height(50.dp).clip(RoundedCornerShape(4.dp)).background(colors.fog), contentAlignment = Alignment.BottomCenter) {
            Box(Modifier.fillMaxWidth().height((2 + 48 * (count.coerceAtMost(5) / 5f)).dp).background(level.color()))
        }
        Text("$count", style = iosMono(10f, FontWeight.Bold), color = colors.onyx)
        Text(riskShortLabel(level), style = iosRounded(8f, FontWeight.Bold), color = colors.slate)
    }
}

@Composable
private fun EmptyResultSurface() {
    val colors = RdTheme.colors
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.greenSoft).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Filled.VerifiedUser, null, tint = colors.greenDark, modifier = Modifier.size(36.dp))
        Spacer(Modifier.height(8.dp))
        Text(stringResource(RdR.string.rd_tehlike_tespit_edilmedi), style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx)
        Text(stringResource(RdR.string.rd_tehlike_tespit_edilmedi_aciklama), style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)
    }
}

@Composable
private fun RichFindingCard(
    finding: Finding,
    displayIndex: Int,
    method: ParityRiskMethod,
    canEdit: Boolean,
    tier: SubscriptionTier,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onUpgrade: (SubscriptionTier) -> Unit,
    onOpenDetail: () -> Unit,
) {
    val colors = RdTheme.colors
    val level = parityLevel(finding, method)
    val score = parityScore(finding, method)
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(16.dp)).clickable(onClick = onOpenDetail).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                "$displayIndex",
                style = iosMono(11f, FontWeight.Bold),
                color = colors.onyx,
                textAlign = TextAlign.Center,
                modifier = Modifier.size(25.dp).clip(RoundedCornerShape(8.dp)).background(colors.fog).padding(top = 5.dp),
            )
            Text(finding.title, style = iosRounded(15f, FontWeight.SemiBold), color = colors.onyx, modifier = Modifier.weight(1f))
            if (canEdit) {
                SmallFindingAction(onEdit, colors.planPlusSoft, colors.planPlus.copy(.55f)) { Icon(Icons.Filled.Edit, null, tint = colors.onyx, modifier = Modifier.size(15.dp)) }
                SmallFindingAction(onDelete, colors.criticalBg, Color.Transparent) { Icon(Icons.Filled.DeleteOutline, null, tint = colors.criticalText, modifier = Modifier.size(16.dp)) }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            MetaChip(parityBandLabel(level), level.backgroundColor(), level.color())
            if (finding.needsFieldVerification) MetaChip(stringResource(RdR.string.rd_saha_teyidi), colors.highBg, colors.highText)
            if (finding.sourcePhotoIndices.isNotEmpty()) MetaChip(stringResource(RdR.string.rd_foto_indeks_format, finding.sourcePhotoIndices.joinToString(",")), colors.fog, colors.slate)
        }
        finding.description?.takeIf { it.isNotBlank() }?.let { Text(it, style = iosRounded(13f), color = colors.onyx.copy(.86f)) }
        FindingScoreBlock(finding, method, level, score)
        val measures = findingMeasures(finding)
        if (measures.isNotEmpty()) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(colors.greenSoft).padding(horizontal = 10.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.GppGood, null, tint = colors.greenDark, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(7.dp))
                    Text(stringResource(RdR.string.rd_kontrol_tedbirleri), style = iosRounded(12f, FontWeight.Bold), color = colors.greenDark)
                }
                finding.recommendedMeasures.orEmpty().filter { it.text.isNotBlank() }.forEach { measure ->
                    val title = measure.title.takeIf(String::isNotBlank) ?: if (measure.kind == "preventive") stringResource(RdR.string.rd_onleyici) else stringResource(RdR.string.rd_duzeltici)
                    Text("$title: ${measure.text}", style = iosRounded(12f), color = colors.charcoal)
                }
                if (finding.recommendedMeasures.isNullOrEmpty()) measures.forEach { measure -> Text(measure, style = iosRounded(12f), color = colors.charcoal) }
            }
        }
        finding.rootCauseText?.takeIf { it.isNotBlank() }?.let {
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(colors.planPlusSoft).padding(horizontal = 10.dp, vertical = 8.dp),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Filled.FactCheck, null, tint = colors.planPlusDark, modifier = Modifier.padding(top = 1.dp).size(14.dp))
                Text(stringResource(RdR.string.rd_kok_neden_dot) + " · ", style = iosRounded(12f, FontWeight.Bold), color = colors.charcoal)
                Text(it, style = iosRounded(12f), color = colors.charcoal, modifier = Modifier.weight(1f))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FindingInfoCard(Icons.Filled.GppGood, stringResource(RdR.string.rd_plani), parityAction(level), level.color(), Modifier.weight(1f))
            FindingInfoCard(
                if (tier.isPaid) Icons.Filled.Description else Icons.Filled.Lock,
                stringResource(RdR.string.rd_mevzuat),
                if (tier.isPaid) finding.referencesText ?: stringResource(RdR.string.rd_referans_yok) else stringResource(RdR.string.rd_plus_ta_acik),
                if (tier.isPaid) colors.greenDark else colors.planPlusDark,
                Modifier.weight(1f).then(if (tier.isPaid) Modifier else Modifier.clickable { onUpgrade(SubscriptionTier.Plus) }),
                badgeTier = if (tier.isPaid) null else SubscriptionTier.Plus,
            )
        }
    }
}

@Composable
private fun FindingScoreBlock(finding: Finding, method: ParityRiskMethod, level: RiskLevel, score: Double) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(10.dp)).padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(
            Modifier.size(56.dp).clip(RoundedCornerShape(10.dp)).background(level.color()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(formatScore(score), style = iosMono(18f, FontWeight.Black), color = colors.white)
            Text(if (method == ParityRiskMethod.FineKinney) "F-KINNEY" else "5×5", style = iosRounded(8f, FontWeight.Bold, tracking = .6f), color = colors.white.copy(.85f))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(parityBandLabel(level), style = iosRounded(12f, FontWeight.Bold), color = level.color())
            Text(parityFormulaValues(finding, method), style = iosMono(11f), color = colors.slate)
            LinearProgressIndicator(
                progress = { (score / if (method == ParityRiskMethod.FineKinney) 1000.0 else 25.0).toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth().height(4.dp).clip(CircleShape),
                color = level.color(),
                trackColor = colors.fog,
            )
        }
    }
}

@Composable
private fun FindingInfoCard(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    value: String,
    tint: Color,
    modifier: Modifier,
    badgeTier: SubscriptionTier? = null,
) {
    val colors = RdTheme.colors
    Row(
        modifier.clip(RoundedCornerShape(9.dp)).background(colors.fog)
            .border(1.dp, colors.line, RoundedCornerShape(9.dp)).padding(horizontal = 8.dp, vertical = 7.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(18.dp).clip(RoundedCornerShape(5.dp)).background(tint.copy(.10f)).padding(3.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(title, style = iosRounded(8f, FontWeight.Black, tracking = .5f), color = colors.slate)
                badgeTier?.let { TierBadge(it, compact = true) }
            }
            Text(value, style = iosRounded(10.5f, FontWeight.SemiBold), color = colors.charcoal)
        }
    }
}

@Composable
private fun SmallFindingAction(onClick: () -> Unit, background: Color, stroke: Color, content: @Composable () -> Unit) {
    Box(
        Modifier.size(28.dp).clip(RoundedCornerShape(8.dp)).background(background)
            .border(1.dp, stroke, RoundedCornerShape(8.dp)).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}

@Composable
private fun TierBadge(tier: SubscriptionTier, compact: Boolean = false) {
    val colors = RdTheme.colors
    val isPlus = tier == SubscriptionTier.Plus
    val accent = if (isPlus) colors.planPlus else colors.green
    val accentText = if (isPlus) colors.planPlusDark else colors.greenDark
    val soft = if (isPlus) colors.planPlusSoft else colors.greenSoft
    Row(
        Modifier.clip(RoundedCornerShape(if (compact) 5.dp else 7.dp)).background(soft)
            .border(1.dp, accent.copy(.34f), RoundedCornerShape(if (compact) 5.dp else 7.dp))
            .padding(horizontal = if (compact) 4.dp else 7.dp, vertical = if (compact) 1.dp else 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Icon(if (isPlus) Icons.Filled.WorkspacePremium else Icons.Filled.Star, null, tint = accentText, modifier = Modifier.size(if (compact) 8.dp else 11.dp))
        Text(if (isPlus) stringResource(RdR.string.rd_plus).uppercase(Locale.forLanguageTag("tr-TR")) else stringResource(RdR.string.rd_pro).uppercase(Locale.forLanguageTag("tr-TR")), style = iosRounded(if (compact) 7f else 9f, FontWeight.Black, tracking = .35f), color = accentText)
    }
}

@Composable
private fun LockedFindingPreviewCard(
    number: Int,
    requiredTier: SubscriptionTier,
    level: RiskLevel,
    onUpgrade: (SubscriptionTier) -> Unit,
) {
    val colors = RdTheme.colors
    val isPlus = requiredTier == SubscriptionTier.Plus
    val tint = if (isPlus) colors.planPlus else colors.green
    val tintSoft = if (isPlus) colors.planPlusSoft else colors.greenSoft
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(tintSoft.copy(.34f))
            .border(1.dp, tint.copy(.30f), RoundedCornerShape(16.dp)).clickable { onUpgrade(requiredTier) }
            .padding(horizontal = 12.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("$number", style = iosMono(12f, FontWeight.Bold), color = colors.onyx, textAlign = TextAlign.Center, modifier = Modifier.size(32.dp).clip(RoundedCornerShape(9.dp)).background(colors.white.copy(.92f)).padding(top = 7.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                Text(stringResource(if (requiredTier == SubscriptionTier.Pro) RdR.string.rd_ek_kritik_bulgu else RdR.string.rd_gizli_uygunsuzluk), style = iosRounded(14f, FontWeight.Bold), color = colors.onyx.copy(.86f), maxLines = 1)
                MetaChip(parityBandLabel(level), level.backgroundColor(), level.color())
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.Lock, null, tint = colors.slate, modifier = Modifier.size(11.dp))
                Text(stringResource(if (requiredTier == SubscriptionTier.Pro) RdR.string.rd_detay_pro_ile_acilir else RdR.string.rd_detay_plus_ile_acilir), style = iosRounded(11.5f, FontWeight.Medium), color = colors.slate, maxLines = 1)
            }
        }
        TierBadge(requiredTier, compact = true)
    }
}

private fun findingMeasures(finding: Finding): List<String> = finding.recommendedMeasures.orEmpty()
    .mapNotNull { it.text.takeIf(String::isNotBlank) }
    .ifEmpty { listOfNotNull(finding.recommendedAction?.takeIf(String::isNotBlank)) }

@Composable
private fun FindingDetailSurface(
    finding: Finding,
    method: ParityRiskMethod,
    photos: List<ByteArray>,
    tier: SubscriptionTier,
    onMethodChange: (ParityRiskMethod) -> Unit,
    onClose: () -> Unit,
    onUpgrade: (SubscriptionTier) -> Unit,
) {
    val colors = RdTheme.colors
    val level = parityLevel(finding, method)
    val sourceIndex = finding.sourcePhotoIndices.firstOrNull()?.coerceAtLeast(1) ?: 1
    val bitmap = remember(photos, sourceIndex) {
        photos.getOrNull(sourceIndex - 1)?.let { bytes ->
            runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }.getOrNull()
        }
    }

    Column(Modifier.fillMaxSize().background(colors.paper)) {
        Box(Modifier.fillMaxWidth().height(54.dp).padding(horizontal = 20.dp, vertical = 8.dp)) {
            Box(
                Modifier.align(Alignment.CenterEnd).size(38.dp).shadow(10.dp, CircleShape, ambientColor = colors.onyx.copy(.14f), spotColor = colors.onyx.copy(.14f))
                    .clip(CircleShape).background(colors.white.copy(.96f)).clickable(onClick = onClose),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.Close, stringResource(RdR.string.rd_kapat), tint = colors.onyx, modifier = Modifier.size(18.dp)) }
        }

        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 20.dp, end = 20.dp, top = 6.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text((finding.category ?: stringResource(RdR.string.rd_genel)).uppercase(Locale.forLanguageTag("tr-TR")), style = iosRounded(11f, FontWeight.Bold, tracking = .6f), color = colors.slate)
                    Text(finding.title, style = iosRounded(22f, FontWeight.Bold, tracking = -.4f), color = colors.onyx)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                        MetaChip(parityBandLabel(level), level.backgroundColor(), level.color())
                        MetaChip(stringResource(RdR.string.rd_ai_guveni_yuzde_format, (finding.confidence * 100).toInt()), colors.greenSoft, colors.greenDark)
                    }
                }
            }
            item {
                Box(
                    Modifier.fillMaxWidth().height(238.dp).clip(RoundedCornerShape(16.dp)).background(colors.graphite),
                ) {
                    if (bitmap != null) Image(bitmap, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    else Icon(Icons.Filled.PhotoLibrary, null, tint = colors.white.copy(.58f), modifier = Modifier.align(Alignment.Center).size(42.dp))

                    Row(
                        Modifier.align(Alignment.TopStart).padding(12.dp).clip(RoundedCornerShape(9.dp)).background(colors.white.copy(.92f)).padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(Icons.Filled.PhotoLibrary, null, tint = colors.onyx, modifier = Modifier.size(12.dp))
                        Text(stringResource(RdR.string.rd_foto_indeks_format, sourceIndex.toString()), style = iosMono(11f, FontWeight.Bold), color = colors.onyx)
                    }

                    Row(
                        Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp)
                            .shadow(14.dp, RoundedCornerShape(16.dp), ambientColor = colors.onyx.copy(.16f), spotColor = colors.onyx.copy(.16f))
                            .clip(RoundedCornerShape(16.dp)).background(colors.white.copy(.84f))
                            .border(1.dp, colors.white.copy(.72f), RoundedCornerShape(16.dp)).padding(horizontal = 14.dp, vertical = 11.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(formatScore(parityScore(finding, method)), style = iosMono(26f, FontWeight.Black, tracking = -.6f), color = level.color())
                            Text(parityAction(level), style = iosRounded(12f, FontWeight.Bold), color = level.color(), maxLines = 2)
                        }
                        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(stringResource(if (method == ParityRiskMethod.FineKinney) RdR.string.rd_fk_upper else RdR.string.rd_matrix_upper), style = iosRounded(9f, FontWeight.Bold, tracking = .6f), color = colors.onyx.copy(.72f), textAlign = TextAlign.End)
                            Text(parityFormulaValues(finding, method), style = iosMono(10.5f, FontWeight.SemiBold), color = colors.onyx.copy(.78f), maxLines = 1)
                        }
                    }
                }
            }
            item {
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.white)
                        .border(1.dp, colors.line, RoundedCornerShape(16.dp)).padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(stringResource(RdR.string.rd_yontem_karsilastirmasi), style = iosRounded(11f, FontWeight.Bold, tracking = .6f), color = colors.slate)
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        DetailMethodBox(finding, ParityRiskMethod.FineKinney, method == ParityRiskMethod.FineKinney, Modifier.weight(1f)) { onMethodChange(ParityRiskMethod.FineKinney) }
                        DetailMethodBox(finding, ParityRiskMethod.Matrix5x5, method == ParityRiskMethod.Matrix5x5, Modifier.weight(1f)) { onMethodChange(ParityRiskMethod.Matrix5x5) }
                    }
                }
            }
            item { DetailTextSection(stringResource(RdR.string.rd_tehlike_aciklamasi), finding.description.orEmpty(), colors.fog, colors.charcoal, Icons.Filled.Info) }
            if (findingMeasures(finding).isNotEmpty()) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(stringResource(RdR.string.rd_onlem_kontrol_tedbirleri), style = iosRounded(11f, FontWeight.Bold, tracking = .6f), color = colors.slate)
                        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(colors.greenSoft).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            finding.recommendedMeasures.orEmpty().filter { it.text.isNotBlank() }.forEach { measure ->
                                val title = measure.title.takeIf(String::isNotBlank) ?: if (measure.kind == "preventive") stringResource(RdR.string.rd_onleyici) else stringResource(RdR.string.rd_duzeltici)
                                Text("$title: ${measure.text}", style = iosRounded(14f), color = colors.charcoal)
                            }
                            if (finding.recommendedMeasures.isNullOrEmpty()) findingMeasures(finding).forEach { Text(it, style = iosRounded(14f), color = colors.charcoal) }
                        }
                    }
                }
            }
            finding.rootCauseText?.takeIf { it.isNotBlank() }?.let { rootCause ->
                item { DetailTextSection(stringResource(RdR.string.rd_kok_neden), rootCause, colors.planPlusSoft, colors.planPlusDark, Icons.Filled.FactCheck) }
            }
            item {
                if (tier.isPaid) {
                    DetailTextSection(stringResource(RdR.string.rd_mevzuat_referanslari), finding.referencesText ?: stringResource(RdR.string.rd_referans_yok), colors.fog, colors.charcoal, Icons.Filled.Description)
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(stringResource(RdR.string.rd_mevzuat_referanslari), style = iosRounded(11f, FontWeight.Bold, tracking = .6f), color = colors.slate)
                            TierBadge(SubscriptionTier.Plus, compact = true)
                        }
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(colors.fog).clickable { onUpgrade(SubscriptionTier.Plus) }.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Icon(Icons.Filled.Description, null, tint = colors.onyx, modifier = Modifier.size(17.dp))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(stringResource(RdR.string.rd_mevzuat_plus_acik), style = iosRounded(13f, FontWeight.Bold), color = colors.onyx)
                                Text(stringResource(RdR.string.rd_mevzuat_plus_aciklama), style = iosRounded(11f), color = colors.slate, maxLines = 2)
                            }
                            TierBadge(SubscriptionTier.Plus, compact = true)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailMethodBox(
    finding: Finding,
    method: ParityRiskMethod,
    active: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val colors = RdTheme.colors
    val level = parityLevel(finding, method)
    Column(
        modifier.clip(RoundedCornerShape(12.dp)).background(colors.white)
            .border(if (active) 1.5.dp else 1.dp, if (active) colors.selected else colors.line, RoundedCornerShape(12.dp))
            .clickable(onClick = onClick).padding(10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.fillMaxWidth()) {
            Text(
                stringResource(if (method == ParityRiskMethod.FineKinney) RdR.string.rd_fine_kinney else RdR.string.rd_bes_carp_bes_matris),
                style = iosRounded(12f, FontWeight.Bold),
                color = if (active) colors.onyx else colors.slate,
                modifier = Modifier.align(Alignment.Center),
            )
            if (active) Icon(Icons.Filled.CheckCircle, null, tint = colors.green, modifier = Modifier.align(Alignment.TopEnd).size(15.dp))
        }
        Text(stringResource(if (method == ParityRiskMethod.FineKinney) RdR.string.rd_fk_formula else RdR.string.rd_matrix_formula), style = iosMono(10f), color = colors.slate)
        Text(formatScore(parityScore(finding, method)), style = iosMono(23f, FontWeight.Black), color = colors.white, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(level.color()).padding(vertical = 12.dp))
        Text(parityBandLabel(level), style = iosRounded(11f, FontWeight.SemiBold), color = level.color())
    }
}

@Composable
private fun DetailTextSection(
    title: String,
    body: String,
    background: Color,
    foreground: Color,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
) {
    val colors = RdTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title.uppercase(Locale.forLanguageTag("tr-TR")), style = iosRounded(11f, FontWeight.Bold, tracking = .6f), color = colors.slate)
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(background).padding(12.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(icon, null, tint = foreground, modifier = Modifier.padding(top = 1.dp).size(14.dp))
            Text(body, style = iosRounded(14f), color = foreground, modifier = Modifier.weight(1f))
        }
    }
}

private data class ResultReportCustomization(
    val companyId: String?,
    val companyName: String,
    val companyInfo: String,
    val companyLogoBytes: ByteArray?,
    val preparedBy: String,
    val preparedTitle: String,
    val certificateNumber: String,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ResultReportSettingsSheet(
    tier: SubscriptionTier,
    method: ParityRiskMethod,
    onMethodChange: (ParityRiskMethod) -> Unit,
    onClose: () -> Unit,
    onOpenCompanies: () -> Unit,
    onUpgrade: () -> Unit,
    companies: List<Company>,
    profile: UserProfile?,
    initialCompanyId: String?,
    onGenerate: (ParityReportKind, ResultReportFormat, ResultReportCustomization) -> Unit,
) {
    val colors = RdTheme.colors
    var kind by remember { mutableStateOf(ParityReportKind.Standard) }
    var format by remember { mutableStateOf(ResultReportFormat.Pdf) }
    var selectedCompanyId by remember(initialCompanyId) { mutableStateOf(initialCompanyId) }
    val selectedCompany = companies.firstOrNull { it.id == selectedCompanyId }
    var companyName by remember(selectedCompany?.id, profile?.id) { mutableStateOf(selectedCompany?.name ?: profile?.companyName.orEmpty()) }
    var companyInfo by remember(selectedCompany?.id, profile?.id) { mutableStateOf(selectedCompany?.reportInfoText() ?: profile?.phone.orEmpty()) }
    var companyLogoBytes by remember { mutableStateOf<ByteArray?>(null) }
    var preparedBy by remember(profile?.id) { mutableStateOf(profile?.displayName.orEmpty()) }
    var preparedTitle by remember(profile?.id) { mutableStateOf(profile?.title.orEmpty()) }
    var certificateNumber by remember(profile?.id) { mutableStateOf(profile?.certificateNumber.orEmpty()) }
    var showOverrides by remember { mutableStateOf(false) }
    var showCompanyPicker by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val logoPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        companyLogoBytes = uri?.let { selected ->
            runCatching { context.contentResolver.openInputStream(selected)?.use { it.readBytes() } }.getOrNull()
        }
    }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = sheetState,
        containerColor = colors.paper,
        dragHandle = { Box(Modifier.padding(top = 8.dp).size(38.dp, 5.dp).clip(CircleShape).background(colors.line)) },
    ) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(.92f).padding(horizontal = 14.dp)) {
            Box(Modifier.fillMaxWidth().height(46.dp)) {
                Text(
                    stringResource(if (showCompanyPicker) RdR.string.rd_rapor_firmasi else RdR.string.rd_rapor_olustur),
                    style = iosRounded(15f, FontWeight.SemiBold),
                    color = colors.onyx,
                    modifier = Modifier.align(Alignment.Center),
                )
                if (showCompanyPicker) {
                    IconButton(onClick = { showCompanyPicker = false }, modifier = Modifier.align(Alignment.CenterStart).size(34.dp).clip(CircleShape).background(colors.fog)) {
                        Icon(Icons.Filled.KeyboardArrowLeft, stringResource(RdR.string.rd_geri), tint = colors.onyx)
                    }
                }
                IconButton(onClick = onClose, modifier = Modifier.align(Alignment.CenterEnd).size(34.dp).clip(CircleShape).background(colors.fog)) {
                    Icon(Icons.Filled.Close, stringResource(RdR.string.rd_kapat), tint = colors.onyx, modifier = Modifier.size(18.dp))
                }
            }
            if (showCompanyPicker) {
                LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    item {
                        CompanyPickerRow(
                            title = stringResource(RdR.string.rd_firma_secmeden_devam_et),
                            subtitle = stringResource(RdR.string.rd_kisisel_profil_bilgileri_kullanilir),
                            selected = selectedCompanyId == null,
                            onClick = {
                                selectedCompanyId = null
                                companyName = profile?.companyName.orEmpty()
                                companyInfo = profile?.phone.orEmpty()
                                showCompanyPicker = false
                            },
                        )
                    }
                    items(companies, key = Company::id) { company ->
                        CompanyPickerRow(
                            title = company.name,
                            subtitle = company.reportInfoText().ifBlank { company.hazardClass.title },
                            selected = selectedCompanyId == company.id,
                            onClick = {
                                selectedCompanyId = company.id
                                companyName = company.name
                                companyInfo = company.reportInfoText()
                                companyLogoBytes = null
                                showCompanyPicker = false
                            },
                        )
                    }
                    item {
                        TextButton(onClick = { onClose(); onOpenCompanies() }, modifier = Modifier.fillMaxWidth()) {
                            Icon(Icons.Filled.Add, null, tint = colors.greenDark)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(RdR.string.rd_yeni_firma_ekle), color = colors.greenDark, style = iosRounded(14f, FontWeight.Bold))
                        }
                    }
                }
            } else LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item {
                    ReportOptionCard(
                        selected = kind == ParityReportKind.Standard,
                        icon = Icons.Filled.Description,
                        title = stringResource(RdR.string.rd_standart_rapor),
                        subtitle = stringResource(RdR.string.rd_standart_rapor_aciklama),
                        onClick = { kind = ParityReportKind.Standard; format = ResultReportFormat.Pdf },
                    )
                }
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
                        if (tier == SubscriptionTier.Free) {
                            FreeTrialRibbon()
                        }
                        ReportOptionCard(
                            selected = kind == ParityReportKind.RiskAnalysis,
                            icon = Icons.Filled.TableChart,
                            title = stringResource(RdR.string.rd_risk_analizi_tablosu),
                            subtitle = stringResource(RdR.string.rd_risk_analizi_tablosu_aciklama),
                            onClick = { kind = ParityReportKind.RiskAnalysis },
                        )
                    }
                }
                if (kind == ParityReportKind.RiskAnalysis) {
                    item {
                        ReportSectionLabel(stringResource(RdR.string.rd_rapor_firmasi))
                        Spacer(Modifier.height(7.dp))
                        if (tier.isPaid) {
                            CompanySelectionCard(
                                company = selectedCompany,
                                onClick = { showCompanyPicker = true },
                            )
                        } else {
                            LockedCompanyCard(onUpgrade)
                        }
                    }
                    item {
                        Text(stringResource(RdR.string.rd_risk_yontemi).uppercase(Locale.forLanguageTag("tr-TR")), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.slate)
                        Spacer(Modifier.height(7.dp))
                        ResultMethodSelector(method, onMethodChange)
                    }
                    item {
                        Text(stringResource(RdR.string.rd_cikti_formati), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.slate)
                        Spacer(Modifier.height(7.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ReportFormatCard(ResultReportFormat.Pdf, format == ResultReportFormat.Pdf, Modifier.weight(1f)) { format = ResultReportFormat.Pdf }
                            ReportFormatCard(ResultReportFormat.Excel, format == ResultReportFormat.Excel, Modifier.weight(1f)) { format = ResultReportFormat.Excel }
                        }
                    }
                    item {
                        ReportIdentityCard(
                            preparedBy = preparedBy,
                            onPreparedByChange = { preparedBy = it },
                            preparedTitle = preparedTitle,
                            onPreparedTitleChange = { preparedTitle = it },
                            certificateNumber = certificateNumber,
                            onCertificateNumberChange = { certificateNumber = it },
                        )
                    }
                    item {
                        ReportSectionLabel(stringResource(RdR.string.rd_bu_rapora_ozel_duzenle))
                        Spacer(Modifier.height(7.dp))
                        ReportOverridesCard(
                            expanded = showOverrides,
                            hasSelectedCompany = selectedCompany != null,
                            companyName = companyName,
                            onCompanyNameChange = { companyName = it },
                            companyInfo = companyInfo,
                            onCompanyInfoChange = { companyInfo = it },
                            companyLogoBytes = companyLogoBytes,
                            onToggle = { showOverrides = !showOverrides },
                            onPickLogo = { logoPicker.launch("image/*") },
                        )
                    }
                }
            }
            if (!showCompanyPicker) Button(
                onClick = {
                    onGenerate(
                        kind,
                        format,
                        ResultReportCustomization(
                            companyId = selectedCompanyId,
                            companyName = companyName,
                            companyInfo = companyInfo,
                            companyLogoBytes = companyLogoBytes,
                            preparedBy = preparedBy,
                            preparedTitle = preparedTitle,
                            certificateNumber = certificateNumber,
                        ),
                    )
                },
                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp).height(56.dp),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = colors.onyx, contentColor = colors.white),
            ) {
                Icon(if (format == ResultReportFormat.Pdf) Icons.Filled.Description else Icons.Filled.TableChart, null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Text(
                    when {
                        kind == ParityReportKind.Standard -> stringResource(RdR.string.rd_rapor_olustur)
                        format == ResultReportFormat.Excel -> stringResource(RdR.string.rd_excel_risk_tablosu_olustur)
                        else -> stringResource(RdR.string.rd_risk_analizi_pdf_olustur)
                    },
                    style = iosRounded(17f, FontWeight.SemiBold),
                    modifier = Modifier.weight(1f),
                )
                Box(Modifier.size(34.dp).clip(CircleShape).background(colors.white), contentAlignment = Alignment.Center) {
                    Icon(Icons.AutoMirrored.Filled.Send, null, tint = colors.onyx, modifier = Modifier.size(17.dp))
                }
            }
        }
    }
}

private fun Company.reportInfoText(): String = listOfNotNull(
    address?.takeIf(String::isNotBlank),
    contactPerson?.takeIf(String::isNotBlank),
    department?.takeIf(String::isNotBlank),
).joinToString(" · ")

@Composable
private fun ReportSectionLabel(title: String) {
    val colors = RdTheme.colors
    Text(
        title.uppercase(Locale.forLanguageTag("tr-TR")),
        style = iosRounded(11f, FontWeight.Bold, tracking = .8f),
        color = colors.slate,
        modifier = Modifier.padding(start = 4.dp),
    )
}

@Composable
private fun CompanySelectionCard(company: Company?, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.size(40.dp).clip(RoundedCornerShape(12.dp))
                .background(if (company == null) colors.fog else colors.greenSoft),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Business, null, tint = if (company == null) colors.slate else colors.greenDark, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                company?.name ?: stringResource(RdR.string.rd_firma_secmeden_devam_et),
                style = iosRounded(14f, FontWeight.Bold),
                color = colors.onyx,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                company?.reportInfoText()?.takeIf(String::isNotBlank)
                    ?: stringResource(RdR.string.rd_arsiv_filtre_firma_aciklama),
                style = iosRounded(12f),
                color = colors.slate,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (company != null) Text(stringResource(RdR.string.rd_degistir), style = iosRounded(12f, FontWeight.Bold), color = colors.greenDark)
        Icon(Icons.Filled.KeyboardArrowRight, null, tint = colors.slate, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun LockedCompanyCard(onUpgrade: () -> Unit) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.white)
            .border(1.dp, colors.planPlus.copy(.28f), RoundedCornerShape(14.dp))
            .clickable(onClick = onUpgrade).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(38.dp).clip(RoundedCornerShape(11.dp)).background(colors.planPlusSoft), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Lock, null, tint = colors.planPlusDark, modifier = Modifier.size(16.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(stringResource(RdR.string.rd_firma_bazli_rapor_plus_pro), style = iosRounded(14f, FontWeight.Bold), color = colors.onyx)
            Text(stringResource(RdR.string.rd_logo_tehlike_firma_arsivi_yukselt), style = iosRounded(12f), color = colors.slate)
        }
        Icon(Icons.Filled.ArrowCircleUp, null, tint = colors.planPlusDark, modifier = Modifier.size(19.dp))
    }
}

@Composable
private fun ReportOverridesCard(
    expanded: Boolean,
    hasSelectedCompany: Boolean,
    companyName: String,
    onCompanyNameChange: (String) -> Unit,
    companyInfo: String,
    onCompanyInfoChange: (String) -> Unit,
    companyLogoBytes: ByteArray?,
    onToggle: () -> Unit,
    onPickLogo: () -> Unit,
) {
    val colors = RdTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.white)
                .border(1.dp, colors.line, RoundedCornerShape(14.dp)).clickable(onClick = onToggle).padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(Modifier.size(38.dp).clip(RoundedCornerShape(11.dp)).background(colors.greenSoft), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Tune, null, tint = colors.greenDark, modifier = Modifier.size(16.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(stringResource(RdR.string.rd_tek_seferlik_firma_logo), style = iosRounded(14f, FontWeight.Bold), color = colors.onyx)
                Text(
                    stringResource(if (hasSelectedCompany) RdR.string.rd_secili_firma_korunur else RdR.string.rd_firma_eklemeden_rapora_ozel),
                    style = iosRounded(12f), color = colors.slate, maxLines = 2,
                )
            }
            Icon(
                Icons.Filled.ExpandMore,
                null,
                tint = colors.slate,
                modifier = Modifier.size(20.dp).scale(scaleX = 1f, scaleY = if (expanded) -1f else 1f),
            )
        }
        if (expanded) {
            ReportLabeledField(stringResource(RdR.string.rd_firma_adi), companyName, onCompanyNameChange)
            ReportLabeledField(stringResource(RdR.string.rd_firma_bilgisi), companyInfo, onCompanyInfoChange)
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.white)
                    .border(1.dp, colors.line, RoundedCornerShape(14.dp)).padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(Modifier.size(width = 68.dp, height = 58.dp).clip(RoundedCornerShape(12.dp)).background(colors.white).border(1.dp, colors.line, RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                    val bitmap = remember(companyLogoBytes) { companyLogoBytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }?.asImageBitmap() }
                    if (bitmap != null) Image(bitmap, null, Modifier.padding(8.dp).fillMaxSize(), contentScale = ContentScale.Fit)
                    else Icon(Icons.Filled.Business, null, tint = colors.slate, modifier = Modifier.size(25.dp))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(stringResource(if (companyLogoBytes == null) RdR.string.rd_logo_secilmedi else RdR.string.rd_logo_rapora_eklenecek), style = iosRounded(13f, FontWeight.Bold), color = colors.onyx)
                    Text(stringResource(if (hasSelectedCompany) RdR.string.rd_secili_firma_logosu_korunur else RdR.string.rd_firma_eklemeden_logo_sec), style = iosRounded(12f), color = colors.slate)
                }
                Box(Modifier.size(34.dp).clip(RoundedCornerShape(10.dp)).background(colors.greenSoft).clickable(onClick = onPickLogo), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Add, stringResource(RdR.string.rd_logo_sec), tint = colors.greenDark, modifier = Modifier.size(16.dp))
                }
            }
        }
    }
}

@Composable
private fun ReportIdentityCard(
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
            .border(1.dp, colors.line, RoundedCornerShape(18.dp)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            Box(Modifier.size(30.dp).clip(RoundedCornerShape(9.dp)).background(colors.greenSoft), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Person, null, tint = colors.greenDark, modifier = Modifier.size(15.dp))
            }
            Text(stringResource(RdR.string.rd_hazirlayan_bilgileri), style = iosRounded(14f, FontWeight.Bold), color = colors.onyx)
        }
        ReportLabeledField(stringResource(RdR.string.rd_hazirlayan), preparedBy, onPreparedByChange)
        ReportLabeledField(stringResource(RdR.string.rd_unvan), preparedTitle, onPreparedTitleChange)
        ReportLabeledField(stringResource(RdR.string.rd_belge_no), certificateNumber, onCertificateNumberChange)
    }
}

@Composable
private fun ReportLabeledField(label: String, value: String, onValueChange: (String) -> Unit) {
    val colors = RdTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(label, style = iosRounded(12f, FontWeight.SemiBold), color = colors.slate)
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            textStyle = iosRounded(14f, FontWeight.Medium).copy(color = colors.onyx),
            singleLine = true,
            modifier = Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(12.dp))
                .background(colors.white).border(1.dp, colors.line, RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 12.dp),
        )
    }
}

@Composable
private fun CompanyPickerRow(title: String, subtitle: String, selected: Boolean, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(colors.white)
            .border(if (selected) 1.5.dp else 1.dp, if (selected) colors.green else colors.line, RoundedCornerShape(14.dp))
            .clickable(onClick = onClick).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(if (selected) colors.greenSoft else colors.fog), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Business, null, tint = if (selected) colors.greenDark else colors.slate, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = iosRounded(14f, FontWeight.Bold), color = colors.onyx)
            Text(subtitle, style = iosRounded(12f), color = colors.slate, maxLines = 2)
        }
        Icon(if (selected) Icons.Filled.CheckCircle else Icons.Filled.KeyboardArrowRight, null, tint = if (selected) colors.green else colors.slate, modifier = Modifier.size(19.dp))
    }
}

@Composable
private fun ReportOptionCard(selected: Boolean, icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 104.dp).shadow(if (selected) 14.dp else 0.dp, RoundedCornerShape(20.dp), ambientColor = colors.green.copy(.12f), spotColor = colors.green.copy(.12f))
            .clip(RoundedCornerShape(20.dp)).background(if (selected) colors.greenSoft.copy(.65f) else colors.white)
            .border(if (selected) 1.4.dp else 1.dp, if (selected) colors.green.copy(.55f) else colors.line, RoundedCornerShape(20.dp))
            .clickable(onClick = onClick).padding(horizontal = 18.dp, vertical = if (selected) 18.dp else 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(58.dp).clip(RoundedCornerShape(15.dp)).background(if (selected) colors.green else colors.greenSoft), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = if (selected) colors.white else colors.greenDark, modifier = Modifier.size(25.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = iosRounded(17f, FontWeight.Bold), color = colors.onyx)
            Text(subtitle, style = iosRounded(13.5f), color = colors.slate, maxLines = 3)
        }
        Box(Modifier.size(24.dp).clip(CircleShape).border(2.dp, if (selected) colors.green else colors.slate.copy(.32f), CircleShape).background(if (selected) colors.green else Color.Transparent), contentAlignment = Alignment.Center) {
            if (selected) Icon(Icons.Filled.Check, null, tint = colors.white, modifier = Modifier.size(15.dp))
        }
    }
}

@Composable
private fun FreeTrialRibbon() {
    val colors = RdTheme.colors
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
            .background(Brush.linearGradient(listOf(colors.planPlusSoft.copy(.98f), colors.white.copy(.96f))))
            .border(1.dp, colors.planPlus.copy(.34f), RoundedCornerShape(18.dp)).padding(horizontal = 16.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Box(Modifier.size(28.dp).clip(RoundedCornerShape(9.dp)).background(colors.white.copy(.72f)), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.WorkspacePremium, null, tint = colors.planPlusDark, modifier = Modifier.size(15.dp))
        }
        Text(stringResource(RdR.string.rd_tek_seferlik_deneme_aciklama), style = iosRounded(13.5f, FontWeight.Bold), color = colors.planPlusDark, modifier = Modifier.weight(1f), maxLines = 2)
    }
}

@Composable
private fun ReportFormatCard(format: ResultReportFormat, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Column(
        modifier.clip(RoundedCornerShape(14.dp)).background(if (selected) colors.greenSoft else colors.white)
            .border(1.dp, if (selected) colors.green else colors.line, RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(12.dp),
    ) {
        Icon(if (format == ResultReportFormat.Pdf) Icons.Filled.Description else Icons.Filled.TableChart, null, tint = if (selected) colors.greenDark else colors.slate)
        Spacer(Modifier.height(6.dp))
        Text(stringResource(if (format == ResultReportFormat.Pdf) RdR.string.rd_pdf_rapor else RdR.string.rd_excel_tablo), style = RdFontStyle.Footnote.toTextStyle(), color = colors.onyx)
        Text(stringResource(if (format == ResultReportFormat.Pdf) RdR.string.rd_pdf_rapor_aciklama else RdR.string.rd_excel_tablo_aciklama), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
    }
}

@Composable
private fun ReportGenerationOverlay(format: ResultReportFormat, progress: Float) {
    val colors = RdTheme.colors
    val pulse by rememberInfiniteTransition(label = "reportPulse").animateFloat(
        initialValue = .95f,
        targetValue = 1.05f,
        animationSpec = infiniteRepeatable(tween(1150), RepeatMode.Reverse),
        label = "reportPulseScale",
    )
    val status = when {
        progress < .25f -> stringResource(RdR.string.rd_rapor_verileri_hazirlaniyor)
        progress < .55f -> stringResource(RdR.string.rd_gorsel_risk_tablolari_isleniyor)
        progress < .85f -> stringResource(RdR.string.rd_pdf_sayfalari_olusturuluyor)
        progress < 1f -> stringResource(RdR.string.rd_rapor_arsive_kaydediliyor)
        format == ResultReportFormat.Pdf -> stringResource(RdR.string.rd_pdf_hazir)
        else -> stringResource(RdR.string.rd_excel_hazir)
    }
    Box(Modifier.fillMaxSize().background(colors.onyx.copy(.22f)), contentAlignment = Alignment.Center) {
        Column(
            Modifier.padding(horizontal = 28.dp).fillMaxWidth().heightIn(max = 470.dp)
                .shadow(34.dp, RoundedCornerShape(30.dp)).clip(RoundedCornerShape(30.dp))
                .background(colors.white.copy(.96f)).border(1.dp, colors.white.copy(.7f), RoundedCornerShape(30.dp))
                .padding(horizontal = 24.dp, vertical = 30.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            Box(Modifier.size(132.dp).scale(pulse).clip(CircleShape).background(colors.greenSoft), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(progress = { progress.coerceIn(.04f, 1f) }, modifier = Modifier.size(104.dp), color = colors.green, trackColor = colors.green.copy(.16f), strokeWidth = 8.dp)
                Icon(Icons.Filled.FindInPage, null, tint = colors.onyx, modifier = Modifier.size(39.dp))
                Icon(Icons.Filled.AutoAwesome, null, tint = colors.green, modifier = Modifier.align(Alignment.TopEnd).padding(17.dp).size(19.dp))
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(if (format == ResultReportFormat.Pdf) RdR.string.rd_pdf_hazirlaniyor else RdR.string.rd_excel_hazirlaniyor), style = iosRounded(28f, FontWeight.Bold, tracking = -.4f), color = colors.onyx)
                Text(status, style = iosRounded(15f, FontWeight.Medium), color = colors.slate, textAlign = TextAlign.Center)
            }
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(RdR.string.rd_ilerleme).uppercase(Locale.forLanguageTag("tr-TR")), style = iosRounded(11f, FontWeight.Bold, tracking = .55f), color = colors.slate, modifier = Modifier.weight(1f))
                    Text("${(progress * 100).toInt()}%", style = iosRounded(20f, FontWeight.Black), color = colors.green)
                }
                LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth().height(12.dp).clip(CircleShape), color = colors.green, trackColor = colors.fog)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.AutoAwesome, null, tint = colors.slate, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(7.dp))
                Text(stringResource(RdR.string.rd_uygulamayi_acik_tut), style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
            }
        }
    }
}

private fun parityLevel(finding: Finding, method: ParityRiskMethod): RiskLevel =
    riskLevelFromRaw(if (method == ParityRiskMethod.FineKinney) finding.fkBand else finding.m5Band)

private fun parityScore(finding: Finding, method: ParityRiskMethod): Double =
    if (method == ParityRiskMethod.FineKinney) finding.fkScore ?: 0.0 else finding.m5Score?.toDouble() ?: 0.0

@Composable
private fun parityBandLabel(level: RiskLevel): String = when (level) {
    RiskLevel.Critical -> stringResource(RdR.string.rd_tolerans_disi)
    RiskLevel.High -> stringResource(RdR.string.rd_risk_yuksek)
    RiskLevel.Medium -> stringResource(RdR.string.rd_risk_orta)
    RiskLevel.Low -> stringResource(RdR.string.rd_risk_dusuk)
    RiskLevel.Unknown -> stringResource(RdR.string.rd_risk_bilinmiyor)
}

@Composable
private fun riskShortLabel(level: RiskLevel): String = stringResource(
    when (level) {
        RiskLevel.Critical -> RdR.string.rd_krt
        RiskLevel.High -> RdR.string.rd_yuk_kisa
        RiskLevel.Medium -> RdR.string.rd_ort_kisa
        RiskLevel.Low -> RdR.string.rd_dus_kisa
        RiskLevel.Unknown -> RdR.string.rd_bilinmiyor_kisa
    },
)

@Composable
private fun parityAction(level: RiskLevel): String = stringResource(
    when (level) {
        RiskLevel.Critical -> RdR.string.rd_is_derhal_durdurulmali
        RiskLevel.High -> RdR.string.rd_acil_duzeltici_faaliyet
        RiskLevel.Medium -> RdR.string.rd_duzeltici_faaliyet_planlanmali
        RiskLevel.Low, RiskLevel.Unknown -> RdR.string.rd_kontroller_surdurulmeli
    },
)

private fun parityFormulaValues(finding: Finding, method: ParityRiskMethod): String = if (method == ParityRiskMethod.FineKinney) {
    "${formatScore(finding.fkProbability ?: 0.0)} × ${formatScore(finding.fkFrequency ?: 0.0)} × ${formatScore(finding.fkSeverity ?: 0.0)}"
} else {
    "${finding.m5Probability ?: 0} × ${finding.m5Severity ?: 0}"
}

private fun formatScore(value: Double): String = NumberFormat.getNumberInstance(Locale.forLanguageTag("tr-TR")).apply {
    maximumFractionDigits = if (value % 1.0 == 0.0) 0 else 1
}.format(value)

private fun formatResultDate(raw: String?): String {
    if (raw.isNullOrBlank()) return "—"
    return runCatching {
        OffsetDateTime.parse(raw).format(DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm", Locale.forLanguageTag("tr-TR")))
    }.getOrDefault(raw.take(16).replace('T', ' '))
}

private fun analysisSectorLabel(raw: String?, fallback: String): String =
    raw?.let(AnalysisSector::fromId)?.titleTr ?: raw?.takeIf { it.isNotBlank() } ?: fallback

private fun Int?.orEmpty(): Int = this ?: 0
