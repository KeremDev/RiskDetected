package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import com.riskdetectedan.core.data.company.CompanyDraft
import com.riskdetectedan.core.data.company.Company
import com.riskdetectedan.core.data.company.CompanyHazardClass
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
    val capabilities by viewModel.capabilities.collectAsState()
    val context = LocalContext.current
    var name by remember { mutableStateOf("") }
    var address by remember { mutableStateOf("") }
    var contactPerson by remember { mutableStateOf("") }
    var department by remember { mutableStateOf("") }
    var defaultResponsible by remember { mutableStateOf("") }
    var defaultDueDaysText by remember { mutableStateOf("") }
    var hazardClass by remember { mutableStateOf(CompanyHazardClass.Medium) }
    var logoBytes by remember { mutableStateOf<ByteArray?>(null) }
    var editingCompany by remember { mutableStateOf<Company?>(null) }
    var deletingCompany by remember { mutableStateOf<Company?>(null) }
    val companyCount = (state as? CompanyListUiState.Loaded)?.companies?.size ?: 0
    val canAddCompany = companyCount < capabilities.companyLimit
    val draft = CompanyDraft(
        name = name,
        hazardClass = hazardClass,
        address = address,
        contactPerson = contactPerson,
        department = department,
        defaultResponsible = defaultResponsible,
        defaultDueDaysText = defaultDueDaysText,
    )

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
        RdScreenHeader(title = stringResource(RdR.string.rd_firmalarim), onBack = onBack)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RdSpacing.lg),
        ) {
            when (val current = state) {
                is CompanyListUiState.Loading -> Box(modifier = Modifier.fillMaxWidth().padding(RdSpacing.xl), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.black)
                }
                is CompanyListUiState.Failed -> RdEmptyState(icon = Icons.Filled.Business, title = stringResource(RdR.string.rd_firmalar_yuklenemedi), subtitle = current.error.message)
                is CompanyListUiState.Loaded -> if (current.companies.isEmpty()) {
                    RdEmptyState(
                        icon = Icons.Filled.Business,
                        title = stringResource(RdR.string.rd_henuz_firma_yok),
                        subtitle = stringResource(RdR.string.rd_ilk_firma_ekle_aciklama),
                    )
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.xs)) {
                        current.companies.forEach { company ->
                            RdListRow(
                                title = company.name,
                                subtitle = company.hazardClass.title,
                                icon = Icons.Filled.Business,
                                onClick = { editingCompany = company },
                                trailing = {
                                    Text(
                                        stringResource(RdR.string.rd_duzenle),
                                        style = RdFontStyle.Caption.toTextStyle(),
                                        color = colors.slate,
                                    )
                                },
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(RdSpacing.lg))
            Text(stringResource(RdR.string.rd_yeni_firma_ekle), style = RdFontStyle.Title3.toTextStyle(), color = colors.black)
            Text(
                if (capabilities.companyLimit == 0) {
                    stringResource(RdR.string.rd_firma_yonetimi_plan_gerektirir)
                } else {
                    stringResource(RdR.string.rd_firma_sayaci_format, companyCount, capabilities.companyLimit)
                },
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
            )
            Spacer(Modifier.height(RdSpacing.sm))
            RdSectionCard {
                Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        label = { Text(stringResource(RdR.string.rd_firma_adi)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(
                        stringResource(RdR.string.rd_tehlike_sinifi),
                        style = RdFontStyle.Footnote.toTextStyle(),
                        color = colors.slate,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(RdSpacing.xs),
                    ) {
                        CompanyHazardClass.entries.forEach { option ->
                            FilterChip(
                                selected = hazardClass == option,
                                onClick = { hazardClass = option },
                                label = { Text(option.title) },
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                    OutlinedTextField(
                        value = address,
                        onValueChange = { address = it },
                        label = { Text(stringResource(RdR.string.rd_firma_adresi)) },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 2,
                    )
                    OutlinedTextField(
                        value = contactPerson,
                        onValueChange = { contactPerson = it },
                        label = { Text(stringResource(RdR.string.rd_firma_yetkilisi)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = department,
                        onValueChange = { department = it },
                        label = { Text(stringResource(RdR.string.rd_departman)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = defaultResponsible,
                        onValueChange = { defaultResponsible = it },
                        label = { Text(stringResource(RdR.string.rd_varsayilan_sorumlu)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = defaultDueDaysText,
                        onValueChange = { value ->
                            defaultDueDaysText = value.filter(Char::isDigit).take(3)
                        },
                        label = { Text(stringResource(RdR.string.rd_varsayilan_termin_gun)) },
                        supportingText = {
                            Text(stringResource(RdR.string.rd_varsayilan_termin_aciklama))
                        },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        isError = defaultDueDaysText.isNotBlank() &&
                            (draft.defaultDueDays?.let { it !in 1..365 } ?: true),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    TextButton(
                        onClick = {
                            pickLogo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        },
                    ) {
                        Text(
                            stringResource(
                                if (logoBytes != null) RdR.string.rd_logo_secildi else RdR.string.rd_logo_sec_opsiyonel,
                            ),
                        )
                    }
                    RdPrimaryButton(
                        text = stringResource(RdR.string.rd_firma_ekle),
                        onClick = {
                            viewModel.addCompany(draft, logoBytes)
                            name = ""
                            address = ""
                            contactPerson = ""
                            department = ""
                            defaultResponsible = ""
                            defaultDueDaysText = ""
                            hazardClass = CompanyHazardClass.Medium
                            logoBytes = null
                        },
                        enabled = draft.isValid && canAddCompany,
                        style = RdButtonStyle.Onyx,
                        showArrow = false,
                    )
                    saveError?.let { Text(it.message, style = RdFontStyle.Caption.toTextStyle(), color = colors.critical) }
                }
            }
            Spacer(Modifier.height(RdSpacing.lg))
        }
    }

    editingCompany?.let { company ->
        CompanyEditDialog(
            company = company,
            onSave = { updated ->
                viewModel.updateCompany(updated)
                editingCompany = null
            },
            onDelete = {
                editingCompany = null
                deletingCompany = company
            },
            onDismiss = { editingCompany = null },
        )
    }

    deletingCompany?.let { company ->
        AlertDialog(
            onDismissRequest = { deletingCompany = null },
            title = { Text(stringResource(RdR.string.rd_firmayi_sil)) },
            text = { Text(stringResource(RdR.string.rd_firma_silme_onayi_format, company.name)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteCompany(company)
                        deletingCompany = null
                    },
                ) { Text(stringResource(RdR.string.rd_evet_sil), color = colors.critical) }
            },
            dismissButton = {
                TextButton(onClick = { deletingCompany = null }) {
                    Text(stringResource(RdR.string.rd_vazgec))
                }
            },
        )
    }
}

@Composable
private fun CompanyEditDialog(
    company: Company,
    onSave: (CompanyDraft) -> Unit,
    onDelete: () -> Unit,
    onDismiss: () -> Unit,
) {
    var name by remember(company.id) { mutableStateOf(company.name) }
    var hazardClass by remember(company.id) { mutableStateOf(company.hazardClass) }
    var address by remember(company.id) { mutableStateOf(company.address.orEmpty()) }
    var contactPerson by remember(company.id) { mutableStateOf(company.contactPerson.orEmpty()) }
    var department by remember(company.id) { mutableStateOf(company.department.orEmpty()) }
    var defaultResponsible by remember(company.id) { mutableStateOf(company.defaultResponsible.orEmpty()) }
    var defaultDueDaysText by remember(company.id) { mutableStateOf(company.defaultDueDays?.toString().orEmpty()) }
    val draft = CompanyDraft(
        id = company.id,
        name = name,
        hazardClass = hazardClass,
        logoPath = company.logoPath,
        address = address,
        contactPerson = contactPerson,
        department = department,
        defaultResponsible = defaultResponsible,
        defaultDueDaysText = defaultDueDaysText,
    )

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(RdR.string.rd_firmayi_duzenle)) },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(RdSpacing.sm),
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(stringResource(RdR.string.rd_firma_adi)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(RdSpacing.xs),
                ) {
                    CompanyHazardClass.entries.forEach { option ->
                        FilterChip(
                            selected = hazardClass == option,
                            onClick = { hazardClass = option },
                            label = { Text(option.title) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
                OutlinedTextField(address, { address = it }, label = { Text(stringResource(RdR.string.rd_firma_adresi)) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(contactPerson, { contactPerson = it }, label = { Text(stringResource(RdR.string.rd_firma_yetkilisi)) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(department, { department = it }, label = { Text(stringResource(RdR.string.rd_departman)) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(defaultResponsible, { defaultResponsible = it }, label = { Text(stringResource(RdR.string.rd_varsayilan_sorumlu)) }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    value = defaultDueDaysText,
                    onValueChange = { defaultDueDaysText = it.filter(Char::isDigit).take(3) },
                    label = { Text(stringResource(RdR.string.rd_varsayilan_termin_gun)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    isError = defaultDueDaysText.isNotBlank() && (draft.defaultDueDays?.let { it !in 1..365 } ?: true),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onSave(draft) }, enabled = draft.isValid) {
                Text(stringResource(RdR.string.rd_kaydet))
            }
        },
        dismissButton = {
            Row {
                TextButton(onClick = onDelete) {
                    Text(stringResource(RdR.string.rd_sil), color = RdTheme.colors.critical)
                }
                TextButton(onClick = onDismiss) { Text(stringResource(RdR.string.rd_vazgec)) }
            }
        },
    )
}

/** Deterministic company-management state used by the release golden suite. */
@Composable
fun CompanyListParityPreviewSurface() {
    val colors = RdTheme.colors
    val companies = listOf(
        Company(
            id = "preview-one",
            userId = "preview-user",
            name = "RiskDetected İnşaat",
            hazardClassId = "high",
        ),
        Company(
            id = "preview-two",
            userId = "preview-user",
            name = "Anadolu Üretim Tesisi",
            hazardClassId = "medium",
        ),
    )

    Column(modifier = Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = stringResource(RdR.string.rd_firmalarim), onBack = {})
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RdSpacing.lg),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.xs)) {
                companies.forEach { company ->
                    RdListRow(
                        title = company.name,
                        subtitle = company.hazardClass.title,
                        icon = Icons.Filled.Business,
                    )
                }
            }
            Spacer(Modifier.height(RdSpacing.lg))
            Text(
                stringResource(RdR.string.rd_yeni_firma_ekle),
                style = RdFontStyle.Title3.toTextStyle(),
                color = colors.black,
            )
            Text(
                stringResource(RdR.string.rd_firma_sayaci_format, companies.size, 5),
                style = RdFontStyle.Caption.toTextStyle(),
                color = colors.slate,
            )
            Spacer(Modifier.height(RdSpacing.sm))
            RdSectionCard {
                Column(verticalArrangement = Arrangement.spacedBy(RdSpacing.sm)) {
                    OutlinedTextField(
                        value = "",
                        onValueChange = {},
                        label = { Text(stringResource(RdR.string.rd_firma_adi)) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    TextButton(onClick = {}) {
                        Text(stringResource(RdR.string.rd_logo_sec_opsiyonel))
                    }
                    RdPrimaryButton(
                        text = stringResource(RdR.string.rd_firma_ekle),
                        onClick = {},
                        enabled = false,
                        style = RdButtonStyle.Onyx,
                        showArrow = false,
                    )
                }
            }
        }
    }
}
