package com.riskdetectedan.feature.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import com.riskdetectedan.core.data.company.CompanyDraft
import com.riskdetectedan.core.designsystem.RdSpacing
import java.io.ByteArrayOutputStream

/** Port of the company list + add form from App/Services/CompanyService.swift's contract
 * (no dedicated iOS view file was read for layout — CompanyPickerSheet.swift exists but this is
 * the management surface, not the analysis-time picker; kept minimal/functional). Logo picking
 * uses the system Photo Picker (`PickVisualMedia`, no storage permission needed) — the picked
 * image is decoded and re-encoded as JPEG client-side since a gallery pick can be any format,
 * unlike CaptureScreen's CameraX output which is already JPEG.
 */
@Composable
fun CompanyListScreen(viewModel: CompanyViewModel = hiltViewModel()) {
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

    Column(modifier = Modifier.fillMaxSize().padding(RdSpacing.lg)) {
        Text("Firmalar")

        when (val current = state) {
            is CompanyListUiState.Loading -> CircularProgressIndicator()
            is CompanyListUiState.Failed -> Text(current.error.message)
            is CompanyListUiState.Loaded -> LazyColumn(modifier = Modifier.padding(top = RdSpacing.sm)) {
                items(current.companies) { company ->
                    ListItem(
                        headlineContent = { Text(company.name) },
                        supportingContent = { Text(company.hazardClass.title) },
                    )
                }
            }
        }

        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text("Yeni firma adı") },
            modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.md),
        )
        TextButton(
            onClick = {
                pickLogo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            },
        ) {
            Text(if (logoBytes != null) "Logo seçildi ✓" else "Logo seç (opsiyonel)")
        }
        Button(
            onClick = {
                viewModel.addCompany(CompanyDraft(name = name), logoBytes)
                name = ""
                logoBytes = null
            },
            enabled = name.isNotBlank(),
            modifier = Modifier.fillMaxWidth().padding(top = RdSpacing.sm),
        ) {
            Text("Firma ekle")
        }
        saveError?.let { Text(it.message) }
    }
}
