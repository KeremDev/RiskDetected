package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.ColorLens
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Gavel
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Numbers
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.SupportAgent
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.profile.RiskMethodWire
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.data.profile.ProfileStats
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.data.legal.LegalDocumentAssets
import com.riskdetectedan.core.data.progress.ProfessionalProgressBadge
import com.riskdetectedan.core.data.progress.ProfessionalProgressCompetencyStat
import com.riskdetectedan.core.data.progress.ProfessionalProgressProfileRow
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import com.riskdetectedan.core.data.progress.ProfessionalProgressTitle
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdLegalDocument
import com.riskdetectedan.core.designsystem.RdLegalDocumentSheet
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSectionCard
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import com.riskdetectedan.core.designsystem.professionalProgressTitleLabel
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Reads the actual `profiles` row for the signed-in user via [ProfileViewModel]/
 * `ProfileRepository` — all logic unchanged (2026-08-08 visual pass, Faz K of the core-flow
 * redesign). Real structure: avatar+name+tier hero card, [RdSectionCard] for professional
 * progress, [RdListRow] menu (Profili düzenle/Planı yükselt/Firmalarım/Destek/Bildirim
 * ayarları), destructive "Hesabı sil" styled with the app's real critical color instead of a
 * plain `Button`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    onBack: (() -> Unit)? = null,
    onManageCompanies: () -> Unit = {},
    onOsgbWorkspace: () -> Unit = {},
    onAnalyses: () -> Unit = {},
    onReports: () -> Unit = {},
    onSupport: () -> Unit = {},
    onNotificationSettings: () -> Unit = {},
    onAppearanceSettings: () -> Unit = {},
    onDataManagement: () -> Unit = {},
    onDeleteAccount: () -> Unit = {},
    onPaywall: () -> Unit = {},
    viewModel: ProfileViewModel = hiltViewModel(),
    osgbWorkspaceViewModel: OsgbWorkspaceViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val osgbState by osgbWorkspaceViewModel.state.collectAsState()
    val restoreState by viewModel.restoreState.collectAsState()
    var isEditing by remember { mutableStateOf(false) }
    var showNotebook by remember { mutableStateOf(false) }
    if (showNotebook && NotebookUIRelease.enabled) {
        NotebookScreen(onClose = { showNotebook = false })
        return
    }
    var showSignOutConfirmation by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        if (NotebookUIRelease.enabled && state is ProfileUiState.Loaded) {
            TextButton(onClick = { showNotebook = true }) { Text("Kişisel Notlar · Ücretsiz") }
        }
        if (onBack != null) {
            RdScreenHeader(title = stringResource(RdR.string.rd_profil), onBack = onBack)
        }

        when (val current = state) {
            is ProfileUiState.Loading -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.black)
            }
            is ProfileUiState.SignedOut -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(RdR.string.rd_oturum_yok), style = RdFontStyle.Callout.toTextStyle(), color = colors.slate)
            }
            is ProfileUiState.Failed -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(RdR.string.rd_profil_yuklenemedi_format, current.error.message), style = RdFontStyle.Callout.toTextStyle(), color = colors.critical)
            }
            is ProfileUiState.Loaded -> if (isEditing) {
                ProfileEditForm(
                    profile = current.profile,
                    viewModel = viewModel,
                    onDone = { isEditing = false },
                )
            } else {
                val progress by viewModel.progress.collectAsState()
                val stats by viewModel.stats.collectAsState()
                var showBadges by remember { mutableStateOf(false) }
                var showCompetencies by remember { mutableStateOf(false) }
                var showTitles by remember { mutableStateOf(false) }
                var showLegal by remember { mutableStateOf(false) }
                var pendingCelebrationBadge by remember { mutableStateOf<ProfessionalProgressBadge?>(null) }

                // Real port of ProfessionalProgressProfileSection.swift's `.task(id:
                // summary.pendingCelebration?.id)` — auto-opens the celebration sheet for the
                // first unseen badge, once per distinct pending badge id (a local dismiss without
                // marking it seen — see the sheet's onDismissRequest below — won't re-trigger
                // until a *different* badge becomes pending).
                LaunchedEffect(progress?.pendingCelebration?.id) {
                    if (pendingCelebrationBadge == null) {
                        progress?.pendingCelebration?.let { pendingCelebrationBadge = it }
                    }
                }

                ProfileLoadedSurface(
                    profile = current.profile,
                    stats = stats,
                    progress = progress,
                    restoreInProgress = restoreState is ProfileRestoreState.Restoring,
                    isSavingAvatar = viewModel.isSavingAvatar.collectAsState().value,
                    avatarErrorMessage = viewModel.avatarError.collectAsState().value?.message,
                    onAvatarBytes = viewModel::updateAvatar,
                    onShowBadges = { showBadges = true },
                    onShowCompetencies = { showCompetencies = true },
                    onShowTitles = { showTitles = true },
                    onEdit = { isEditing = true },
                    onManageCompanies = onManageCompanies,
                    showOsgbWorkspace = osgbState.hasWorkspace == true,
                    onOsgbWorkspace = onOsgbWorkspace,
                    onAnalyses = onAnalyses,
                    onReports = onReports,
                    onNotificationSettings = onNotificationSettings,
                    onPaywall = onPaywall,
                    onAppearanceSettings = onAppearanceSettings,
                    onRestorePurchases = viewModel::restorePurchases,
                    onDataManagement = onDataManagement,
                    onShowLegal = { showLegal = true },
                    onSupport = onSupport,
                    onDeleteAccount = onDeleteAccount,
                    onSignOut = { showSignOutConfirmation = true },
                )

                if (showBadges) {
                    progress?.let { summary ->
                        val sheetState = rememberModalBottomSheetState()
                        ModalBottomSheet(onDismissRequest = { showBadges = false }, sheetState = sheetState) {
                            ProfessionalProgressBadgesSheet(summary = summary, onDismiss = { showBadges = false })
                        }
                    }
                }
                if (showCompetencies) {
                    progress?.let { summary ->
                        val sheetState = rememberModalBottomSheetState()
                        ModalBottomSheet(onDismissRequest = { showCompetencies = false }, sheetState = sheetState) {
                            Column(
                                modifier = Modifier
                                    .verticalScroll(rememberScrollState())
                                    .padding(RdSpacing.lg),
                            ) {
                                ProfessionalProgressCompetencyMapView(competencies = summary.competencies, compact = false)
                            }
                        }
                    }
                }
                if (showTitles) {
                    progress?.let { summary ->
                        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
                        ModalBottomSheet(onDismissRequest = { showTitles = false }, sheetState = sheetState) {
                            ProfessionalProgressTitlesSheet(summary = summary, onDismiss = { showTitles = false })
                        }
                    }
                }
                if (showLegal) {
                    val context = LocalContext.current
                    var legalDocuments by remember { mutableStateOf<List<RdLegalDocument>>(emptyList()) }
                    LaunchedEffect(Unit) {
                        legalDocuments = LegalDocumentAssets.load(context)
                            .map { RdLegalDocument(kind = it.kind, title = it.title, text = it.text) }
                    }
                    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
                    ModalBottomSheet(onDismissRequest = { showLegal = false }, sheetState = sheetState) {
                        RdLegalDocumentSheet(
                            documents = legalDocuments,
                            initialKind = null,
                            onClose = { showLegal = false },
                        )
                    }
                }
                // Real port of the Swift `onClose` closure — marks the badge seen and refreshes
                // the summary only on an explicit close (Tamam / X), never on a plain swipe-away
                // (see the LaunchedEffect above's doc comment for why that distinction matters).
                pendingCelebrationBadge?.let { badge ->
                    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
                    ModalBottomSheet(
                        onDismissRequest = { pendingCelebrationBadge = null },
                        sheetState = sheetState,
                        containerColor = colors.paper,
                    ) {
                        ProfessionalProgressCelebrationSheet(badge = badge) {
                            viewModel.markBadgeSeen(badge)
                            pendingCelebrationBadge = null
                        }
                    }
                }
            }
        }
    }

    if (showSignOutConfirmation) {
        AlertDialog(
            onDismissRequest = { showSignOutConfirmation = false },
            title = { Text(stringResource(RdR.string.rd_cikis_yapilsin_mi)) },
            text = { Text(stringResource(RdR.string.rd_bu_cihazdaki_oturumun_kapatilacak)) },
            confirmButton = {
                TextButton(onClick = {
                    showSignOutConfirmation = false
                    viewModel.signOut()
                }) { Text(stringResource(RdR.string.rd_cikis_yap)) }
            },
            dismissButton = {
                TextButton(onClick = { showSignOutConfirmation = false }) { Text(stringResource(RdR.string.rd_vazgec)) }
            },
        )
    }

    when (val restore = restoreState) {
        is ProfileRestoreState.Completed -> AlertDialog(
            onDismissRequest = viewModel::clearRestoreState,
            title = { Text(stringResource(RdR.string.rd_geri_yukleme_tamamlandi)) },
            text = { Text(restore.message) },
            confirmButton = { TextButton(onClick = viewModel::clearRestoreState) { Text(stringResource(RdR.string.rd_tamam)) } },
        )
        is ProfileRestoreState.Failed -> AlertDialog(
            onDismissRequest = viewModel::clearRestoreState,
            title = { Text(restore.error.title) },
            text = { Text(restore.error.message) },
            confirmButton = { TextButton(onClick = viewModel::clearRestoreState) { Text(stringResource(RdR.string.rd_tamam)) } },
        )
        ProfileRestoreState.Idle, ProfileRestoreState.Restoring -> Unit
    }
}

/** The real loaded-state body shared by [ProfileScreen] and deterministic visual tests. */
@Composable
fun ProfileLoadedSurface(
    profile: UserProfile,
    stats: ProfileStats?,
    progress: ProfessionalProgressSummary?,
    restoreInProgress: Boolean = false,
    isSavingAvatar: Boolean = false,
    avatarErrorMessage: String? = null,
    onAvatarBytes: (ByteArray) -> Unit = {},
    onShowBadges: () -> Unit = {},
    onShowCompetencies: () -> Unit = {},
    onShowTitles: () -> Unit = {},
    onEdit: () -> Unit = {},
    onManageCompanies: () -> Unit = {},
    showOsgbWorkspace: Boolean = false,
    onOsgbWorkspace: () -> Unit = {},
    onAnalyses: () -> Unit = {},
    onReports: () -> Unit = {},
    onNotificationSettings: () -> Unit = {},
    onPaywall: () -> Unit = {},
    onAppearanceSettings: () -> Unit = {},
    onRestorePurchases: () -> Unit = {},
    onDataManagement: () -> Unit = {},
    onShowLegal: () -> Unit = {},
    onSupport: () -> Unit = {},
    onDeleteAccount: () -> Unit = {},
    onSignOut: () -> Unit = {},
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = RdSpacing.lg)
            .padding(bottom = 112.dp),
    ) {
        ProfileHero(
            profile = profile,
            stats = stats,
            progress = progress,
            isSavingAvatar = isSavingAvatar,
            avatarErrorMessage = avatarErrorMessage,
            onAvatarBytes = onAvatarBytes,
            onShowBadges = onShowBadges,
            onShowTitles = onShowTitles,
            onAnalyses = onAnalyses,
            onReports = onReports,
        )
        Spacer(Modifier.height(14.dp))
        SubscriptionStatusCard(profile = profile, onPaywall = onPaywall)
        progress?.let {
            Spacer(Modifier.height(14.dp))
            ProfessionalProgressSection(
                progress = it,
                onShowTitles = onShowTitles,
                onShowCompetencies = onShowCompetencies,
            )
        }
        Spacer(Modifier.height(14.dp))
        ProfileMenuSection(title = stringResource(RdR.string.rd_hesap_upper)) {
            ProfileMenuRow(stringResource(RdR.string.rd_profil_bilgileri), Icons.Filled.Edit, onClick = onEdit)
            ProfileMenuDivider()
            ProfileMenuRow(
                stringResource(RdR.string.rd_firmalarim),
                Icons.Filled.Business,
                detail = if (profile.isPaid) stringResource(RdR.string.rd_yonet) else stringResource(RdR.string.rd_plus_pro),
                onClick = if (profile.isPaid) onManageCompanies else onPaywall,
            )
            if (showOsgbWorkspace) {
                ProfileMenuDivider()
                ProfileMenuRow(
                    "OSGB Çalışma Alanı",
                    Icons.Filled.Business,
                    detail = "Firma ve operasyon yönetimi",
                    onClick = onOsgbWorkspace,
                )
            }
            ProfileMenuDivider()
            ProfileMenuRow(stringResource(RdR.string.rd_gecmis_analizler), Icons.Filled.Assessment, detail = stats?.analysisCount?.toString() ?: "—", onClick = onAnalyses)
            ProfileMenuDivider()
            ProfileMenuRow(stringResource(RdR.string.rd_raporlarim), Icons.Filled.Description, detail = stats?.reportCount?.toString() ?: "—", onClick = onReports)
            ProfileMenuDivider()
            ProfileMenuRow(stringResource(RdR.string.rd_bildirimler), Icons.Filled.Notifications, onClick = onNotificationSettings)
        }
        Spacer(Modifier.height(14.dp))
        ProfileMenuSection(title = stringResource(RdR.string.rd_ayarlar_upper)) {
            ProfileMenuRow(stringResource(RdR.string.rd_tercihler), Icons.Filled.ColorLens, onClick = onAppearanceSettings)
            ProfileMenuDivider()
            ProfileMenuRow(
                stringResource(if (restoreInProgress) RdR.string.rd_satin_alimlar_geri_yukleniyor else RdR.string.rd_satin_alimlari_geri_yukle),
                Icons.Filled.Restore,
                onClick = onRestorePurchases,
            )
            ProfileMenuDivider()
            ProfileMenuRow(stringResource(RdR.string.rd_verilerim), Icons.Filled.Storage, onClick = onDataManagement)
            ProfileMenuDivider()
            ProfileMenuRow(stringResource(RdR.string.rd_guvenlik_gizlilik), Icons.Filled.Gavel, onClick = onShowLegal)
            ProfileMenuDivider()
            ProfileMenuRow(stringResource(RdR.string.rd_destek), Icons.Filled.SupportAgent, onClick = onSupport)
        }
        Spacer(Modifier.height(14.dp))
        ProfileStandaloneRow(stringResource(RdR.string.rd_hesabimi_sil), Icons.Filled.DeleteForever, danger = true, onClick = onDeleteAccount)
        Spacer(Modifier.height(10.dp))
        ProfileStandaloneRow(stringResource(RdR.string.rd_cikis_yap), Icons.AutoMirrored.Filled.Logout, danger = true, onClick = onSignOut)
    }
}

/** Deterministic data fixture for Roborazzi; the rendered body is [ProfileLoadedSurface]. */
@Composable
fun ProfileParityPreviewSurface(
    onAnalyses: () -> Unit = {},
    onReports: () -> Unit = {},
    onShowTitles: () -> Unit = {},
) {
    val colors = RdTheme.colors
    val profile = UserProfile(
        id = "visual-contract",
        email = "uzman@riskdetected.com",
        fullName = "Kerem Kayalar",
        title = "A Sınıfı İş Güvenliği Uzmanı",
        tier = SubscriptionTier.Pro,
        subscriptionPeriod = "yearly",
        subscriptionRenewalAt = "2026-12-10T09:00:00Z",
    )
    val progress = ProfessionalProgressSummary(
        profile = ProfessionalProgressProfileRow(
            userId = profile.id,
            totalMdp = 375,
            totalAnalyses = 12,
            totalReports = 8,
            highFindings = 7,
            criticalFindings = 2,
            activeDays = 6,
        ),
        competencies = listOf(
            ProfessionalProgressCompetencyStat(userId = profile.id, competencyKey = "working_at_height", findingCount = 8, reportCount = 2),
            ProfessionalProgressCompetencyStat(userId = profile.id, competencyKey = "construction", findingCount = 2, reportCount = 1),
        ),
        badges = emptyList(),
        messages = emptyList(),
        weeklySummary = null,
    )
    val stats = ProfileStats(analysisCount = 12, reportCount = 8, weeklyAnalysisCount = 3)
    Box(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        ProfileLoadedSurface(
            profile = profile,
            stats = stats,
            progress = progress,
            onAnalyses = onAnalyses,
            onReports = onReports,
            onShowTitles = onShowTitles,
        )
    }
}

/**
 * Real port of `ProfileView.swift`'s avatar picker (`selectedProfileAvatarItem`/
 * `handleProfileAvatarSelection`) — closes a real gap: `UserProfile.avatarUrl` decoded a real
 * column that nothing ever uploaded to or displayed. Tap the circle to replace it via the system
 * Photo Picker; the real photo (via [ProfileAvatarImage]) layers over the initials fallback,
 * center-cropped to a square client-side (512px/quality 86, same budget as iOS's
 * `centeredSquareJPEG`) before upload.
 */
@Composable
private fun ProfileHero(
    profile: UserProfile,
    stats: ProfileStats? = null,
    progress: ProfessionalProgressSummary? = null,
    isSavingAvatar: Boolean = false,
    avatarErrorMessage: String? = null,
    onAvatarBytes: (ByteArray) -> Unit = {},
    onShowBadges: () -> Unit = {},
    onShowTitles: () -> Unit = {},
    onAnalyses: () -> Unit = {},
    onReports: () -> Unit = {},
) {
    val colors = RdTheme.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val avatarReadError = stringResource(RdR.string.rd_fotograf_okunamadi)
    var localAvatarError by remember { mutableStateOf<String?>(null) }

    val pickAvatar = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        localAvatarError = null
        scope.launch {
            try {
                onAvatarBytes(prepareAvatarJpeg(context, uri))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Throwable) {
                localAvatarError = avatarReadError
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(30.dp))
            .background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(30.dp)),
    ) {
        Column {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(148.dp)
                    .background(
                        Brush.linearGradient(
                            if (colors.paper.luminance() < 0.5f) {
                                listOf(Color(0xFF1A2529), Color(0xFF202C31), Color(0xFF0D1514))
                            } else {
                                listOf(Color(0xFFC8E0EF), Color(0xFFE0EFF7), Color(0xFFAFCFE4))
                            },
                        ),
                    ),
            ) {
                Box(
                    Modifier
                        .size(150.dp)
                        .offset(x = 238.dp, y = (-38).dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = if (colors.paper.luminance() < 0.5f) 0.10f else 0.42f)),
                )
                Box(
                    Modifier
                        .width(196.dp)
                        .height(56.dp)
                        .offset(x = 124.dp, y = 58.dp)
                        .clip(RoundedCornerShape(50))
                        .background(Color.White.copy(alpha = if (colors.paper.luminance() < 0.5f) 0.24f else 0.80f)),
                )
                Box(
                    Modifier
                        .size(92.dp)
                        .offset(x = 92.dp, y = 34.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = if (colors.paper.luminance() < 0.5f) 0.34f else 0.94f)),
                )
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 24.dp, end = 24.dp, top = 48.dp, bottom = 12.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    profile.displayName,
                    style = RdFontStyle.Title2.toTextStyle().copy(fontSize = 21.sp, fontWeight = FontWeight.Bold),
                    color = colors.black,
                    maxLines = 1,
                )
                Text(
                    profile.title?.takeIf { it.isNotBlank() } ?: stringResource(RdR.string.rd_isg_uzmani),
                    style = RdFontStyle.Footnote.toTextStyle().copy(fontSize = 12.5.sp),
                    color = colors.slate,
                    maxLines = 2,
                )
                if (progress != null) {
                    Row(
                        modifier = Modifier
                            .padding(top = 2.dp)
                            .clip(RoundedCornerShape(50))
                            .clickable(onClick = onShowBadges)
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.MilitaryTech, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(stringResource(RdR.string.rd_basarilarim), style = RdFontStyle.Caption.toTextStyle(), color = colors.greenDark)
                    }
                }
            }

            ProfileHeroStats(stats = stats, progress = progress, onAnalyses = onAnalyses, onReports = onReports)
        }

        Box(
            modifier = Modifier
                .padding(start = 28.dp, top = 96.dp)
                .size(96.dp)
                .clickable(enabled = !isSavingAvatar) {
                    pickAvatar.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                },
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .shadow(12.dp, CircleShape)
                    .clip(CircleShape)
                    .background(colors.cta)
                    .border(5.dp, colors.white, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(profile.displayInitials, style = RdFontStyle.Title1.toTextStyle(), color = Color.White)
                profile.avatarUrl?.let { path ->
                    ProfileAvatarImage(path = path, modifier = Modifier.fillMaxSize().clip(CircleShape))
                }
                if (isSavingAvatar) {
                    Box(modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White, modifier = Modifier.size(20.dp))
                    }
                }
            }
            Box(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .size(27.dp)
                    .offset(x = 3.dp, y = 3.dp)
                    .clip(CircleShape)
                    .background(colors.cta)
                    .border(3.dp, colors.white, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.CameraAlt, contentDescription = null, tint = Color.White, modifier = Modifier.size(12.dp))
            }
        }

        if (profile.tier != SubscriptionTier.Free) {
            val tierColor = if (profile.tier == SubscriptionTier.Plus) colors.planPlus else colors.green
            Box(
                modifier = Modifier
                    .padding(start = 100.dp, top = 91.dp)
                    .size(28.dp)
                    .clip(CircleShape)
                    .background(tierColor)
                    .border(3.dp, colors.white, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Star, contentDescription = null, tint = Color.White, modifier = Modifier.size(12.dp))
            }
        }

        if (progress != null) {
            Row(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(end = 16.dp, top = 172.dp)
                    .widthIn(max = 155.dp)
                    .clip(RoundedCornerShape(50))
                    .background(colors.white.copy(alpha = 0.94f))
                    .border(1.dp, colors.greenDark.copy(alpha = 0.22f), RoundedCornerShape(50))
                    .clickable(onClick = onShowTitles)
                    .padding(start = 6.dp, end = 9.dp, top = 5.dp, bottom = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(21.dp).clip(CircleShape).background(colors.greenDark), contentAlignment = Alignment.Center) {
                    Icon(Icons.Filled.MilitaryTech, contentDescription = null, tint = Color.White, modifier = Modifier.size(11.dp))
                }
                Spacer(Modifier.width(6.dp))
                Text(
                    professionalProgressTitleLabel(progress.currentTitle.key),
                    style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 11.sp, fontWeight = FontWeight.Bold),
                    color = colors.black,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        (avatarErrorMessage ?: localAvatarError)?.let { error ->
            Text(
                error,
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.critical,
                modifier = Modifier.align(Alignment.TopEnd).padding(12.dp),
            )
        }
    }
}

private suspend fun prepareAvatarJpeg(context: android.content.Context, uri: Uri): ByteArray =
    withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            ?: error("avatar_stream_unavailable")
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) error("avatar_decode_failed")

        var sampleSize = 1
        while (bounds.outWidth / sampleSize > 1_024 || bounds.outHeight / sampleSize > 1_024) {
            sampleSize *= 2
        }
        val decoded = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sampleSize })
        } ?: error("avatar_decode_failed")

        val side = 512
        var scaled: Bitmap? = null
        var cropped: Bitmap? = null
        try {
            val scale = maxOf(side.toFloat() / decoded.width, side.toFloat() / decoded.height)
            scaled = Bitmap.createScaledBitmap(
                decoded,
                (decoded.width * scale).toInt(),
                (decoded.height * scale).toInt(),
                true,
            )
            cropped = Bitmap.createBitmap(
                scaled,
                maxOf(0, (scaled.width - side) / 2),
                maxOf(0, (scaled.height - side) / 2),
                side,
                side,
            )
            ByteArrayOutputStream().use { output ->
                check(cropped.compress(Bitmap.CompressFormat.JPEG, 86, output))
                output.toByteArray()
            }
        } finally {
            if (cropped !== scaled && cropped !== decoded) cropped?.recycle()
            if (scaled !== decoded) scaled?.recycle()
            decoded.recycle()
        }
    }

@Composable
private fun ProfileHeroStats(
    stats: ProfileStats?,
    progress: ProfessionalProgressSummary?,
    onAnalyses: () -> Unit,
    onReports: () -> Unit,
) {
    val colors = RdTheme.colors
    val items = listOf(
        Triple(stats?.analysisCount?.toString() ?: "—", stringResource(RdR.string.rd_analiz), Icons.Filled.Assessment),
        Triple(stats?.reportCount?.toString() ?: "—", stringResource(RdR.string.rd_rapor), Icons.Filled.Description),
        Triple(progress?.weeklyTracking?.reportsCount?.toString() ?: stats?.weeklyAnalysisCount?.toString() ?: "—", stringResource(RdR.string.rd_bu_hafta), Icons.Filled.CalendarMonth),
        Triple(progress?.profile?.let { (it.highFindings + it.criticalFindings).toString() } ?: "—", stringResource(RdR.string.rd_yuksek_kritik), Icons.Filled.WorkspacePremium),
    )
    BoxWithConstraints {
        val compact = maxWidth < 340.dp || LocalDensity.current.fontScale > 1.15f
        val cellHeight = if (compact) 76.dp else 54.dp
        Row(modifier = Modifier.fillMaxWidth().border(0.5.dp, colors.line)) {
            items.forEachIndexed { index, item ->
                if (index > 0) Box(Modifier.width(1.dp).height(cellHeight).background(colors.line))
                val accent = when (index) { 0 -> colors.info; 1 -> colors.green; 2 -> colors.planPlus; else -> colors.critical }
                val action = when (index) { 0 -> onAnalyses; 1 -> onReports; else -> null }
                if (compact) {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .height(cellHeight)
                            .clickable(enabled = action != null) { action?.invoke() }
                            .padding(horizontal = 3.dp, vertical = 5.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(22.dp).clip(RoundedCornerShape(7.dp)).background(accent.copy(alpha = 0.10f)), contentAlignment = Alignment.Center) {
                                Icon(item.third, contentDescription = null, tint = accent, modifier = Modifier.size(13.dp))
                            }
                            Spacer(Modifier.width(4.dp))
                            Text(item.first, style = RdFontStyle.Data.toTextStyle().copy(fontSize = 14.sp, fontWeight = FontWeight.Bold), color = colors.black, maxLines = 1)
                        }
                        Text(item.second, style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 8.sp), color = colors.slate, maxLines = 2, textAlign = TextAlign.Center, overflow = TextOverflow.Ellipsis)
                    }
                } else {
                    Row(
                        modifier = Modifier
                            .weight(1f)
                            .height(cellHeight)
                            .clickable(enabled = action != null) { action?.invoke() }
                            .padding(horizontal = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        Box(Modifier.size(22.dp).clip(RoundedCornerShape(7.dp)).background(accent.copy(alpha = 0.10f)), contentAlignment = Alignment.Center) {
                            Icon(item.third, contentDescription = null, tint = accent, modifier = Modifier.size(13.dp))
                        }
                        Spacer(Modifier.width(5.dp))
                        Column {
                            Text(item.first, style = RdFontStyle.Data.toTextStyle().copy(fontSize = 15.sp, fontWeight = FontWeight.Bold), color = colors.black, maxLines = 1)
                            Text(item.second, style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 8.5.sp), color = colors.slate, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Real port of `ProfessionalProgressProfileSection.swift`'s scope (title/MDP core loop text +
 * `competencyPreview` card). The first card is the `.showcase` title/MDP ladder from iOS and
 * opens the same title-details sheet when any part of it is tapped. The competency preview is
 * the real donut-chart port ([ProfessionalProgressCompetencyMapView], compact),
 * not a text summary — "Tümü" opens the full scored-row sheet, matching `showCompetencies`.
 */
@Composable
private fun ProfessionalProgressSection(
    progress: ProfessionalProgressSummary,
    onShowTitles: () -> Unit,
    onShowCompetencies: () -> Unit,
) {
    val colors = RdTheme.colors
    val isDark = RdTheme.isDark
    Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .shadow(5.dp, RoundedCornerShape(RdRadius.lg))
                .clip(RoundedCornerShape(RdRadius.lg))
                .background(colors.white)
                .border(1.6.dp, colors.black, RoundedCornerShape(RdRadius.lg))
                .clickable(onClick = onShowTitles)
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(
                modifier = Modifier
                    .width(105.dp)
                    .height(144.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .background(Brush.linearGradient(listOf(colors.fog.copy(alpha = .70f), colors.white)))
                    .border(1.dp, colors.black.copy(alpha = .14f), RoundedCornerShape(24.dp))
                    .padding(horizontal = 8.dp, vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Box(
                    Modifier.size(68.dp).clip(CircleShape)
                        .background(Brush.radialGradient(listOf(colors.planPlus.copy(.26f), Color(0xFFFF8A3D).copy(.12f), Color.Transparent))),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.LocalFireDepartment,
                        contentDescription = null,
                        tint = colors.planPlus,
                        modifier = Modifier.size(39.dp),
                    )
                }
                Spacer(Modifier.height(7.dp))
                Text(
                    professionalProgressTitleLabel(progress.currentTitle.key),
                    style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.Bold),
                    color = colors.black,
                    maxLines = 2,
                    textAlign = TextAlign.Center,
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(
                        progress.profile.totalMdp.toString(),
                        style = RdFontStyle.Title1.toTextStyle().copy(fontSize = 25.sp),
                        color = colors.black,
                    )
                    val threshold = progress.nextTitle?.threshold ?: progress.currentTitle.threshold
                    Text(" / $threshold", style = RdFontStyle.Subheadline.toTextStyle(), color = colors.slate)
                }
                Text(
                    progress.nextTitle?.let {
                        stringResource(
                            RdR.string.rd_professional_progress_target_format,
                            professionalProgressTitleLabel(it.key),
                            progress.nextTitleRemaining,
                        )
                    } ?: stringResource(RdR.string.rd_en_yuksek_unvan),
                    style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 10.sp, fontWeight = FontWeight.SemiBold),
                    color = colors.slate,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Box(Modifier.fillMaxWidth().height(15.dp).clip(RoundedCornerShape(50)).background(colors.black.copy(alpha = 0.10f))) {
                    Box(
                        Modifier
                            .fillMaxWidth(progress.titleProgress.toFloat().coerceIn(0f, 1f))
                            .height(15.dp)
                            .clip(RoundedCornerShape(50))
                            .background(
                                // The bar filled itself with a fixed near-black gradient, which
                                // vanished against the dark surface. Dark mode gets the brand
                                // green the rest of its accents use.
                                Brush.horizontalGradient(
                                    if (RdTheme.isDark) {
                                        listOf(colors.greenDark, colors.green, colors.greenDark)
                                    } else {
                                        listOf(Color(0xFF050607), Color(0xFF202426), Color(0xFF050607))
                                    },
                                ),
                            ),
                    )
                }
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(colors.fog.copy(.76f))
                        .padding(horizontal = 8.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    val currentIndex = ProfessionalProgressTitle.entries.indexOf(progress.currentTitle)
                    ProfessionalProgressTitle.entries.forEachIndexed { index, title ->
                        val reached = index <= currentIndex
                        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                            Box(
                                Modifier.size(23.dp).clip(CircleShape)
                                    .background(if (reached) colors.planPlus else colors.fog),
                                contentAlignment = Alignment.Center,
                            ) {
                                if (reached) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(11.dp))
                                else Text((index + 1).toString(), style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 9.sp), color = colors.slate)
                            }
                            Spacer(Modifier.height(3.dp))
                            Text(
                                professionalProgressStageLabel(title),
                                style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 7.5.sp, fontWeight = FontWeight.SemiBold),
                                color = if (reached) colors.black.copy(.78f) else colors.slate.copy(.74f),
                                maxLines = 1,
                            )
                        }
                    }
                }
            }
        }

        val weekly = progress.weeklyTracking
        val weeklyAccent = if (weekly.hasActivity) colors.green else colors.info
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .shadow(4.dp, RoundedCornerShape(RdRadius.lg))
                .clip(RoundedCornerShape(RdRadius.lg))
                .background(
                    Brush.linearGradient(
                        when {
                            isDark && weekly.hasActivity -> listOf(Color(0xFF102619), Color(0xFF151A17), Color(0xFF2A2514))
                            isDark -> listOf(Color(0xFF111A24), Color(0xFF14181C), Color(0xFF1D1825))
                            weekly.hasActivity -> listOf(colors.greenSoft, colors.greenSoft)
                            else -> listOf(Color(0xFFEEF6FF), Color(0xFFEEF6FF))
                        },
                    ),
                )
                .border(1.dp, weeklyAccent.copy(alpha = 0.18f), RoundedCornerShape(RdRadius.lg))
                .padding(horizontal = 14.dp, vertical = 13.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(40.dp).clip(RoundedCornerShape(14.dp)).background(weeklyAccent.copy(alpha = 0.13f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (weekly.hasActivity) Icons.Filled.CheckCircle else Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = weeklyAccent,
                    modifier = Modifier.size(22.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Text(
                weekly.body,
                style = RdFontStyle.Callout.toTextStyle().copy(fontWeight = FontWeight.SemiBold),
                color = colors.black,
                modifier = Modifier.weight(1f),
                maxLines = 3,
            )
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .shadow(5.dp, RoundedCornerShape(RdRadius.lg))
                .clip(RoundedCornerShape(RdRadius.lg))
                .background(colors.white)
                .border(1.dp, colors.line, RoundedCornerShape(RdRadius.lg))
                .padding(14.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(RdR.string.rd_yetkinlik_haritasi),
                style = RdFontStyle.Subheadline.toTextStyle().copy(fontWeight = FontWeight.Bold),
                color = colors.black,
                modifier = Modifier.weight(1f),
            )
            Text(
                stringResource(RdR.string.rd_tumu),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.greenDark,
                modifier = Modifier.clickable(onClick = onShowCompetencies),
            )
            }
            Spacer(Modifier.height(RdSpacing.sm))
            if (progress.topCompetencies.isEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier.size(36.dp).clip(RoundedCornerShape(RdRadius.sm)).background(colors.fog),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.AutoMirrored.Filled.ShowChart, contentDescription = null, tint = colors.slate, modifier = Modifier.size(16.dp))
                    }
                    Spacer(Modifier.width(10.dp))
                    Text(stringResource(RdR.string.rd_yetkinlik_bos_aciklama), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
                }
            } else {
                ProfessionalProgressCompetencyMapView(competencies = progress.competencies, compact = true)
            }
        }
    }
}

@Composable
private fun professionalProgressStageLabel(title: ProfessionalProgressTitle): String = stringResource(
    when (title) {
        ProfessionalProgressTitle.Candidate -> RdR.string.rd_progress_stage_candidate
        ProfessionalProgressTitle.FieldObserver -> RdR.string.rd_progress_stage_field
        ProfessionalProgressTitle.RiskHunter -> RdR.string.rd_progress_stage_risk
        ProfessionalProgressTitle.HazardAnalyst -> RdR.string.rd_progress_stage_analysis
        ProfessionalProgressTitle.SeniorRiskSpecialist -> RdR.string.rd_progress_stage_senior
        ProfessionalProgressTitle.SafetyStrategist -> RdR.string.rd_progress_stage_strategy
        ProfessionalProgressTitle.MasterHSESpecialist -> RdR.string.rd_progress_stage_master
    },
)

@Composable
private fun SubscriptionStatusCard(profile: UserProfile, onPaywall: () -> Unit) {
    val colors = RdTheme.colors
    val locale = LocalConfiguration.current.locales[0]
    val paid = profile.tier.isPaid
    val accent = when (profile.tier) {
        SubscriptionTier.Plus -> colors.planPlus
        SubscriptionTier.Pro -> colors.green
        SubscriptionTier.Free -> colors.black
    }
    val soft = when (profile.tier) {
        SubscriptionTier.Plus -> colors.planPlusSoft
        SubscriptionTier.Pro -> colors.greenSoft
        SubscriptionTier.Free -> colors.fog
    }
    val tierLabel = when (profile.tier) {
        SubscriptionTier.Free -> stringResource(RdR.string.rd_ucretsiz)
        SubscriptionTier.Plus -> stringResource(RdR.string.rd_plus)
        SubscriptionTier.Pro -> stringResource(RdR.string.rd_pro)
    }
    val periodLabel = when (val period = subscriptionPeriodValue(profile.subscriptionPeriod)) {
        SubscriptionPeriodValue.Monthly -> stringResource(RdR.string.rd_aylik_plan)
        SubscriptionPeriodValue.Yearly -> stringResource(RdR.string.rd_yillik_plan)
        SubscriptionPeriodValue.Missing -> stringResource(RdR.string.rd_plan_format, tierLabel)
        is SubscriptionPeriodValue.Unknown -> period.value.replaceFirstChar { it.titlecase(locale) }
    }
    val renewalLabel = formatSubscriptionRenewal(profile.subscriptionRenewalAt)
        ?: stringResource(RdR.string.rd_google_play_aboneligi_aktif)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(4.dp, RoundedCornerShape(RdRadius.lg))
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(
                Brush.linearGradient(
                    if (paid) listOf(soft, soft)
                    else listOf(colors.greenSoft, colors.greenSoft),
                ),
            )
            .border(1.2.dp, (if (paid) accent else colors.green).copy(alpha = 0.32f), RoundedCornerShape(RdRadius.lg))
            .clickable(enabled = !paid, onClick = onPaywall)
            .padding(horizontal = 15.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(42.dp).clip(RoundedCornerShape(14.dp)).background((if (paid) accent else colors.green).copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (paid) Icons.Filled.CheckCircle else Icons.Filled.WorkspacePremium,
                contentDescription = null,
                tint = if (paid) accent else colors.greenDark,
                modifier = Modifier.size(23.dp),
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            if (!paid) {
                Text(
                    tierLabel.uppercase(locale),
                    style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 9.sp, fontWeight = FontWeight.Bold),
                    color = colors.greenDark,
                )
            }
            Text(
                if (paid) stringResource(RdR.string.rd_plan_aktif_format, tierLabel)
                else stringResource(RdR.string.rd_planini_yukselt),
                style = RdFontStyle.Footnote.toTextStyle().copy(fontWeight = FontWeight.Bold),
                color = colors.black,
            )
            Text(
                if (paid) stringResource(RdR.string.rd_abonelik_detay_format, periodLabel, renewalLabel)
                else stringResource(RdR.string.rd_daha_fazla_analiz_rapor),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
            )
        }
        Icon(
            if (paid) Icons.Filled.CheckCircle else Icons.AutoMirrored.Filled.ArrowForward,
            contentDescription = null,
            tint = if (profile.tier == SubscriptionTier.Free) colors.greenDark else accent,
            modifier = Modifier.size(20.dp),
        )
    }
}

internal sealed interface SubscriptionPeriodValue {
    data object Monthly : SubscriptionPeriodValue
    data object Yearly : SubscriptionPeriodValue
    data object Missing : SubscriptionPeriodValue
    data class Unknown(val value: String) : SubscriptionPeriodValue
}

internal fun subscriptionPeriodValue(raw: String?): SubscriptionPeriodValue {
    val clean = raw?.trim().orEmpty()
    return when (clean.lowercase(Locale.ROOT)) {
        "monthly" -> SubscriptionPeriodValue.Monthly
        "yearly" -> SubscriptionPeriodValue.Yearly
        "" -> SubscriptionPeriodValue.Missing
        else -> SubscriptionPeriodValue.Unknown(clean)
    }
}

internal fun formatSubscriptionRenewal(
    raw: String?,
    locale: Locale = Locale.getDefault(),
): String? {
    val value = raw?.trim().takeUnless { it.isNullOrEmpty() } ?: return null
    val instant = runCatching { Instant.parse(value) }.getOrElse {
        runCatching { OffsetDateTime.parse(value).toInstant() }.getOrNull() ?: return null
    }
    return DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG)
        .withLocale(locale)
        .withZone(ZoneId.of("Europe/Istanbul"))
        .format(instant)
}

@Composable
private fun ProfileMenuSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    val colors = RdTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            title,
            style = RdFontStyle.Caption.toTextStyle().copy(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp),
            color = colors.slate,
            modifier = Modifier.padding(start = 4.dp),
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .shadow(4.dp, RoundedCornerShape(RdRadius.lg))
                .clip(RoundedCornerShape(RdRadius.lg))
                .background(colors.white)
                .border(1.dp, colors.line, RoundedCornerShape(RdRadius.lg)),
            content = content,
        )
    }
}

@Composable
private fun ProfileMenuRow(
    title: String,
    icon: ImageVector,
    danger: Boolean = false,
    detail: String? = null,
    onClick: () -> Unit,
) {
    val colors = RdTheme.colors
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val accent = if (danger) colors.criticalText else colors.charcoal
        Box(Modifier.size(32.dp).clip(RoundedCornerShape(8.dp)).background(if (danger) colors.criticalBg else colors.fog), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(16.dp))
        }
        Spacer(Modifier.width(12.dp))
        Text(title, style = RdFontStyle.Subheadline.toTextStyle().copy(fontWeight = FontWeight.Medium), color = if (danger) colors.criticalText else colors.black, modifier = Modifier.weight(1f))
        detail?.let {
            Text(it, style = RdFontStyle.Data.toTextStyle(), color = colors.slate)
            Spacer(Modifier.width(8.dp))
        }
        Text("›", style = RdFontStyle.Title3.toTextStyle(), color = colors.slate)
    }
}

@Composable
private fun ProfileMenuDivider() {
    HorizontalDivider(modifier = Modifier.padding(start = 60.dp), thickness = 1.dp, color = RdTheme.colors.line)
}

@Composable
private fun ProfileStandaloneRow(title: String, icon: ImageVector, danger: Boolean, onClick: () -> Unit) {
    val colors = RdTheme.colors
    Box(
        Modifier
            .fillMaxWidth()
            .shadow(4.dp, RoundedCornerShape(RdRadius.lg))
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.white)
            .border(1.dp, colors.line, RoundedCornerShape(RdRadius.lg)),
    ) {
        ProfileMenuRow(title = title, icon = icon, danger = danger, onClick = onClick)
    }
}

@Composable
private fun ProfileEditForm(profile: UserProfile, viewModel: ProfileViewModel, onDone: () -> Unit) {
    val colors = RdTheme.colors
    var fullName by remember { mutableStateOf(profile.fullName ?: "") }
    var title by remember { mutableStateOf(profile.title ?: "") }
    var certificateNumber by remember { mutableStateOf(profile.certificateNumber ?: "") }
    var companyName by remember { mutableStateOf(profile.companyName ?: "") }
    var phone by remember { mutableStateOf(profile.phone ?: "") }
    var logoBytes by remember { mutableStateOf<ByteArray?>(null) }
    var preferredMethod by remember {
        mutableStateOf(
            RiskMethodWire.entries.firstOrNull { it.wireValue == profile.preferredMethod }
                ?: RiskMethodWire.FineKinney,
        )
    }

    val context = LocalContext.current
    val pickLogo = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        context.contentResolver.openInputStream(uri)?.use { stream ->
            val bitmap = BitmapFactory.decodeStream(stream)
            if (bitmap != null) {
                val output = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, output)
                logoBytes = output.toByteArray()
            }
        }
    }

    val isSaving by viewModel.isSaving.collectAsState()
    val saveError by viewModel.saveError.collectAsState()
    var wasSaving by remember { mutableStateOf(false) }

    // Returns to the read-only view once a save finishes without error — mirrors
    // ProfileView.swift's `save()` calling `onSaved()` (which dismisses the edit sheet) only
    // on the non-throwing path, never on a caught error.
    LaunchedEffect(isSaving) {
        if (wasSaving && !isSaving && saveError == null) onDone()
        wasSaving = isSaving
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = RdSpacing.lg)
            .padding(bottom = 120.dp),
    ) {
        RdScreenHeader(title = stringResource(RdR.string.rd_profil_bilgileri), onBack = onDone)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(24.dp))
                .background(Brush.linearGradient(listOf(colors.greenSoft, colors.white)))
                .border(1.dp, colors.green.copy(alpha = 0.20f), RoundedCornerShape(24.dp))
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(46.dp).clip(RoundedCornerShape(15.dp)).background(colors.green.copy(alpha = 0.13f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Person, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(24.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    stringResource(RdR.string.rd_profilini_guncelle),
                    style = RdFontStyle.Title3.toTextStyle().copy(fontWeight = FontWeight.Bold),
                    color = colors.black,
                )
                Text(
                    stringResource(RdR.string.rd_profil_rapor_aciklama),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                )
            }
        }

        Spacer(Modifier.height(RdSpacing.md))
        RdSectionCard {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    stringResource(RdR.string.rd_profil_ve_sirket_upper),
                    style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.Bold),
                    color = colors.greenDark,
                )
                ProfileEditField(fullName, { fullName = it }, stringResource(RdR.string.rd_ad_soyad), Icons.Filled.Person)
                ProfileEditField(title, { title = it }, stringResource(RdR.string.rd_unvan), Icons.Filled.Badge)
                ProfileEditField(certificateNumber, { certificateNumber = it }, stringResource(RdR.string.rd_sertifika_no), Icons.Filled.Numbers)
                ProfileEditField(companyName, { companyName = it }, stringResource(RdR.string.rd_firma), Icons.Filled.Business)
                ProfileEditField(phone, { phone = it }, stringResource(RdR.string.rd_telefon), Icons.Filled.Phone)
            }
        }

        Spacer(Modifier.height(RdSpacing.md))
        RdSectionCard {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    stringResource(RdR.string.rd_risk_yontemi_upper),
                    style = RdFontStyle.Caption.toTextStyle().copy(fontWeight = FontWeight.Bold),
                    color = colors.greenDark,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(RdSpacing.xs)) {
                    RiskMethodWire.entries.forEach { method ->
                        val isSelected = preferredMethod == method
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(14.dp))
                                .background(if (isSelected) colors.cta else colors.fog)
                                .border(1.dp, if (isSelected) colors.cta else colors.line, RoundedCornerShape(14.dp))
                                .clickable { preferredMethod = method }
                                .padding(horizontal = 10.dp, vertical = 12.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                if (method == RiskMethodWire.FineKinney) stringResource(RdR.string.rd_fine_kinney)
                                else stringResource(RdR.string.rd_bes_carp_bes_matris),
                                style = RdFontStyle.Footnote.toTextStyle().copy(fontWeight = FontWeight.SemiBold),
                                color = if (isSelected) Color.White else colors.black,
                            )
                        }
                    }
                }
            }
        }

        Spacer(Modifier.height(RdSpacing.md))
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(RdRadius.lg))
                .background(colors.white)
                .border(1.dp, colors.line, RoundedCornerShape(RdRadius.lg))
                .clickable { pickLogo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(40.dp).clip(RoundedCornerShape(13.dp)).background(colors.fog), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Image, contentDescription = null, tint = colors.greenDark, modifier = Modifier.size(21.dp))
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    if (logoBytes != null) stringResource(RdR.string.rd_logo_secildi)
                    else stringResource(RdR.string.rd_logo_degistir_opsiyonel),
                    style = RdFontStyle.Footnote.toTextStyle().copy(fontWeight = FontWeight.SemiBold),
                    color = colors.black,
                )
                Text(stringResource(RdR.string.rd_logo_raporlarda_kullanilir), style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
            }
        }

        Spacer(Modifier.height(RdSpacing.sm))
        if (isSaving) {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.black)
            }
        } else {
            RdPrimaryButton(text = stringResource(RdR.string.rd_kaydet), onClick = {
                viewModel.saveProfile(
                    fullName = fullName,
                    title = title,
                    certificateNumber = certificateNumber,
                    companyName = companyName,
                    phone = phone,
                    preferredMethod = preferredMethod,
                    logoJpegBytes = logoBytes,
                )
            }, style = RdButtonStyle.Onyx)
        }
        Spacer(Modifier.height(RdSpacing.xs))
        TextButton(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text(stringResource(RdR.string.rd_vazgec)) }
    }

    saveError?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearSaveError,
            title = { Text(error.title) },
            text = { Text(error.message) },
            confirmButton = {
                TextButton(onClick = viewModel::clearSaveError) { Text(stringResource(RdR.string.rd_tamam)) }
            },
        )
    }
}

@Composable
private fun ProfileEditField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    icon: ImageVector,
) {
    val colors = RdTheme.colors
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        leadingIcon = { Icon(icon, contentDescription = null, tint = colors.slate, modifier = Modifier.size(20.dp)) },
        shape = RoundedCornerShape(16.dp),
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
}
