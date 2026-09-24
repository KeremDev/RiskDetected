package com.riskdetectedan.feature.nova

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.isg.*

private const val PPE_EXAMPLE_FILE = "ISGADA_KKD_Zimmet_ve_Teslim_Formu_Duzenlenebilir.docx"

/** One bundled Word sample; no user details are sent to the PPE record service. */
@Composable
fun NovaPPEExampleScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    LaunchedEffect(Unit) { com.riskdetectedan.core.data.nova.NovaForYouService.recordUse("ppe_form") }
    var message by remember { mutableStateOf<String?>(null) }
    val save = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/vnd.openxmlformats-officedocument.wordprocessingml.document")) { uri ->
        if (uri != null) message = runCatching {
            context.assets.open("ppe_forms/$PPE_EXAMPLE_FILE").use { source ->
                context.contentResolver.openOutputStream(uri)?.use { target -> source.copyTo(target) }
                    ?: error("Unable to open destination")
            }
            "Word dosyası kaydedildi."
        }.getOrElse { "Word dosyası kaydedilemedi." }
    }
    val available = remember(context) { runCatching {
        context.assets.open("ppe_forms/$PPE_EXAMPLE_FILE").use { it.read() >= 0 }
    }.getOrDefault(false) }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())
        .padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        NovaListHeading("KKD Zimmet Formu Örneği", onBack)
        NovaHelpHint("Düzenlenebilir Word örneğini indirin, kendi işyerinizin bilgileriyle doldurun ve kullanın. Uygulama burada zimmet veya teslim kaydı oluşturmaz.")
        NovaCard(Modifier.fillMaxWidth(), padding = 16) {
            Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                NovaText("KKD Zimmet ve Teslim Formu", style = NovaTypeToken.cardTitle)
                NovaText("Çalışan bilgileri, teslim edilen donanımlar, imzalar, ek teslim ve iade alanları içerir.", style = NovaTypeToken.meta)
                NovaText("Word · Düzenlenebilir örnek", style = NovaTypeToken.metaQuiet)
                if (available) NovaCompactActionButton("Word dosyasını indir", "arrow.down.doc", identifier = "ppe.example.download") {
                    message = null; save.launch(PPE_EXAMPLE_FILE)
                } else NovaText("Word dosyası bulunamadı", style = NovaTypeToken.metaQuiet)
            }
        }
        message?.let { NovaText(it, style = NovaTypeToken.meta) }
    }
}
