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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.HealthAndSafety
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
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
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.reports.Report
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdListRow
import com.riskdetectedan.core.designsystem.RdRiskChip
import com.riskdetectedan.core.designsystem.RdSectionCard
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.riskLevelFromRaw
import com.riskdetectedan.core.designsystem.toTextStyle
import com.riskdetectedan.feature.reports.HistoryUiState
import com.riskdetectedan.feature.reports.HistoryViewModel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

/**
 * Not a port of App/Views/Home/HomeView.swift's full 2852-line dashboard/`MainTabView.swift`'s
 * tab bar (those are [com.riskdetectedan.app.navigation.MainShellScreen]/[com.riskdetectedan.app.navigation.RdTabBar]
 * now, Faz M) — this is Home's *own* tab content, reusing [RdListRow]/[RdSectionCard]/[RdRiskChip]
 * (Faz F). iOS's "reports" tab (generated PDF/XLSX list) is a separate tab now too (Faz M/R stub),
 * not conflated with this screen's own "Geçmiş analizler" card (which is Analizler-tab content).
 *
 * Reuses `feature:reports`'s already-built [HistoryViewModel] for the last-analysis summary card
 * (rather than adding a second parallel query) — `app` already depends on `feature:reports` for
 * `ReportsScreen`, so this doesn't add a new module edge.
 *
 * Faz N/O (2026-08-08): "Fotoğraf çek" opens the real [CanvasSheet] (Odaklı Analiz picker) then
 * the real [PhotoTraySheet] (multi-photo picker) — matching HomeView.swift's real flow order
 * (canvas, then photos) instead of jumping straight to Capture. Selected canvases still aren't
 * threaded into analysis creation (Faz Q's job). `userTier` defaults to Free (no shared app-wide
 * session/tier state exists yet) — same documented gap as Faz N.
 *
 * Faz P (2026-08-08): real daily-quota hint row (mirrors HomeView.swift's `freeQuotaHint`) below
 * "Fotoğraf çek" — free-tier default the same way `userTier` is (`!SubscriptionTier.Free.isPaid`
 * is always true here, so the hint always shows, same as every other Faz N/O free-tier default).
 * Tapping "Fotoğraf çek" while exhausted skips [CanvasSheet] entirely and goes straight to
 * [onUpgrade], mirroring `isFreeQuotaExhausted && selectedPhotos.isEmpty` → `showQuotaPaywall()`.
 *
 * Faz Q (2026-08-08): [selectedCanvases] is now actually threaded into analysis creation —
 * `onStartAnalysis`'s first two params mirror AnalysisService.swift's real contract exactly:
 * `canvasIds` = the full sorted selection, `analysisMode` = "detailed" if any selected canvas is
 * paid-tier else "standard" (`canvases.contains { $0.isPaid }`). Previously this was silently
 * dropped — CanvasSheet's selection UI worked but never reached the actual analyze request.
 *
 * Faz S (2026-08-08): real professional-progress card (see [ProfessionalProgressCard]'s doc
 * comment) between the quota hint and "Geçmiş analizler" — tapping it opens
 * [ProfessionalTitlesSheet], port of `ProfessionalProgressHomeCard.swift`'s `onTap`.
 *
 * Post-Faz-S (2026-08-08): `userTier` is now the real fetched tier (see [HomeTierViewModel]'s
 * doc comment) instead of a permanent hardcoded Free — closes that documented gap's local-default
 * half; the remote `PlanCapabilities` override system stays a separate, still-open gap.
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
    val fetchedTier by tierViewModel.tier.collectAsState()
    // Same fallback iOS's own AppState.currentTier defaults to before a profile loads.
    val userTier = fetchedTier ?: SubscriptionTier.Free
    // AppState.swift's PlanCapabilities local default (pre-remote-override):
    // `maxPhotosPerAnalysis: tier.isPaid ? 3 : 1`, `safeMaxPhotosPerAnalysis` clamps 1..3 — the
    // clamp is a no-op for these two inputs, kept for the same "never silently exceed 3" intent.
    val maxPhotoCount = (if (userTier.isPaid) 3 else 1).coerceIn(1, 3)
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

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.paper)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = RdSpacing.lg),
    ) {
        Spacer(Modifier.height(RdSpacing.xl))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.size(44.dp).clip(CircleShape).background(colors.onyx),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.HealthAndSafety, contentDescription = null, tint = colors.white, modifier = Modifier.size(22.dp))
            }
            Spacer(Modifier.width(RdSpacing.sm))
            Column(modifier = Modifier.weight(1f)) {
                Text("RiskDetected", style = RdFontStyle.Title2.toTextStyle(), color = colors.onyx)
                Text("Profesyonel İSG Asistanı", style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
            }
            // Port of HomeHeader.swift's RDHeaderAccountCTA — opens the paywall directly from
            // the header, same as iOS.
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(colors.onyx)
                    .clickable(onClick = onUpgrade)
                    .padding(horizontal = RdSpacing.sm, vertical = RdSpacing.xs),
            ) {
                Text("Planı Yükselt", style = RdFontStyle.Caption.toTextStyle(), color = colors.white)
            }
        }

        Spacer(Modifier.height(RdSpacing.xl))
        Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
            RdListRow(
                title = "Fotoğraf çek",
                subtitle = "Yeni analiz başlat",
                icon = Icons.Filled.CameraAlt,
                iconTint = colors.white,
                iconBackground = colors.onyx,
                onClick = {
                    if (quota?.isExhausted == true) onUpgrade() else showCanvasSheet = true
                },
            )
            if (quota != null) {
                FreeQuotaHint(quota = quota!!, onClick = { if (quota!!.isExhausted) onUpgrade() })
            }
            progress?.let { summary ->
                ProfessionalProgressCard(progress = summary, onClick = { showTitlesSheet = true })
            }
            RdListRow(
                title = "Geçmiş analizler",
                subtitle = "Tüm analizlerini gör",
                icon = Icons.Filled.History,
                onClick = onHistory,
            )
            RdListRow(
                title = "Profil",
                subtitle = "Hesap ve ayarlar",
                icon = Icons.Filled.Person,
                onClick = onProfile,
            )
        }

        val loaded = state as? HistoryUiState.Loaded
        val recentItems = loaded?.items?.take(5).orEmpty()
        if (state is HistoryUiState.Loading) {
            Spacer(Modifier.height(RdSpacing.xl))
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
            }
        } else if (recentItems.isNotEmpty()) {
            // Faz Q: port of HomeView.swift's recentSection — real list (up to 5), not just the
            // single last item. Simplified vs iOS's RecentAnalysisCard (AngularGradient risk-ring
            // + photo thumbnail, horizontal scroll): a plain vertical RdListRow list, same rows
            // Analizler's own history screen already uses — no Storage signed-URL photo-fetch
            // exists yet to back a real thumbnail, documented gap, not silently dropped.
            Spacer(Modifier.height(RdSpacing.xl))
            RdSectionCard(title = "Son Analizler") {
                Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.xs)) {
                    recentItems.forEach { item -> LastAnalysisRow(item = item, onClick = onHistory) }
                }
            }
        }

        val reportsLoaded = reportsState as? GeneratedReportsUiState.Loaded
        val recentReports = reportsLoaded?.items?.take(5).orEmpty()
        if (recentReports.isNotEmpty()) {
            // Port of HomeView.swift's generatedReportsSection — real data from Faz R's
            // GeneratedReportsViewModel, same simplified single-icon row style as the Raporlar
            // tab itself (see GeneratedReportsScreen's doc comment).
            Spacer(Modifier.height(RdSpacing.lg))
            RdSectionCard(title = "Oluşturulan Raporlar") {
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
                    showPhotoTray = true
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
                    // Deliberately NOT closing the sheet here (unlike onLockedSlot/onStartAnalysis)
                    // — CaptureForTray covers MainShell (disposing this composition per Navigation
                    // Compose default), but showPhotoTray is rememberSaveable, so it survives and
                    // the sheet reopens automatically on the way back, now showing the new photo.
                    // Found via on-device repro: closing it here left nothing to reopen it, so a
                    // captured photo silently landed in the ViewModel with no visible sheet.
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
                    showPhotoTray = false
                    val paths = trayPhotoPaths
                    // Same "canvas = sorted().first, canvases = sorted()" contract as
                    // AnalysisService.swift — see this function's doc comment.
                    val sortedCanvasIds = selectedCanvases.map { it.id }.sorted()
                    val analysisMode = if (selectedCanvases.any { it.isPaid }) "detailed" else "standard"
                    photoTrayViewModel.clear()
                    onStartAnalysis(sortedCanvasIds, analysisMode, paths)
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

@Composable
private fun LastAnalysisRow(item: HistoryItem, onClick: () -> Unit) {
    val colors = RdTheme.colors
    val level = riskLevelFromRaw(item.riskBand)
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(item.title, style = RdFontStyle.Callout.toTextStyle(), color = colors.onyx)
            Text(
                "${item.findingCount} bulgu · ${item.createdAt?.take(10) ?: ""}",
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
            )
        }
        RdRiskChip(level = level)
    }
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
