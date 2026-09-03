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
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
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
import androidx.compose.material.icons.filled.Book
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
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.outlined.ThumbDownAlt
import androidx.compose.material.icons.outlined.ThumbUpAlt
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
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
import com.riskdetectedan.core.data.analysis.AnalysisResultHubResponse
import com.riskdetectedan.core.data.analysis.AnalysisResultSection
import com.riskdetectedan.core.data.analysis.AnalysisResultSectionId
import com.riskdetectedan.core.data.analysis.AnalysisResultAccess
import com.riskdetectedan.core.data.analysis.AnalysisResultHubItem
import com.riskdetectedan.core.data.analysis.AnalysisItemReaction
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.Finding
import com.riskdetectedan.core.data.analysis.FindingMeasure
import com.riskdetectedan.core.data.analysis.FindingPatch
import com.riskdetectedan.core.data.analysis.FineKinneyValues
import com.riskdetectedan.core.data.analysis.PlanCapabilities
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.designsystem.R as RdR
import com.riskdetectedan.core.designsystem.RdColors
import com.riskdetectedan.core.designsystem.RdFontFamily
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
import com.riskdetectedan.core.designsystem.rdAnalysisCanvasTitle
import com.riskdetectedan.core.designsystem.rdAnalysisSectorTitle
import java.io.File
import java.io.ByteArrayOutputStream
import java.text.NumberFormat
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

private enum class ParityRiskMethod(val wire: String) { FineKinney("fine_kinney"), Matrix5x5("matrix_5x5") }
private enum class ParityReportKind { Standard, RiskAnalysis }

/**
 * Screen-specific mirror of iOS `RDTypography.font` calls. Build 87 moved the complete iOS
 * product to Mulish, so the Android result flow must use the same bundled family and metrics.
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
        fontFamily = RdFontFamily,
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
        fontFamily = RdFontFamily,
        fontFeatureSettings = "tnum",
        letterSpacing = tracking.sp,
        platformStyle = PlatformTextStyle(includeFontPadding = false),
    )
}

@Composable
private fun String.localizedUppercase(): String =
    uppercase(LocalConfiguration.current.locales[0])

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
                            Text("$percent", style = iosRounded(64f, FontWeight.Black, tracking = -0.5f, lineHeightMultiplier = 1f), color = Color.White)
                            Text("%", style = iosRounded(28f, FontWeight.Black, lineHeightMultiplier = 1f), color = Color.White.copy(.92f), modifier = Modifier.padding(bottom = 5.dp))
                        }
                        if (photoCount > 1) {
                            Text(
                                stringResource(RdR.string.rd_fotograf_sayisi_format, photoCount),
                                style = iosRounded(11f, FontWeight.Bold),
                                color = Color.White,
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
            Text(stringResource(RdR.string.rd_analiz_devam_ediyor), style = iosRounded(22f, FontWeight.Bold, tracking = -0.4f), color = colors.black)
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
            if (complete) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(13.dp))
            else if (active) Box(Modifier.size(7.dp).clip(CircleShape).background(colors.selected))
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(label, style = iosRounded(13.5f, FontWeight.SemiBold), color = colors.black, maxLines = 1)
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
    resultHub: AnalysisResultHubResponse? = null,
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
    onUpgradeTierAt: (SubscriptionTier, String) -> Unit = { tier, _ -> onUpgradeTier(tier) },
    onResultHubUpgrade: (AnalysisResultSectionId) -> Unit = { onUpgradeTier(SubscriptionTier.Plus) },
    onFeedback: (AnalysisResultSectionId, AnalysisResultHubItem, AnalysisItemReaction, String?, String?) -> Unit = { _, _, _, _, _ -> },
    onResultEvent: (String, AnalysisResultSectionId?, String?) -> Unit = { _, _, _ -> },
    onEditNotebook: (AnalysisResultHubItem, String, String) -> Unit = { _, _, _ -> },
    onSuppressNotebook: (AnalysisResultHubItem) -> Unit = {},
) {
    val colors = RdTheme.colors
    var method by remember { mutableStateOf(ParityRiskMethod.FineKinney) }
    var showReportSheet by remember { mutableStateOf(false) }
    var editingFinding by remember { mutableStateOf<Finding?>(null) }
    var deletingFinding by remember { mutableStateOf<Finding?>(null) }
    var selectedFinding by remember { mutableStateOf<Finding?>(null) }
    var selectedHubItemId by remember { mutableStateOf<String?>(null) }
    var hubSection by remember { mutableStateOf(AnalysisResultSectionId.RiskAnalysis) }
    var hubSelections by remember { mutableStateOf<Map<AnalysisResultSectionId, Set<String>>>(emptyMap()) }
    val context = LocalContext.current
    val chooserTitle = stringResource(RdR.string.rd_raporu_paylas)
    val fallbackAnalysisTitle = stringResource(RdR.string.rd_adsiz_analiz)
    val canvasLabel = summary?.canvas?.let { id -> rdAnalysisCanvasTitle(id, AnalysisCanvas.all.firstOrNull { it.id == id }?.title ?: id) }
        ?: stringResource(RdR.string.rd_genel)
    val selectedHubItem = selectedHubItemId?.let { id ->
        resultHub?.sections?.asSequence()?.flatMap { it.items.asSequence() }?.firstOrNull { it.id == id }
    }

    LaunchedEffect(resultHub?.analysisId) {
        val hub = resultHub ?: return@LaunchedEffect
        hubSelections = hub.sections.associate { section ->
            section.id to if (section.access == AnalysisResultAccess.Full && section.canReport) {
                section.items.map { it.id }.toSet()
            } else {
                emptySet()
            }
        }
    }

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
            ParityResultHeader(
                onBack = onBack,
                profile = reportSetup.profile,
                tier = reportSetup.profile?.tier ?: capabilities.tier,
                onUpgrade = { tier -> onUpgradeTierAt(tier, "result_header_upgrade") },
            )
            if (resultHub?.enabled == true) {
                ResultHubSurface(
                    hub = resultHub,
                    summary = summary,
                    photoBytes = photoBytes,
                    selectedSection = hubSection,
                    onSectionSelected = {
                        hubSection = it
                        onResultEvent("result_section_selected", it, null)
                        if (resultHub.sections.firstOrNull { section -> section.id == it }?.access == AnalysisResultAccess.Teaser) {
                            onResultEvent("locked_teaser_impression", it, null)
                        }
                    },
                    selections = hubSelections,
                    onSelectionsChanged = { hubSelections = it },
                    method = method,
                    onMethodChange = { method = it },
                    canEdit = true,
                    onEdit = { editingFinding = it.toFinding(analysisId) },
                    onDelete = { deletingFinding = it.toFinding(analysisId) },
                    onDetail = { item ->
                        if (hubSection == AnalysisResultSectionId.RiskAnalysis) {
                            selectedHubItemId = item.id
                            selectedFinding = item.toFinding(analysisId)
                        }
                    },
                    onFeedback = onFeedback,
                    onUpgrade = {
                        onResultEvent("locked_teaser_cta_tapped", hubSection, null)
                        onResultHubUpgrade(hubSection)
                    },
                    onReport = { showReportSheet = true },
                    onBack = { onBack?.invoke() },
                    onEvent = onResultEvent,
                    onEditNotebook = onEditNotebook,
                    onSuppressNotebook = onSuppressNotebook,
                )
            } else LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 20.dp, end = 20.dp, bottom = 108.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item {
                    ResultMetaSurface(summary, canvasLabel, photoBytes, findings, capabilities) { tier ->
                        onUpgradeTierAt(tier, "result_summary_upgrade_hint")
                    }
                }
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
                                onUpgrade = { tier -> onUpgradeTierAt(tier, "result_finding_locked_feature") },
                                onOpenDetail = { selectedHubItemId = null; selectedFinding = finding },
                            )
                            if (capabilities.tier == SubscriptionTier.Free && index < 2) {
                                LockedFindingPreviewCard(
                                    number = findings.size + index + 1,
                                    requiredTier = if (index == 0) SubscriptionTier.Pro else SubscriptionTier.Plus,
                                    level = if (index == 0) RiskLevel.High else RiskLevel.Medium,
                                    onUpgrade = { tier -> onUpgradeTierAt(tier, "result_locked_finding_preview") },
                                )
                            }
                        }
                    }
                }
            }
        }

        if (resultHub?.enabled != true) Box(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, colors.paper, colors.paper)))
                .padding(horizontal = 20.dp, vertical = 14.dp),
        ) {
            Button(
                onClick = { showReportSheet = true },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = colors.cta, contentColor = Color.White),
            ) {
                Icon(Icons.Filled.Tune, null, Modifier.size(20.dp))
                Spacer(Modifier.width(10.dp))
                Text(stringResource(RdR.string.rd_rapor_olustur), style = RdFontStyle.Callout.toTextStyle(), modifier = Modifier.weight(1f))
                Box(Modifier.size(34.dp).clip(CircleShape).background(colors.white), contentAlignment = Alignment.Center) {
                    Icon(Icons.AutoMirrored.Filled.Send, null, tint = colors.black, modifier = Modifier.size(17.dp))
                }
            }
        }

        selectedFinding?.let { finding ->
            FindingDetailSurface(
                finding = finding,
                method = method,
                photos = photoBytes,
                tier = capabilities.tier,
                analysisTitle = summary?.title.orEmpty(),
                analysisSector = summary?.analysisSector,
                reaction = selectedHubItem?.userReaction,
                onFeedback = selectedHubItem?.let { hubItem ->
                    { reaction, reason, note -> onFeedback(hubSection, hubItem, reaction, reason, note) }
                },
                onMethodChange = { method = it },
                onClose = { selectedHubItemId = null; selectedFinding = null },
                onEdit = { editingFinding = finding },
                onDelete = { deletingFinding = finding },
                onGenerateReport = { showReportSheet = true },
                onShareReport = { showReportSheet = true },
                onUpgrade = { tier -> onUpgradeTierAt(tier, "finding_detail_regulatory_references") },
            )
        }
    }

    BackHandler(enabled = selectedFinding != null) { selectedHubItemId = null; selectedFinding = null }

    if (showReportSheet) {
        val reportSection = resultHub?.takeIf { it.enabled }?.sections?.firstOrNull { it.id == hubSection }
        val reportSelectedCount = reportSection?.let { hubSelections[hubSection].orEmpty().size } ?: findings.size
        val reportTotalCount = reportSection?.count ?: findings.size
        val reportSectorLabel = summary?.analysisSector?.let { analysisSectorLabel(it, it) }
        ResultReportSettingsSheet(
            tier = reportSetup.profile?.tier ?: capabilities.tier,
            sectionId = reportSection?.id ?: AnalysisResultSectionId.RiskAnalysis,
            selectedCount = reportSelectedCount,
            totalCount = reportTotalCount,
            method = method,
            onMethodChange = { method = it },
            onClose = { showReportSheet = false },
            onOpenCompanies = onOpenCompanies,
            onUpgrade = { onUpgradeTierAt(SubscriptionTier.Plus, "result_locked_report_options") },
            companies = reportSetup.companies,
            profile = reportSetup.profile,
            initialCompanyId = summary?.companyId,
            onGenerate = { kind, output, customization ->
                showReportSheet = false
                val activeHubSection = resultHub?.takeIf { it.enabled }?.sections?.firstOrNull { it.id == hubSection }
                val selectedHubIds = hubSelections[hubSection].orEmpty()
                val selectedHubItems = activeHubSection?.items?.filter { it.id in selectedHubIds }.orEmpty()
                val request = ResultReportRequest(
                    analysisId = analysisId,
                    title = summary?.title ?: fallbackAnalysisTitle,
                    canvasLabel = canvasLabel,
                    createdAt = summary?.createdAt,
                    companyId = customization.companyId,
                    findings = if (activeHubSection != null) selectedHubItems.map { it.toFinding(analysisId) } else findings,
                    coverPhotoBytes = photoBytes.firstOrNull(),
                    photoBytes = photoBytes,
                    analysisSummary = summary?.aiSummary,
                    analysisSectorLabel = reportSectorLabel,
                    companyNameOverride = customization.companyName,
                    companyInfoOverride = customization.companyInfo,
                    companyLogoOverrideBytes = customization.companyLogoBytes,
                    preparedByOverride = customization.preparedBy,
                    preparedTitleOverride = customization.preparedTitle,
                    certificateNumberOverride = customization.certificateNumber,
                    contentScope = activeHubSection?.id,
                    selectedItemKeys = selectedHubIds.toList(),
                )
                onGenerateReport(
                    request,
                    activeHubSection?.id?.let {
                        when (it) {
                            AnalysisResultSectionId.RiskAnalysis -> "risk_analysis"
                            AnalysisResultSectionId.ExpertRecommendations -> "expert_recommendations"
                            AnalysisResultSectionId.TrainingRecommendations -> "training_recommendations"
                            AnalysisResultSectionId.ApprovedNotebook -> "approved_notebook"
                        }
                    } ?: if (kind == ParityReportKind.Standard) "standard" else "risk_analysis",
                    method.wire,
                    output,
                )
            },
        )
    }

    editingFinding?.let { finding ->
        IosParityFindingEditorSheet(
            finding = finding,
            method = method,
            onDismiss = { editingFinding = null },
            onDelete = { deletingFinding = finding; editingFinding = null },
            onSave = { patch ->
                editingFinding = null
                onUpdate(finding, patch)
            },
        )
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ResultHubSurface(
    hub: AnalysisResultHubResponse,
    summary: AnalysisResultSummary?,
    photoBytes: List<ByteArray>,
    selectedSection: AnalysisResultSectionId,
    onSectionSelected: (AnalysisResultSectionId) -> Unit,
    selections: Map<AnalysisResultSectionId, Set<String>>,
    onSelectionsChanged: (Map<AnalysisResultSectionId, Set<String>>) -> Unit,
    method: ParityRiskMethod,
    onMethodChange: (ParityRiskMethod) -> Unit,
    canEdit: Boolean,
    onEdit: (AnalysisResultHubItem) -> Unit,
    onDelete: (AnalysisResultHubItem) -> Unit,
    onDetail: (AnalysisResultHubItem) -> Unit,
    onFeedback: (AnalysisResultSectionId, AnalysisResultHubItem, AnalysisItemReaction, String?, String?) -> Unit,
    onUpgrade: () -> Unit,
    onReport: () -> Unit,
    onBack: () -> Unit,
    onEvent: (String, AnalysisResultSectionId?, String?) -> Unit,
    onEditNotebook: (AnalysisResultHubItem, String, String) -> Unit,
    onSuppressNotebook: (AnalysisResultHubItem) -> Unit,
) {
    val colors = RdTheme.colors
    val section = hub.sections.firstOrNull { it.id == selectedSection } ?: hub.sections.firstOrNull()
    val selected = selections[selectedSection].orEmpty()
    val activeAccent = resultSectionAccent(selectedSection, colors)
    val activeStrong = resultSectionStrong(selectedSection, colors)
    val activeTint = resultSectionTint(selectedSection, colors)
    var detailItem by remember { mutableStateOf<AnalysisResultHubItem?>(null) }
    var editingNotebook by remember { mutableStateOf<AnalysisResultHubItem?>(null) }
    var notebookFindingDraft by remember { mutableStateOf("") }
    var notebookRecommendationDraft by remember { mutableStateOf("") }
    var pendingNotebookSuppression by remember { mutableStateOf<AnalysisResultHubItem?>(null) }
    var pendingDislike by remember { mutableStateOf<AnalysisResultHubItem?>(null) }
    var feedbackComposerExpanded by remember { mutableStateOf(false) }
    var feedbackNote by remember { mutableStateOf("") }
    var feedbackThanksVisible by remember { mutableStateOf(false) }
    val trainingDisclaimer = stringResource(RdR.string.rd_result_training_disclaimer)

    LaunchedEffect(feedbackThanksVisible) {
        if (feedbackThanksVisible) {
            kotlinx.coroutines.delay(3_000)
            feedbackThanksVisible = false
        }
    }

    Box(Modifier.fillMaxSize().background(colors.resultBackground)) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 112.dp),
        ) {
            stickyHeader {
                ResultHubSectionTabs(hub.sections, selectedSection, onSectionSelected)
            }

            if (section == null || section.items.isEmpty()) {
                item {
                    Column(
                        Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 18.dp)
                            .clip(RoundedCornerShape(12.dp)).background(colors.resultSurface)
                            .border(1.dp, colors.resultLine, RoundedCornerShape(12.dp)).padding(vertical = 34.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Filled.FactCheck, null, tint = activeStrong)
                        Text(stringResource(RdR.string.rd_result_empty_section), style = iosRounded(14f, FontWeight.Bold), color = colors.resultPrimaryText)
                    }
                }
            } else {
                if (selectedSection == AnalysisResultSectionId.RiskAnalysis) {
                    item {
                        ResultHubAnalysisInfoCard(summary, photoBytes, section.count)
                    }
                    item {
                        ResultHubRiskSummary(
                            items = section.items,
                            method = method,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp),
                        )
                    }
                    item {
                        ResultHubMethodSelector(
                            method = method,
                            onChange = onMethodChange,
                            modifier = Modifier.padding(horizontal = 20.dp),
                        )
                    }
                    item {
                        ResultHubSelectionControls(
                            section = section,
                            selected = selected,
                            accent = activeStrong,
                            onToggleAll = {
                                val all = section.items.map { it.id }.toSet()
                                val next = if (selected.size == all.size) emptySet() else all
                                onSelectionsChanged(selections + (selectedSection to next))
                                onEvent("report_selection_changed", selectedSection, null)
                            },
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
                        )
                    }
                } else {
                    val disclaimer = when (selectedSection) {
                        AnalysisResultSectionId.ApprovedNotebook -> hub.disclaimers?.notebook
                        AnalysisResultSectionId.TrainingRecommendations -> trainingDisclaimer
                        AnalysisResultSectionId.ExpertRecommendations -> hub.disclaimers?.expert
                        AnalysisResultSectionId.RiskAnalysis -> null
                    }
                    if (!disclaimer.isNullOrBlank()) item {
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp)
                                .clip(RoundedCornerShape(12.dp)).background(activeTint).padding(12.dp),
                            horizontalArrangement = Arrangement.spacedBy(9.dp),
                        ) {
                            Icon(Icons.Filled.Info, null, tint = activeStrong, modifier = Modifier.size(18.dp))
                            Text(disclaimer, style = iosRounded(11.5f), color = colors.resultSecondaryText, modifier = Modifier.weight(1f))
                        }
                    }
                    if (selectedSection == AnalysisResultSectionId.ApprovedNotebook && section.observationBasis != null) item {
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(7.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Filled.FactCheck, null, tint = activeStrong, modifier = Modifier.size(16.dp))
                            Text(
                                stringResource(RdR.string.rd_result_notebook_observation_basis),
                                style = iosRounded(11f),
                                color = colors.resultSecondaryText,
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                    item {
                        ResultHubSelectionControls(
                            section = section,
                            selected = selected,
                            accent = activeStrong,
                            onToggleAll = {
                                val all = section.items.map { it.id }.toSet()
                                val next = if (selected.size == all.size) emptySet() else all
                                onSelectionsChanged(selections + (selectedSection to next))
                                onEvent("report_selection_changed", selectedSection, null)
                            },
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
                        )
                    }
                }

                if (selectedSection == AnalysisResultSectionId.ApprovedNotebook) {
                    item {
                        ResultHubNotebookPaper(
                            items = section.items,
                            access = section.access,
                            onUpgrade = onUpgrade,
                            modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 34.dp),
                        )
                    }
                } else itemsIndexed(section.items, key = { _, item -> item.id }) { index, item ->
                    Box(Modifier.padding(start = 20.dp, end = 20.dp, bottom = 34.dp)) {
                        ResultHubItemCard(
                            item = item,
                            position = index + 1,
                            sectionId = selectedSection,
                            access = section.access,
                            selected = item.id in selected,
                            method = method,
                            // Risk findings are always editable in the full result section.
                            // Some older result-hub payloads were persisted before `can_edit`
                            // was added and decode it as false; iOS still exposes the finding
                            // editor for this section, so keep the Android parity behaviour
                            // independent from that legacy metadata value.
                            canEdit = canEdit && (section.canEdit || selectedSection == AnalysisResultSectionId.RiskAnalysis),
                            canReport = section.canReport,
                            onToggleSelected = {
                                val next = selected.toMutableSet().also { set -> if (!set.add(item.id)) set.remove(item.id) }
                                onSelectionsChanged(selections + (selectedSection to next))
                                onEvent("report_selection_changed", selectedSection, item.id)
                            },
                            onLike = {
                                val next = if (item.userReaction == AnalysisItemReaction.Like) AnalysisItemReaction.None else AnalysisItemReaction.Like
                                onFeedback(selectedSection, item, next, null, null)
                                if (next == AnalysisItemReaction.Like) feedbackThanksVisible = true
                            },
                            onDislike = {
                                if (item.userReaction == AnalysisItemReaction.Dislike) {
                                    onFeedback(selectedSection, item, AnalysisItemReaction.None, null, null)
                                } else {
                                    feedbackComposerExpanded = false
                                    feedbackNote = ""
                                    pendingDislike = item
                                }
                            },
                            onEdit = { onEdit(item) },
                            onDelete = { onDelete(item) },
                            onDetail = {
                                onEvent("result_item_detail_opened", selectedSection, item.id)
                                if (selectedSection == AnalysisResultSectionId.RiskAnalysis) onDetail(item) else detailItem = item
                            },
                            onUpgrade = onUpgrade,
                        )
                    }
                }
            }
        }

        val trainingWithoutReport = selectedSection == AnalysisResultSectionId.TrainingRecommendations && section?.canReport != true
        val trainingPro = trainingWithoutReport && hub.tier.equals("pro", ignoreCase = true)
        ResultHubReportBar(
            selectedSection = selectedSection,
            section = section,
            selectedCount = selected.size,
            activeAccent = activeAccent,
            activeStrong = activeStrong,
            activeTint = activeTint,
            trainingWithoutReport = trainingWithoutReport,
            trainingPro = trainingPro,
            onBack = onBack,
            onUpgrade = onUpgrade,
            onReport = onReport,
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }

    detailItem?.let { item ->
        ModalBottomSheet(
            onDismissRequest = { detailItem = null },
            containerColor = colors.paper,
        ) {
            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    when (selectedSection) {
                        AnalysisResultSectionId.ApprovedNotebook -> stringResource(RdR.string.rd_result_notebook_recommendation)
                        AnalysisResultSectionId.TrainingRecommendations -> stringResource(RdR.string.rd_result_training_recommendation)
                        AnalysisResultSectionId.ExpertRecommendations -> stringResource(RdR.string.rd_result_expert_recommendation)
                        AnalysisResultSectionId.RiskAnalysis -> stringResource(RdR.string.rd_result_risk_finding)
                    },
                    style = iosRounded(11f, FontWeight.Bold), color = colors.greenDark,
                )
                Text(item.displayTitle, style = iosRounded(21f, FontWeight.Bold), color = colors.black)
                if (selectedSection == AnalysisResultSectionId.TrainingRecommendations) {
                    listOfNotNull(item.categoryLabel, item.audienceLabel, item.durationLabel)
                        .filter(String::isNotBlank)
                        .forEach { label ->
                            Text(
                                label,
                                style = iosRounded(11f, FontWeight.SemiBold),
                                color = colors.greenDark,
                                modifier = Modifier.clip(RoundedCornerShape(10.dp))
                                    .background(colors.greenSoft)
                                    .padding(horizontal = 10.dp, vertical = 6.dp),
                            )
                        }
                }
                if (item.displayBody.isNotBlank()) Text(item.displayBody, style = iosRounded(13f), color = colors.graphite)
                item.durationValue?.takeIf(String::isNotBlank)?.let {
                    Text(stringResource(RdR.string.rd_result_duration), style = iosRounded(11f, FontWeight.Bold), color = colors.greenDark)
                    Text(it, style = iosRounded(13f), color = colors.graphite)
                }
                item.durationNote?.takeIf(String::isNotBlank)?.let {
                    Text(it, style = iosRounded(11.5f), color = colors.slate)
                }
                item.recommendedAction?.takeIf(String::isNotBlank)?.let {
                    Text(stringResource(RdR.string.rd_result_recommendation), style = iosRounded(11f, FontWeight.Bold), color = colors.greenDark)
                    Text(it, style = iosRounded(13f), color = colors.graphite)
                }
                item.referenceText?.takeIf(String::isNotBlank)?.let {
                    Text(stringResource(RdR.string.rd_result_basis), style = iosRounded(11f, FontWeight.Bold), color = colors.greenDark)
                    Text(it, style = iosRounded(12f), color = colors.slate)
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }

    editingNotebook?.let { item ->
        AlertDialog(
            onDismissRequest = { editingNotebook = null },
            title = { Text(stringResource(RdR.string.rd_result_edit_notebook_draft)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(
                        value = notebookFindingDraft,
                        onValueChange = { notebookFindingDraft = it },
                        label = { Text(stringResource(RdR.string.rd_result_finding)) },
                        minLines = 4,
                    )
                    OutlinedTextField(
                        value = notebookRecommendationDraft,
                        onValueChange = { notebookRecommendationDraft = it },
                        label = { Text(stringResource(RdR.string.rd_result_recommendation)) },
                        minLines = 5,
                    )
                    Text(stringResource(RdR.string.rd_result_notebook_draft_disclaimer), style = iosRounded(11f), color = colors.slate)
                }
            },
            confirmButton = {
                TextButton(
                    enabled = notebookFindingDraft.isNotBlank() && notebookRecommendationDraft.isNotBlank(),
                    onClick = {
                        onEditNotebook(item, notebookFindingDraft.trim(), notebookRecommendationDraft.trim())
                        editingNotebook = null
                    },
                ) { Text(stringResource(RdR.string.rd_kaydet)) }
            },
            dismissButton = { TextButton(onClick = { editingNotebook = null }) { Text(stringResource(RdR.string.rd_vazgec)) } },
        )
    }
    pendingNotebookSuppression?.let { item ->
        AlertDialog(
            onDismissRequest = { pendingNotebookSuppression = null },
            title = { Text(stringResource(RdR.string.rd_result_hide_notebook_title)) },
            text = { Text(stringResource(RdR.string.rd_result_hide_notebook_body)) },
            confirmButton = {
                TextButton(onClick = { pendingNotebookSuppression = null; onSuppressNotebook(item) }) { Text(stringResource(RdR.string.rd_result_hide)) }
            },
            dismissButton = { TextButton(onClick = { pendingNotebookSuppression = null }) { Text(stringResource(RdR.string.rd_vazgec)) } },
        )
    }
    pendingDislike?.let { item ->
        val reasons = listOf(
            stringResource(RdR.string.rd_feedback_incorrect_detection) to "incorrect_detection",
            stringResource(RdR.string.rd_feedback_missing_context) to "missing_context",
            stringResource(RdR.string.rd_feedback_wrong_score) to "wrong_score",
            stringResource(RdR.string.rd_feedback_wrong_recommendation) to "wrong_recommendation",
            stringResource(RdR.string.rd_feedback_duplicate) to "duplicate",
            stringResource(RdR.string.rd_feedback_irrelevant) to "irrelevant",
            stringResource(RdR.string.rd_feedback_unclear_text) to "unclear_text",
            stringResource(RdR.string.rd_feedback_other) to "other",
        )
        AlertDialog(
            onDismissRequest = {
                pendingDislike = null
                feedbackComposerExpanded = false
                feedbackNote = ""
            },
            title = { Text(stringResource(RdR.string.rd_feedback_improve_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        stringResource(RdR.string.rd_feedback_improve_body),
                        style = iosRounded(11.5f),
                        color = colors.slate,
                    )
                    if (!feedbackComposerExpanded) reasons.forEach { (label, code) ->
                        TextButton(onClick = {
                            pendingDislike = null
                            onFeedback(selectedSection, item, AnalysisItemReaction.Dislike, code, null)
                            feedbackThanksVisible = true
                        }) {
                            Text(label, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Start)
                        }
                    }
                    if (!feedbackComposerExpanded) {
                        TextButton(onClick = { feedbackComposerExpanded = true }) {
                            Icon(Icons.Filled.Edit, null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(7.dp))
                            Text(stringResource(RdR.string.rd_feedback_write_reason), modifier = Modifier.fillMaxWidth())
                        }
                    } else {
                        OutlinedTextField(
                            value = feedbackNote,
                            onValueChange = { feedbackNote = it.take(1000) },
                            label = { Text(stringResource(RdR.string.rd_feedback_label)) },
                            placeholder = { Text(stringResource(RdR.string.rd_feedback_placeholder)) },
                            minLines = 4,
                            supportingText = { Text("${feedbackNote.length}/1000") },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            },
            confirmButton = {
                if (feedbackComposerExpanded) {
                    TextButton(
                        enabled = feedbackNote.isNotBlank(),
                        onClick = {
                            val note = feedbackNote.trim()
                            pendingDislike = null
                            feedbackComposerExpanded = false
                            feedbackNote = ""
                            onFeedback(selectedSection, item, AnalysisItemReaction.Dislike, "other", note)
                            feedbackThanksVisible = true
                        },
                    ) { Text(stringResource(RdR.string.rd_gonder)) }
                } else {
                    TextButton(onClick = { pendingDislike = null }) { Text(stringResource(RdR.string.rd_kapat)) }
                }
            },
            dismissButton = if (feedbackComposerExpanded) {
                { TextButton(onClick = { feedbackComposerExpanded = false; feedbackNote = "" }) { Text(stringResource(RdR.string.rd_geri)) } }
            } else null,
        )
    }

    if (feedbackThanksVisible) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 20.dp)
                .clip(RoundedCornerShape(14.dp)).background(colors.white)
                .border(1.dp, colors.line, RoundedCornerShape(14.dp)).padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.CheckCircle, null, tint = colors.green, modifier = Modifier.size(26.dp))
            Text(
                stringResource(RdR.string.rd_feedback_thanks),
                style = iosRounded(11.5f, FontWeight.SemiBold),
                color = colors.black,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun ResultHubSectionTabs(
    sections: List<AnalysisResultSection>,
    selectedSection: AnalysisResultSectionId,
    onSectionSelected: (AnalysisResultSectionId) -> Unit,
) {
    val colors = RdTheme.colors
    val scrollState = rememberScrollState()
    val density = LocalDensity.current
    val railColor = resultSectionAccent(selectedSection, colors)
    BoxWithConstraints(Modifier.fillMaxWidth().height(96.dp).background(colors.resultBackground)) {
        val gap = 6.7.dp
        val horizontalGutter = 14.dp
        val visibleTabs = if (sections.size <= 3) sections.size.coerceAtLeast(1).toFloat() else 3.5f
        val fittedWidth = ((maxWidth - horizontalGutter * 2 - gap * (sections.size.coerceAtMost(4) - 1)) / visibleTabs)
            .coerceAtLeast(88.dp)
        val scrollable = sections.size > 3
        LaunchedEffect(selectedSection, scrollable, maxWidth) {
            if (!scrollable) return@LaunchedEffect
            withFrameNanos { }
            val index = sections.indexOfFirst { it.id == selectedSection }.coerceAtLeast(0)
            val target = with(density) {
                ((fittedWidth + gap) * index - (maxWidth - fittedWidth) / 2).roundToPx()
            }.coerceIn(0, scrollState.maxValue)
            scrollState.animateScrollTo(target)
        }
        Box(Modifier.fillMaxSize()) {
            Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(1.5.dp).background(railColor))
            Row(
                Modifier.fillMaxWidth().padding(horizontal = horizontalGutter)
                    .then(if (scrollable) Modifier.horizontalScroll(scrollState) else Modifier),
                horizontalArrangement = Arrangement.spacedBy(gap),
                verticalAlignment = Alignment.Bottom,
            ) {
                sections.forEach { target ->
                    val active = target.id == selectedSection
                    val accent = resultSectionAccent(target.id, colors)
                    val title = when (target.id) {
                        AnalysisResultSectionId.RiskAnalysis -> stringResource(RdR.string.rd_risk_analizi)
                        AnalysisResultSectionId.ExpertRecommendations -> stringResource(RdR.string.rd_result_expert_opinion)
                        AnalysisResultSectionId.TrainingRecommendations -> stringResource(RdR.string.rd_result_training_recommendations)
                        AnalysisResultSectionId.ApprovedNotebook -> stringResource(RdR.string.rd_result_approved_notebook)
                    }
                    val countName = when (target.id) {
                        AnalysisResultSectionId.RiskAnalysis -> stringResource(RdR.string.rd_result_unit_finding)
                        AnalysisResultSectionId.ExpertRecommendations -> stringResource(RdR.string.rd_result_unit_recommendation)
                        AnalysisResultSectionId.TrainingRecommendations -> stringResource(RdR.string.rd_result_unit_recommendation)
                        AnalysisResultSectionId.ApprovedNotebook -> stringResource(RdR.string.rd_result_unit_record)
                    }
                    val icon = when (target.id) {
                        AnalysisResultSectionId.RiskAnalysis -> Icons.Filled.Warning
                        AnalysisResultSectionId.ExpertRecommendations -> Icons.Filled.VerifiedUser
                        AnalysisResultSectionId.TrainingRecommendations -> Icons.Filled.School
                        AnalysisResultSectionId.ApprovedNotebook -> Icons.Filled.Book
                    }
                    val borderModifier = if (active) {
                        Modifier.drawBehind {
                            val line = 1.5.dp.toPx()
                            val radius = 8.dp.toPx()
                            val path = Path().apply {
                                moveTo(line / 2, size.height)
                                lineTo(line / 2, radius)
                                quadraticBezierTo(line / 2, line / 2, radius, line / 2)
                                lineTo(size.width - radius, line / 2)
                                quadraticBezierTo(size.width - line / 2, line / 2, size.width - line / 2, radius)
                                lineTo(size.width - line / 2, size.height)
                            }
                            drawPath(path, accent, style = Stroke(line))
                        }
                    } else {
                        Modifier.clip(RoundedCornerShape(6.dp))
                            .border(1.dp, colors.resultLine, RoundedCornerShape(6.dp))
                    }
                    Column(
                        Modifier.width(fittedWidth)
                            .height(if (active) 84.dp else 72.dp)
                            .background(
                                if (active) colors.resultElevatedSurface else colors.resultSurface,
                                RoundedCornerShape(
                                    topStart = if (active) 8.dp else 6.dp,
                                    topEnd = if (active) 8.dp else 6.dp,
                                    bottomStart = if (active) 0.dp else 6.dp,
                                    bottomEnd = if (active) 0.dp else 6.dp,
                                ),
                            )
                            .then(borderModifier)
                            .clickable { onSectionSelected(target.id) }
                            .padding(horizontal = 4.dp, vertical = 7.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Icon(icon, null, tint = if (active) accent else colors.resultPrimaryText, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.height(5.dp))
                        Text(title, style = iosRounded(11.5f, FontWeight.ExtraBold), color = colors.resultPrimaryText, maxLines = 1, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(2.dp))
                        Text("${target.count} $countName", style = iosRounded(10f, FontWeight.SemiBold), color = colors.resultSecondaryText)
                    }
                }
            }
        }
    }
}

@Composable
private fun ResultHubAnalysisInfoCard(
    summary: AnalysisResultSummary?,
    photos: List<ByteArray>,
    itemCount: Int,
) {
    val colors = RdTheme.colors
    val images = remember(photos) {
        photos.take(3).mapNotNull { bytes ->
            runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }.getOrNull()
        }
    }
    Row(
        Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 12.dp)
            .clip(RoundedCornerShape(12.dp)).background(colors.resultGreenTint)
            .border(1.dp, colors.resultLine, RoundedCornerShape(12.dp))
            .padding(horizontal = 13.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                summary?.title?.takeIf(String::isNotBlank) ?: stringResource(RdR.string.rd_adsiz_analiz),
                style = iosRounded(16f, FontWeight.Black),
                color = colors.resultPrimaryText,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            summary?.analysisSector?.takeIf(String::isNotBlank)?.let { sector ->
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(RdR.string.rd_result_sector_label), style = iosRounded(10.5f, FontWeight.Bold), color = colors.resultTertiaryText)
                    Text(
                        analysisSectorLabel(sector, sector),
                        style = iosRounded(10.5f, FontWeight.Black),
                        color = colors.resultGreenDark,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (summary?.analysisSector.isNullOrBlank()) {
                Text(stringResource(RdR.string.rd_result_finding_count_format, itemCount), style = iosRounded(10.5f, FontWeight.Bold), color = colors.resultGreenDark)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            images.forEach { bitmap ->
                Image(
                    bitmap = bitmap,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(42.dp).shadow(4.dp, RoundedCornerShape(8.dp))
                        .clip(RoundedCornerShape(8.dp)).border(1.5.dp, Color.White, RoundedCornerShape(8.dp)),
                )
            }
        }
    }
}

@Composable
private fun ResultHubMethodSelector(
    method: ParityRiskMethod,
    onChange: (ParityRiskMethod) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = RdTheme.colors
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        ParityRiskMethod.entries.forEach { candidate ->
            val active = method == candidate
            Column(
                Modifier.weight(1f)
                    .shadow(if (active) 6.dp else 0.dp, RoundedCornerShape(8.dp), ambientColor = Color.Black.copy(.08f))
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (active) colors.resultSelectedSurface else colors.resultSubtleSurface)
                    .border(if (active) 1.5.dp else 1.dp, if (active) colors.resultGreen else colors.resultLine, RoundedCornerShape(8.dp))
                    .clickable { onChange(candidate) }
                    .padding(vertical = 5.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (active) Icon(Icons.Filled.Check, null, tint = colors.resultGreenDark, modifier = Modifier.size(10.dp))
                    Text(
                        if (candidate == ParityRiskMethod.FineKinney) "Fine-Kinney" else stringResource(RdR.string.rd_bes_carp_bes_matris),
                        style = iosRounded(11.5f, if (active) FontWeight.Black else FontWeight.Bold),
                        color = if (active) colors.resultGreenDark else colors.resultSecondaryText,
                    )
                }
                Text(
                    stringResource(if (candidate == ParityRiskMethod.FineKinney) RdR.string.rd_fk_formula else RdR.string.rd_matrix_formula),
                    style = iosRounded(8.5f, FontWeight.Bold, tracking = .2f),
                    color = if (active) colors.resultGreenDark else colors.resultSecondaryText,
                )
            }
        }
    }
}

@Composable
private fun ResultHubSelectionControls(
    section: AnalysisResultSection,
    selected: Set<String>,
    accent: Color,
    onToggleAll: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = RdTheme.colors
    val unit = when (section.id) {
        AnalysisResultSectionId.RiskAnalysis -> stringResource(RdR.string.rd_result_unit_finding)
        AnalysisResultSectionId.ExpertRecommendations -> stringResource(RdR.string.rd_result_unit_opinion)
        AnalysisResultSectionId.TrainingRecommendations -> stringResource(RdR.string.rd_result_unit_recommendation)
        AnalysisResultSectionId.ApprovedNotebook -> stringResource(RdR.string.rd_result_unit_record)
    }
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(RdR.string.rd_result_selection_format, selected.size, section.count, unit), style = iosRounded(10.5f, FontWeight.Bold), color = colors.resultTertiaryText)
        Spacer(Modifier.weight(1f))
        if (section.access == AnalysisResultAccess.Full) {
            Row(
                Modifier.clickable(onClick = onToggleAll).padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Icon(Icons.Filled.Check, null, tint = accent, modifier = Modifier.size(12.dp))
                Text(
                    stringResource(if (selected.size == section.items.size) RdR.string.rd_result_clear_all else RdR.string.rd_result_select_all),
                    style = iosRounded(11.5f, FontWeight.Black),
                    color = accent,
                )
            }
        }
    }
}

@Composable
private fun ResultHubRiskSummary(
    items: List<AnalysisResultHubItem>,
    method: ParityRiskMethod,
    modifier: Modifier = Modifier,
) {
    val colors = RdTheme.colors
    val levels = listOf(RiskLevel.Critical, RiskLevel.High, RiskLevel.Medium, RiskLevel.Low)
    val counts = levels.associateWith { level ->
        items.count {
            riskLevelFromRaw(if (method == ParityRiskMethod.FineKinney) it.fkBand ?: "unknown" else it.m5Band ?: "unknown") == level
        }
    }
    val actualTotal = counts.values.sum()
    val highestItem = items.maxByOrNull {
        if (method == ParityRiskMethod.FineKinney) it.fkScore ?: 0.0 else it.m5Score?.toDouble() ?: 0.0
    }
    val highest = highestItem?.let {
        if (method == ParityRiskMethod.FineKinney) it.fkScore else it.m5Score?.toDouble()
    } ?: 0.0
    val highestLevel = highestItem?.let {
        riskLevelFromRaw(if (method == ParityRiskMethod.FineKinney) it.fkBand else it.m5Band)
    } ?: RiskLevel.Unknown
    val maximumCount = counts.values.maxOrNull()?.coerceAtLeast(1) ?: 1

    Row(
        modifier.fillMaxWidth().height(87.dp)
            .shadow(9.dp, RoundedCornerShape(15.dp), ambientColor = Color(0xFF1F3557).copy(.18f))
            .clip(RoundedCornerShape(15.dp))
            .background(Brush.horizontalGradient(listOf(Color(0xFF3F6FA8), Color(0xFF2F5183), Color(0xFF1F3557))))
            .padding(horizontal = 15.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(RdR.string.rd_result_total_findings), style = iosRounded(10f, FontWeight.Black, tracking = .4f), color = Color.White.copy(.88f))
            Text(actualTotal.toString(), style = iosRounded(30f, FontWeight.Black, tracking = -1.4f), color = Color.White)
        }
        Box(Modifier.width(1.dp).height(42.dp).background(Color.White.copy(.26f)))
        Column(Modifier.widthIn(min = 104.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(RdR.string.rd_result_highest_score), style = iosRounded(10f, FontWeight.Black, tracking = .4f), color = Color.White.copy(.88f))
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(formatScore(highest), style = iosRounded(22f, FontWeight.Black, tracking = -1f), color = Color.White)
                Text(if (method == ParityRiskMethod.FineKinney) "puan" else "/25", style = iosRounded(9.5f, FontWeight.Bold), color = Color.White.copy(.85f), modifier = Modifier.padding(bottom = 3.dp))
            }
            Text(
                parityBandLabel(highestLevel),
                style = iosRounded(8f, FontWeight.Black, tracking = .3f),
                color = Color.White,
                modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(highestLevel.color()).padding(horizontal = 5.dp, vertical = 2.dp),
                maxLines = 1,
            )
        }
        Spacer(Modifier.weight(1f))
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(RdR.string.rd_dagilim).localizedUppercase(), style = iosRounded(8.5f, FontWeight.Black, tracking = .3f), color = Color.White.copy(.88f))
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.Bottom) {
                levels.forEach { level ->
                    val count = counts[level] ?: 0
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(count.toString(), style = iosRounded(8.5f, FontWeight.Black), color = Color.White)
                        Box(
                            Modifier.width(12.dp).height((6 + 22 * (count.toFloat() / maximumCount)).dp)
                                .clip(RoundedCornerShape(3.dp)).background(level.color()),
                        )
                        Text(riskShortLabel(level), style = iosRounded(7.5f, FontWeight.Black), color = Color.White.copy(.76f))
                    }
                }
            }
        }
    }
}

@Composable
private fun ResultHubItemCard(
    item: AnalysisResultHubItem,
    position: Int,
    sectionId: AnalysisResultSectionId,
    access: AnalysisResultAccess,
    selected: Boolean,
    method: ParityRiskMethod,
    canEdit: Boolean,
    canReport: Boolean,
    onToggleSelected: () -> Unit,
    onLike: () -> Unit,
    onDislike: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onDetail: () -> Unit,
    onUpgrade: () -> Unit,
) {
    val colors = RdTheme.colors
    val activeAccent = resultSectionAccent(sectionId, colors)
    val activeStrong = resultSectionStrong(sectionId, colors)
    val activeTint = resultSectionTint(sectionId, colors)
    val level = riskLevelFromRaw(if (method == ParityRiskMethod.FineKinney) item.fkBand ?: "unknown" else item.m5Band ?: "unknown")
    val score = if (method == ParityRiskMethod.FineKinney) item.fkScore else item.m5Score?.toDouble()
    val corrective = item.recommendedMeasures.orEmpty()
        .firstOrNull { it.kind.equals("corrective", ignoreCase = true) }?.text
        ?.takeIf(String::isNotBlank)
        ?: item.recommendedAction?.takeIf(String::isNotBlank)

    Box(Modifier.fillMaxWidth()) {
        Column(
            Modifier.fillMaxWidth().padding(top = 18.dp)
                .shadow(7.dp, RoundedCornerShape(8.dp), ambientColor = Color.Black.copy(.10f), spotColor = Color.Black.copy(.10f))
                .clip(RoundedCornerShape(8.dp)).background(colors.resultSurface)
                .border(1.5.dp, activeAccent, RoundedCornerShape(8.dp))
                .clickable(onClick = onDetail),
        ) {
            Column(
                Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 24.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(0.dp),
            ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    if (sectionId == AnalysisResultSectionId.RiskAnalysis) riskMethodBandLabel(item, method, level) else when (sectionId) {
                        AnalysisResultSectionId.ExpertRecommendations -> stringResource(RdR.string.rd_result_card_expert)
                        AnalysisResultSectionId.TrainingRecommendations -> stringResource(RdR.string.rd_result_card_training)
                        AnalysisResultSectionId.ApprovedNotebook -> stringResource(RdR.string.rd_result_card_notebook)
                        AnalysisResultSectionId.RiskAnalysis -> stringResource(RdR.string.rd_result_card_risk)
                    },
                    style = iosRounded(9.25f, FontWeight.Black, tracking = .3f),
                    color = if (sectionId == AnalysisResultSectionId.RiskAnalysis) Color.White else activeStrong,
                    modifier = Modifier.clip(RoundedCornerShape(if (sectionId == AnalysisResultSectionId.RiskAnalysis) 2.dp else 6.dp))
                        .background(if (sectionId == AnalysisResultSectionId.RiskAnalysis) level.color() else activeTint)
                        .padding(horizontal = 6.dp, vertical = 3.dp),
                )
                if (sectionId == AnalysisResultSectionId.RiskAnalysis) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(score?.let(::formatScore) ?: "—", style = iosRounded(14f, FontWeight.Black), color = colors.resultPrimaryText)
                        Text(if (method == ParityRiskMethod.FineKinney) "puan" else "/25", style = iosRounded(9.5f, FontWeight.Bold), color = colors.resultTertiaryText, modifier = Modifier.padding(bottom = 2.dp))
                    }
                }
                Spacer(Modifier.weight(1f))
                if (access == AnalysisResultAccess.Full && canReport) {
                    Row(
                        Modifier.clickable(onClick = onToggleSelected),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(7.dp),
                    ) {
                        Text(stringResource(if (selected) RdR.string.rd_result_selected else RdR.string.rd_result_select), style = iosRounded(10.5f, FontWeight.Black), color = activeStrong)
                        Box(
                            Modifier.size(24.dp).clip(CircleShape)
                                .background(if (selected) activeAccent else colors.resultSurface)
                                .border(1.5.dp, if (selected) activeAccent else colors.resultLine, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            if (selected) Icon(Icons.Filled.Check, stringResource(RdR.string.rd_result_remove_from_report), tint = Color.White, modifier = Modifier.size(12.dp))
                        }
                    }
                }
            }
            if (sectionId == AnalysisResultSectionId.ApprovedNotebook) {
                Text(stringResource(RdR.string.rd_result_finding).localizedUppercase(), style = iosRounded(10.5f, FontWeight.Black), color = activeStrong, modifier = Modifier.padding(top = 12.dp))
                Text(item.findingText.orEmpty(), style = iosRounded(15f, FontWeight.Black), color = colors.resultPrimaryText, modifier = Modifier.padding(top = 5.dp))
                if (access == AnalysisResultAccess.Full) {
                    Text(stringResource(RdR.string.rd_result_recommendation).localizedUppercase(), style = iosRounded(10.5f, FontWeight.Black), color = activeStrong, modifier = Modifier.padding(top = 12.dp))
                    Text(item.recommendationText.orEmpty(), style = iosRounded(13f), color = colors.resultSecondaryText, modifier = Modifier.padding(top = 5.dp))
                }
            } else if (sectionId == AnalysisResultSectionId.TrainingRecommendations) {
                item.categoryLabel?.takeIf(String::isNotBlank)?.let {
                    Text(it.localizedUppercase(), style = iosRounded(10f, FontWeight.Black), color = activeStrong, modifier = Modifier.padding(top = 12.dp))
                }
                if (access == AnalysisResultAccess.Teaser) {
                    ResultPremiumTextTeaser(
                        title = item.displayTitle,
                        body = item.displayBody,
                        minimumBlurHeight = 148.dp,
                        accent = activeAccent,
                        onUpgrade = onUpgrade,
                    )
                } else {
                    Text(item.displayTitle, style = iosRounded(15f, FontWeight.Black), color = colors.resultPrimaryText, modifier = Modifier.padding(top = 8.dp))
                    Text(
                        item.displayBody,
                        style = iosRounded(12.5f),
                        color = colors.resultSecondaryText,
                        modifier = Modifier.padding(top = 8.dp),
                        maxLines = 6,
                        overflow = TextOverflow.Ellipsis,
                    )
                    val duration = listOfNotNull(item.durationLabel, item.durationValue)
                        .filter(String::isNotBlank)
                        .joinToString(" · ")
                    if (duration.isNotBlank()) {
                        Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                            Icon(Icons.Filled.Description, null, tint = activeStrong, modifier = Modifier.size(15.dp))
                            Text(duration, style = iosRounded(11.5f, FontWeight.SemiBold), color = activeStrong)
                        }
                    }
                    item.durationNote?.takeIf(String::isNotBlank)?.let {
                        Text(it, style = iosRounded(11f), color = colors.resultSecondaryText, modifier = Modifier.padding(top = 5.dp))
                    }
                }
            } else {
                if (access == AnalysisResultAccess.Teaser && sectionId == AnalysisResultSectionId.ExpertRecommendations) {
                    ResultPremiumTextTeaser(
                        title = item.displayTitle,
                        body = item.displayBody,
                        minimumBlurHeight = 128.dp,
                        accent = activeAccent,
                        onUpgrade = onUpgrade,
                    )
                } else {
                    Text(item.displayTitle, style = iosRounded(15f, FontWeight.Black), color = colors.resultPrimaryText, modifier = Modifier.padding(top = 12.dp))
                    Text(
                        item.displayBody,
                        style = iosRounded(12.5f),
                        color = colors.resultSecondaryText,
                        modifier = Modifier.padding(top = 8.dp),
                        maxLines = if (access == AnalysisResultAccess.Teaser) 2 else 6,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (access == AnalysisResultAccess.Full && sectionId == AnalysisResultSectionId.RiskAnalysis && !corrective.isNullOrBlank()) {
                Column(
                    Modifier.fillMaxWidth().padding(top = 12.dp).clip(RoundedCornerShape(8.dp))
                        .background(colors.resultGreenTintStrong)
                        .border(1.dp, colors.resultGreen.copy(.30f), RoundedCornerShape(8.dp))
                        .clickable(onClick = onDetail).padding(horizontal = 10.dp, vertical = 9.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        Icon(Icons.Filled.CheckCircle, null, tint = colors.resultGreenDark, modifier = Modifier.size(11.dp))
                        Text(stringResource(RdR.string.rd_result_corrective_measure), style = iosRounded(9.5f, FontWeight.Black, tracking = .45f), color = colors.resultGreenDark)
                    }
                    Text(firstSentence(corrective), style = iosRounded(11.5f, FontWeight.Medium), color = colors.resultSecondaryText)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(stringResource(RdR.string.rd_result_tap_for_more), style = iosRounded(10.5f, FontWeight.Black), color = colors.resultGreenDark)
                        Box(Modifier.size(13.dp).clip(CircleShape).background(colors.resultGreenDark), contentAlignment = Alignment.Center) {
                            Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White, modifier = Modifier.size(11.dp))
                        }
                    }
                }
            }
            if (access == AnalysisResultAccess.Full && sectionId == AnalysisResultSectionId.RiskAnalysis) {
                val tags = buildList {
                    if (!item.rootCauseText.isNullOrBlank()) add(stringResource(RdR.string.rd_result_tag_root_cause) to true)
                    if (item.recommendedMeasures.orEmpty().any { it.kind.equals("preventive", true) && it.text.isNotBlank() }) add(stringResource(RdR.string.rd_result_tag_preventive) to false)
                    if (!item.referencesText.isNullOrBlank() || !item.referenceText.isNullOrBlank()) add(stringResource(RdR.string.rd_result_tag_legislation) to false)
                }
                if (tags.isNotEmpty()) {
                    Row(
                        Modifier.fillMaxWidth().padding(top = 12.dp).horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        tags.forEach { (tag, isRootCause) ->
                            Text(
                                tag,
                                style = iosRounded(10.5f, FontWeight.Black),
                                // A fixed dark ink keeps the amber chip readable in both themes.
                                color = if (isRootCause) Color(0xFF5C4000) else colors.resultPrimaryText,
                                modifier = Modifier.clip(RoundedCornerShape(3.dp))
                                    .background(if (isRootCause) Color(0xFFFFE89A) else colors.resultMintTint)
                                    .padding(horizontal = 6.dp, vertical = 4.dp),
                            )
                        }
                    }
                }
            }
            if (access == AnalysisResultAccess.Teaser && sectionId == AnalysisResultSectionId.RiskAnalysis) {
                Column(Modifier.fillMaxWidth().padding(top = 12.dp).blur(3.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Box(Modifier.fillMaxWidth().height(11.dp).clip(RoundedCornerShape(4.dp)).background(colors.resultLine))
                    Box(Modifier.fillMaxWidth(.66f).height(11.dp).clip(RoundedCornerShape(4.dp)).background(colors.resultLine.copy(.7f)))
                }
                Button(onClick = onUpgrade, modifier = Modifier.fillMaxWidth().padding(top = 9.dp), colors = ButtonDefaults.buttonColors(containerColor = activeStrong)) {
                    Icon(Icons.Filled.Lock, null, Modifier.size(16.dp)); Spacer(Modifier.width(7.dp)); Text(stringResource(RdR.string.rd_result_unlock_all))
                }
            }
        }

        if (access == AnalysisResultAccess.Full) {
            Row(
                Modifier.fillMaxWidth().height(48.dp).background(activeAccent).padding(horizontal = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (canEdit) {
                    IconButton(onClick = onEdit, modifier = Modifier.size(34.dp)) { Icon(Icons.Filled.Edit, stringResource(RdR.string.rd_duzenle), tint = Color.White, modifier = Modifier.size(17.dp)) }
                    IconButton(onClick = onDelete, modifier = Modifier.size(34.dp)) { Icon(Icons.Filled.DeleteOutline, stringResource(RdR.string.rd_sil), tint = Color.White, modifier = Modifier.size(17.dp)) }
                }
                IconButton(onClick = onLike, modifier = Modifier.size(34.dp)) {
                    Icon(
                        if (item.userReaction == AnalysisItemReaction.Like) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUpAlt,
                        stringResource(RdR.string.rd_result_like),
                        tint = if (item.userReaction == AnalysisItemReaction.Like) activeTint else Color.White,
                        modifier = Modifier.size(17.dp),
                    )
                }
                IconButton(onClick = onDislike, modifier = Modifier.size(34.dp)) {
                    Icon(
                        if (item.userReaction == AnalysisItemReaction.Dislike) Icons.Filled.ThumbDown else Icons.Outlined.ThumbDownAlt,
                        stringResource(RdR.string.rd_result_dislike),
                        tint = if (item.userReaction == AnalysisItemReaction.Dislike) activeTint else Color.White,
                        modifier = Modifier.size(17.dp),
                    )
                }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onDetail) {
                    Text(stringResource(RdR.string.rd_result_details), style = iosRounded(11.5f, FontWeight.Black), color = Color.White)
                    Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color.White)
                }
            }
        }
        }

        Row(
            Modifier.align(Alignment.TopStart).offset(x = 15.dp)
                .clip(RoundedCornerShape(22.dp)).background(colors.resultSurface)
                .padding(start = 4.dp, end = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Icon(
                when (sectionId) {
                    AnalysisResultSectionId.RiskAnalysis -> Icons.Filled.Warning
                    AnalysisResultSectionId.ExpertRecommendations -> Icons.Filled.VerifiedUser
                    AnalysisResultSectionId.TrainingRecommendations -> Icons.Filled.School
                    AnalysisResultSectionId.ApprovedNotebook -> Icons.Filled.Book
                },
                null,
                tint = if (sectionId == AnalysisResultSectionId.RiskAnalysis) level.color() else activeAccent,
                modifier = Modifier.size(36.dp).padding(4.dp),
            )
            Text("$position -", style = iosRounded(13f, FontWeight.Black), color = colors.resultSecondaryText)
        }
    }
}

@Composable
private fun ResultPremiumTextTeaser(
    title: String,
    body: String,
    minimumBlurHeight: androidx.compose.ui.unit.Dp,
    accent: Color,
    onUpgrade: () -> Unit,
) {
    val colors = RdTheme.colors
    Column(Modifier.fillMaxWidth().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Text(
            firstWords(title, 2),
            style = iosRounded(14f, FontWeight.Black),
            color = colors.resultPrimaryText,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Box(
            Modifier.fillMaxWidth().heightIn(min = minimumBlurHeight).clip(RoundedCornerShape(10.dp))
                .clickable(onClick = onUpgrade),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                Modifier.fillMaxWidth().heightIn(min = minimumBlurHeight).blur(5.5.dp).alpha(.72f).clearAndSetSemantics { },
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(title, style = iosRounded(13f, FontWeight.Bold), color = colors.resultPrimaryText, maxLines = 2)
                Text(body, style = iosRounded(12f), color = colors.resultSecondaryText, maxLines = 6, overflow = TextOverflow.Ellipsis)
                Box(Modifier.fillMaxWidth(.82f).height(10.dp).clip(CircleShape).background(accent.copy(.32f)))
                Box(Modifier.fillMaxWidth(.58f).height(10.dp).clip(CircleShape).background(colors.resultLine))
            }
            ResultPremiumTeaserCallout(onUpgrade)
        }
    }
}

@Composable
private fun ResultPremiumTeaserCallout(onUpgrade: () -> Unit) {
    val colors = RdTheme.colors
    Column(
        Modifier.shadow(7.dp, RoundedCornerShape(13.dp))
            .clip(RoundedCornerShape(13.dp))
            .background(colors.resultElevatedSurface.copy(.96f))
            .border(
                1.6.dp,
                Brush.linearGradient(
                    listOf(Color(0xFFE8762A), Color(0xFFE0A828), Color(0xFF4FAE7A), Color(0xFF1F8F9C)),
                ),
                RoundedCornerShape(13.dp),
            )
            .clickable(onClick = onUpgrade)
            .padding(horizontal = 18.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            Icon(Icons.Filled.WorkspacePremium, null, tint = Color(0xFFE0A828), modifier = Modifier.size(15.dp))
            Text(stringResource(RdR.string.rd_plus).localizedUppercase(), style = iosRounded(12.5f, FontWeight.Black), color = Color(0xFFA67C12))
            Box(Modifier.width(1.dp).height(14.dp).background(Color.Black.copy(.12f)))
            Icon(Icons.Filled.Star, null, tint = colors.resultGreen, modifier = Modifier.size(15.dp))
            Text(stringResource(RdR.string.rd_pro).localizedUppercase(), style = iosRounded(12.5f, FontWeight.Black), color = colors.resultGreenDark)
        }
        Text(
            stringResource(RdR.string.rd_result_premium_caption),
            style = iosRounded(10.5f, FontWeight.SemiBold),
            color = colors.resultSecondaryText,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun ResultHubNotebookPaper(
    items: List<AnalysisResultHubItem>,
    access: AnalysisResultAccess,
    onUpgrade: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = RdTheme.colors
    val accent = colors.sectionNotebookAccent
    val strong = colors.sectionNotebookStrong
    val tint = colors.sectionNotebookTint
    val shape = RoundedCornerShape(10.dp)
    Column(
        modifier
            .shadow(10.dp, shape, ambientColor = Color.Black.copy(.16f), spotColor = Color.Black.copy(.16f))
            .clip(shape)
            .background(colors.resultKhakiTint)
            .border(1.2.dp, accent.copy(.50f), shape)
            .then(if (access == AnalysisResultAccess.Teaser) Modifier.clickable(onClick = onUpgrade) else Modifier),
    ) {
        Row(
            Modifier.fillMaxWidth().background(tint).padding(start = 50.dp, end = 15.dp, top = 15.dp, bottom = 15.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                stringResource(RdR.string.rd_result_notebook_entries).localizedUppercase(),
                style = iosRounded(9.5f, FontWeight.ExtraBold, tracking = .7f),
                color = strong,
                modifier = Modifier.weight(1f),
            )
            if (access == AnalysisResultAccess.Teaser) Icon(Icons.Filled.Lock, null, tint = strong, modifier = Modifier.size(15.dp))
        }

        Box(
            Modifier.fillMaxWidth()
                .drawBehind {
                    val spacing = 29.dp.toPx()
                    var y = 25.dp.toPx()
                    while (y < size.height) {
                        drawLine(colors.resultLine.copy(.72f), Offset(0f, y), Offset(size.width, y), 1.dp.toPx())
                        y += spacing
                    }
                    drawLine(accent.copy(.58f), Offset(38.dp.toPx(), 0f), Offset(38.dp.toPx(), size.height), 1.5.dp.toPx())
                }
                .padding(start = 50.dp, end = 15.dp, top = 14.dp, bottom = 18.dp),
        ) {
            if (access == AnalysisResultAccess.Teaser) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    items.firstOrNull()?.let { first ->
                        Row(horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.Top) {
                            Text("1-", style = iosRounded(13f, FontWeight.ExtraBold), color = strong, modifier = Modifier.width(18.dp), textAlign = TextAlign.End)
                            Text(
                                firstWords(notebookCombinedText(first), 2),
                                style = iosRounded(12.5f, FontWeight.Medium).copy(lineHeight = 23.sp),
                                color = colors.resultPrimaryText,
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                    Box(Modifier.fillMaxWidth().heightIn(min = 154.dp), contentAlignment = Alignment.Center) {
                        Column(
                            Modifier.fillMaxWidth().heightIn(min = 154.dp).blur(4.5.dp).alpha(.76f).clearAndSetSemantics { },
                            verticalArrangement = Arrangement.spacedBy(16.dp),
                        ) {
                            items.forEachIndexed { index, item ->
                                Row(horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.Top) {
                                    Text("${index + 1}-", style = iosRounded(13f, FontWeight.ExtraBold), color = strong, modifier = Modifier.width(18.dp), textAlign = TextAlign.End)
                                    Text(
                                        notebookCombinedText(item),
                                        style = iosRounded(12.5f, FontWeight.Medium).copy(lineHeight = 23.sp),
                                        color = colors.resultPrimaryText,
                                        modifier = Modifier.weight(1f),
                                        maxLines = 3,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                        }
                        ResultPremiumTeaserCallout(onUpgrade)
                    }
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(27.dp)) {
                    items.forEachIndexed { index, item ->
                        Row(horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.Top) {
                            Text("${index + 1}-", style = iosRounded(13f, FontWeight.ExtraBold), color = strong, modifier = Modifier.width(18.dp), textAlign = TextAlign.End)
                            Text(
                                notebookCombinedText(item),
                                style = iosRounded(12.5f, FontWeight.Medium).copy(lineHeight = 23.sp),
                                color = colors.resultPrimaryText,
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }
            }
        }

        Row(
            Modifier.fillMaxWidth().background(tint).padding(start = 50.dp, end = 15.dp, top = 12.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(stringResource(RdR.string.rd_result_expert_review).localizedUppercase(), style = iosRounded(9.5f, FontWeight.ExtraBold, tracking = .5f), color = strong)
                Text(stringResource(RdR.string.rd_result_notebook_is_draft), style = iosRounded(12f, FontWeight.Bold), color = colors.resultPrimaryText)
            }
            Column(
                Modifier.size(74.dp).border(1.5.dp, accent.copy(.62f), CircleShape),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text(stringResource(RdR.string.rd_result_draft).localizedUppercase(), style = iosRounded(8.5f, FontWeight.ExtraBold, tracking = .5f), color = strong)
                Text(stringResource(RdR.string.rd_result_expert_approval).localizedUppercase(), style = iosRounded(8f, FontWeight.Bold), color = strong, textAlign = TextAlign.Center)
            }
        }
    }
}

private fun notebookCombinedText(item: AnalysisResultHubItem): String {
    val finding = item.findingText.orEmpty().trim()
    val recommendation = item.recommendationText.orEmpty().trim()
    return if (recommendation.isBlank()) finding else "$finding $recommendation"
}

@Composable
private fun riskMethodBandLabel(item: AnalysisResultHubItem, method: ParityRiskMethod, fallback: RiskLevel): String {
    return if (method == ParityRiskMethod.FineKinney) {
        when (item.fkScore ?: return fallbackBandLabel(fallback)) {
            in 401.0..Double.MAX_VALUE -> stringResource(RdR.string.rd_result_fine_kinney_outside_tolerance)
            in 201.0..400.0 -> stringResource(RdR.string.rd_result_fine_kinney_high)
            in 71.0..200.0 -> stringResource(RdR.string.rd_result_fine_kinney_significant)
            in 21.0..70.0 -> stringResource(RdR.string.rd_result_fine_kinney_possible)
            else -> stringResource(RdR.string.rd_result_fine_kinney_trivial)
        }
    } else {
        when (item.m5Score ?: return fallbackBandLabel(fallback)) {
            in 20..25 -> stringResource(RdR.string.rd_result_matrix_very_high)
            in 15..19 -> stringResource(RdR.string.rd_result_matrix_high)
            in 8..14 -> stringResource(RdR.string.rd_result_matrix_medium)
            in 2..7 -> stringResource(RdR.string.rd_result_matrix_low)
            else -> stringResource(RdR.string.rd_result_matrix_very_low)
        }
    }
}

@Composable
private fun fallbackBandLabel(level: RiskLevel): String = when (level) {
    RiskLevel.Critical -> stringResource(RdR.string.rd_result_risk_critical)
    RiskLevel.High -> stringResource(RdR.string.rd_result_matrix_high)
    RiskLevel.Medium -> stringResource(RdR.string.rd_result_matrix_medium)
    RiskLevel.Low -> stringResource(RdR.string.rd_result_matrix_low)
    RiskLevel.Unknown -> stringResource(RdR.string.rd_result_risk_unassessed)
}

private fun firstSentence(text: String, maximumLength: Int = 170): String {
    val normalized = text.replace('\n', ' ').trim().split(Regex("\\s+")).joinToString(" ")
        .replace(Regex("^\\s*(?:(?:\\d+\\s*[.):\\-])|(?:\\(\\d+\\))|[-•*])\\s*"), "")
    val punctuation = normalized.indexOfFirst { it == '.' || it == '!' || it == '?' }
    if (punctuation >= 0) return normalized.take(punctuation + 1)
    if (normalized.length <= maximumLength) return normalized
    return normalized.take(maximumLength).substringBeforeLast(' ', normalized.take(maximumLength)) + "…"
}

private fun firstWords(text: String, count: Int): String {
    val words = text.trim().split(Regex("\\s+")).filter(String::isNotBlank)
    val visible = words.take(count.coerceAtLeast(1)).joinToString(" ")
    return if (words.size > count) "$visible…" else visible
}

@Composable
private fun ResultHubReportBar(
    selectedSection: AnalysisResultSectionId,
    section: AnalysisResultSection?,
    selectedCount: Int,
    activeAccent: Color,
    activeStrong: Color,
    activeTint: Color,
    trainingWithoutReport: Boolean,
    trainingPro: Boolean,
    onBack: () -> Unit,
    onUpgrade: () -> Unit,
    onReport: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = RdTheme.colors
    val isDark = RdTheme.isDark
    val ctaContent = if (isDark) colors.onyx else Color.White
    val ctaArrowSurface = if (isDark) colors.resultElevatedSurface else Color.White
    val ctaArrowContent = if (isDark) Color.White else colors.onyx
    val enabled = when {
        section?.access == AnalysisResultAccess.Teaser -> true
        trainingWithoutReport -> !trainingPro
        else -> selectedCount > 0
    }
    val actionLabel = when {
        section?.access == AnalysisResultAccess.Teaser -> stringResource(RdR.string.rd_result_unlock_plus_pro)
        trainingPro -> stringResource(RdR.string.rd_result_training_not_in_report)
        trainingWithoutReport -> stringResource(RdR.string.rd_result_upgrade_pro)
        else -> stringResource(RdR.string.rd_rapor_olustur)
    }
    val action = when {
        section?.access == AnalysisResultAccess.Teaser -> onUpgrade
        trainingWithoutReport && !trainingPro -> onUpgrade
        trainingWithoutReport -> ({})
        else -> onReport
    }
    Column(
        modifier.fillMaxWidth().shadow(9.dp, RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp), ambientColor = Color.Black.copy(.22f))
            .background(colors.resultElevatedSurface).padding(start = 20.dp, end = 20.dp, top = 9.dp, bottom = 18.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(
                Modifier.width(66.dp).height(50.dp)
                    .shadow(6.dp, RoundedCornerShape(14.dp), ambientColor = activeStrong.copy(.12f))
                    .clip(RoundedCornerShape(14.dp)).background(activeTint)
                    .border(1.2.dp, activeAccent.copy(.48f), RoundedCornerShape(14.dp))
                    .clickable(onClick = onBack),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(Icons.Filled.KeyboardArrowLeft, null, tint = activeStrong, modifier = Modifier.size(16.dp))
                Text(stringResource(RdR.string.rd_result_back), style = iosRounded(8.5f, FontWeight.Black), color = activeStrong, maxLines = 1)
            }
            Row(
                Modifier.weight(1f).height(50.dp)
                    .shadow(8.dp, RoundedCornerShape(14.dp), ambientColor = Color.Black.copy(.28f))
                    .clip(RoundedCornerShape(14.dp))
                    .background(if (enabled) colors.cta else colors.resultLine)
                    .then(if (enabled) Modifier.clickable(onClick = action) else Modifier)
                    .padding(end = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    Modifier.weight(1f),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(if (section?.access == AnalysisResultAccess.Teaser || trainingWithoutReport) Icons.Filled.Lock else Icons.Filled.Tune, null, tint = if (enabled) ctaContent else colors.resultTertiaryText, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(9.dp))
                    Text(actionLabel, style = iosRounded(15.5f, FontWeight.Black), color = if (enabled) ctaContent else colors.resultTertiaryText, maxLines = 1)
                }
                Box(Modifier.size(38.dp).clip(RoundedCornerShape(11.dp)).background(if (enabled) ctaArrowSurface else colors.resultSubtleSurface), contentAlignment = Alignment.Center) {
                    Icon(Icons.AutoMirrored.Filled.Send, null, tint = if (enabled) ctaArrowContent else colors.resultTertiaryText, modifier = Modifier.size(17.dp))
                }
            }
        }
        if (selectedSection != AnalysisResultSectionId.ApprovedNotebook) {
            Row(Modifier.fillMaxWidth()) {
                Spacer(Modifier.width(76.dp))
                Text(
                    stringResource(
                        RdR.string.rd_result_selection_format,
                        selectedCount,
                        section?.count ?: 0,
                        stringResource(if (selectedSection == AnalysisResultSectionId.RiskAnalysis) RdR.string.rd_result_unit_finding else RdR.string.rd_result_unit_recommendation),
                    ),
                    style = iosRounded(10.5f, FontWeight.Bold),
                    color = colors.resultSecondaryText,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

private fun resultSectionAccent(id: AnalysisResultSectionId, colors: RdColors): Color = when (id) {
    AnalysisResultSectionId.RiskAnalysis -> colors.resultGreen
    AnalysisResultSectionId.ExpertRecommendations -> colors.sectionExpertAccent
    AnalysisResultSectionId.TrainingRecommendations -> colors.sectionTrainingAccent
    AnalysisResultSectionId.ApprovedNotebook -> colors.sectionNotebookAccent
}

private fun resultSectionStrong(id: AnalysisResultSectionId, colors: RdColors): Color = when (id) {
    AnalysisResultSectionId.RiskAnalysis -> colors.resultGreenDark
    AnalysisResultSectionId.ExpertRecommendations -> colors.sectionExpertStrong
    AnalysisResultSectionId.TrainingRecommendations -> colors.sectionTrainingStrong
    AnalysisResultSectionId.ApprovedNotebook -> colors.sectionNotebookStrong
}

private fun resultSectionTint(id: AnalysisResultSectionId, colors: RdColors): Color = when (id) {
    AnalysisResultSectionId.RiskAnalysis -> colors.resultGreenTint
    AnalysisResultSectionId.ExpertRecommendations -> colors.sectionExpertTint
    AnalysisResultSectionId.TrainingRecommendations -> colors.sectionTrainingTint
    AnalysisResultSectionId.ApprovedNotebook -> colors.sectionNotebookTint
}

/** iOS `FindingEditorSheet` parity: tall sheet, pinned actions and method-first scoring. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun IosParityFindingEditorSheet(
    finding: Finding,
    method: ParityRiskMethod,
    onDismiss: () -> Unit,
    onDelete: () -> Unit,
    onSave: (FindingPatch) -> Unit,
) {
    val colors = RdTheme.colors
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var title by remember(finding.id) { mutableStateOf(finding.title) }
    var description by remember(finding.id) { mutableStateOf(finding.description.orEmpty()) }
    var corrective by remember(finding.id) {
        mutableStateOf(
            finding.recommendedMeasures.orEmpty().firstOrNull { it.kind == "corrective" }?.text
                ?: finding.recommendedAction.orEmpty(),
        )
    }
    var preventive by remember(finding.id) {
        mutableStateOf(finding.recommendedMeasures.orEmpty().firstOrNull { it.kind == "preventive" }?.text.orEmpty())
    }
    var references by remember(finding.id) { mutableStateOf(finding.referencesText.orEmpty()) }
    var rootCause by remember(finding.id) { mutableStateOf(finding.rootCauseText.orEmpty()) }
    var fkProbability by remember(finding.id) { mutableStateOf(finding.fkProbability) }
    var fkFrequency by remember(finding.id) { mutableStateOf(finding.fkFrequency) }
    var fkSeverity by remember(finding.id) { mutableStateOf(finding.fkSeverity) }
    var m5Probability by remember(finding.id) { mutableStateOf(finding.m5Probability) }
    var m5Severity by remember(finding.id) { mutableStateOf(finding.m5Severity) }
    val canSave = title.isNotBlank() && description.isNotBlank() && corrective.isNotBlank()
    val correctiveMeasureLabel = stringResource(RdR.string.rd_result_corrective_action)
    val preventiveMeasureLabel = stringResource(RdR.string.rd_result_preventive_control)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        sheetGesturesEnabled = false,
        containerColor = colors.paper,
        dragHandle = null,
    ) {
        Column(Modifier.fillMaxHeight(0.94f)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, null, tint = colors.black) }
                Text(
                    stringResource(RdR.string.rd_bulguyu_duzenle),
                    style = iosRounded(20f, FontWeight.Bold),
                    color = colors.black,
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.size(48.dp))
            }
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                item {
                    Column(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
                            .background(colors.fog).padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(
                            stringResource(if (method == ParityRiskMethod.FineKinney) RdR.string.rd_result_score_fine_kinney else RdR.string.rd_result_score_matrix),
                            style = iosRounded(15f, FontWeight.Bold),
                            color = colors.black,
                        )
                        if (method == ParityRiskMethod.FineKinney) {
                            FindingScorePicker(stringResource(RdR.string.rd_result_probability), FineKinneyValues.PROBABILITY, fkProbability) { fkProbability = it }
                            FindingScorePicker(stringResource(RdR.string.rd_result_frequency), FineKinneyValues.FREQUENCY, fkFrequency) { fkFrequency = it }
                            FindingScorePicker(stringResource(RdR.string.rd_result_severity), FineKinneyValues.SEVERITY, fkSeverity) { fkSeverity = it }
                        } else {
                            FindingScorePicker(stringResource(RdR.string.rd_result_probability), (1..5).map(Int::toDouble), m5Probability?.toDouble()) { m5Probability = it.toInt() }
                            FindingScorePicker(stringResource(RdR.string.rd_result_severity), (1..5).map(Int::toDouble), m5Severity?.toDouble()) { m5Severity = it.toInt() }
                        }
                    }
                }
                item { FindingEditorTextField(title, { title = it }, stringResource(RdR.string.rd_bulgu_kisa), true) }
                item { FindingEditorTextField(description, { description = it }, stringResource(RdR.string.rd_gozlenen_durum)) }
                item { FindingEditorTextField(corrective, { corrective = it }, stringResource(RdR.string.rd_result_corrective_action)) }
                item { FindingEditorTextField(preventive, { preventive = it }, stringResource(RdR.string.rd_result_preventive_control)) }
                item { FindingEditorTextField(references, { references = it }, stringResource(RdR.string.rd_kaynak_ve_standartlar)) }
                item { FindingEditorTextField(rootCause, { rootCause = it }, stringResource(RdR.string.rd_kok_neden)) }
            }
            Row(
                modifier = Modifier.fillMaxWidth().background(colors.paper)
                    .border(1.dp, colors.line.copy(alpha = .55f), RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp))
                    .padding(horizontal = 20.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                IconButton(
                    onClick = onDelete,
                    modifier = Modifier.size(52.dp).clip(RoundedCornerShape(16.dp)).background(colors.criticalBg),
                ) { Icon(Icons.Filled.DeleteOutline, null, tint = colors.critical) }
                TextButton(onClick = onDismiss, modifier = Modifier.height(52.dp)) {
                    Text(stringResource(RdR.string.rd_vazgec), color = colors.slate)
                }
                Button(
                    onClick = {
                        val measures = buildList {
                            if (corrective.isNotBlank()) add(FindingMeasure("corrective", correctiveMeasureLabel, corrective.trim()))
                            if (preventive.isNotBlank()) add(FindingMeasure("preventive", preventiveMeasureLabel, preventive.trim()))
                        }
                        onSave(
                            FindingPatch(
                                title = title.trim(), description = description.trim(),
                                recommendedAction = corrective.trim(), recommendedMeasures = measures,
                                referencesText = references.trim(), rootCauseText = rootCause.trim(),
                                fkProbability = fkProbability, fkFrequency = fkFrequency, fkSeverity = fkSeverity,
                                m5Probability = m5Probability, m5Severity = m5Severity,
                            ),
                        )
                    },
                    enabled = canSave,
                    modifier = Modifier.weight(1f).height(52.dp),
                    shape = RoundedCornerShape(16.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = colors.cta, contentColor = Color.White),
                ) { Text(stringResource(RdR.string.rd_kaydet), style = iosRounded(15f, FontWeight.Bold)) }
            }
        }
    }
}

@Composable
private fun FindingEditorTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    singleLine: Boolean = false,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        singleLine = singleLine,
        minLines = if (singleLine) 1 else 3,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
    )
}

@Composable
private fun FindingScorePicker(label: String, options: List<Double>, selected: Double?, onSelect: (Double) -> Unit) {
    val colors = RdTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, style = iosRounded(12f, FontWeight.SemiBold), color = colors.slate)
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            options.forEach { value ->
                val active = selected == value
                Text(
                    if (value % 1.0 == 0.0) value.toInt().toString() else value.toString(),
                    style = iosRounded(12.5f, FontWeight.SemiBold),
                    color = if (active) Color.White else colors.black,
                    modifier = Modifier.clip(RoundedCornerShape(10.dp))
                        .background(if (active) colors.selected else colors.white)
                        .border(1.dp, if (active) colors.selected else colors.line, RoundedCornerShape(10.dp))
                        .clickable { onSelect(value) }.padding(horizontal = 12.dp, vertical = 8.dp),
                )
            }
        }
    }
}

@Composable
private fun ParityResultHeader(
    onBack: (() -> Unit)?,
    profile: UserProfile?,
    tier: SubscriptionTier,
    onUpgrade: (SubscriptionTier) -> Unit,
) {
    val colors = RdTheme.colors
    val targetTier = if (tier == SubscriptionTier.Plus) SubscriptionTier.Pro else SubscriptionTier.Plus
    val upgradeAccent = if (targetTier == SubscriptionTier.Pro) colors.resultGreen else colors.planPlus
    val upgradeAccentDark = if (targetTier == SubscriptionTier.Pro) colors.resultGreenDark else colors.planPlusDark
    Row(
        Modifier.fillMaxWidth().height(64.dp).background(colors.resultElevatedSurface).padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RoundHeaderButton(onBack) {
            Icon(Icons.Filled.KeyboardArrowLeft, stringResource(RdR.string.rd_geri), tint = colors.resultPrimaryText, modifier = Modifier.size(23.dp))
        }
        Spacer(Modifier.width(10.dp))
        Image(
            painter = painterResource(RdR.drawable.rd_logo),
            contentDescription = "RiskDetected",
            contentScale = ContentScale.Fit,
            // iOS templates the wordmark in dark appearance. The source PNG is predominantly
            // black, so leaving it unmodified makes the Android header disappear at night.
            colorFilter = if (RdTheme.isDark) ColorFilter.tint(Color.White) else null,
            modifier = Modifier.width(126.dp).height(36.dp),
        )
        Spacer(Modifier.weight(1f))
        if (tier != SubscriptionTier.Pro) {
            Row(
                Modifier.shadow(8.dp, RoundedCornerShape(7.dp), ambientColor = upgradeAccent.copy(.24f), spotColor = upgradeAccent.copy(.24f))
                    .clip(RoundedCornerShape(7.dp))
                    .background(Brush.linearGradient(listOf(upgradeAccent, upgradeAccentDark)))
                    .clickable { onUpgrade(targetTier) }
                    .height(24.dp).padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Icon(Icons.Filled.ArrowCircleUp, null, tint = Color.White, modifier = Modifier.size(12.dp))
                Text(stringResource(RdR.string.rd_yukselt), style = iosRounded(10.5f, FontWeight.SemiBold), color = Color.White)
            }
            Spacer(Modifier.width(8.dp))
        }
        Box(Modifier.size(40.dp)) {
            Box(
                Modifier.fillMaxSize().clip(CircleShape)
                    .background(if (RdTheme.isDark) colors.resultGreenTintStrong else Color(0xFFDDE5E0))
                    .border(1.dp, colors.resultLine, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    profile?.displayInitials?.takeIf { it != "—" } ?: "RD",
                    style = iosRounded(13f, FontWeight.Black),
                    color = if (RdTheme.isDark) colors.resultGreenDark else colors.onyx,
                    maxLines = 1,
                )
                profile?.avatarUrl?.takeIf(String::isNotBlank)?.let { path ->
                    AnalysisHeaderAvatarImage(path = path, modifier = Modifier.clip(CircleShape))
                }
            }
            if (tier != SubscriptionTier.Free) {
                Box(
                    Modifier.align(Alignment.BottomEnd).size(18.dp).clip(CircleShape)
                        .background(if (tier == SubscriptionTier.Plus) colors.planPlus else colors.resultGreen)
                        .border(1.5.dp, colors.resultElevatedSurface, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        if (tier == SubscriptionTier.Plus) Icons.Filled.WorkspacePremium else Icons.Filled.Star,
                        null,
                        tint = Color.White,
                        modifier = Modifier.size(11.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun RoundHeaderButton(onClick: (() -> Unit)?, content: @Composable () -> Unit) {
    val colors = RdTheme.colors
    Box(
        Modifier.size(40.dp).clip(RoundedCornerShape(11.dp)).background(colors.resultSurface)
            .border(1.dp, colors.resultLine, RoundedCornerShape(11.dp))
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
    Row(
        Modifier.fillMaxWidth().shadow(10.dp, RoundedCornerShape(16.dp), ambientColor = colors.onyx.copy(.04f), spotColor = colors.onyx.copy(.04f))
            .clip(RoundedCornerShape(16.dp)).background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(16.dp)).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        PhotoMosaic(photos)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(summary?.title ?: stringResource(RdR.string.rd_adsiz_analiz), style = iosRounded(15f, FontWeight.SemiBold), color = colors.black, maxLines = 2, overflow = TextOverflow.Ellipsis)
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
                MetaChip(stringResource(RdR.string.rd_bulgu_sayisi_format, findings.size), colors.fog, colors.black)
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
                    Text(stringResource(if (item == ParityRiskMethod.FineKinney) RdR.string.rd_fine_kinney else RdR.string.rd_bes_carp_bes_matris), style = iosRounded(13f, FontWeight.Bold), color = if (active) colors.black else colors.slate)
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
            Text(stringResource(RdR.string.rd_dagilim).localizedUppercase(), style = iosRounded(9f, FontWeight.Bold, tracking = .45f), color = colors.slate)
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
        Text("$count", style = iosMono(10f, FontWeight.Bold), color = colors.black)
        Text(riskShortLabel(level), style = iosRounded(8f, FontWeight.Bold), color = colors.slate)
    }
}

@Composable
private fun EmptyResultSurface() {
    val colors = RdTheme.colors
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(colors.greenSoft).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Filled.VerifiedUser, null, tint = colors.greenDark, modifier = Modifier.size(36.dp))
        Spacer(Modifier.height(8.dp))
        Text(stringResource(RdR.string.rd_tehlike_tespit_edilmedi), style = RdFontStyle.Title3.toTextStyle(), color = colors.black)
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
                color = colors.black,
                textAlign = TextAlign.Center,
                modifier = Modifier.size(25.dp).clip(RoundedCornerShape(8.dp)).background(colors.fog).padding(top = 5.dp),
            )
            Text(finding.title, style = iosRounded(15f, FontWeight.SemiBold), color = colors.black, modifier = Modifier.weight(1f))
            if (canEdit) {
                SmallFindingAction(onEdit, colors.planPlusSoft, colors.planPlus.copy(.55f)) {
                    Icon(Icons.Filled.Edit, stringResource(RdR.string.rd_bulguyu_duzenle), tint = colors.black, modifier = Modifier.size(15.dp))
                }
                SmallFindingAction(onDelete, colors.criticalBg, Color.Transparent) {
                    Icon(Icons.Filled.DeleteOutline, stringResource(RdR.string.rd_bulguyu_sil), tint = colors.criticalText, modifier = Modifier.size(16.dp))
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            MetaChip(parityBandLabel(level), level.backgroundColor(), level.color())
            if (finding.sourcePhotoIndices.isNotEmpty()) MetaChip(stringResource(RdR.string.rd_foto_indeks_format, finding.sourcePhotoIndices.joinToString(",")), colors.fog, colors.slate)
        }
        finding.description?.takeIf { it.isNotBlank() }?.let { Text(it, style = iosRounded(13f), color = colors.black.copy(.86f)) }
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
            Text(formatScore(score), style = iosMono(18f, FontWeight.Black), color = Color.White)
            Text(if (method == ParityRiskMethod.FineKinney) "F-KINNEY" else "5×5", style = iosRounded(8f, FontWeight.Bold, tracking = .6f), color = Color.White.copy(.85f))
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
        Text(if (isPlus) stringResource(RdR.string.rd_plus).localizedUppercase() else stringResource(RdR.string.rd_pro).localizedUppercase(), style = iosRounded(if (compact) 7f else 9f, FontWeight.Black, tracking = .35f), color = accentText)
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
        Text("$number", style = iosMono(12f, FontWeight.Bold), color = colors.black, textAlign = TextAlign.Center, modifier = Modifier.size(32.dp).clip(RoundedCornerShape(9.dp)).background(colors.white.copy(.92f)).padding(top = 7.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                Text(stringResource(if (requiredTier == SubscriptionTier.Pro) RdR.string.rd_ek_kritik_bulgu else RdR.string.rd_gizli_uygunsuzluk), style = iosRounded(14f, FontWeight.Bold), color = colors.black.copy(.86f), maxLines = 1)
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
    analysisTitle: String,
    analysisSector: String?,
    reaction: AnalysisItemReaction? = null,
    onFeedback: ((AnalysisItemReaction, String?, String?) -> Unit)? = null,
    onMethodChange: (ParityRiskMethod) -> Unit,
    onClose: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    onGenerateReport: () -> Unit,
    onShareReport: () -> Unit,
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
    var pendingDislike by remember { mutableStateOf(false) }
    var feedbackComposerExpanded by remember { mutableStateOf(false) }
    var feedbackNote by remember { mutableStateOf("") }
    var feedbackThanksVisible by remember { mutableStateOf(false) }

    LaunchedEffect(feedbackThanksVisible) {
        if (feedbackThanksVisible) {
            kotlinx.coroutines.delay(3_000)
            feedbackThanksVisible = false
        }
    }

    Box(Modifier.fillMaxSize().background(colors.resultBackground)) {
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 26.dp),
        ) {
            item {
                Box(Modifier.fillMaxWidth().height(296.dp).background(Color(0xFF18201B))) {
                    if (bitmap != null) Image(bitmap, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    else Icon(Icons.Filled.PhotoLibrary, null, tint = Color.White.copy(.38f), modifier = Modifier.align(Alignment.Center).size(48.dp))
                    Box(
                        Modifier.fillMaxSize().background(
                            Brush.verticalGradient(
                                listOf(
                                    Color(0xFF0C140E).copy(.62f),
                                    Color(0xFF0C140E).copy(.12f),
                                    Color(0xFF0C140E).copy(.20f),
                                    Color(0xFF0C140E).copy(.82f),
                                ),
                            ),
                        ),
                    )
                    Row(
                        Modifier.align(Alignment.TopCenter).fillMaxWidth().padding(horizontal = 14.dp, vertical = 22.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        DetailHeroButton(onClose) {
                            Icon(Icons.Filled.KeyboardArrowLeft, stringResource(RdR.string.rd_kapat), tint = Color.White, modifier = Modifier.size(22.dp))
                        }
                        Spacer(Modifier.weight(1f))
                        if (onFeedback != null) {
                            DetailHeroButton({
                                val next = if (reaction == AnalysisItemReaction.Like) AnalysisItemReaction.None else AnalysisItemReaction.Like
                                onFeedback(next, null, null)
                                if (next == AnalysisItemReaction.Like) feedbackThanksVisible = true
                            }) {
                                Icon(
                                    if (reaction == AnalysisItemReaction.Like) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUpAlt,
                                    stringResource(RdR.string.rd_result_like),
                                    tint = if (reaction == AnalysisItemReaction.Like) colors.resultGreen else Color.White,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                            Spacer(Modifier.width(8.dp))
                            DetailHeroButton({
                                if (reaction == AnalysisItemReaction.Dislike) onFeedback(AnalysisItemReaction.None, null, null)
                                else {
                                    feedbackComposerExpanded = false
                                    feedbackNote = ""
                                    pendingDislike = true
                                }
                            }) {
                                Icon(
                                    if (reaction == AnalysisItemReaction.Dislike) Icons.Filled.ThumbDown else Icons.Outlined.ThumbDownAlt,
                                    stringResource(RdR.string.rd_result_dislike),
                                    tint = if (reaction == AnalysisItemReaction.Dislike) colors.resultGreen else Color.White,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        }
                    }
                    Column(
                        Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(horizontal = 20.dp, vertical = 30.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(
                                findingRiskBandLabel(finding, method, level),
                                style = iosRounded(8.5f, FontWeight.Black),
                                color = Color.White,
                                modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(level.color()).padding(horizontal = 7.dp, vertical = 4.dp),
                            )
                            Text(stringResource(RdR.string.rd_result_finding_id_format, finding.id.takeLast(4).uppercase()), style = iosRounded(9f, FontWeight.Bold, tracking = .3f), color = Color.White.copy(.72f))
                            Spacer(Modifier.weight(1f))
                            Text(formatScore(parityScore(finding, method)), style = iosRounded(15f, FontWeight.Black), color = Color.White)
                            Text(stringResource(if (method == ParityRiskMethod.FineKinney) RdR.string.rd_result_score else RdR.string.rd_result_risk), style = iosRounded(9f, FontWeight.Bold), color = Color.White.copy(.72f))
                        }
                        Text(finding.title, style = iosRounded(13f, FontWeight.Black), color = Color.White)
                        Text(
                            listOfNotNull(
                                analysisTitle.takeIf(String::isNotBlank),
                                analysisSector?.takeIf(String::isNotBlank)?.let { analysisSectorLabel(it, it) },
                            ).joinToString(" · ").ifBlank { finding.category.orEmpty() },
                            style = iosRounded(10f, FontWeight.Medium),
                            color = Color.White.copy(.70f),
                            maxLines = 1,
                        )
                    }
                    Text(
                        stringResource(RdR.string.rd_foto_indeks_format, sourceIndex),
                        style = iosRounded(1f),
                        color = Color.Transparent,
                        modifier = Modifier.align(Alignment.BottomEnd),
                    )
                }
            }
            item {
                Box(Modifier.fillMaxWidth().height(44.dp)) {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 16.dp).offset(y = (-24).dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Row(
                            Modifier.weight(1f).height(60.dp)
                                .shadow(8.dp, RoundedCornerShape(18.dp), ambientColor = colors.resultPrimaryText.copy(.18f))
                                .clip(RoundedCornerShape(18.dp)).background(colors.resultElevatedSurface)
                                .clickable(onClick = onGenerateReport).padding(horizontal = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Box(Modifier.size(42.dp).clip(RoundedCornerShape(12.dp)).background(colors.resultGreenTint), contentAlignment = Alignment.Center) {
                                Icon(Icons.Filled.Download, null, tint = colors.resultGreenDark, modifier = Modifier.size(21.dp))
                            }
                            Spacer(Modifier.width(8.dp))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(stringResource(RdR.string.rd_result_download_report), style = iosRounded(14.5f, FontWeight.Black), color = colors.resultPrimaryText, maxLines = 1)
                                Text(stringResource(RdR.string.rd_result_standard_report_caption), style = iosRounded(8.8f, FontWeight.Medium, lineHeightMultiplier = 1f), color = colors.resultTertiaryText, maxLines = 3)
                            }
                            Spacer(Modifier.width(4.dp))
                            Icon(Icons.Filled.KeyboardArrowRight, null, tint = colors.resultTertiaryText, modifier = Modifier.size(14.dp))
                        }
                        DetailActionSquare(onEdit, colors.resultGreenDark) { Icon(Icons.Filled.Edit, stringResource(RdR.string.rd_result_edit), tint = colors.resultGreenDark, modifier = Modifier.size(20.dp)) }
                        DetailActionSquare(onDelete, colors.criticalText) { Icon(Icons.Filled.DeleteOutline, stringResource(RdR.string.rd_sil), tint = colors.criticalText, modifier = Modifier.size(20.dp)) }
                        DetailActionSquare(onShareReport, colors.resultGreenDark) { Icon(Icons.Filled.IosShare, stringResource(RdR.string.rd_result_share_report), tint = colors.resultGreenDark, modifier = Modifier.size(20.dp)) }
                    }
                }
            }
            item {
                val score = parityScore(finding, method)
                Row(
                    Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 18.dp).height(66.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Brush.horizontalGradient(listOf(level.color(), level.color().copy(.76f))))
                        .padding(horizontal = 13.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(formatScore(score), style = iosRounded(26f, FontWeight.Black, tracking = -1.2f), color = Color.White)
                        Text(stringResource(if (method == ParityRiskMethod.FineKinney) RdR.string.rd_result_score else RdR.string.rd_result_risk), style = iosRounded(8.5f, FontWeight.Black), color = Color.White.copy(.78f), modifier = Modifier.padding(bottom = 5.dp))
                    }
                    Box(Modifier.width(1.dp).height(26.dp).background(Color.White.copy(.28f)))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(if (method == ParityRiskMethod.FineKinney) "Fine-Kinney" else stringResource(RdR.string.rd_bes_carp_bes_matris), style = iosRounded(10.5f, FontWeight.Black), color = Color.White)
                            Text(stringResource(if (method == ParityRiskMethod.FineKinney) RdR.string.rd_fk_formula else RdR.string.rd_matrix_formula), style = iosRounded(9f, FontWeight.Bold), color = Color.White.copy(.60f))
                        }
                        Text(parityFormulaValues(finding, method), style = iosRounded(9.5f, FontWeight.Bold), color = Color.White.copy(.86f))
                    }
                }
            }
            item {
                Row(
                    Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 18.dp)
                        .clip(RoundedCornerShape(10.dp)).background(colors.resultSurface)
                        .border(1.dp, colors.resultLine, RoundedCornerShape(10.dp)),
                ) {
                    Box(Modifier.width(4.dp).fillMaxHeight().background(level.color()))
                    Column(Modifier.weight(1f).padding(horizontal = 12.dp, vertical = 13.dp)) {
                        Text(
                            findingRiskBandLabel(finding, method, level),
                            style = iosRounded(8.5f, FontWeight.Black), color = Color.White,
                            modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(level.color()).padding(horizontal = 7.dp, vertical = 4.dp),
                        )
                        Text(finding.title, style = iosRounded(15f, FontWeight.Black), color = colors.resultPrimaryText, modifier = Modifier.padding(top = 8.dp))
                        Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(RdR.string.rd_result_hazard_description), style = iosRounded(9f, FontWeight.Black, tracking = .3f), color = colors.resultTertiaryText)
                            Spacer(Modifier.width(6.dp))
                            Box(Modifier.weight(1f).height(1.dp).background(colors.resultLine))
                        }
                        Text(finding.description.orEmpty(), style = iosRounded(12.5f, FontWeight.Medium), color = colors.resultSecondaryText, modifier = Modifier.padding(top = 7.dp))
                    }
                }
            }
            finding.rootCauseText?.takeIf(String::isNotBlank)?.let { rootCause ->
                item {
                    ResultDetailBlock(Icons.Filled.FactCheck, stringResource(RdR.string.rd_kok_neden_dot), stringResource(RdR.string.rd_result_finding), stringResource(RdR.string.rd_result_root_cause_description), rootCause, if (RdTheme.isDark) colors.sectionExpertStrong else Color(0xFFA66A13), colors.resultAmberTint)
                }
            }
            val corrective = finding.recommendedMeasures.orEmpty().filter { !it.kind.equals("preventive", true) && it.text.isNotBlank() }
                .map { it.text }.ifEmpty { listOfNotNull(finding.recommendedAction?.takeIf(String::isNotBlank)) }
            if (corrective.isNotEmpty()) {
                item {
                    ResultDetailBlock(Icons.Filled.Edit, stringResource(RdR.string.rd_result_corrective_measure), stringResource(RdR.string.rd_result_priority), stringResource(RdR.string.rd_result_corrective_description), corrective.joinToString("\n"), colors.resultGreenDark, colors.resultGreenTint)
                }
            }
            if (tier != SubscriptionTier.Pro) {
                item { DetailMembershipPromotion(tier, onUpgrade) }
            }
            val preventive = finding.recommendedMeasures.orEmpty().filter { it.kind.equals("preventive", true) && it.text.isNotBlank() }.map { it.text }
            if (preventive.isNotEmpty()) {
                item {
                    ResultDetailBlock(Icons.Filled.VerifiedUser, stringResource(RdR.string.rd_result_preventive_action), stringResource(RdR.string.rd_result_permanent), stringResource(RdR.string.rd_result_preventive_description), preventive.joinToString("\n"), colors.resultGreenDark, colors.resultMintTint)
                }
            }
            item {
                if (tier.isPaid) {
                    ResultDetailBlock(
                        Icons.Filled.Business,
                        stringResource(RdR.string.rd_mevzuat),
                        stringResource(RdR.string.rd_result_basis),
                        stringResource(RdR.string.rd_result_legal_references),
                        finding.referencesText?.takeIf(String::isNotBlank) ?: stringResource(RdR.string.rd_result_no_verified_reference),
                        Color(0xFF4E8EB8),
                        colors.resultBlueTint,
                    )
                } else {
                    ResultLockedReferenceBlock { onUpgrade(SubscriptionTier.Plus) }
                }
            }
        }

        if (feedbackThanksVisible) {
            Row(
                Modifier.align(Alignment.TopCenter).padding(horizontal = 20.dp, vertical = 58.dp)
                    .shadow(8.dp, RoundedCornerShape(14.dp)).clip(RoundedCornerShape(14.dp))
                    .background(colors.resultElevatedSurface).border(1.dp, colors.resultLine, RoundedCornerShape(14.dp)).padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(Icons.Filled.CheckCircle, null, tint = colors.resultGreen, modifier = Modifier.size(24.dp))
                Text(stringResource(RdR.string.rd_feedback_thanks), style = iosRounded(11.5f, FontWeight.SemiBold), color = colors.resultPrimaryText, modifier = Modifier.weight(1f))
            }
        }
    }

    if (pendingDislike && onFeedback != null) {
        val reasons = listOf(
            stringResource(RdR.string.rd_feedback_incorrect_detection) to "incorrect_detection",
            stringResource(RdR.string.rd_feedback_missing_context) to "missing_context",
            stringResource(RdR.string.rd_feedback_wrong_score) to "wrong_score",
            stringResource(RdR.string.rd_feedback_wrong_recommendation) to "wrong_recommendation",
            stringResource(RdR.string.rd_feedback_duplicate) to "duplicate",
            stringResource(RdR.string.rd_feedback_irrelevant) to "irrelevant",
            stringResource(RdR.string.rd_feedback_unclear_text) to "unclear_text",
            stringResource(RdR.string.rd_feedback_other) to "other",
        )
        AlertDialog(
            onDismissRequest = { pendingDislike = false; feedbackComposerExpanded = false; feedbackNote = "" },
            title = { Text(stringResource(RdR.string.rd_feedback_improve_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (!feedbackComposerExpanded) reasons.forEach { (label, code) ->
                        TextButton(onClick = {
                            pendingDislike = false
                            onFeedback(AnalysisItemReaction.Dislike, code, null)
                            feedbackThanksVisible = true
                        }) { Text(label, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Start) }
                    }
                    if (!feedbackComposerExpanded) {
                        TextButton(onClick = { feedbackComposerExpanded = true }) {
                            Icon(Icons.Filled.Edit, null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(7.dp))
                            Text(stringResource(RdR.string.rd_feedback_write_reason), modifier = Modifier.fillMaxWidth())
                        }
                    } else {
                        OutlinedTextField(
                            value = feedbackNote,
                            onValueChange = { feedbackNote = it.take(1000) },
                            label = { Text(stringResource(RdR.string.rd_feedback_label)) },
                            placeholder = { Text(stringResource(RdR.string.rd_feedback_placeholder)) },
                            minLines = 4,
                            supportingText = { Text("${feedbackNote.length}/1000") },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            },
            confirmButton = {
                if (feedbackComposerExpanded) {
                    TextButton(
                        enabled = feedbackNote.isNotBlank(),
                        onClick = {
                            val note = feedbackNote.trim()
                            pendingDislike = false
                            feedbackComposerExpanded = false
                            feedbackNote = ""
                            onFeedback(AnalysisItemReaction.Dislike, "other", note)
                            feedbackThanksVisible = true
                        },
                    ) { Text(stringResource(RdR.string.rd_gonder)) }
                } else TextButton(onClick = { pendingDislike = false }) { Text(stringResource(RdR.string.rd_kapat)) }
            },
            dismissButton = if (feedbackComposerExpanded) {
                { TextButton(onClick = { feedbackComposerExpanded = false; feedbackNote = "" }) { Text(stringResource(RdR.string.rd_geri)) } }
            } else null,
        )
    }
}

@Composable
private fun DetailHeroButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        Modifier.size(38.dp).clip(CircleShape).background(Color.Black.copy(.34f))
            .border(1.dp, Color.White.copy(.28f), CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}

@Composable
private fun DetailActionSquare(onClick: () -> Unit, tint: Color, content: @Composable () -> Unit) {
    val colors = RdTheme.colors
    Box(
        Modifier.size(48.dp).shadow(8.dp, RoundedCornerShape(15.dp), ambientColor = colors.resultPrimaryText.copy(.14f))
            .clip(RoundedCornerShape(15.dp)).background(colors.resultElevatedSurface)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}

@Composable
private fun ResultDetailBlock(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    tag: String,
    lead: String,
    text: String,
    color: Color,
    background: Color,
) {
    val colors = RdTheme.colors
    Column(
        Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 10.dp)
            .clip(RoundedCornerShape(10.dp)).background(background).padding(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(icon, null, tint = color, modifier = Modifier.size(15.dp))
            Text(title, style = iosRounded(10f, FontWeight.Black, tracking = .25f), color = color)
            Spacer(Modifier.weight(1f))
            Text(tag, style = iosRounded(8.5f, FontWeight.Black), color = color, modifier = Modifier.clip(RoundedCornerShape(5.dp)).background(colors.resultElevatedSurface.copy(.74f)).padding(horizontal = 6.dp, vertical = 3.dp))
        }
        Text(lead, style = iosRounded(12.5f, FontWeight.Black), color = colors.resultPrimaryText, modifier = Modifier.padding(top = 10.dp))
        Text(text, style = iosRounded(12f, FontWeight.Medium), color = colors.resultSecondaryText, modifier = Modifier.padding(top = 6.dp))
    }
}

@Composable
private fun DetailMembershipPromotion(tier: SubscriptionTier, onUpgrade: (SubscriptionTier) -> Unit) {
    val colors = RdTheme.colors
    val target = if (tier == SubscriptionTier.Free) SubscriptionTier.Plus else SubscriptionTier.Pro
    val plusAndPro = tier == SubscriptionTier.Free
    val borderColors = if (plusAndPro) {
        listOf(Color(0xFFF0A400), Color(0xFFE8762A), Color(0xFF7259F5), Color(0xFF168FC7), Color(0xFF00AE73))
    } else {
        listOf(Color(0xFF7259F5), Color(0xFF168FC7), Color(0xFF00AE73))
    }
    val actionColors = if (plusAndPro) {
        listOf(Color(0xFFD88A00), Color(0xFF7259F5), Color(0xFF168FC7), Color(0xFF00A86B))
    } else {
        listOf(Color(0xFF6656E8), Color(0xFF168FC7), Color(0xFF00A86B))
    }
    val cardShape = RoundedCornerShape(14.dp)
    Row(
        Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 12.dp)
            .shadow(11.dp, cardShape, ambientColor = Color(0xFF6656E8).copy(.16f), spotColor = Color(0xFF168FC7).copy(.10f))
            .clip(cardShape)
            .background(
                Brush.linearGradient(
                    if (plusAndPro) {
                        listOf(colors.resultAmberTint, colors.resultElevatedSurface, colors.resultBlueTint, colors.resultMintTint)
                    } else {
                        listOf(colors.resultElevatedSurface, colors.resultBlueTint, colors.resultMintTint)
                    },
                ),
            )
            .border(2.dp, Brush.linearGradient(borderColors), cardShape)
            .clickable { onUpgrade(target) }.padding(14.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.size(44.dp).shadow(9.dp, RoundedCornerShape(12.dp), ambientColor = Color(0xFF7259F5).copy(.28f))
                .clip(RoundedCornerShape(12.dp)).background(Brush.linearGradient(actionColors)),
            contentAlignment = Alignment.Center,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(1.dp), verticalAlignment = Alignment.CenterVertically) {
                if (plusAndPro) Icon(Icons.Filled.WorkspacePremium, null, tint = Color.White, modifier = Modifier.size(13.dp))
                Icon(Icons.Filled.Star, null, tint = Color.White, modifier = Modifier.size(if (plusAndPro) 13.dp else 18.dp))
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Text(
                stringResource(if (plusAndPro) RdR.string.rd_result_upgrade_plus_title else RdR.string.rd_result_upgrade_pro_title),
                style = iosRounded(14f, FontWeight.Black),
                color = colors.resultPrimaryText,
                maxLines = if (plusAndPro) 2 else 1,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                if (plusAndPro) PremiumPlanBadge(
                    text = stringResource(RdR.string.rd_plus).localizedUppercase(),
                    icon = Icons.Filled.WorkspacePremium,
                    colors = listOf(Color(0xFFF0A400), Color(0xFFE8762A)),
                )
                PremiumPlanBadge(
                    text = stringResource(RdR.string.rd_pro).localizedUppercase(),
                    icon = Icons.Filled.Star,
                    colors = listOf(Color(0xFF7259F5), Color(0xFF168FC7), Color(0xFF00AE73)),
                )
            }
            Text(
                stringResource(if (plusAndPro) RdR.string.rd_result_upgrade_plus_body else RdR.string.rd_result_upgrade_pro_body),
                style = iosRounded(11.25f, FontWeight.Medium),
                color = colors.resultSecondaryText,
            )
            Row(
                Modifier.height(28.dp).clip(CircleShape).background(Brush.linearGradient(actionColors)).padding(horizontal = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Text(
                    stringResource(if (plusAndPro) RdR.string.rd_result_explore_plans else RdR.string.rd_result_upgrade_to_pro),
                    style = iosRounded(10.5f, FontWeight.Black),
                    color = Color.White,
                )
                Icon(Icons.Filled.ArrowCircleUp, null, tint = Color.White, modifier = Modifier.size(12.dp))
            }
        }
        Icon(Icons.Filled.KeyboardArrowRight, null, tint = Color(0xFF6656E8), modifier = Modifier.padding(top = 15.dp).size(16.dp))
    }
}

@Composable
private fun PremiumPlanBadge(
    text: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    colors: List<Color>,
) {
    Row(
        Modifier.height(20.dp).clip(CircleShape).background(Brush.linearGradient(colors)).padding(horizontal = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(8.dp))
        Text(text, style = iosRounded(8.5f, FontWeight.Black, tracking = .5f), color = Color.White)
    }
}

@Composable
private fun ResultLockedReferenceBlock(onClick: () -> Unit) {
    val colors = RdTheme.colors
    Box(
        Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 10.dp).height(154.dp)
            .clip(RoundedCornerShape(10.dp)).background(colors.resultBlueTint).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Column(Modifier.fillMaxSize().blur(5.dp).padding(12.dp)) {
            Text(stringResource(RdR.string.rd_mevzuat), style = iosRounded(10f, FontWeight.Black), color = Color(0xFF316A92))
            Text(stringResource(RdR.string.rd_result_legal_references), style = iosRounded(12.5f, FontWeight.Black), color = colors.resultPrimaryText, modifier = Modifier.padding(top = 18.dp))
            Box(Modifier.fillMaxWidth().height(10.dp).padding(top = 8.dp).background(colors.resultLine))
        }
        Column(
            Modifier.shadow(7.dp, RoundedCornerShape(13.dp)).clip(RoundedCornerShape(13.dp))
                .background(colors.resultElevatedSurface.copy(.96f)).border(1.6.dp, colors.planPlus, RoundedCornerShape(13.dp))
                .padding(horizontal = 18.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                Icon(Icons.Filled.WorkspacePremium, null, tint = colors.planPlus, modifier = Modifier.size(15.dp))
                Text(stringResource(RdR.string.rd_plus).localizedUppercase(), style = iosRounded(12.5f, FontWeight.Black), color = colors.planPlusDark)
                Box(Modifier.width(1.dp).height(14.dp).background(Color.Black.copy(.12f)))
                Icon(Icons.Filled.Star, null, tint = colors.resultGreen, modifier = Modifier.size(15.dp))
                Text(stringResource(RdR.string.rd_pro).localizedUppercase(), style = iosRounded(12.5f, FontWeight.Black), color = colors.resultGreenDark)
            }
            Text(stringResource(RdR.string.rd_result_premium_caption), style = iosRounded(10.5f, FontWeight.SemiBold), color = colors.resultSecondaryText)
        }
    }
}

@Composable
private fun findingRiskBandLabel(finding: Finding, method: ParityRiskMethod, fallback: RiskLevel): String {
    return if (method == ParityRiskMethod.FineKinney) {
        when (finding.fkScore ?: return fallbackBandLabel(fallback)) {
            in 401.0..Double.MAX_VALUE -> stringResource(RdR.string.rd_result_fine_kinney_outside_tolerance)
            in 201.0..400.0 -> stringResource(RdR.string.rd_result_fine_kinney_high)
            in 71.0..200.0 -> stringResource(RdR.string.rd_result_fine_kinney_significant)
            in 21.0..70.0 -> stringResource(RdR.string.rd_result_fine_kinney_possible)
            else -> stringResource(RdR.string.rd_result_fine_kinney_trivial)
        }
    } else {
        when (finding.m5Score ?: return fallbackBandLabel(fallback)) {
            in 20..25 -> stringResource(RdR.string.rd_result_matrix_very_high)
            in 15..19 -> stringResource(RdR.string.rd_result_matrix_high)
            in 8..14 -> stringResource(RdR.string.rd_result_matrix_medium)
            in 2..7 -> stringResource(RdR.string.rd_result_matrix_low)
            else -> stringResource(RdR.string.rd_result_matrix_very_low)
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
                color = if (active) colors.black else colors.slate,
                modifier = Modifier.align(Alignment.Center),
            )
            if (active) Icon(Icons.Filled.CheckCircle, null, tint = colors.green, modifier = Modifier.align(Alignment.TopEnd).size(15.dp))
        }
        Text(stringResource(if (method == ParityRiskMethod.FineKinney) RdR.string.rd_fk_formula else RdR.string.rd_matrix_formula), style = iosMono(10f), color = colors.slate)
        Text(formatScore(parityScore(finding, method)), style = iosMono(23f, FontWeight.Black), color = Color.White, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(level.color()).padding(vertical = 12.dp))
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
        Text(title.localizedUppercase(), style = iosRounded(11f, FontWeight.Bold, tracking = .6f), color = colors.slate)
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
    sectionId: AnalysisResultSectionId,
    selectedCount: Int,
    totalCount: Int,
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
    val isRiskSection = sectionId == AnalysisResultSectionId.RiskAnalysis
    val isDark = RdTheme.isDark
    val ctaContent = if (isDark) colors.onyx else Color.White
    var kind by remember(isRiskSection) {
        mutableStateOf<ParityReportKind?>(if (isRiskSection) null else ParityReportKind.Standard)
    }
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
    val canGenerate = selectedCount > 0 && (!isRiskSection || kind != null)
    val maximumSheetHeight = (LocalConfiguration.current.screenHeightDp * .92f).dp
    val context = LocalContext.current
    val logoPicker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        companyLogoBytes = uri?.let { selected ->
            runCatching {
                context.contentResolver.openInputStream(selected)?.use(BitmapFactory::decodeStream)?.let { bitmap ->
                    val scale = minOf(1f, 1000f / maxOf(bitmap.width, bitmap.height).toFloat())
                    val resized = if (scale < 1f) {
                        android.graphics.Bitmap.createScaledBitmap(
                            bitmap,
                            (bitmap.width * scale).toInt().coerceAtLeast(1),
                            (bitmap.height * scale).toInt().coerceAtLeast(1),
                            true,
                        )
                    } else bitmap
                    ByteArrayOutputStream().use { output ->
                        resized.compress(android.graphics.Bitmap.CompressFormat.JPEG, 88, output)
                        output.toByteArray()
                    }.also {
                        if (resized !== bitmap) resized.recycle()
                        bitmap.recycle()
                    }
                }
            }.getOrNull()
        }
    }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = sheetState,
        containerColor = colors.paper,
        dragHandle = { Box(Modifier.padding(top = 8.dp).size(38.dp, 5.dp).clip(CircleShape).background(colors.line)) },
    ) {
        Column(Modifier.fillMaxWidth().heightIn(max = maximumSheetHeight)) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 11.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(13.dp),
            ) {
                if (showCompanyPicker) {
                    IconButton(onClick = { showCompanyPicker = false }, modifier = Modifier.size(40.dp).clip(CircleShape).background(colors.fog)) {
                        Icon(Icons.Filled.KeyboardArrowLeft, stringResource(RdR.string.rd_geri), tint = colors.black)
                    }
                } else {
                    Box(
                        Modifier.size(46.dp).clip(RoundedCornerShape(12.dp))
                            .background(Brush.linearGradient(listOf(Color(0xFFE8762A), Color(0xFFE0A828), Color(0xFF4FAE7A), Color(0xFF1F8F9C))))
                            .shadow(6.dp, RoundedCornerShape(12.dp), ambientColor = Color(0xFF1F8F9C).copy(.26f), spotColor = Color(0xFF1F8F9C).copy(.26f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Filled.IosShare, null, tint = Color.White, modifier = Modifier.size(21.dp))
                    }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        stringResource(if (showCompanyPicker) RdR.string.rd_rapor_firmasi else RdR.string.rd_report_sheet_title),
                        style = iosRounded(16.5f, FontWeight.Black),
                        color = colors.resultPrimaryText,
                    )
                    if (!showCompanyPicker) Text(
                        stringResource(RdR.string.rd_report_sheet_subtitle_format, selectedCount, totalCount),
                        style = iosRounded(11f, FontWeight.SemiBold),
                        color = colors.resultTertiaryText,
                    )
                }
                IconButton(onClick = onClose, modifier = Modifier.size(40.dp).clip(CircleShape).background(colors.fog)) {
                    Icon(Icons.Filled.Close, stringResource(RdR.string.rd_kapat), tint = colors.black, modifier = Modifier.size(18.dp))
                }
            }
            if (showCompanyPicker) {
                LazyColumn(
                    Modifier.fillMaxWidth().weight(1f, fill = false).padding(horizontal = 20.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
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
            } else LazyColumn(
                Modifier.fillMaxWidth().weight(1f, fill = false).padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (isRiskSection) {
                    item {
                        ReportOptionCard(
                            selected = kind == ParityReportKind.Standard,
                            icon = Icons.Filled.Description,
                            title = stringResource(RdR.string.rd_standart_rapor),
                            subtitle = stringResource(RdR.string.rd_standart_rapor_aciklama),
                            emphasized = false,
                            onClick = { kind = ParityReportKind.Standard; format = ResultReportFormat.Pdf },
                        )
                    }
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            if (tier == SubscriptionTier.Free) FreeTrialRibbon()
                            ReportOptionCard(
                                selected = kind == ParityReportKind.RiskAnalysis,
                                icon = Icons.Filled.TableChart,
                                title = stringResource(RdR.string.rd_risk_analizi_tablosu),
                                subtitle = stringResource(RdR.string.rd_risk_analizi_tablosu_aciklama),
                                emphasized = true,
                                onClick = { kind = ParityReportKind.RiskAnalysis },
                            )
                        }
                    }
                } else {
                    item {
                        Text(stringResource(RdR.string.rd_cikti_formati), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.slate)
                        Spacer(Modifier.height(7.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ReportFormatCard(ResultReportFormat.Pdf, format == ResultReportFormat.Pdf, Modifier.weight(1f)) { format = ResultReportFormat.Pdf }
                            ReportFormatCard(ResultReportFormat.Excel, format == ResultReportFormat.Excel, Modifier.weight(1f)) { format = ResultReportFormat.Excel }
                        }
                    }
                }
                if (isRiskSection && kind == ParityReportKind.RiskAnalysis) {
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
                        Text(stringResource(RdR.string.rd_risk_yontemi).localizedUppercase(), style = RdFontStyle.SectionHeader.toTextStyle(), color = colors.slate)
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
                    kind?.let { selectedKind ->
                        onGenerate(
                            selectedKind,
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
                    }
                },
                enabled = canGenerate,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp).height(58.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.cta,
                    contentColor = ctaContent,
                    disabledContainerColor = colors.resultLine,
                    disabledContentColor = colors.resultTertiaryText,
                ),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 18.dp),
            ) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.Download, null, modifier = Modifier.align(Alignment.CenterStart).size(20.dp))
                    Text(
                        when {
                            kind == null -> stringResource(RdR.string.rd_rapor_turu_secin)
                            kind == ParityReportKind.Standard -> stringResource(RdR.string.rd_rapor_olustur)
                            format == ResultReportFormat.Excel -> stringResource(RdR.string.rd_excel_risk_tablosu_olustur)
                            else -> stringResource(RdR.string.rd_risk_analizi_pdf_olustur)
                        },
                        style = iosRounded(15.5f, FontWeight.Black),
                        textAlign = TextAlign.Center,
                    )
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
        title.localizedUppercase(),
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
                color = colors.black,
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
            Text(stringResource(RdR.string.rd_firma_bazli_rapor_plus_pro), style = iosRounded(14f, FontWeight.Bold), color = colors.black)
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
                Text(stringResource(RdR.string.rd_tek_seferlik_firma_logo), style = iosRounded(14f, FontWeight.Bold), color = colors.black)
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
                    Text(stringResource(if (companyLogoBytes == null) RdR.string.rd_logo_secilmedi else RdR.string.rd_logo_rapora_eklenecek), style = iosRounded(13f, FontWeight.Bold), color = colors.black)
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
            Text(stringResource(RdR.string.rd_hazirlayan_bilgileri), style = iosRounded(14f, FontWeight.Bold), color = colors.black)
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
            textStyle = iosRounded(14f, FontWeight.Medium).copy(color = colors.black),
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
            Text(title, style = iosRounded(14f, FontWeight.Bold), color = colors.black)
            Text(subtitle, style = iosRounded(12f), color = colors.slate, maxLines = 2)
        }
        Icon(if (selected) Icons.Filled.CheckCircle else Icons.Filled.KeyboardArrowRight, null, tint = if (selected) colors.green else colors.slate, modifier = Modifier.size(19.dp))
    }
}

@Composable
private fun ReportOptionCard(
    selected: Boolean,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    emphasized: Boolean,
    onClick: () -> Unit,
) {
    val colors = RdTheme.colors
    val shape = RoundedCornerShape(15.dp)
    val idleBorder = if (emphasized) {
        Brush.linearGradient(listOf(Color(0xFFE8762A), Color(0xFFE0A828), Color(0xFF4FAE7A), Color(0xFF1F8F9C)))
    } else {
        Brush.linearGradient(listOf(colors.line, colors.line))
    }
    Row(
        Modifier.fillMaxWidth().heightIn(min = if (emphasized) 120.dp else 78.dp)
            .shadow(if (selected) 12.dp else 0.dp, shape, ambientColor = colors.green.copy(.12f), spotColor = colors.green.copy(.12f))
            .clip(shape).background(if (selected) colors.greenSoft.copy(.65f) else colors.white)
            .border(if (selected) 2.2.dp else if (emphasized) 1.8.dp else 1.2.dp, if (selected) Brush.linearGradient(listOf(colors.green, colors.greenDark)) else idleBorder, shape)
            .clickable(onClick = onClick).padding(horizontal = 15.dp, vertical = if (emphasized) 14.dp else 13.dp),
        verticalAlignment = if (emphasized) Alignment.CenterVertically else Alignment.Top,
    ) {
        Box(
            Modifier.size(if (emphasized) 52.dp else 48.dp).clip(RoundedCornerShape(10.dp)).background(
                when {
                    selected -> Brush.linearGradient(listOf(colors.green, colors.greenDark))
                    emphasized -> Brush.linearGradient(listOf(Color(0xFFE9A62C), Color(0xFF2C9B82)))
                    else -> Brush.linearGradient(listOf(colors.greenSoft, colors.greenSoft))
                },
            ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, null, tint = if (selected || emphasized) colors.white else colors.greenDark, modifier = Modifier.size(if (emphasized) 25.dp else 23.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(
            Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Text(title, style = iosRounded(14.5f, FontWeight.Black), color = colors.black, maxLines = 2)
            Text(
                subtitle,
                style = if (emphasized) {
                    iosRounded(11.8f, FontWeight.Medium).copy(lineHeight = 15.sp)
                } else {
                    iosRounded(11.5f, FontWeight.Medium)
                },
                color = colors.slate,
                maxLines = if (emphasized) 4 else 2,
            )
        }
        Box(Modifier.size(if (emphasized) 29.dp else 26.dp).clip(CircleShape).border(1.5.dp, if (selected) colors.green else colors.line, CircleShape).background(if (selected) colors.green else colors.white), contentAlignment = Alignment.Center) {
            if (selected) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(if (emphasized) 17.dp else 15.dp))
        }
    }
}

@Composable
private fun FreeTrialRibbon() {
    val colors = RdTheme.colors
    val isDark = RdTheme.isDark
    val accent = if (isDark) colors.sectionExpertStrong else colors.planPlusDark
    val ribbonGradient = if (isDark) {
        listOf(colors.resultAmberTint, colors.resultSurface)
    } else {
        listOf(colors.planPlusSoft.copy(.98f), colors.white.copy(.96f))
    }
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
            .background(Brush.linearGradient(ribbonGradient))
            .border(1.dp, colors.planPlus.copy(if (isDark) .62f else .34f), RoundedCornerShape(18.dp)).padding(horizontal = 16.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Box(Modifier.size(28.dp).clip(RoundedCornerShape(9.dp)).background(colors.resultElevatedSurface), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.WorkspacePremium, null, tint = accent, modifier = Modifier.size(15.dp))
        }
        Text(stringResource(RdR.string.rd_tek_seferlik_deneme_aciklama), style = iosRounded(13.5f, FontWeight.Bold), color = accent, modifier = Modifier.weight(1f), maxLines = 2)
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
        Text(stringResource(if (format == ResultReportFormat.Pdf) RdR.string.rd_pdf_rapor else RdR.string.rd_excel_tablo), style = RdFontStyle.Footnote.toTextStyle(), color = colors.black)
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
                Icon(Icons.Filled.FindInPage, null, tint = colors.black, modifier = Modifier.size(39.dp))
                Icon(Icons.Filled.AutoAwesome, null, tint = colors.green, modifier = Modifier.align(Alignment.TopEnd).padding(17.dp).size(19.dp))
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(if (format == ResultReportFormat.Pdf) RdR.string.rd_pdf_hazirlaniyor else RdR.string.rd_excel_hazirlaniyor), style = iosRounded(28f, FontWeight.Bold, tracking = -.4f), color = colors.black)
                Text(status, style = iosRounded(15f, FontWeight.Medium), color = colors.slate, textAlign = TextAlign.Center)
            }
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(RdR.string.rd_ilerleme).localizedUppercase(), style = iosRounded(11f, FontWeight.Bold, tracking = .55f), color = colors.slate, modifier = Modifier.weight(1f))
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

private fun formatScore(value: Double): String = NumberFormat.getNumberInstance(Locale.getDefault()).apply {
    maximumFractionDigits = if (value % 1.0 == 0.0) 0 else 1
}.format(value)

private fun formatResultDate(raw: String?): String {
    if (raw.isNullOrBlank()) return "—"
    return runCatching {
        OffsetDateTime.parse(raw).format(DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm", Locale.getDefault()))
    }.getOrDefault(raw.take(16).replace('T', ' '))
}

@Composable
private fun analysisSectorLabel(raw: String?, fallback: String): String {
    val sector = raw?.let(AnalysisSector::fromId)
    return sector?.let { rdAnalysisSectorTitle(it.id, it.titleTr) }
        ?: raw?.takeIf { it.isNotBlank() }
        ?: fallback
}

private fun Int?.orEmpty(): Int = this ?: 0
