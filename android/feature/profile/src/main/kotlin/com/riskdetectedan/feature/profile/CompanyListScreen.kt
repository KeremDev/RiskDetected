package com.riskdetectedan.feature.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Business
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.company.CompanyDraft
import com.riskdetectedan.core.designsystem.RdButtonStyle
import com.riskdetectedan.core.designsystem.RdEmptyState
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdListRow
import com.riskdetectedan.core.designsystem.RdPrimaryButton
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSectionCard
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import java.io.ByteArrayOutputStream

/** Port of the company list + add form from App/Services/CompanyService.swift's contract
 * (2026-08-08 visual pass, Faz K of the core-flow redesign; no dedicated iOS view file was read
 * for layout — CompanyPickerSheet.swift exists but this is the management surface, not the
 * analysis-time picker; kept minimal/functional). Logo picking uses the system Photo Picker
 * (`PickVisualMedia`, no storage permission needed) — the picked image is decoded and re-encoded
 * as JPEG client-side since a gallery pick can be any format, unlike CaptureScreen's CameraX
 * output which is already JPEG. Repository/ViewModel logic unchanged.
 */
@Composable
fun CompanyListScreen(onBack: (() -> Unit)? = null, viewModel: CompanyViewModel = hiltViewModel()) {
    val colors = RdTheme.colors
    val state by viewModel.state.collectAsState()
    val saveError by viewModel.saveError.collectAsState()
    val context = LocalContext.current
    var name by remember { mutableStateOf("") }
    var logoBytes by remember { mutableStateOf<ByteArray?>(null) }

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

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = "Firmalarım", onBack = onBack)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RdSpacing.lg),
        ) {
            when (val current = state) {
                is CompanyListUiState.Loading -> Box(modifier = Modifier.fillMaxWidth().padding(RdSpacing.xl), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.onyx)
                }
                is CompanyListUiState.Failed -> RdEmptyState(icon = Icons.Filled.Business, title = "Firmalar yüklenemedi", subtitle = current.error.message)
                is CompanyListUiState.Loaded -> if (current.companies.isEmpty()) {
                    RdEmptyState(icon = Icons.Filled.Business, title = "Henüz firma yok", subtitle = "Aşağıdan ilk firmanı ekleyebilirsin.")
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.xs)) {
                        current.companies.forEach { company ->
                            RdListRow(title = company.name, subtitle = company.hazardClass.title, icon = Icons.Filled.Business)
                        }
                    }
                }
            }

            Spacer(Modifier.height(RdSpacing.lg))
            Text("Yeni firma ekle", style = RdFontStyle.Title3.toTextStyle(), color = colors.onyx)
            Spacer(Modifier.height(RdSpacing.sm))
            RdSectionCard {
                Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        label = { Text("Firma adı") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    TextButton(
                        onClick = {
                            pickLogo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        },
                    ) {
                        Text(if (logoBytes != null) "Logo seçildi ✓" else "Logo seç (opsiyonel)")
                    }
                    RdPrimaryButton(
                        text = "Firma ekle",
                        onClick = {
                            viewModel.addCompany(CompanyDraft(name = name), logoBytes)
                            name = ""
                            logoBytes = null
                        },
                        enabled = name.isNotBlank(),
                        style = RdButtonStyle.Onyx,
                        showArrow = false,
                    )
                    saveError?.let { Text(it.message, style = RdFontStyle.Caption.toTextStyle(), color = colors.critical) }
                }
            }
            Spacer(Modifier.height(RdSpacing.lg))
        }
    }
}
