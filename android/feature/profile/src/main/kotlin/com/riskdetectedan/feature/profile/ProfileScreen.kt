package com.riskdetectedan.feature.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.RadioButton
import com.riskdetectedan.core.data.profile.RiskMethodWire
import com.riskdetectedan.core.data.profile.UserProfile
import com.riskdetectedan.core.data.progress.ProfessionalProgressSummary
import com.riskdetectedan.core.designsystem.RdSpacing
import java.io.ByteArrayOutputStream

/**
 * Reads the actual `profiles` row for the signed-in user via [ProfileViewModel]/
 * `ProfileRepository`, and now also supports editing the basic-field subset ProfileView.swift's
 * `save()` covers (fullName/title/certificateNumber/companyName/phone/preferredMethod — see
 * ProfileRepository's doc comment for what's deliberately left out). Layout still far short of
 * App/Views/Profile/ProfileView.swift's real design (deferred visual-parity pass).
 */
@Composable
fun ProfileScreen(
    onManageCompanies: () -> Unit = {},
    onSupport: () -> Unit = {},
    onNotificationSettings: () -> Unit = {},
    onDeleteAccount: () -> Unit = {},
    onPaywall: () -> Unit = {},
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    var isEditing by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(RdSpacing.lg),
        contentAlignment = Alignment.Center,
    ) {
        when (val current = state) {
            is ProfileUiState.Loading -> CircularProgressIndicator()
            is ProfileUiState.SignedOut -> Text("Oturum yok")
            is ProfileUiState.Failed -> Text("Profil yüklenemedi: ${current.error.message}")
            is ProfileUiState.Loaded -> if (isEditing) {
                ProfileEditForm(
                    profile = current.profile,
                    viewModel = viewModel,
                    onDone = { isEditing = false },
                )
            } else {
                val progress by viewModel.progress.collectAsState()
                Column {
                    Text(current.profile.displayName)
                    Text(current.profile.tier.name)
                    progress?.let { ProfessionalProgressSection(it) }
                    Button(onClick = { isEditing = true }) { Text("Profili düzenle") }
                    Button(onClick = onPaywall) { Text("Planı yükselt") }
                    Button(onClick = onManageCompanies) { Text("Firmalarım") }
                    Button(onClick = onSupport) { Text("Destek") }
                    Button(onClick = onNotificationSettings) { Text("Bildirim ayarları") }
                    Button(onClick = onDeleteAccount) { Text("Hesabı sil") }
                }
            }
        }
    }
}

/**
 * First functional slice of ProfessionalProgress (mirrors `ProfessionalProgressHomeCard.swift`/
 * `ProfileSection.swift` in scope, not layout — plain Text list, same "functional skeleton
 * first" pass every other screen got). Shows the title/MDP core loop (current title, progress
 * toward the next one, top competencies by signal count) and the weekly summary when the server
 * has computed one. Deliberately NOT ported in this slice: badge/message UI (unlock celebration
 * sheet, mark-seen taps — `pendingCelebration` is exposed on the model but nothing reads it
 * yet), the competency map's visual chart, the full titles-ladder catalog sheet. All three are
 * presentation-only additions on top of data that's already correctly fetched — deferred to the
 * visual-design pass, not a functional gap.
 */
@Composable
private fun ProfessionalProgressSection(progress: ProfessionalProgressSummary) {
    Column(modifier = Modifier.padding(vertical = RdSpacing.sm)) {
        Text("${progress.currentTitle.label} · ${progress.profile.totalMdp} MDP")
        progress.nextTitle?.let { next ->
            Text("Sıradaki: ${next.label} (${progress.nextTitleRemaining} MDP kaldı)")
        }
        Text("${progress.profile.totalAnalyses} analiz · ${progress.profile.totalReports} rapor · ${progress.profile.activeDays} aktif gün")
        val topCompetencies = progress.topCompetencies.take(3)
        if (topCompetencies.isNotEmpty()) {
            Text(
                "En güçlü alanlar: " +
                    topCompetencies.joinToString(", ") { stat ->
                        "${stat.competency?.label ?: stat.competencyKey} (${stat.score})"
                    },
            )
        }
        progress.weeklySummary?.let { weekly ->
            Text(
                weekly.messageTitle
                    ?: "Bu hafta: ${weekly.analysesCount} analiz, ${weekly.reportsCount} rapor",
            )
        }
    }
}

@Composable
private fun ProfileEditForm(profile: UserProfile, viewModel: ProfileViewModel, onDone: () -> Unit) {
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

    Column(modifier = Modifier.fillMaxWidth()) {
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

        Text("Risk yöntemi")
        Row {
            RiskMethodWire.entries.forEach { method ->
                Row {
                    RadioButton(
                        selected = preferredMethod == method,
                        onClick = { preferredMethod = method },
                    )
                    Text(
                        if (method == RiskMethodWire.FineKinney) "Fine-Kinney" else "5x5 Matris",
                        modifier = Modifier.padding(end = RdSpacing.sm),
                    )
                }
            }
        }

        TextButton(
            onClick = {
                pickLogo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            },
        ) {
            Text(if (logoBytes != null) "Logo seçildi ✓" else "Logo değiştir (opsiyonel)")
        }

        if (isSaving) {
            CircularProgressIndicator()
        } else {
            Button(
                onClick = {
                    viewModel.saveProfile(
                        fullName = fullName,
                        title = title,
                        certificateNumber = certificateNumber,
                        companyName = companyName,
                        phone = phone,
                        preferredMethod = preferredMethod,
                        logoJpegBytes = logoBytes,
                    )
                },
            ) { Text("Kaydet") }
        }
        TextButton(onClick = onDone) { Text("Vazgeç") }
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
