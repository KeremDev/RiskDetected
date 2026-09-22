package com.riskdetectedan.feature.nova

import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch

/** The library's words in one place (iOS `NovaFileWords`). */
object NovaFileWords {
    fun category(code: String): String = when (code) {
        "risk_assessment" -> "Risk değerlendirmesi"; "emergency_plan" -> "Acil durum planı"; "training_material" -> "Eğitim belgesi"
        "inspection_report" -> "Periyodik kontrol raporu"; "measurement_report" -> "Ortam ölçüm raporu"
        "accident_record" -> "İş kazası kaydı"; "board_document" -> "Kurul belgesi"; "handover_form" -> "Zimmet formu"
        "personnel_document" -> "Personel belgesi"; "contract" -> "Sözleşme"; "permit_form" -> "Çalışma izni formu"
        "contractor_document" -> "Taşeron belgesi"; "other" -> "Diğer"; "nonconformity_evidence" -> "Uygunsuzluk kanıtı"
        else -> code
    }
    fun size(bytes: Int): String {
        val units = listOf("B", "KB", "MB")
        var value = bytes.toDouble(); var index = 0
        while (value >= 1024 && index < units.size - 1) { value /= 1024; index++ }
        return if (index == 0) "${value.toInt()} ${units[index]}" else String.format(java.util.Locale.forLanguageTag("tr-TR"), "%.1f %s", value, units[index])
    }
    fun symbol(state: NovaFileState): String = when (state) {
        NovaFileState.promoted -> "checkmark.circle"
        NovaFileState.pending, NovaFileState.uploaded, NovaFileState.scanning, NovaFileState.clean -> "arrow.up.circle"
        NovaFileState.rejected -> "exclamationmark.triangle"
        NovaFileState.scanFailed -> "questionmark.circle"
        NovaFileState.expired -> "clock"
    }
    fun rejection(code: String?): String = when (code) {
        null -> ""
        "UNSUPPORTED_FORMAT" -> "Bu dosya türü kabul edilmiyor."
        "SIZE_LIMIT" -> "Dosya boyutu sınırın dışında."
        "HASH_MISMATCH" -> "Ulaşan dosya, gönderilen dosyayla aynı değil."
        "MIME_MISMATCH" -> "Dosyanın gerçek türü adıyla uyuşmuyor."
        "SCAN_REJECTED" -> "Dosya, biçim denetiminden geçmedi."
        "SCAN_UNAVAILABLE" -> "Denetim tamamlanamadı. Dosya arşive alınmadı."
        "EXPIRED" -> "Yükleme süresi doldu."
        else -> "Dosya kabul edilmedi. ($code)"
    }
    fun finding(code: String?): String = when (code) {
        null -> ""
        "MACRO_PRESENT" -> "Belgede makro var."
        "ACTIVE_CONTENT" -> "Belgede çalışan içerik var."
        "ENCRYPTED_FILE" -> "Dosya şifreli; içeriği denetlenemiyor. Şifresiz nüsha yükleyin."
        "EMBEDDED_FILE" -> "Belgeye başka bir dosya gömülü."
        "EXTERNAL_REFERENCE" -> "Belge dışarıdan içerik çağırıyor."
        "XML_ENTITY" -> "Belgede güvenli olmayan XML tanımı var."
        "ARCHIVE_BOMB" -> "Dosya, açıldığında sınırların çok üstüne çıkıyor."
        "PATH_TRAVERSAL" -> "Belge paketinde geçersiz dosya yolu var."
        "IMAGE_TOO_LARGE" -> "Görselin çözünürlüğü sınırın üstünde."
        "TYPE_MISMATCH" -> "Dosyanın gerçek türü uzantısıyla uyuşmuyor."
        "MALFORMED_FILE" -> "Dosya okunamadı."
        else -> code
    }
    fun tone(group: NovaFileGroup): NovaStatus = when (group) {
        NovaFileGroup.filed -> NovaStatus.Success; NovaFileGroup.working -> NovaStatus.Info
        NovaFileGroup.rejected -> NovaStatus.Danger; NovaFileGroup.unchecked -> NovaStatus.Warning
    }
    fun failure(error: Throwable): String = (error as? NovaFileException)?.failure?.message ?: NovaFileFailure.unavailable.message
}

/** Everything a file surface needs, bound to one identity (iOS `NovaFileLibraryClient`). */
class NovaFileClient(private val service: NovaFileLibraryService, private val identity: IsgWorkspaceIdentity) {
    suspend fun catalogue() = service.catalogue(identity)
    suspend fun library(query: NovaFileQuery) = service.library(identity, query)
    suspend fun file(company: String?, draft: NovaFileDraft, data: ByteArray) = service.file(identity, company, draft, data)
    suspend fun rename(entry: NovaFileEntry, title: String, category: String, note: String) = service.rename(identity, entry, title, category, note)
    suspend fun archive(entry: NovaFileEntry) = service.archive(identity, entry)
    suspend fun cancel(entry: NovaFileEntry) = service.cancel(identity, entry)
    suspend fun recheck(entry: NovaFileEntry) = service.recheck(identity, entry)
    suspend fun contents(entry: NovaFileEntry) = service.contents(identity, entry)
    suspend fun download(bucket: String, path: String) = service.download(identity, bucket, path)
}

private data class PickedFile(val bytes: ByteArray, val name: String, val extension: String)

private fun readPicked(context: android.content.Context, uri: Uri): PickedFile? = runCatching {
    val resolver = context.contentResolver
    val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
    } ?: uri.lastPathSegment ?: "dosya"
    val extension = name.substringAfterLast('.', "").lowercase().ifEmpty {
        MimeTypeMap.getSingleton().getExtensionFromMimeType(resolver.getType(uri)).orEmpty()
    }
    val bytes = resolver.openInputStream(uri)?.use { it.readBytes() } ?: return null
    PickedFile(bytes, name, extension)
}.getOrNull()

/**
 * The bare upload flow — pick, title/category/note, send, result — with no
 * chrome of its own (iOS `NovaFileAddInline`). Never shows a file as filed
 * before the server says so.
 */
@Composable
fun NovaFileAddInline(companies: List<NovaCompanyOption>, preselected: String?, categories: List<NovaFileCategory>,
                      accepts: List<NovaFileAcceptance>, assurance: NovaFileAssurance, client: NovaFileClient,
                      pickerLabel: String = "Dosya seç", onDone: (NovaFileEntry?) -> Unit) {
    val context = LocalContext.current
    val coroutines = rememberCoroutineScope()
    var company by remember { mutableStateOf(preselected) }
    var draft by remember { mutableStateOf(NovaFileDraft()) }
    var payload by remember { mutableStateOf<ByteArray?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var outcome by remember { mutableStateOf<NovaFileEntry?>(null) }
    var choosingCategory by remember { mutableStateOf(false) }
    var choosingCompany by remember { mutableStateOf(false) }
    var infoOpen by remember { mutableStateOf(false) }
    val maxBytes = accepts.maxOfOrNull { it.maxBytes } ?: 0
    val extensions = accepts.flatMap { it.extensions }.map { it.lowercase() }.distinct().sorted()
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        error = null
        val file = uri?.let { readPicked(context, it) } ?: return@rememberLauncherForActivityResult
        when {
            file.extension !in extensions -> error = NovaFileFailure.unsupportedFormat.message
            file.bytes.isEmpty() || file.bytes.size > maxBytes -> error = NovaFileFailure.tooLarge.message
            else -> {
                payload = file.bytes
                draft = draft.copy(fileName = file.name, fileExtension = file.extension, bytes = file.bytes.size,
                    sha256 = NovaFileDraft.sha256(file.bytes), title = draft.title.ifEmpty { file.name.substringBeforeLast('.') })
                // The heading is the expert's decision, so it is asked for rather than defaulted.
                if (draft.category == null) choosingCategory = true
            }
        }
    }
    val result = outcome
    Column(verticalArrangement = Arrangement.spacedBy(11.dp)) {
        if (result != null) {
            val group = NovaFileGroup.of(result.state)
            val tone = NovaFileWords.tone(group)
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(42.dp), contentAlignment = Alignment.Center) { NovaIcon(NovaFileWords.symbol(result.state), 20.dp, tint = tone.ink.color()) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    NovaText(result.title, style = NovaTypeToken.cardTitle, maxLines = 2)
                    NovaText(result.state.title, style = NovaTypeToken.metaQuiet)
                }
            }
            if (result.state.isStopped) NovaCard(Modifier.fillMaxWidth(), padding = 11, tint = tone.background.color()) {
                NovaText(NovaFileWords.rejection(result.rejectionCode), style = NovaTypeToken.meta)
                if (!result.scanFinding.isNullOrEmpty()) NovaText(NovaFileWords.finding(result.scanFinding), style = NovaTypeToken.metaQuiet)
            } else if (result.state.isWorking) NovaText("Dosya denetimde. Listedeki kaydından durumu izleyebilir, denetimi tekrar çalıştırabilirsiniz.",
                style = NovaTypeToken.metaQuiet)
            NovaButton("Kapat", { onDone(result) }, Modifier.testTag("file.add.close"), variant = NovaButtonVariant.Surface, symbol = "xmark")
            return@Column
        }
        if (preselected == null) {
            NovaChooserButton("Firma", companies.firstOrNull { it.id == company }?.name ?: "Kişisel dosya", "file.add.company",
                symbol = "building.2", open = choosingCompany) { choosingCompany = !choosingCompany }
            if (choosingCompany) NovaChooserPanel(listOf(NovaChooserOption(null, "Kişisel dosya", symbol = "person")) +
                companies.map { NovaChooserOption(it.id, it.name, symbol = "building.2") }, company, "file.add.company") {
                company = it; choosingCompany = false
            }
        }
        NovaPopupOption(if (payload == null) pickerLabel else draft.fileName, if (payload == null) "folder.badge.plus" else "doc",
            if (payload == null) "PDF, belge veya fotoğraf" else NovaFileWords.size(draft.bytes), identifier = "file.add.pick") {
            picker.launch(extensions.mapNotNull { MimeTypeMap.getSingleton().getMimeTypeFromExtension(it) }.distinct()
                .ifEmpty { listOf("*/*") }.toTypedArray())
        }
        if (payload != null) {
            NovaTextField("Başlık", draft.title, { draft = draft.copy(title = it) }, identifier = "file.add.title")
            NovaChooserButton("Başlık altında sakla", draft.category?.let(NovaFileWords::category) ?: "Başlık seçin", "file.add.category",
                symbol = "folder", open = choosingCategory) { choosingCategory = !choosingCategory }
            if (choosingCategory) NovaChooserPanel(categories.map { NovaChooserOption(it.code, NovaFileWords.category(it.code), symbol = "folder") },
                draft.category, "file.add.category") { picked -> if (picked != null) draft = draft.copy(category = picked); choosingCategory = false }
            NovaTextField("Etiketler · virgülle ayırın", draft.tags, { draft = draft.copy(tags = it) }, identifier = "file.add.tags")
            NovaTextField("Not", draft.note, { draft = draft.copy(note = it) }, identifier = "file.add.note")
        }
        Row(Modifier.heightIn(min = 36.dp).novaRowPress { infoOpen = !infoOpen }, horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("info.circle", 14.dp, tint = NovaColorToken.textSecondary.color())
            NovaText("Dosya bilgileri", style = NovaTypeToken.meta, color = NovaColorToken.textSecondary.color())
        }
        if (infoOpen) {
            NovaText("${extensions.joinToString(", ").uppercase()} · En fazla ${NovaFileWords.size(maxBytes)}", style = NovaTypeToken.metaQuiet)
            if (!assurance.malwareScanningAvailable) NovaText("Dosya biçimi kontrol edilir; virüs taraması yapılmaz.", style = NovaTypeToken.metaQuiet)
        }
        error?.let { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) }
        val data = payload
        if (data != null) NovaButton("Dosyayı ekle", {
            coroutines.launch {
                busy = true; error = null
                try { outcome = client.file(company, draft, data) } catch (failure: Exception) { error = NovaFileWords.failure(failure) }
                busy = false
            }
        }, Modifier.testTag("file.add.save"), symbol = "arrow.up.doc", enabled = !busy && draft.isReady, loading = busy)
    }
}

/**
 * One "attach a file" field for a module form (iOS `NovaInlineFileField`): shows
 * what is attached, opens the upload inline when there is none.
 */
@Composable
fun NovaInlineFileField(category: String, company: String?, client: NovaFileClient, assetId: String,
                        onAssetId: (String) -> Unit, label: String = "Dosya seç", imagesOnly: Boolean = false, pdfOnly: Boolean = false) {
    var adding by remember { mutableStateOf(false) }
    var catalogue by remember { mutableStateOf<NovaFileLibraryService.Catalogue?>(null) }
    LaunchedEffect(Unit) { catalogue = runCatching { client.catalogue() }.getOrNull() }
    if (assetId.isNotEmpty() && !adding) {
        Row(Modifier.fillMaxWidth().novaControlBackground(16.dp).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            NovaIcon("doc.fill", 14.dp, tint = NovaColorToken.statusSuccessInk.color())
            NovaText("$label ekli", Modifier.weight(1f), NovaTypeToken.meta)
            NovaButton("Dosyayı değiştir", { adding = true }, Modifier.testTag("nova.inline.file.replace"), variant = NovaButtonVariant.Surface,
                symbol = "arrow.triangle.2.circlepath", compact = true)
            Box(Modifier.size(36.dp).novaRowPress { onAssetId("") }.semantics { contentDescription = "Dosyayı kaldır" }
                .testTag("nova.inline.file.remove"), contentAlignment = Alignment.Center) { NovaIcon("xmark.circle", 14.dp) }
        }
    } else {
        val loaded = catalogue
        if (loaded == null) NovaText("Dosya seçenekleri yükleniyor…", style = NovaTypeToken.metaQuiet)
        else {
            val scoped = loaded.categories.filter { it.code == category }.ifEmpty { loaded.categories }
            val accepts = when {
                imagesOnly -> loaded.accepts.filter { it.purpose == "evidence_photo" }
                pdfOnly -> loaded.accepts.mapNotNull { item -> item.copy(extensions = item.extensions.filter { it.equals("pdf", true) }).takeIf { it.extensions.isNotEmpty() } }
                else -> loaded.accepts
            }
            NovaFileAddInline(emptyList(), company, scoped, accepts, loaded.assurance, client, label) { entry ->
                entry?.assetId?.let(onAssetId)
                adding = false
            }
        }
    }
}

/**
 * One presentation owns the company lookup and the company-specific form
 * (iOS `NovaCompanyCreateFlow`). The selected id is handed straight to the
 * form, so the two can never disagree for a frame.
 */
@Composable
fun <C> NovaCompanyCreateFlow(title: String, companies: suspend () -> List<NovaCompanyOption>, catalogue: suspend (String) -> C,
                              fixedCompany: String? = null, onClose: () -> Unit, content: @Composable (C, String) -> Unit) {
    var options by remember { mutableStateOf<List<NovaCompanyOption>>(emptyList()) }
    var search by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf<NovaCompanyOption?>(null) }
    var loaded by remember { mutableStateOf<C?>(null) }
    var busy by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    val coroutines = rememberCoroutineScope()
    suspend fun select(company: NovaCompanyOption) {
        busy = true; failure = null
        try { loaded = catalogue(company.id); selected = company } catch (_: Exception) {
            failure = "Firma bilgileri yüklenemedi. Firma seçimini yeniden deneyin."
        }
        busy = false
    }
    suspend fun load() {
        busy = true; failure = null
        try {
            options = companies().filter { fixedCompany == null || it.id == fixedCompany }
            fixedCompany?.let { id -> options.firstOrNull { it.id == id }?.let { busy = false; select(it) } }
        } catch (_: Exception) { failure = "Firmalar yüklenemedi. Lütfen tekrar deneyin." }
        busy = false
    }
    LaunchedEffect(Unit) { load() }
    val chosen = selected
    val data = loaded
    Column(Modifier.fillMaxSize()) {
        if (chosen != null && data != null) {
            Row(Modifier.padding(horizontal = 20.dp).padding(top = 4.dp).fillMaxWidth().novaControlBackground(14.dp)
                .padding(horizontal = 14.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(9.dp),
                verticalAlignment = Alignment.CenterVertically) {
                NovaIcon("building.2", 17.dp)
                NovaText(chosen.name, Modifier.weight(1f), NovaTypeToken.label, maxLines = 2)
                if (fixedCompany == null) Row(Modifier.heightIn(min = 36.dp).novaRowPress { loaded = null; selected = null },
                    horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaIcon("arrow.left.arrow.right", 12.dp)
                    NovaText("Değiştir", style = NovaTypeToken.micro)
                }
            }
            key(chosen.id) { content(data, chosen.id) }
        } else {
            Row(Modifier.padding(horizontal = 16.dp).padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                NovaBackButton(onClick = onClose)
                NovaText(title, style = NovaTypeToken.screenTitle)
            }
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                NovaHelpHint("Kaydı eklemek istediğiniz firmayı seçin.")
                NovaSearchCapsule(search, "Firma ara", "create.company.search") { search = it }
                if (busy) NovaText("Yükleniyor…", style = NovaTypeToken.metaQuiet)
                failure?.let {
                    NovaText(it, style = NovaTypeToken.meta)
                    NovaButton("Yeniden dene", { coroutines.launch { load() } }, variant = NovaButtonVariant.Surface, compact = true)
                }
                val matches = options.filter { search.isBlank() || novaFold(it.name).contains(novaFold(search)) }
                if (matches.isEmpty() && !busy && failure == null) NovaText(
                    if (options.isEmpty()) "Henüz firma yok. Firmalar bölümünden firma ekleyebilirsiniz." else "Aramanıza uygun firma bulunamadı.")
                matches.forEach { company ->
                    NovaPopupOption(company.name, "building.2", company.detail.ifEmpty { null }, identifier = "create.company.${company.id}") {
                        if (!busy) coroutines.launch { select(company) }
                    }
                }
            }
        }
    }
}

