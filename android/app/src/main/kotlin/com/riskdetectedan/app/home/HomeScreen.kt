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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.HealthAndSafety
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
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
import com.riskdetectedan.core.data.analysis.AnalysisCanvas
import com.riskdetectedan.core.data.analysis.HistoryItem
import com.riskdetectedan.core.data.profile.SubscriptionTier
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
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onNavigateToCamera: () -> Unit = {},
    onStartAnalysis: (List<String>) -> Unit = {},
    onHistory: () -> Unit = {},
    onProfile: () -> Unit = {},
    onUpgrade: () -> Unit = {},
    viewModel: HistoryViewModel = hiltViewModel(),
    photoTrayViewModel: PhotoTrayViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val context = LocalContext.current
    val state by viewModel.state.collectAsState()
    val trayPhotoPaths by photoTrayViewModel.photoPaths.collectAsState()
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
        val remaining = 1 - trayPhotoPaths.size // Free-tier default cap, see PhotoTraySheet's doc
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
            Column {
                Text("RiskDetected", style = RdFontStyle.Title2.toTextStyle(), color = colors.onyx)
                Text("Profesyonel İSG Asistanı", style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
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
                onClick = { showCanvasSheet = true },
            )
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
        val lastItem = loaded?.items?.firstOrNull()
        if (state is HistoryUiState.Loading) {
            Spacer(Modifier.height(RdSpacing.xl))
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
            }
        } else if (lastItem != null) {
            Spacer(Modifier.height(RdSpacing.xl))
            RdSectionCard(title = "Son Analiz") {
                LastAnalysisRow(item = lastItem, onClick = onHistory)
            }
        }
    }

    if (showCanvasSheet) {
        ModalBottomSheet(onDismissRequest = { showCanvasSheet = false }, sheetState = canvasSheetState) {
            CanvasSheet(
                selected = selectedCanvases,
                onSelectedChange = { selectedCanvases = it },
                userTier = SubscriptionTier.Free,
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
                    photoTrayViewModel.clear()
                    onStartAnalysis(paths)
                },
                onClose = { showPhotoTray = false },
            )
        }
    }
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
