package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.ColorLens
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Gavel
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.ShowChart
import androidx.compose.material.icons.filled.SupportAgent
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.filled.Restore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.profile.RiskMethodWire
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.data.legal.LegalDocumentAssets
import com.riskdetectedan.core.data.progress.ProfessionalProgressBadge
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdLegalDocument
import com.riskdetectedan.core.designsystem.RdLegalDocumentSheet
import com.riskdetectedan.core.designsystem.RdListRow
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSectionCard
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import com.riskdetectedan.core.designsystem.professionalProgressTitleLabel
import java.io.ByteArrayOutputStream

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
    onSupport: () -> Unit = {},
    onNotificationSettings: () -> Unit = {},
    onAppearanceSettings: () -> Unit = {},
    onDataManagement: () -> Unit = {},
    onDeleteAccount: () -> Unit = {},
    onPaywall: () -> Unit = {},
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val restoreState by viewModel.restoreState.collectAsState()
    var isEditing by remember { mutableStateOf(false) }
    var showSignOutConfirmation by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = stringResource(RdR.string.rd_profil), onBack = onBack)

        when (val current = state) {
            is ProfileUiState.Loading -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
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
                var showBadges by remember { mutableStateOf(false) }
                var showCompetencies by remember { mutableStateOf(false) }
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

                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = RdSpacing.lg),
                ) {
                    ProfileHero(
                        profile = current.profile,
                        viewModel = viewModel,
                        progress = progress,
                        onShowBadges = { showBadges = true },
                    )

                    progress?.let {
                        Spacer(Modifier.height(RdSpacing.md))
                        RdSectionCard(title = stringResource(RdR.string.rd_ilerleme)) {
                            ProfessionalProgressSection(it, onShowCompetencies = { showCompetencies = true })
                        }
                    }

                    Spacer(Modifier.height(RdSpacing.md))
                    Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.xs)) {
                        RdListRow(title = stringResource(RdR.string.rd_profili_duzenle), icon = Icons.Filled.Edit, onClick = { isEditing = true })
                        RdListRow(title = stringResource(RdR.string.rd_plani_yukselt), icon = Icons.Filled.WorkspacePremium, onClick = onPaywall)
                        RdListRow(
                            title = stringResource(
                                if (restoreState is ProfileRestoreState.Restoring) RdR.string.rd_satin_alimlar_geri_yukleniyor
                                else RdR.string.rd_satin_alimlari_geri_yukle,
                            ),
                            icon = Icons.Filled.Restore,
                            onClick = viewModel::restorePurchases,
                        )
                        RdListRow(title = stringResource(RdR.string.rd_firmalarim), icon = Icons.Filled.Business, onClick = onManageCompanies)
                        RdListRow(title = stringResource(RdR.string.rd_destek), icon = Icons.Filled.SupportAgent, onClick = onSupport)
                        RdListRow(title = stringResource(RdR.string.rd_bildirim_ayarlari), icon = Icons.Filled.Notifications, onClick = onNotificationSettings)
                        RdListRow(title = stringResource(RdR.string.rd_gorunum), icon = Icons.Filled.ColorLens, onClick = onAppearanceSettings)
                        RdListRow(title = stringResource(RdR.string.rd_verilerim), icon = Icons.Filled.Storage, onClick = onDataManagement)
                        RdListRow(title = stringResource(RdR.string.rd_yasal_bilgilendirme), icon = Icons.Filled.Gavel, onClick = { showLegal = true })
                        RdListRow(title = stringResource(RdR.string.rd_cikis_yap), icon = Icons.Filled.Logout, onClick = { showSignOutConfirmation = true })
                        RdListRow(
                            title = stringResource(RdR.string.rd_hesabimi_sil),
                            icon = Icons.Filled.DeleteForever,
                            iconTint = colors.critical,
                            iconBackground = colors.criticalBg,
                            onClick = onDeleteAccount,
                        )
                    }
                    Spacer(Modifier.height(RdSpacing.lg))
                }

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
                    val sheetState = rememberModalBottomSheetState()
                    ModalBottomSheet(
                        onDismissRequest = { pendingCelebrationBadge = null },
                        sheetState = sheetState,
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
    viewModel: ProfileViewModel,
    progress: ProfessionalProgressSummary? = null,
    onShowBadges: () -> Unit = {},
) {
    val colors = RdTheme.colors
    val context = LocalContext.current
    val isSavingAvatar by viewModel.isSavingAvatar.collectAsState()
    val avatarError by viewModel.avatarError.collectAsState()

    val pickAvatar = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        context.contentResolver.openInputStream(uri)?.use { stream ->
            val bitmap = BitmapFactory.decodeStream(stream) ?: return@use
            val side = 512
            val scale = maxOf(side.toFloat() / bitmap.width, side.toFloat() / bitmap.height)
            val scaled = Bitmap.createScaledBitmap(
                bitmap,
                (bitmap.width * scale).toInt(),
                (bitmap.height * scale).toInt(),
                true,
            )
            val cropped = Bitmap.createBitmap(
                scaled,
                maxOf(0, (scaled.width - side) / 2),
                maxOf(0, (scaled.height - side) / 2),
                side,
                side,
            )
            val output = ByteArrayOutputStream()
            cropped.compress(Bitmap.CompressFormat.JPEG, 86, output)
            viewModel.updateAvatar(output.toByteArray())
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = RdSpacing.md)
            .clip(RoundedCornerShape(RdRadius.lg))
            .background(colors.white)
            .border(1.dp, colors.onyx.copy(alpha = 0.06f), RoundedCornerShape(RdRadius.lg))
            .padding(RdSpacing.md),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(64.dp)
                .clip(CircleShape)
                .background(colors.onyx)
                .clickable {
                    pickAvatar.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                profile.displayName.take(1).uppercase(),
                style = RdFontStyle.Title2.toTextStyle(),
                color = colors.white,
            )
            ProfileAvatarImage(path = profile.avatarUrl, modifier = Modifier.clip(CircleShape))
            if (isSavingAvatar) {
                Box(modifier = Modifier.fillMaxSize().background(colors.onyx.copy(alpha = 0.5f)), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.white, modifier = Modifier.size(20.dp))
                }
            }
        }
        avatarError?.let { error ->
            Text(
                error.message,
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.critical,
                modifier = Modifier.padding(top = RdSpacing.xxs),
            )
        }
        Spacer(Modifier.height(RdSpacing.xs))
        Text(profile.displayName, style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx, textAlign = TextAlign.Center)
        profile.email?.let {
            Text(it, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate, textAlign = TextAlign.Center)
        }
        Spacer(Modifier.height(4.dp))
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                .background(colors.fog)
                .padding(horizontal = RdSpacing.sm, vertical = 4.dp),
        ) {
            Text(profile.tier.name, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
        }
        profile.subscriptionRenewalAt?.takeIf(String::isNotBlank)?.let { renewal ->
            Text(
                stringResource(RdR.string.rd_uyelik_donemi_format, renewal.take(10)),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
        // Real port of ProfileView.swift's "Başarılarım" rosette button under the display name
        // (`showProfileBadges(professionalProgressSummary)`) — the only real trigger for the
        // badges catalog sheet on either platform (`ProfessionalProgressProfileSection`'s own
        // `showBadges` state is unused dead code on iOS itself, confirmed via source grep).
        if (progress != null) {
            Row(
                modifier = Modifier
                    .padding(top = RdSpacing.xxs)
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
}

/**
 * Real port of `ProfessionalProgressProfileSection.swift`'s scope (title/MDP core loop text +
 * `competencyPreview` card), minus the `.showcase`-style [ProfessionalProgressHomeCard] (Home's
 * own `.compactStrip` card already carries the real MDP/title-ladder UI — see
 * `app/home/ProfessionalProgressCard.kt` — Profile keeps this plain text line instead of
 * duplicating that whole card, the one deliberate layout simplification here). The competency
 * preview itself is the real donut-chart port ([ProfessionalProgressCompetencyMapView], compact),
 * not a text summary — "Tümü" opens the full scored-row sheet, matching `showCompetencies`.
 */
@Composable
private fun ProfessionalProgressSection(progress: ProfessionalProgressSummary, onShowCompetencies: () -> Unit) {
    val colors = RdTheme.colors
    Column {
        Text(
            stringResource(
                RdR.string.rd_unvan_mdp_format,
                professionalProgressTitleLabel(progress.currentTitle.key),
                progress.profile.totalMdp,
            ),
            style = RdFontStyle.Callout.toTextStyle(),
            color = colors.onyx,
        )
        progress.nextTitle?.let { next ->
            Text(
                stringResource(
                    RdR.string.rd_siradaki_mdp_format,
                    professionalProgressTitleLabel(next.key),
                    progress.nextTitleRemaining,
                ),
                style = RdFontStyle.Footnote.toTextStyle(),
                color = colors.slate,
            )
        }
        Spacer(Modifier.height(RdSpacing.xxs))
        Text(
            stringResource(
                RdR.string.rd_ilerleme_istatistik_format,
                progress.profile.totalAnalyses,
                progress.profile.totalReports,
                progress.profile.activeDays,
            ),
            style = RdFontStyle.Caption.toTextStyle(),
            color = colors.slate,
        )

        Spacer(Modifier.height(RdSpacing.sm))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(RdR.string.rd_yetkinlik_haritasi),
                style = RdFontStyle.Callout.toTextStyle(),
                color = colors.onyx,
                modifier = Modifier.weight(1f),
            )
            Text(
                stringResource(RdR.string.rd_tumu),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.greenDark,
                modifier = Modifier.clickable(onClick = onShowCompetencies),
            )
        }
        Spacer(Modifier.height(RdSpacing.xxs))
        if (progress.topCompetencies.isEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier.size(36.dp).clip(RoundedCornerShape(RdRadius.sm)).background(colors.fog),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.ShowChart, contentDescription = null, tint = colors.slate, modifier = Modifier.size(16.dp))
                }
                Spacer(Modifier.width(10.dp))
                Text(
                    stringResource(RdR.string.rd_yetkinlik_bos_aciklama),
                    style = RdFontStyle.Caption.toTextStyle(),
                    color = colors.slate,
                )
            }
        } else {
            ProfessionalProgressCompetencyMapView(competencies = progress.competencies, compact = true)
        }

        progress.weeklySummary?.let { weekly ->
            Text(
                weekly.messageTitle
                    ?: stringResource(RdR.string.rd_bu_hafta_istatistik_format, weekly.analysesCount, weekly.reportsCount),
                style = RdFontStyle.Footnote.toTextStyle(),
                color = colors.greenDark,
                modifier = Modifier.padding(top = RdSpacing.sm),
            )
        }
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
            .padding(horizontal = RdSpacing.lg),
    ) {
        Spacer(Modifier.height(RdSpacing.sm))
        RdSectionCard {
            Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                OutlinedTextField(fullName, { fullName = it }, label = { Text(stringResource(RdR.string.rd_ad_soyad)) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(title, { title = it }, label = { Text(stringResource(RdR.string.rd_unvan)) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    certificateNumber,
                    { certificateNumber = it },
                    label = { Text(stringResource(RdR.string.rd_sertifika_no)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(companyName, { companyName = it }, label = { Text(stringResource(RdR.string.rd_firma)) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(phone, { phone = it }, label = { Text(stringResource(RdR.string.rd_telefon)) }, modifier = Modifier.fillMaxWidth())
            }
        }

        Spacer(Modifier.height(RdSpacing.md))
        Text(stringResource(RdR.string.rd_risk_yontemi), style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
        Spacer(Modifier.height(RdSpacing.xs))
        Row(horizontalArrangement = Arrangement.spacedBy(RdSpacing.xs)) {
            RiskMethodWire.entries.forEach { method ->
                val isSelected = preferredMethod == method
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(RdRadius.xs))
                        .background(if (isSelected) colors.onyx else colors.fog)
                        .clickable { preferredMethod = method }
                        .padding(horizontal = RdSpacing.sm, vertical = RdSpacing.xs),
                ) {
                    Text(
                        if (method == RiskMethodWire.FineKinney) {
                            stringResource(RdR.string.rd_fine_kinney)
                        } else {
                            stringResource(RdR.string.rd_bes_carp_bes_matris)
                        },
                        style = RdFontStyle.Footnote.toTextStyle(),
                        color = if (isSelected) colors.white else colors.onyx,
                    )
                }
            }
        }

        Spacer(Modifier.height(RdSpacing.md))
        TextButton(
            onClick = {
                pickLogo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            },
        ) {
            Text(
                if (logoBytes != null) {
                    stringResource(RdR.string.rd_logo_secildi)
                } else {
                    stringResource(RdR.string.rd_logo_degistir_opsiyonel)
                },
            )
        }

        Spacer(Modifier.height(RdSpacing.sm))
        if (isSaving) {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
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
        Spacer(Modifier.height(RdSpacing.lg))
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
