package com.riskdetectedan.feature.profile

import com.riskdetectedan.core.designsystem.R as RdR

import androidx.compose.ui.res.stringResource

import android.content.Intent
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.FileProvider
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.riskdetectedan.core.common.RdResult
import com.riskdetectedan.core.data.account.UserDataExport
import com.riskdetectedan.core.data.account.UserDataRepository
import com.riskdetectedan.core.data.error.AppErrorMessage
import com.riskdetectedan.core.data.error.AppErrorMessages
import com.riskdetectedan.core.designsystem.RdFontStyle
import com.riskdetectedan.core.designsystem.RdListRow
import com.riskdetectedan.core.designsystem.RdScreenHeader
import com.riskdetectedan.core.designsystem.RdSpacing
import com.riskdetectedan.core.designsystem.RdTheme
import com.riskdetectedan.core.designsystem.toTextStyle
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

private enum class DataAction { Export, DeleteReports, DeleteAnalyses }

@HiltViewModel
class DataManagementViewModel @Inject constructor(
    private val repository: UserDataRepository,
    @ApplicationContext private val context: Context,
) : ViewModel() {
    private val _working = MutableStateFlow<DataAction?>(null)
    private val _isWorking = MutableStateFlow(false)
    val isWorking: StateFlow<Boolean> = _isWorking.asStateFlow()
    private val _export = MutableStateFlow<UserDataExport?>(null)
    val export: StateFlow<UserDataExport?> = _export.asStateFlow()
    private val _error = MutableStateFlow<AppErrorMessage?>(null)
    val error: StateFlow<AppErrorMessage?> = _error.asStateFlow()
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()
    fun export() = run(DataAction.Export) { repository.exportUserData() }
    fun deleteReports() = runUnit(DataAction.DeleteReports, context.getString(RdR.string.rd_tum_raporlar_silindi)) { repository.deleteAllReports() }
    fun deleteAnalyses() = runUnit(DataAction.DeleteAnalyses, context.getString(RdR.string.rd_tum_analizler_silindi)) {
        repository.deleteAllAnalyses()
    }

    private fun run(action: DataAction, block: suspend () -> RdResult<UserDataExport>) {
        if (_isWorking.value) return
        _isWorking.value = true
        _working.value = action
        _error.value = null
        viewModelScope.launch {
            when (val result = block()) {
                is RdResult.Success -> _export.value = result.value
                is RdResult.Failure -> _error.value = AppErrorMessages.make(
                    result.message,
                    context.getString(RdR.string.rd_veri_disari_aktarilamadi),
                )
            }
            _working.value = null
            _isWorking.value = false
        }
    }

    private fun runUnit(action: DataAction, success: String, block: suspend () -> RdResult<Unit>) {
        if (_isWorking.value) return
        _isWorking.value = true
        _working.value = action
        _error.value = null
        viewModelScope.launch {
            when (val result = block()) {
                is RdResult.Success -> _message.value = success
                is RdResult.Failure -> _error.value = AppErrorMessages.make(
                    result.message,
                    context.getString(RdR.string.rd_veriler_silinemedi),
                )
            }
            _working.value = null
            _isWorking.value = false
        }
    }

    fun clearExport() { _export.value = null }
    fun clearMessage() { _message.value = null }
    fun clearError() { _error.value = null }
}

@Composable
fun DataManagementScreen(
    onBack: () -> Unit,
    viewModel: DataManagementViewModel = hiltViewModel(),
) {
    val colors = RdTheme.colors
    val export by viewModel.export.collectAsState()
    val error by viewModel.error.collectAsState()
    val message by viewModel.message.collectAsState()
    val isWorking by viewModel.isWorking.collectAsState()
    var confirmation by remember { mutableStateOf<DataAction?>(null) }
    val context = LocalContext.current
    val shareChooserTitle = stringResource(RdR.string.rd_verilerimi_paylas)

    LaunchedEffect(export) {
        val value = export ?: return@LaunchedEffect
        val directory = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(directory, value.fileName).apply { writeBytes(value.bytes) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        context.startActivity(
            Intent.createChooser(
                Intent(Intent.ACTION_SEND).apply {
                    type = "application/json"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
                shareChooserTitle,
            ),
        )
        viewModel.clearExport()
    }

    Column(Modifier.fillMaxSize().background(colors.paper)) {
        RdScreenHeader(title = stringResource(RdR.string.rd_verilerim), onBack = onBack)
        Column(Modifier.padding(horizontal = RdSpacing.lg)) {
            if (isWorking) CircularProgressIndicator(color = colors.onyx)
            RdListRow(
                title = stringResource(RdR.string.rd_verilerimi_disari_aktar),
                subtitle = stringResource(RdR.string.rd_veri_disari_aktar_aciklama),
                icon = Icons.Filled.Download,
                onClick = { confirmation = DataAction.Export },
            )
            RdListRow(
                title = stringResource(RdR.string.rd_tum_raporlari_sil),
                subtitle = stringResource(RdR.string.rd_tum_raporlari_sil_aciklama),
                icon = Icons.Filled.PictureAsPdf,
                iconTint = colors.critical,
                iconBackground = colors.criticalBg,
                onClick = { confirmation = DataAction.DeleteReports },
            )
            RdListRow(
                title = stringResource(RdR.string.rd_tum_analizleri_sil),
                subtitle = stringResource(RdR.string.rd_tum_analizleri_sil_aciklama),
                icon = Icons.Filled.DeleteSweep,
                iconTint = colors.critical,
                iconBackground = colors.criticalBg,
                onClick = { confirmation = DataAction.DeleteAnalyses },
            )
            Spacer(Modifier.height(RdSpacing.md))
            Text(stringResource(RdR.string.rd_silme_islemleri_geri_alinamaz), style = RdFontStyle.Footnote.toTextStyle(), color = colors.critical)
        }
    }

    confirmation?.let { action ->
        val destructive = action != DataAction.Export
        AlertDialog(
            onDismissRequest = { confirmation = null },
            title = {
                Text(
                    stringResource(
                        if (destructive) RdR.string.rd_bu_islem_geri_alinamaz
                        else RdR.string.rd_veriler_disari_aktarilsin_mi,
                    ),
                )
            },
            text = {
                Text(
                    when (action) {
                        DataAction.Export -> stringResource(RdR.string.rd_veri_paylasim_uyarisi)
                        DataAction.DeleteReports -> stringResource(RdR.string.rd_raporlar_kalici_silinecek)
                        DataAction.DeleteAnalyses -> stringResource(RdR.string.rd_analizler_kalici_silinecek)
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmation = null
                    when (action) {
                        DataAction.Export -> viewModel.export()
                        DataAction.DeleteReports -> viewModel.deleteReports()
                        DataAction.DeleteAnalyses -> viewModel.deleteAnalyses()
                    }
                }) {
                    Text(
                        stringResource(
                            if (destructive) RdR.string.rd_kalici_olarak_sil else RdR.string.rd_disari_aktar,
                        ),
                    )
                }
            },
            dismissButton = { TextButton(onClick = { confirmation = null }) { Text(stringResource(RdR.string.rd_vazgec)) } },
        )
    }

    error?.let {
        AlertDialog(
            onDismissRequest = viewModel::clearError,
            title = { Text(it.title) },
            text = { Text(it.message) },
            confirmButton = { TextButton(onClick = viewModel::clearError) { Text(stringResource(RdR.string.rd_tamam)) } },
        )
    }
    message?.let {
        AlertDialog(
            onDismissRequest = viewModel::clearMessage,
            title = { Text(stringResource(RdR.string.rd_i_slem_tamamlandi)) },
            text = { Text(it) },
            confirmButton = { TextButton(onClick = viewModel::clearMessage) { Text(stringResource(RdR.string.rd_tamam)) } },
        )
    }
}
