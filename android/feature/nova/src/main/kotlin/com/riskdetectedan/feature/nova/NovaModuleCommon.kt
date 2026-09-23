package com.riskdetectedan.feature.nova

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** A small labelled value on a module row (iOS `fact(_:_:_:)`). */
@Composable
internal fun NovaRowFact(symbol: String, label: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon(symbol, 10.dp, tint = NovaColorToken.textMuted.color())
        Column {
            NovaSizedText(label, 9f, FontWeight.Medium, NovaColorToken.textMuted.color())
            NovaSizedText(value, 11f, FontWeight.Bold)
        }
    }
}

/** One cell of a detail sheet's fact grid (iOS `cell(_:_:_:detail:)`). */
@Composable
internal fun NovaFactCell(symbol: String, label: String, value: String, modifier: Modifier, detail: String = "") {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        NovaIcon(symbol, 11.dp, Modifier.padding(top = 2.dp), tint = NovaColorToken.textMuted.color())
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            NovaSizedText(label, 9f, FontWeight.Medium, NovaColorToken.textMuted.color())
            NovaSizedText(value, 12f, FontWeight.Bold)
            if (detail.isNotEmpty()) NovaSizedText(detail, 9.5f, FontWeight.Medium, NovaColorToken.textSecondary.color())
        }
    }
}

/** Lays a fact grid out two to a row. */
@Composable
internal fun NovaFactGrid(cells: List<@Composable (Modifier) -> Unit>) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        cells.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pair.forEach { it(Modifier.weight(1f)) }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** An attached, filed document with an open button (iOS `fileRow`/`letterRow`). */
@Composable
internal fun NovaAttachedFileRow(title: String, bucket: String, path: String, download: suspend (String, String) -> ByteArray, identifier: String) {
    val coroutines = rememberCoroutineScope()
    val context = LocalContext.current
    var opening by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        NovaIcon("doc.fill", 14.dp, tint = NovaColorToken.statusSuccessInk.color())
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            NovaText(title, style = NovaTypeToken.cardTitle)
            failure?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        }
        NovaButton("Dosyayı aç", {
            opening = true; failure = null
            coroutines.launch {
                try {
                    val bytes = download(bucket, path)
                    val name = path.substringAfterLast('/').ifEmpty { "belge" }
                    novaShareFile(context, bytes, name, android.webkit.MimeTypeMap.getSingleton()
                        .getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream")
                } catch (_: Exception) { failure = "Dosya servisi şu anda kullanılamıyor." }
                opening = false
            }
        }, Modifier.testTag(identifier), variant = NovaButtonVariant.Surface, enabled = !opening, loading = opening,
            symbol = "arrow.up.right.square", compact = true)
    }
}

/** A task page: header, scrolling body and sticky actions that clear the floating tab bar. */
@Composable
internal fun NovaModuleTask(title: String, step: Int, total: Int, stepTitle: String, primaryTitle: String, primarySymbol: String, working: Boolean,
                            onBack: () -> Unit, onPrimary: () -> Unit, failure: String?, canGoBack: Boolean = true,
                            content: @Composable ColumnScope.() -> Unit) {
    androidx.activity.compose.BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize()) {
        NovaTaskHeader(title, step, total, stepTitle, Modifier.padding(horizontal = 18.dp).padding(top = 10.dp), onClose = onBack)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(20.dp).padding(bottom = 18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            content()
            failure?.let { NovaTaskErrorSummary(it) }
        }
        NovaTaskStickyActions(primaryTitle, onBack, onPrimary, Modifier.navigationBarsPadding().padding(bottom = novaTabBarClearance),
            primarySymbol, working, canGoBack)
    }
}


/** A 24-hour time that opens the Material time picker (iOS `DatePicker(.hourAndMinute)`). */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
internal fun NovaTimeField(label: String, time: java.time.LocalTime, identifier: String, onChange: (java.time.LocalTime) -> Unit) {
    var picking by remember { mutableStateOf(false) }
    NovaFormValueRow(label, "clock") {
        Box(Modifier.heightIn(min = 36.dp).novaRowPress { picking = true }.testTag(identifier).padding(horizontal = 10.dp),
            contentAlignment = Alignment.Center) { NovaText(time.format(java.time.format.DateTimeFormatter.ofPattern("HH:mm")), style = NovaTypeToken.bodyStrong) }
    }
    if (picking) {
        val state = androidx.compose.material3.rememberTimePickerState(time.hour, time.minute, is24Hour = true)
        androidx.compose.ui.window.Dialog({ picking = false }) {
            NovaCard(padding = 16) {
                androidx.compose.material3.TimePicker(state)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    androidx.compose.material3.TextButton({ picking = false }) {
                        NovaText("Vazgeç", style = NovaTypeToken.button, color = NovaColorToken.textSecondary.color())
                    }
                    androidx.compose.material3.TextButton({ onChange(java.time.LocalTime.of(state.hour, state.minute)); picking = false }) {
                        NovaText("Tamam", style = NovaTypeToken.button, color = NovaColorToken.accentInk.color())
                    }
                }
            }
        }
    }
}
