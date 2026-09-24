package com.riskdetectedan.feature.nova

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.IconButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.serialization.json.*
import java.text.Normalizer
import java.util.Locale

private data class WorkPermitSample(
    val code: String, val title: String, val usage: String, val sectors: List<String>,
    val jobs: List<String>, val filename: String, val note: String,
) {
    val searchText = (listOf(code, title, usage, note) + sectors + jobs).joinToString(" ")
}

private fun workPermitCatalog(raw: String): List<WorkPermitSample> = Json.parseToJsonElement(raw).jsonArray.map { element ->
    val item = element.jsonObject
    fun value(key: String) = item.getValue(key).jsonPrimitive.content
    fun values(key: String) = item.getValue(key).jsonArray.map { it.jsonPrimitive.content }
    WorkPermitSample(value("code"), value("title"), value("usage"), values("sectors"), values("jobs"), value("filename"), value("note"))
}.sortedBy { it.code }

private fun permitSearchKey(value: String): String = Normalizer.normalize(value.lowercase(Locale.forLanguageTag("tr-TR")), Normalizer.Form.NFD)
    .replace(Regex("\\p{Mn}+"), "").replace('ı', 'i')

/** Bundled Word examples only; saving a file never creates or approves a permit record. */
@Composable
fun NovaWorkPermitLibraryScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    LaunchedEffect(Unit) { com.riskdetectedan.core.data.nova.NovaForYouService.recordUse("work_permit_forms") }
    val catalog = remember(context) { runCatching {
        context.assets.open("work_permits/catalog.json").bufferedReader(Charsets.UTF_8).use { workPermitCatalog(it.readText()) }
    }.getOrDefault(emptyList()) }
    var query by remember { mutableStateOf("") }
    var sector by remember { mutableStateOf<String?>(null) }
    var job by remember { mutableStateOf<String?>(null) }
    var openFilter by remember { mutableStateOf<String?>(null) }
    var pending by remember { mutableStateOf<WorkPermitSample?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    val save = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/vnd.openxmlformats-officedocument.wordprocessingml.document")) { uri ->
        val entry = pending
        pending = null
        if (uri != null && entry != null) {
            message = runCatching {
                require(entry.filename.startsWith(entry.code + "_") && '/' !in entry.filename)
                context.assets.open("work_permits/${entry.filename}").use { source ->
                    context.contentResolver.openOutputStream(uri)?.use { target -> source.copyTo(target) }
                        ?: error("Unable to open destination")
                }
                "Word dosyası kaydedildi."
            }.getOrElse { "Word dosyası kaydedilemedi." }
        }
    }
    val sectors = remember(catalog) { catalog.flatMap { it.sectors }.distinct().filterNot { it == "Tüm sektörler" }.sorted() }
    val jobs = remember(catalog) { catalog.flatMap { it.jobs }.distinct().sorted() }
    val terms = remember(query) { permitSearchKey(query).split(Regex("\\s+")).filter { it.isNotEmpty() } }
    val visible = catalog.filter { item ->
        (sector == null || sector in item.sectors || "Tüm sektörler" in item.sectors) &&
            (job == null || job in item.jobs) && terms.all { it in permitSearchKey(item.searchText) }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())
        .padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaListHeading("Çalışma İzni Örnekleri", onBack)
        NovaListHint("56 düzenlenebilir Word örneği. Uygun formu arayın, indirin ve kendi saha prosedürünüze göre uyarlayın. Bu örnekler çalışma onayı veya izin kaydı oluşturmaz.")
        NovaSearchCapsule(query, "Form, iş veya kelime ara", "permit.search") { query = it }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaChooserButton("Sektör", sector ?: "Tüm sektörler", "permit.sector", Modifier.weight(1f), open = openFilter == "sector") {
                openFilter = if (openFilter == "sector") null else "sector"
            }
            NovaChooserButton("İş grubu", job ?: "Tüm işler", "permit.job", Modifier.weight(1f), open = openFilter == "job") {
                openFilter = if (openFilter == "job") null else "job"
            }
        }
        if (openFilter == "sector") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm sektörler")) + sectors.map { NovaChooserOption(it, it) },
            sector, "permit.sector.options") { sector = it; openFilter = null }
        if (openFilter == "job") NovaChooserPanel(listOf(NovaChooserOption(null, "Tüm işler")) + jobs.map { NovaChooserOption(it, it) },
            job, "permit.job.options") { job = it; openFilter = null }
        NovaListSectionHeading("Örnek Formlar", "${visible.size} / ${catalog.size} örnek form")
        message?.let { NovaText(it, style = NovaTypeToken.meta) }
        when {
            catalog.isEmpty() -> NovaEmptyState("Formlar yüklenemedi", "Uygulama paketindeki Word kataloğu bulunamadı.")
            visible.isEmpty() -> NovaEmptyState("Uygun form bulunamadı", "Arama kelimesini veya filtreleri değiştirin.")
            else -> visible.forEach { item ->
                NovaCard(Modifier.fillMaxWidth(), padding = 12) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            NovaText("${item.code} · ${item.title}", style = NovaTypeToken.bodyStrong, maxLines = 2)
                            NovaText(item.usage, style = NovaTypeToken.meta, maxLines = 1)
                            NovaText(item.jobs.joinToString(" · "), style = NovaTypeToken.metaQuiet, maxLines = 1)
                        }
                        IconButton(onClick = { message = null; pending = item; save.launch(item.filename) },
                            modifier = Modifier.size(44.dp).clip(RoundedCornerShape(12.dp))
                                .background(NovaColorToken.surfaceMuted.color())
                                .semantics { contentDescription = "${item.title} Word dosyasını indir" }
                                .testTag("permit.download.${item.code}")) {
                            NovaIcon("arrow.down.doc", 20.dp)
                        }
                    }
                }
            }
        }
    }
}
