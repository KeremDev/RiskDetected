package com.riskdetectedan.app.home

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
import androidx.compose.material.icons.filled.ArrowCircleUp
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.ReportProblem
import androidx.compose.material.icons.filled.Send
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
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.app.R
import com.riskdetectedan.app.reports.GeneratedReportsUiState
import com.riskdetectedan.app.reports.GeneratedReportsViewModel
import com.riskdetectedan.core.data.analysis.AnalysisCanvas
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
 * 5. "Taramayı Başlat" button — now the real last-step trigger: empty tray opens [PhotoTraySheet]
 *    (mirrors `showSourceDialog = true`), non-empty tray opens [CanvasSheet] directly (mirrors
 *    `beginPreAnalysisSelection()`). iOS also inserts a sector-picker sheet before CanvasSheet
 *    here (`RDConfig.Features.activeAnalysisSectorEnabled`); Android's sector picker still lives
 *    on the `AnalysisScreen` reached *after* canvas confirm instead — a real ordering
 *    simplification, documented, not silently dropped (sector selection itself is unaffected).
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
    onStartAnalysis: (canvasIds: List<String>, analysisMode: String, photoPaths: List<String>) -> Unit = { _, _, _ -> },
    onResumeAnalysis: () -> Unit = {},
    onHistory: () -> Unit = {},
    onReports: () -> Unit = {},
    onProfile: () -> Unit = {},
    onUpgrade: () -> Unit = {},
    viewModel: HistoryViewModel = hiltViewModel(),
    photoTrayViewModel: PhotoTrayViewModel = hiltViewModel(),
    quotaViewModel: QuotaViewModel = hiltViewModel(),
    reportsViewModel: GeneratedReportsViewModel = hiltViewModel(),
    progressViewModel: HomeProgressViewModel = hiltViewModel(),
    tierViewModel: HomeTierViewModel = hiltViewModel(),
    inFlightResumeViewModel: InFlightResumeViewModel = hiltViewModel(),
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
    // AppState.swift's PlanCapabilities local default (`tier.isPaid ? 3 : 1`,
    // `safeMaxPhotosPerAnalysis` clamps 1..3) paints instantly; `remotePhotoCapabilities`
    // (PlanCapabilitiesRepository.fetchPhotoCapabilities, real `plan_capability_rules`+
    // `app_feature_flags` read) overwrites it once resolved, same two-step sequencing as
    // `applyTier`/`refreshRemotePlanCapabilities` — closes the previously-documented remote
    // PlanCapabilities-override gap.
    val maxPhotoCount = remotePhotoCapabilities?.maxPhotosPerAnalysis
        ?: (if (userTier.isPaid) 3 else 1).coerceIn(1, 3)
    val isFreeQuotaExhausted = !userTier.isPaid && quota?.isExhausted == true

    var showTitlesSheet by rememberSaveable { mutableStateOf(false) }
    val titlesSheetState = rememberModalBottomSheetState()
    LaunchedEffect(Unit) {
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
    var selectedCanvases by remember { mutableStateOf(setOf(AnalysisCanvas.general)) }
    val canvasSheetState = rememberModalBottomSheetState()
    val traySheetState = rememberModalBottomSheetState()

    val galleryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(),
    ) { uris ->
        val remaining = maxPhotoCount - trayPhotoPaths.size
        uris.take(maxOf(0, remaining)).forEach { uri ->
            context.contentResolver.openInputStream(uri)?.use { stream ->
                val bitmap = BitmapFactory.decodeStream(stream)
                if (bitmap != null) {
                    val output = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, output)
                    val file = File(context.cacheDir, "tray_${UUID.randomUUID()}.jpg")
                    file.writeBytes(output.toByteArray())
                    photoTrayViewModel.addPhoto(file.absolutePath)
                }
            }
        }
    }

    /** Mirrors `beginPreAnalysisSelection()`: last step before analyzing, canvas confirm. */
    fun openCanvasSheetOrPaywall() {
        if (isFreeQuotaExhausted) onUpgrade() else showCanvasSheet = true
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.paper)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = RdSpacing.lg),
    ) {
        Spacer(Modifier.height(RdSpacing.lg))
        // Port of HomeHeader.swift: real RDLogo asset (the exact wordmark PNG from
        // Assets.xcassets/RDLogo.imageset — a text approximation read visibly different from the
        // real sparkle+magnifying-glass mark, so this uses the actual asset), "Yükselt" pill
        // (RDHeaderAccountCTA — hidden once paid, real icon+gradient+shadow), avatar (RDAvatar).
        // Avatar's real dropdown menu not ported, taps onProfile directly instead — see
        // HomeHeaderAvatar's doc comment.
        Row(verticalAlignment = Alignment.CenterVertically) {
            // Real image height ≈ size / capHeightRatio(0.44) in RDLogo.swift's own math — 34dp
            // puts the wordmark's cap-height roughly level with the 36dp avatar, sparkle poking
            // above, matching the reference screenshot's proportions (a flat 20dp read visibly
            // smaller/thinner than real iOS).
            Image(
                painter = painterResource(R.drawable.rd_logo),
                contentDescription = "RiskDetected",
                contentScale = ContentScale.FillHeight,
                modifier = Modifier.height(34.dp),
                alignment = Alignment.CenterStart,
            )
            Spacer(Modifier.weight(1f))
            if (!userTier.isPaid) {
                Row(
                    modifier = Modifier
                        .shadow(elevation = 8.dp, shape = RoundedCornerShape(7.dp), ambientColor = colors.green.copy(alpha = 0.24f), spotColor = colors.green.copy(alpha = 0.24f))
                        .clip(RoundedCornerShape(7.dp))
                        .background(colors.green)
                        .clickable(onClick = onUpgrade)
                        .padding(horizontal = RdSpacing.sm)
                        .height(24.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.ArrowCircleUp, contentDescription = null, tint = colors.white, modifier = Modifier.size(12.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Yükselt", style = RdFontStyle.Caption.toTextStyle(), color = colors.white)
                }
                Spacer(Modifier.width(RdSpacing.sm))
            }
            Box(modifier = Modifier.clickable(onClick = onProfile)) {
                HomeHeaderAvatar(initials = initials, tier = userTier, avatarPath = fetchedProfile?.avatarUrl)
            }
        }

        // Exact iOS gaps from here down (HomeView.swift body's real .padding values, not
        // approximated RdSpacing tokens): weekly→photoUpload 12, photoUpload→quotaHint 10,
        // →scanButton 14, →progressCard 18, →recentSection 28, →reportsSection 20.
        Spacer(Modifier.height(16.dp))
        progress?.let { summary -> WeeklyTrackingCard(summary = summary) }
        if (progress != null) Spacer(Modifier.height(12.dp))

        if (isFreeQuotaExhausted && trayPhotoPaths.isEmpty()) {
            LockedPhotoUploadCard(onClick = onUpgrade)
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
            FreeQuotaHint(quota = quota!!, onClick = { if (quota!!.isExhausted) onUpgrade() })
        }

        Spacer(Modifier.height(14.dp))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
                .shadow(elevation = 10.dp, shape = RoundedCornerShape(RdRadius.xl), ambientColor = colors.onyx.copy(alpha = 0.18f), spotColor = colors.onyx.copy(alpha = 0.18f))
                .clip(RoundedCornerShape(RdRadius.xl))
                .background(colors.onyx)
                .clickable {
                    if (isFreeQuotaExhausted) {
                        onUpgrade()
                    } else if (trayPhotoPaths.isEmpty()) {
                        showPhotoTray = true
                    } else {
                        showCanvasSheet = true
                    }
                }
                .padding(horizontal = RdSpacing.md),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Taramayı Başlat", style = RdFontStyle.Callout.toTextStyle(), color = colors.white)
            Box(
                modifier = Modifier.size(32.dp).clip(RoundedCornerShape(RdRadius.md)).background(colors.white),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Send, contentDescription = null, tint = colors.onyx, modifier = Modifier.size(15.dp))
            }
        }

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
            title = "Son uygunsuzluklar",
            icon = Icons.Filled.ReportProblem,
            tint = colors.critical,
            countLabel = "${loaded?.items?.size ?: 0} kayıt",
            onSeeAll = onHistory,
        ) {
            when {
                state is HistoryUiState.Loading -> Box(modifier = Modifier.fillMaxWidth().padding(vertical = RdSpacing.md), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.onyx, modifier = Modifier.size(22.dp))
                }
                recentItems.isEmpty() -> EmptyHomeSectionRow(
                    icon = Icons.Filled.CheckCircle,
                    iconTint = colors.greenDark,
                    iconBackground = colors.greenSoft,
                    title = "Henüz tamamlanmış analiz yok",
                    subtitle = "İlk tarama tamamlandığında burada listelenecek.",
                )
                else -> Row(
                    modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    recentItems.forEach { item ->
                        RecentAnalysisRingCard(item = item, photoPath = recentPhotoPaths[item.id], onClick = onHistory)
                    }
                }
            }
        }

        val reportsLoaded = reportsState as? GeneratedReportsUiState.Loaded
        val recentReports = reportsLoaded?.items?.take(5).orEmpty()
        Spacer(Modifier.height(20.dp))
        HomeSectionCard(
            title = "Oluşturulan raporlar",
            icon = Icons.Filled.Description,
            tint = colors.greenDark,
            countLabel = "${reportsLoaded?.items?.size ?: 0} dosya",
            onSeeAll = onReports,
        ) {
            if (recentReports.isEmpty()) {
                EmptyHomeSectionRow(
                    icon = Icons.Filled.Description,
                    iconTint = colors.slate,
                    iconBackground = colors.fog,
                    title = "Henüz rapor oluşturulmadı",
                    subtitle = "PDF veya Excel çıktıları burada görünecek.",
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.xs)) {
                    recentReports.forEach { report -> HomeReportRow(report = report, onClick = onReports) }
                }
            }
        }
        Spacer(Modifier.height(RdSpacing.xl))
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
                    photoTrayViewModel.clear()
                    onStartAnalysis(sortedCanvasIds, analysisMode, paths)
                },
                onDismiss = { showCanvasSheet = false },
                onUpgradeRequested = {
                    showCanvasSheet = false
                    onUpgrade()
                },
            )
        }
    }

    if (showPhotoTray) {
        ModalBottomSheet(onDismissRequest = { showPhotoTray = false }, sheetState = traySheetState) {
            PhotoTraySheet(
                photoPaths = trayPhotoPaths,
                maxPhotoCount = maxPhotoCount,
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
                    onUpgrade()
                },
                onStartAnalysis = {
                    // Mirrors continueFromPhotoTrayToAnalysis() -> beginPreAnalysisSelection():
                    // confirming the tray moves to canvas selection, the real *last* step, not
                    // straight to analysis.
                    showPhotoTray = false
                    openCanvasSheetOrPaywall()
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

/** Port of HomeView.swift's `freeQuotaHint` — compact "remaining/limit" badge (onyx normally,
 * critical when exhausted), title + dynamic subtitle, trailing gift icon. Only tappable (and only
 * navigates anywhere) when exhausted, same as iOS — a non-exhausted tap does nothing there either. */
@Composable
private fun FreeQuotaHint(quota: DailyQuotaUsage, onClick: () -> Unit) {
    val colors = RdTheme.colors
    RdListRow(
        title = "Ücretsiz Analiz Hakkı",
        subtitle = if (quota.isExhausted) {
            "Bugünkü hakkın doldu. Daha fazlası için hesabını yükselt."
        } else {
            "Günde 1 ücretsiz analiz hakkın hazır."
        },
        icon = Icons.Filled.CardGiftcard,
        iconTint = colors.white,
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
                    color = colors.white,
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
            Text(report.title ?: report.fileName ?: "Rapor", style = RdFontStyle.Callout.toTextStyle(), color = colors.onyx)
            report.createdAt?.take(10)?.let {
                Text(it, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }
        }
    }
}
