package com.riskdetectedan.feature.profile

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
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.SupportAgent
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdListRow
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdRadius
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSectionCard
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import java.io.ByteArrayOutputStream

/**
 * Reads the actual `profiles` row for the signed-in user via [ProfileViewModel]/
 * `ProfileRepository` — all logic unchanged (2026-08-08 visual pass, Faz K of the core-flow
 * redesign). Real structure: avatar+name+tier hero card, [RdSectionCard] for professional
 * progress, [RdListRow] menu (Profili düzenle/Planı yükselt/Firmalarım/Destek/Bildirim
 * ayarları), destructive "Hesabı sil" styled with the app's real critical color instead of a
 * plain `Button`.
 */
@Composable
fun ProfileScreen(
    onBack: (() -> Unit)? = null,
    onManageCompanies: () -> Unit = {},
    onSupport: () -> Unit = {},
    onNotificationSettings: () -> Unit = {},
    onDeleteAccount: () -> Unit = {},
    onPaywall: () -> Unit = {},
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    var isEditing by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = "Profil", onBack = onBack)

        when (val current = state) {
            is ProfileUiState.Loading -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
            }
            is ProfileUiState.SignedOut -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Oturum yok", style = RdFontStyle.Callout.toTextStyle(), color = colors.slate)
            }
            is ProfileUiState.Failed -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Profil yüklenemedi: ${current.error.message}", style = RdFontStyle.Callout.toTextStyle(), color = colors.critical)
            }
            is ProfileUiState.Loaded -> if (isEditing) {
                ProfileEditForm(
                    profile = current.profile,
                    viewModel = viewModel,
                    onDone = { isEditing = false },
                )
            } else {
                val progress by viewModel.progress.collectAsState()
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = RdSpacing.lg),
                ) {
                    ProfileHero(profile = current.profile)

                    progress?.let {
                        Spacer(Modifier.height(RdSpacing.md))
                        RdSectionCard(title = "İlerleme") { ProfessionalProgressSection(it) }
                    }

                    Spacer(Modifier.height(RdSpacing.md))
                    Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.xs)) {
                        RdListRow(title = "Profili düzenle", icon = Icons.Filled.Edit, onClick = { isEditing = true })
                        RdListRow(title = "Planı yükselt", icon = Icons.Filled.WorkspacePremium, onClick = onPaywall)
                        RdListRow(title = "Firmalarım", icon = Icons.Filled.Business, onClick = onManageCompanies)
                        RdListRow(title = "Destek", icon = Icons.Filled.SupportAgent, onClick = onSupport)
                        RdListRow(title = "Bildirim ayarları", icon = Icons.Filled.Notifications, onClick = onNotificationSettings)
                        RdListRow(
                            title = "Hesabı sil",
                            icon = Icons.Filled.DeleteForever,
                            iconTint = colors.critical,
                            iconBackground = colors.criticalBg,
                            onClick = onDeleteAccount,
                        )
                    }
                    Spacer(Modifier.height(RdSpacing.lg))
                }
            }
        }
    }
}

@Composable
private fun ProfileHero(profile: UserProfile) {
    val colors = RdTheme.colors
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
            modifier = Modifier.size(64.dp).clip(CircleShape).background(colors.onyx),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                profile.displayName.take(1).uppercase(),
                style = RdFontStyle.Title2.toTextStyle(),
                color = colors.white,
            )
        }
        Spacer(Modifier.height(RdSpacing.xs))
        Text(profile.displayName, style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx, textAlign = TextAlign.Center)
        Spacer(Modifier.height(4.dp))
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                .background(colors.fog)
                .padding(horizontal = RdSpacing.sm, vertical = 4.dp),
        ) {
            Text(profile.tier.name, style = RdFontStyle.Caption.toTextStyle(), color = colors.slate)
        }
    }
}

/**
 * First functional slice of ProfessionalProgress (mirrors `ProfessionalProgressHomeCard.swift`/
 * `ProfileSection.swift` in scope, not layout). Shows the title/MDP core loop (current title,
 * progress toward the next one, top competencies by signal count) and the weekly summary when
 * the server has computed one. Deliberately NOT ported in this slice: badge/message UI (unlock
 * celebration sheet, mark-seen taps), the competency map's visual chart, the full titles-ladder
 * catalog sheet — presentation-only additions on top of data that's already correctly fetched.
 */
@Composable
private fun ProfessionalProgressSection(progress: ProfessionalProgressSummary) {
    val colors = RdTheme.colors
    Column {
        Text(
            "${progress.currentTitle.label} · ${progress.profile.totalMdp} MDP",
            style = RdFontStyle.Callout.toTextStyle(),
            color = colors.onyx,
        )
        progress.nextTitle?.let { next ->
            Text(
                "Sıradaki: ${next.label} (${progress.nextTitleRemaining} MDP kaldı)",
                style = RdFontStyle.Footnote.toTextStyle(),
                color = colors.slate,
            )
        }
        Spacer(Modifier.height(RdSpacing.xxs))
        Text(
            "${progress.profile.totalAnalyses} analiz · ${progress.profile.totalReports} rapor · ${progress.profile.activeDays} aktif gün",
            style = RdFontStyle.Caption.toTextStyle(),
            color = colors.slate,
        )
        val topCompetencies = progress.topCompetencies.take(3)
        if (topCompetencies.isNotEmpty()) {
            Text(
                "En güçlü alanlar: " +
                    topCompetencies.joinToString(", ") { stat ->
                        "${stat.competency?.label ?: stat.competencyKey} (${stat.score})"
                    },
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
                modifier = Modifier.padding(top = RdSpacing.xxs),
            )
        }
        progress.weeklySummary?.let { weekly ->
            Text(
                weekly.messageTitle
                    ?: "Bu hafta: ${weekly.analysesCount} analiz, ${weekly.reportsCount} rapor",
                style = RdFontStyle.Footnote.toTextStyle(),
                color = colors.greenDark,
                modifier = Modifier.padding(top = RdSpacing.xs),
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
                OutlinedTextField(fullName, { fullName = it }, label = { Text("Ad soyad") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(title, { title = it }, label = { Text("Unvan") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    certificateNumber,
                    { certificateNumber = it },
                    label = { Text("Sertifika no") },
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(companyName, { companyName = it }, label = { Text("Firma") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(phone, { phone = it }, label = { Text("Telefon") }, modifier = Modifier.fillMaxWidth())
            }
        }

        Spacer(Modifier.height(RdSpacing.md))
        Text("Risk yöntemi", style = RdFontStyle.Footnote.toTextStyle(), color = colors.slate)
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
                        if (method == RiskMethodWire.FineKinney) "Fine-Kinney" else "5x5 Matris",
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
            Text(if (logoBytes != null) "Logo seçildi ✓" else "Logo değiştir (opsiyonel)")
        }

        Spacer(Modifier.height(RdSpacing.sm))
        if (isSaving) {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = colors.onyx)
            }
        } else {
            RdPrimaryButton(text = "Kaydet", onClick = {
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
        TextButton(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text("Vazgeç") }
        Spacer(Modifier.height(RdSpacing.lg))
    }

    saveError?.let { error ->
        AlertDialog(
            onDismissRequest = viewModel::clearSaveError,
            title = { Text(error.title) },
            text = { Text(error.message) },
            confirmButton = {
                TextButton(onClick = viewModel::clearSaveError) { Text("Tamam") }
            },
        )
    }
}
