package com.riskdetectedan.app.home

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.Image
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.ReportProblem
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.app.R
import com.riskdetectedan.app.reports.GeneratedReportsUiState
import com.riskdetectedan.app.reports.GeneratedReportsViewModel
import com.riskdetectedan.core.data.analysis.AnalysisCanvas
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.analysis.DailyQuotaUsage
import com.riskdetectedan.core.data.reports.Report
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdListRow
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import com.riskdetectedan.feature.reports.HistoryUiState
import com.riskdetectedan.feature.reports.HistoryViewModel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

/**
 * Real visual+flow rebuild (2026-08-08) matching the actual iOS Home screenshot the owner
 * supplied — the previous RdListRow-based layout ("Fotoğraf çek"/"Geçmiş analizler"/"Profil" rows)
 * was functionally real (Faz M-S wired every data source correctly) but visually nothing like
 * `HomeView.swift`. This pass keeps every ViewModel/data source from Faz M-S unchanged and only
 * replaces the presentation layer + corrects the interaction order to match iOS's real one:
 *
 * 1. Header: logo, "Yükselt" pill (hidden once paid, port of `RDHeaderAccountCTA`), avatar
 *    (initials + tier badge, port of `RDAvatar`) — taps `onProfile` (iOS opens a dropdown menu
 *    there instead; not ported, see [HomeHeaderAvatar]'s doc comment).
 * 2. [WeeklyTrackingCard] (if progress loaded) — was previously not shown on Home at all.
 * 3. [PhotoUploadCard] / [LockedPhotoUploadCard] — photos are gathered **here first**, inline on
 *    Home (`photoTrayViewModel.photoPaths`), matching iOS's real `photoUploadCard` +
 *    `selectedPhotos` state placement — not behind a "Fotoğraf çek" row that used to open
 *    CanvasSheet as the *first* step.
 * 4. [FreeQuotaHint] (free tier only).
 * 5. "Taramayı Başlat" button — the real last-step trigger: empty tray opens [PhotoTraySheet]
 *    (mirrors `showSourceDialog = true`); non-empty tray opens [SectorPickerSheet] first, then
 *    [CanvasSheet] — real port of `beginPreAnalysisSelection()`'s real order (sector sheet,
 *    *then* canvas sheet — this was previously reversed/skipped on Android, sector picking lived
 *    only inside `AnalysisScreen` after canvas confirm; closed, see [SectorPickerSheet]'s doc
 *    comment).
 * 6. [ProfessionalProgressCard] (if progress loaded) — real `.compactStrip` MDP card.
 * 7. Recent-analyses section ([RecentAnalysisRingCard] horizontal scroll) and generated-reports
 *    section, both via [HomeSectionCard] — real port of `homeSectionCard`/`sectionHeader`.
 *
 * `userTier`/`maxPhotoCount` come from [HomeTierViewModel] (real fetched tier + the remote
 * `PlanCapabilities` override, see its own doc comment).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onNavigateToCamera: () -> Unit = {},
    onAnnotatePhotos: (List<String>) -> Unit = {},
    onStartAnalysis: (canvasIds: List<String>, analysisMode: String, photoPaths: List<String>, sectorId: String?) -> Unit = { _, _, _, _ -> },
    onResumeAnalysis: () -> Unit = {},
    onHistory: () -> Unit = {},
    onOpenAnalysis: (String) -> Unit = {},
    onReports: () -> Unit = {},
    onProfile: () -> Unit = {},
    onUpgrade: (entryPoint: String) -> Unit = {},
    quickScanRequestKey: Int = 0,
    onQuickScanRequestConsumed: (Int) -> Unit = {},
    viewModel: HistoryViewModel = hiltViewModel(),
    photoTrayViewModel: PhotoTrayViewModel = hiltViewModel(),
    quotaViewModel: QuotaViewModel = hiltViewModel(),
    reportsViewModel: GeneratedReportsViewModel = hiltViewModel(),
    progressViewModel: HomeProgressViewModel = hiltViewModel(),
    tierViewModel: HomeTierViewModel = hiltViewModel(),
    inFlightResumeViewModel: InFlightResumeViewModel = hiltViewModel(),
    sectorPickerViewModel: SectorPickerViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val context = LocalContext.current
    val state by viewModel.state.collectAsState()
    val recentPhotoPaths by viewModel.photoPaths.collectAsState()
    val trayPhotoPaths by photoTrayViewModel.photoPaths.collectAsState()
    val quota by quotaViewModel.quota.collectAsState()
    val reportsState by reportsViewModel.state.collectAsState()
    val progress by progressViewModel.progress.collectAsState()
    val fetchedProfile by tierViewModel.profile.collectAsState()
    val remotePhotoCapabilities by tierViewModel.photoCapabilities.collectAsState()
    val userTier = fetchedProfile?.tier ?: com.riskdetectedan.core.data.profile.SubscriptionTier.Free
    val initials = fetchedProfile?.displayInitials ?: "—"
    // Paid plans locally resolve to the product contract (three photos), so a slow/offline
    // capability fetch never flashes an incorrect 0/1 Free limit for Plus/Pro. A successfully
    // resolved remote emergency gate remains authoritative and can still lower the limit.
    val localPhotoCapabilities = com.riskdetectedan.core.data.analysis.PlanCapabilities.forTier(userTier)
    val resolvedMaxPhotoCount = remotePhotoCapabilities?.maxPhotosPerAnalysis
        ?: localPhotoCapabilities.maxPhotosPerAnalysis
    val resolvedVisiblePhotoSlots = remotePhotoCapabilities?.visiblePhotoSlotsInUI
        ?: localPhotoCapabilities.visiblePhotoSlotsInUI
    // iOS intentionally shows the value of multi-photo analysis to free members: one usable
    // slot and two locked previews. Capability enforcement remains one photo for Free.
    val maxPhotoCount = if (userTier.isPaid) resolvedMaxPhotoCount else 1
    val visiblePhotoSlots = if (userTier.isPaid) resolvedVisiblePhotoSlots else 3
    val isFreeQuotaExhausted = !userTier.isPaid && quota?.isExhausted == true

    var showTitlesSheet by rememberSaveable { mutableStateOf(false) }
    val titlesSheetState = rememberModalBottomSheetState()
    LaunchedEffect(Unit) {
        // These ViewModels are scoped to the MainShell back-stack entry and survive a pushed
        // analysis/result route. Refresh on every real Home re-entry so a just-completed
        // analysis/report is visible immediately instead of leaving the pre-analysis empty
        // state on screen until the process is restarted.
        viewModel.load()
        reportsViewModel.load()
        quotaViewModel.refresh()
        progressViewModel.refresh()
        tierViewModel.refresh()
        // Real port of resumeInFlightAnalysisIfNeeded's trigger — Home checks once per real entry
        // (not full-screen every recomposition) for an analysis that survived an app-process
        // death mid-submit/mid-poll, navigating straight into its progress screen instead of
        // silently losing track of it (the analysis itself never stops server-side either way —
        // this is purely about not losing the client's own "watching it" UI state).
        if (inFlightResumeViewModel.hasInFlightAnalysis()) onResumeAnalysis()
    }
    // rememberSaveable (not remember) — same fix as MainShellScreen's activeTab (Faz M): this
    // composable is disposed while CaptureForTray covers it (nav pushes a destination on top of
    // MainShell), so a plain `remember` lost showPhotoTray=true on the way back from the camera,
    // silently dropping the just-captured photo's sheet. Reproduced on-device, fixed here.
    var showCanvasSheet by rememberSaveable { mutableStateOf(false) }
    var showPhotoTray by rememberSaveable { mutableStateOf(false) }
    var showSectorSheet by rememberSaveable { mutableStateOf(false) }
    var selectedCanvases by remember { mutableStateOf(setOf(AnalysisCanvas.general)) }
    var selectedSector by remember { mutableStateOf<AnalysisSector?>(null) }
    val canvasSheetState = rememberModalBottomSheetState()
    val traySheetState = rememberModalBottomSheetState()
    // Material's default partially-expanded anchor opened this flow at roughly half height,
    // leaving the iOS-parity Continue button below the fold until the user dragged the sheet.
    // iOS presents this picker at a fixed 600pt detent, so enter directly at the expanded anchor.
    val sectorSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // Real port of `appendPickedPhotos(images, shouldAnnotate: true, ...)` — every gallery-picked
    // photo queues through Annotate before it lands in the tray, same as a freshly captured one
    // (see [onAnnotatePhotos]'s doc comment on the call site).
    val galleryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(),
    ) { uris ->
        val remaining = maxPhotoCount - trayPhotoPaths.size
        val savedPaths = uris.take(maxOf(0, remaining)).mapNotNull { uri ->
            context.contentResolver.openInputStream(uri)?.use { stream ->
                val bitmap = BitmapFactory.decodeStream(stream)
                if (bitmap != null) {
                    val output = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, output)
                    val file = File(context.cacheDir, "tray_${UUID.randomUUID()}.jpg")
                    file.writeBytes(output.toByteArray())
                    file.absolutePath
                } else {
                    null
                }
            }
        }
        if (savedPaths.isNotEmpty()) onAnnotatePhotos(savedPaths)
    }

    /** Real port of `beginPreAnalysisSelection()` — the real order is sector sheet *first*, then
     * [CanvasSheet] (see [SectorPickerSheet]'s doc comment for why this used to be reversed). */
    fun beginPreAnalysisSelection() {
        if (isFreeQuotaExhausted) onUpgrade("home_analysis_start_quota") else showSectorSheet = true
    }

    // Live iOS MainTabView always routes the center action back through Home. Empty drafts open
    // the source/tray chooser; an existing draft continues with sector then canvas. Keeping the
    // request as a monotonically increasing key also makes repeated taps observable while Home
    // remains the active tab.
    LaunchedEffect(quickScanRequestKey) {
        if (quickScanRequestKey <= 0) return@LaunchedEffect
        val latestQuota = if (!userTier.isPaid) quotaViewModel.refreshAndGet() else quota
        when (
            QuickScanReducer.decide(
                isPaid = userTier.isPaid,
                quotaExhausted = latestQuota?.isExhausted == true,
                hasPhotos = trayPhotoPaths.isNotEmpty(),
            )
        ) {
            QuickScanDecision.Upgrade -> onUpgrade("home_quick_scan_quota")
            QuickScanDecision.OpenPhotoTray -> showPhotoTray = true
            QuickScanDecision.SelectSector -> showSectorSheet = true
        }
        onQuickScanRequestConsumed(quickScanRequestKey)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.paper)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = RdSpacing.lg),
    ) {
        Spacer(Modifier.height(RdSpacing.lg))
        AppMainHeader(
            profile = fetchedProfile,
            onLogo = {},
            onProfile = onProfile,
            onUpgradeTier = { onUpgrade("home_header_upgrade") },
            horizontalPadding = 0.dp,
            topPadding = 0.dp,
            bottomPadding = 0.dp,
        )

        // Exact iOS gaps from here down (HomeView.swift body's real .padding values, not
        // approximated RdSpacing tokens): weekly→photoUpload 12, photoUpload→quotaHint 10,
        // →scanButton 14, →progressCard 18, →recentSection 28, →reportsSection 20.
        Spacer(Modifier.height(16.dp))
        progress?.let { summary -> WeeklyTrackingCard(summary = summary) }
        if (progress != null) Spacer(Modifier.height(12.dp))

        if (isFreeQuotaExhausted && trayPhotoPaths.isEmpty()) {
            LockedPhotoUploadCard(onClick = { onUpgrade("home_photo_upload_quota") })
        } else {
            PhotoUploadCard(
                photoPaths = trayPhotoPaths,
                maxPhotoCount = maxPhotoCount,
                onOpenTray = { showPhotoTray = true },
                onRemove = photoTrayViewModel::removePhoto,
            )
        }

        if (quota != null && !userTier.isPaid) {
            Spacer(Modifier.height(10.dp))
            FreeQuotaHint(quota = quota!!, onClick = { if (quota!!.isExhausted) onUpgrade("home_quota_hint") })
        }

        Spacer(Modifier.height(14.dp))
        HomeStartScanButton(
            onClick = {
                if (isFreeQuotaExhausted) {
                    onUpgrade("home_analysis_start_quota")
                } else if (trayPhotoPaths.isEmpty()) {
                    showPhotoTray = true
                } else {
                    beginPreAnalysisSelection()
                }
            },
        )

        progress?.let { summary ->
            Spacer(Modifier.height(18.dp))
            ProfessionalProgressCard(progress = summary, onClick = { showTitlesSheet = true })
        }

        // Always visible, matching iOS's real `recentSection`/`generatedReportsSection` — both
        // show their header + a real empty-state row (EmptyHomeSectionRow) rather than
        // disappearing when there's nothing to list yet (the earlier pass hid the whole section,
        // which read as "these cards don't exist" — this was the actual gap, not a visual one).
        val loaded = state as? HistoryUiState.Loaded
        val recentItems = loaded?.items?.take(8).orEmpty()
        Spacer(Modifier.height(28.dp))
        HomeSectionCard(
            title = stringResource(RdR.string.rd_son_uygunsuzluklar),
            icon = Icons.Filled.ReportProblem,
            tint = colors.critical,
            countLabel = stringResource(RdR.string.rd_kayit_sayisi_format, loaded?.items?.size ?: 0),
            onSeeAll = onHistory,
        ) {
            when {
                state is HistoryUiState.Loading -> Box(modifier = Modifier.fillMaxWidth().padding(vertical = RdSpacing.md), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.black, modifier = Modifier.size(22.dp))
                }
                recentItems.isEmpty() -> EmptyHomeSectionRow(
                    icon = Icons.Filled.CheckCircle,
                    iconTint = colors.greenDark,
                    iconBackground = colors.greenSoft,
                    title = stringResource(RdR.string.rd_henuz_tamamlanmis_analiz_yok),
                    subtitle = stringResource(RdR.string.rd_ilk_tarama_listelenecek),
                )
                else -> Row(
                    modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    recentItems.forEach { item ->
                        RecentAnalysisRingCard(
                            item = item,
                            photoPath = recentPhotoPaths[item.id],
                            onClick = { onOpenAnalysis(item.id) },
                        )
                    }
                }
            }
        }

        val reportsLoaded = reportsState as? GeneratedReportsUiState.Loaded
        val recentReports = reportsLoaded?.items?.take(5).orEmpty()
        Spacer(Modifier.height(20.dp))
        HomeSectionCard(
            title = stringResource(RdR.string.rd_olusturulan_raporlar),
            icon = Icons.Filled.Description,
            tint = colors.greenDark,
            countLabel = stringResource(RdR.string.rd_dosya_sayisi_format, reportsLoaded?.items?.size ?: 0),
            onSeeAll = onReports,
        ) {
            if (recentReports.isEmpty()) {
                EmptyHomeSectionRow(
                    icon = Icons.Filled.Description,
                    iconTint = colors.slate,
                    iconBackground = colors.fog,
                    title = stringResource(RdR.string.rd_henuz_rapor_olusturulmadi),
                    subtitle = stringResource(RdR.string.rd_rapor_ciktilari_burada),
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.xs)) {
                    recentReports.forEach { report -> HomeReportRow(report = report, onClick = onReports) }
                }
            }
        }
        Spacer(Modifier.height(RdSpacing.xl))
    }

    if (showSectorSheet) {
        ModalBottomSheet(onDismissRequest = { showSectorSheet = false }, sheetState = sectorSheetState) {
            SectorPickerSheet(
                items = remember(showSectorSheet) { sectorPickerViewModel.pickerItems() },
                onSelect = { sector ->
                    // Real port of continueAfterSectorSelection(): sector chosen -> straight to
                    // CanvasSheet, the real last step before analyzing.
                    selectedSector = sector
                    showSectorSheet = false
                    showCanvasSheet = true
                },
            )
        }
    }

    if (showCanvasSheet) {
        ModalBottomSheet(onDismissRequest = { showCanvasSheet = false }, sheetState = canvasSheetState) {
            CanvasSheet(
                selected = selectedCanvases,
                onSelectedChange = { selectedCanvases = it },
                userTier = userTier,
                onConfirm = {
                    showCanvasSheet = false
                    val paths = trayPhotoPaths
                    val sortedCanvasIds = selectedCanvases.map { it.id }.sorted()
                    val analysisMode = if (selectedCanvases.any { it.isPaid }) "detailed" else "standard"
                    // Real port of runAnalysis()'s AnalysisSectorPreferences.recordLastUsed(selected)
                    // call — right before the analyze request itself, not at selection time (a
                    // sector picked then abandoned mid-flow shouldn't become "last used").
                    selectedSector?.let { sectorPickerViewModel.recordLastUsed(it) }
                    photoTrayViewModel.clear()
                    onStartAnalysis(sortedCanvasIds, analysisMode, paths, selectedSector?.id)
                },
                onDismiss = { showCanvasSheet = false },
                onUpgradeRequested = {
                    showCanvasSheet = false
                    onUpgrade("home_canvas_locked_focus")
                },
            )
        }
    }

    if (showPhotoTray) {
        ModalBottomSheet(onDismissRequest = { showPhotoTray = false }, sheetState = traySheetState) {
            PhotoTraySheet(
                photoPaths = trayPhotoPaths,
                maxPhotoCount = maxPhotoCount,
                visibleSlotCount = visiblePhotoSlots,
                onCamera = {
                    // Deliberately NOT closing the sheet here (unlike onLockedSlot) —
                    // CaptureForTray covers MainShell (disposing this composition per Navigation
                    // Compose default), but showPhotoTray is rememberSaveable, so it survives and
                    // the sheet reopens automatically on the way back, now showing the new photo.
                    onNavigateToCamera()
                },
                onGallery = { galleryLauncher.launch(androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                onRemove = photoTrayViewModel::removePhoto,
                onMove = photoTrayViewModel::movePhoto,
                onLockedSlot = {
                    showPhotoTray = false
                    onUpgrade("home_photo_tray_locked_slot")
                },
                onStartAnalysis = {
                    // Mirrors continueFromPhotoTrayToAnalysis() -> beginPreAnalysisSelection():
                    // confirming the tray moves to sector selection, the real next step.
                    showPhotoTray = false
                    beginPreAnalysisSelection()
                },
                onClose = { showPhotoTray = false },
            )
        }
    }

    if (showTitlesSheet) {
        progress?.let { summary ->
            ModalBottomSheet(onDismissRequest = { showTitlesSheet = false }, sheetState = titlesSheetState) {
                ProfessionalTitlesSheet(progress = summary)
            }
        }
    }
}

/**
 * iOS `RDButton(style: .detect, icon: "sparkles")` parity: the center label includes the
 * leading sparkle while the white action capsule keeps its paper-plane icon at the trailing
 * edge. Keeping this as a small surface also lets visual tests catch either icon disappearing.
 */
@Composable
internal fun HomeStartScanButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = RdTheme.colors
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(56.dp)
            .shadow(
                elevation = 10.dp,
                shape = RoundedCornerShape(RdRadius.xl),
                ambientColor = colors.cta.copy(alpha = 0.18f),
                spotColor = colors.cta.copy(alpha = 0.18f),
            )
            .clip(RoundedCornerShape(RdRadius.xl))
            .background(colors.cta)
            .clickable(onClick = onClick)
            .padding(horizontal = RdSpacing.md)
            .testTag("home_start_scan_button"),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Filled.AutoAwesome,
                contentDescription = null,
                tint = androidx.compose.ui.graphics.Color.White,
                modifier = Modifier.size(17.dp).testTag("home_start_scan_sparkles"),
            )
            Text(
                stringResource(RdR.string.rd_taramayi_baslat),
                style = RdFontStyle.Callout.toTextStyle(),
                color = androidx.compose.ui.graphics.Color.White,
            )
        }
        Box(
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .size(38.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(androidx.compose.ui.graphics.Color.White),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.AutoMirrored.Filled.Send,
                contentDescription = null,
                tint = colors.cta,
                modifier = Modifier.size(20.dp).testTag("home_start_scan_action_icon"),
            )
        }
    }
}

/** Port of HomeView.swift's `freeQuotaHint` — compact "remaining/limit" badge (onyx normally,
 * critical when exhausted), title + dynamic subtitle, trailing gift icon. Only tappable (and only
 * navigates anywhere) when exhausted, same as iOS — a non-exhausted tap does nothing there either. */
@Composable
private fun FreeQuotaHint(quota: DailyQuotaUsage, onClick: () -> Unit) {
    val colors = RdTheme.colors
    RdListRow(
        title = stringResource(RdR.string.rd_ucretsiz_analiz_hakki),
        subtitle = if (quota.isExhausted) {
            stringResource(RdR.string.rd_bugunku_hak_doldu)
        } else {
            stringResource(RdR.string.rd_gunluk_ucretsiz_hak_hazir)
        },
        icon = Icons.Filled.CardGiftcard,
        iconTint = androidx.compose.ui.graphics.Color.White,
        iconBackground = if (quota.isExhausted) colors.critical else colors.onyx,
        onClick = onClick,
        trailing = {
            Box(
                modifier = Modifier
                    .size(width = 42.dp, height = 32.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(if (quota.isExhausted) colors.critical else colors.onyx),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "${quota.remaining}/${quota.limit}",
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = androidx.compose.ui.graphics.Color.White,
                )
            }
        },
    )
}

/** Home-embedded row for [GeneratedReportsUiState.Loaded] items — mirrors HomeView.swift's
 * `HomeReportRow` structurally (icon/title/date, tap opens), simplified to a single icon per
 * `isExcel` like Faz R's own tab list, not iOS's per-kind tinted chip. Tapping any row here just
 * switches to the Raporlar tab ([onClick] = `onReports`) rather than downloading+opening inline —
 * Home is a summary surface, the real open action lives on the tab itself (Faz R). */
@Composable
private fun HomeReportRow(report: Report, onClick: () -> Unit) {
    val colors = RdTheme.colors
    val isExcel = report.format == "xlsx" ||
        report.mimeType == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (isExcel) Icons.Filled.TableChart else Icons.Filled.Description,
            contentDescription = null,
            tint = colors.slate,
            modifier = Modifier.size(18.dp),
        )
        Spacer(Modifier.width(RdSpacing.sm))
        Column(modifier = Modifier.weight(1f)) {
            Text(report.title ?: report.fileName ?: stringResource(RdR.string.rd_rapor), style = RdFontStyle.Callout.toTextStyle(), color = colors.black)
            report.createdAt?.take(10)?.let {
                Text(it, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }
        }
    }
}
