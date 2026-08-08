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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CardGiftcard
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
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
 * `userTier`/`maxPhotoCount` come from [HomeTierViewModel] (real fetched tier, see its own doc
 * comment for what's still not ported — the remote `PlanCapabilities` override system).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onNavigateToCamera: () -> Unit = {},
    onStartAnalysis: (canvasIds: List<String>, analysisMode: String, photoPaths: List<String>) -> Unit = { _, _, _ -> },
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
) {
    val colors = RdTheme.colors
    val context = LocalContext.current
    val state by viewModel.state.collectAsState()
    val trayPhotoPaths by photoTrayViewModel.photoPaths.collectAsState()
    val quota by quotaViewModel.quota.collectAsState()
    val reportsState by reportsViewModel.state.collectAsState()
    val progress by progressViewModel.progress.collectAsState()
    val fetchedProfile by tierViewModel.profile.collectAsState()
    val userTier = fetchedProfile?.tier ?: com.riskdetectedan.core.data.profile.SubscriptionTier.Free
    val initials = fetchedProfile?.displayInitials ?: "—"
    // AppState.swift's PlanCapabilities local default (pre-remote-override):
    // `maxPhotosPerAnalysis: tier.isPaid ? 3 : 1`, `safeMaxPhotosPerAnalysis` clamps 1..3.
    val maxPhotoCount = (if (userTier.isPaid) 3 else 1).coerceIn(1, 3)
    val isFreeQuotaExhausted = !userTier.isPaid && quota?.isExhausted == true

    var showTitlesSheet by rememberSaveable { mutableStateOf(false) }
    val titlesSheetState = rememberModalBottomSheetState()
    LaunchedEffect(Unit) {
        quotaViewModel.refresh()
        progressViewModel.refresh()
        tierViewModel.refresh()
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
        // Port of HomeHeader.swift: logo, "Yükselt" pill (RDHeaderAccountCTA — hidden once
        // paid), avatar (RDAvatar). Avatar's real dropdown menu not ported, taps onProfile
        // directly instead — see HomeHeaderAvatar's doc comment.
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("Risk", style = RdFontStyle.Title2.toTextStyle(), color = colors.black)
                    Text("Detected", style = RdFontStyle.Title2.toTextStyle(), color = colors.slate)
                }
            }
            if (!userTier.isPaid) {
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(colors.green)
                        .clickable(onClick = onUpgrade)
                        .padding(horizontal = RdSpacing.sm, vertical = RdSpacing.xs),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Yükselt", style = RdFontStyle.Caption.toTextStyle(), color = colors.white)
                }
                Spacer(Modifier.width(RdSpacing.sm))
            }
            Box(modifier = Modifier.clickable(onClick = onProfile)) {
                HomeHeaderAvatar(initials = initials, tier = userTier)
            }
        }

        Spacer(Modifier.height(RdSpacing.md))
        progress?.let { summary -> WeeklyTrackingCard(summary = summary) }
        if (progress != null) Spacer(Modifier.height(RdSpacing.md))

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
            Spacer(Modifier.height(RdSpacing.sm))
            FreeQuotaHint(quota = quota!!, onClick = { if (quota!!.isExhausted) onUpgrade() })
        }

        Spacer(Modifier.height(RdSpacing.md))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
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
            Spacer(Modifier.height(RdSpacing.md))
            ProfessionalProgressCard(progress = summary, onClick = { showTitlesSheet = true })
        }

        val loaded = state as? HistoryUiState.Loaded
        val recentItems = loaded?.items?.take(8).orEmpty()
        if (state is HistoryUiState.Loading) {
            Spacer(Modifier.height(RdSpacing.xl))
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
            }
        } else if (recentItems.isNotEmpty()) {
            Spacer(Modifier.height(RdSpacing.lg))
            HomeSectionCard(
                title = "Son uygunsuzluklar",
                icon = Icons.Filled.ReportProblem,
                tint = colors.critical,
                countLabel = "${loaded?.items?.size ?: recentItems.size} kayıt",
                onSeeAll = onHistory,
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(RdSpacing.md),
                ) {
                    recentItems.forEach { item -> RecentAnalysisRingCard(item = item, onClick = onHistory) }
                }
            }
        }

        val reportsLoaded = reportsState as? GeneratedReportsUiState.Loaded
        val recentReports = reportsLoaded?.items?.take(5).orEmpty()
        if (recentReports.isNotEmpty()) {
            Spacer(Modifier.height(RdSpacing.md))
            HomeSectionCard(
                title = "Oluşturulan raporlar",
                icon = Icons.Filled.Description,
                tint = colors.greenDark,
                countLabel = "${reportsLoaded?.items?.size ?: recentReports.size} dosya",
                onSeeAll = onReports,
            ) {
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
