package com.riskdetectedan.feature.nova

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.riskdetectedan.core.data.analysis.AnalysisCanvas
import com.riskdetectedan.core.data.analysis.AnalysisSector
import com.riskdetectedan.core.data.nova.NovaAnalysisCompanyOption
import com.riskdetectedan.core.data.nova.NovaAnalysisService
import com.riskdetectedan.core.data.profile.SubscriptionTier
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File
import java.text.Normalizer
import java.util.Locale

/** Turns a company's free-text sector into one analysis sector, or into nothing (iOS `NovaSectorMatch`). */
internal object NovaSectorMatch {
    /** Folded under an invariant locale; the dotless ı is mapped by hand so a name typed without diacritics still matches. */
    fun normalize(value: String): String {
        val folded = Normalizer.normalize(value.lowercase(Locale.ROOT), Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").replace('ı', 'i')
        return folded.map { if (it.isLetterOrDigit()) it else ' ' }.joinToString("").split(' ').filter { it.isNotEmpty() }.joinToString(" ")
    }

    private fun names(sector: AnalysisSector): Set<String> = buildSet {
        add(normalize(sector.id.replace('_', ' ')))
        add(normalize(sector.titleTr))
        sector.titleTr.split('/').map(::normalize).filter { it.isNotEmpty() }.forEach(::add)
    } - ""

    /** Exact match, and only when exactly one sector answers: a wrong pre-selection is worse than none. */
    fun suggestion(companySector: String?): String? {
        val needle = normalize(companySector ?: return null).takeIf { it.isNotEmpty() } ?: return null
        return AnalysisSector.entries.filter { needle in names(it) }.singleOrNull()?.id
    }
}

/** What the three intake steps have collected (iOS `NovaAnalysisIntakeDraft`). */
internal data class NovaAnalysisIntakeDraft(
    val photoCount: Int = 0, val companyId: String? = null, val companyName: String? = null, val sectorId: String? = null,
    val sectorCameFromCompany: Boolean = false, val focusIds: List<String> = emptyList(),
) {
    val isReady: Boolean get() = photoCount > 0 && sectorId != null && focusIds.isNotEmpty()

    fun chooseOwner(company: NovaAnalysisCompanyOption?): NovaAnalysisIntakeDraft {
        val suggested = NovaSectorMatch.suggestion(company?.sector)
        return when {
            suggested != null -> copy(companyId = company?.id, companyName = company?.name, sectorId = suggested, sectorCameFromCompany = true)
            // An unrecognised sector leaves a choice the expert made by hand alone.
            sectorCameFromCompany -> copy(companyId = company?.id, companyName = company?.name, sectorId = null, sectorCameFromCompany = false)
            else -> copy(companyId = company?.id, companyName = company?.name)
        }
    }

    fun chooseSector(value: String) = copy(sectorId = value, sectorCameFromCompany = sectorCameFromCompany && sectorId == value)
    fun toggleFocus(value: String) = copy(focusIds = if (value in focusIds) focusIds - value else focusIds + value)
}

internal fun sectorSymbol(sector: AnalysisSector) = when (sector) {
    AnalysisSector.General -> "shield.lefthalf.filled"; AnalysisSector.Construction -> "hammer.fill"; AnalysisSector.Manufacturing -> "gearshape.2.fill"
    AnalysisSector.Mining -> "mountain.2.fill"; AnalysisSector.Energy -> "bolt.fill"; AnalysisSector.Office -> "building.2.fill"
    AnalysisSector.LogisticsWarehouse -> "shippingbox.fill"; AnalysisSector.ChemicalLaboratory -> "flask.fill"
    AnalysisSector.Healthcare -> "cross.case.fill"; AnalysisSector.FoodProduction -> "fork.knife"; AnalysisSector.AgricultureLivestock -> "leaf.fill"
    AnalysisSector.Retail -> "bag.fill"; AnalysisSector.MunicipalFieldServices -> "signpost.right.fill"; AnalysisSector.Education -> "graduationcap.fill"
    AnalysisSector.Hospitality -> "bed.double.fill"
}

/** A JPEG of at most 2048 px on the long side, as both pipelines expect. */
internal fun normalizedAnalysisPhoto(image: Bitmap): ByteArray {
    val scale = minOf(1f, 2048f / maxOf(image.width, image.height))
    val scaled = if (scale < 1f) Bitmap.createScaledBitmap(image, (image.width * scale).toInt(), (image.height * scale).toInt(), true) else image
    return java.io.ByteArrayOutputStream().also { scaled.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
}

/**
 * Fotoğraf Analizi (iOS `NovaPhotoIntakeScreen`): the picture area and one control; everything after this runs in
 * popups.
 */
@Composable
internal fun NovaPhotoIntakeScreen(images: List<Bitmap>, onImages: (List<Bitmap>) -> Unit, onStart: () -> Unit, onBack: () -> Unit, maximum: Int = 3) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    var choosing by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf<Bitmap?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var cameraFile by remember { mutableStateOf<File?>(null) }
    fun add(values: List<Bitmap>) {
        val room = maximum - images.size
        if (room <= 0) { notice = "En fazla $maximum fotoğraf eklenebilir."; return }
        onImages(images + values.take(room))
        if (values.size > room) notice = "En fazla $maximum fotoğraf eklenebilir."
    }
    fun decode(uri: Uri): Bitmap? = runCatching { context.contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream) }.getOrNull()
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(maxOf(2, maximum))) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        val loaded = uris.mapNotNull(::decode)
        if (loaded.isEmpty()) notice = "Seçilen fotoğraflar okunamadı. Tekrar deneyin." else add(loaded)
    }
    val single = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri?.let(::decode)?.let { add(listOf(it)) } ?: uri?.let { notice = "Seçilen fotoğraflar okunamadı. Tekrar deneyin." }
    }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { taken ->
        val file = cameraFile
        if (taken && file != null) BitmapFactory.decodeFile(file.path)?.let { add(listOf(it)) }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).padding(bottom = novaTabBarInset).testTag("photo.intake"),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaBackButton(onClick = onBack)
            NovaText("Fotoğraf Analizi", style = NovaTypeToken.screenTitle)
        }
        NovaHelpHint(if (maximum == 1) "Tek fotoğraf seçin. Fotoğraf bağlı bulunduğunuz firmanın dosyalarına kaydedilir ve analiz sonucu aynı çalışma alanında açılır."
            else "En fazla üç fotoğraf. Firma, sektör ve odak seçimini analizi başlatırken soracağız.")
        if (images.isEmpty()) Column(Modifier.fillMaxWidth().heightIn(min = 168.dp).clip(RoundedCornerShape(20.dp))
            .background(NovaColorToken.surfaceMuted.color()).border(1.6.dp, NovaColorToken.borderStrong.color(), RoundedCornerShape(20.dp))
            .novaRowPress { choosing = true }.semantics { contentDescription = "Fotoğraf ekle" }.testTag("photo.intake.add"),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(9.dp, Alignment.CenterVertically)) {
            NovaIcon("camera", 24.dp)
            NovaText("Fotoğraf çek veya galeriden seç", style = NovaTypeToken.meta, color = NovaColorToken.textTertiary.color())
        } else Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            (images.map<Bitmap, Bitmap?> { it } + List(maxOf(0, maximum - images.size)) { null }).chunked(3).forEachIndexed { row, cells ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    cells.forEachIndexed { column, image ->
                        val index = row * 3 + column
                        Box(Modifier.weight(1f).height(104.dp).clip(RoundedCornerShape(16.dp))) {
                            if (image != null) {
                                Image(image.asImageBitmap(), null, Modifier.fillMaxSize().novaRowPress { preview = image }.testTag("photo.intake.thumbnail.$index"),
                                    contentScale = ContentScale.Crop)
                                Box(Modifier.align(Alignment.TopEnd).padding(5.dp).size(28.dp).clip(CircleShape).background(NovaColorToken.inverse.color().copy(alpha = 0.7f))
                                    .novaRowPress { onImages(images.filterIndexed { i, _ -> i != index }) }.semantics { contentDescription = "Fotoğrafı çıkar" }
                                    .testTag("photo.intake.remove.$index"), contentAlignment = Alignment.Center) {
                                    NovaIcon("xmark", 11.dp, tint = NovaColorToken.onInverse.color())
                                }
                            } else Column(Modifier.fillMaxSize().background(NovaColorToken.surface.color())
                                .border(1.4.dp, NovaColorToken.borderStrong.color(), RoundedCornerShape(16.dp)).novaRowPress { choosing = true }
                                .testTag("photo.intake.add.${index - images.size}"), horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterVertically)) {
                                NovaIcon("plus", 18.dp, tint = NovaColorToken.textTertiary.color())
                                NovaText("Fotoğraf ekle", style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
                            }
                        }
                    }
                    repeat(3 - cells.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            NovaText("${images.size} / $maximum fotoğraf", style = NovaTypeToken.metaQuiet)
        }
        NovaButton("Analizi başlat", onStart, Modifier.testTag("photo.intake.start"), symbol = "sparkles", enabled = images.isNotEmpty())
        if (images.isEmpty()) NovaText("Başlatmak için en az bir fotoğraf ekleyin.", style = NovaTypeToken.metaQuiet)
    }
    NovaChoiceDialog(choosing, "Fotoğrafı nereden ekleyelim?", listOf(
        Triple("Kamera", "camera") {
            val file = File(context.cacheDir, "analysis-${System.currentTimeMillis()}.jpg")
            cameraFile = file
            camera.launch(FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file))
        },
        Triple("Galeri", "photo") {
            val request = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
            if (maximum - images.size > 1) gallery.launch(request) else single.launch(request)
        })) { choosing = false }
    NovaPopup(preview != null, { preview = null }, identifier = "photo.intake.preview") {
        preview?.let { Image(it.asImageBitmap(), "Analiz fotoğrafı", Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)), contentScale = ContentScale.Fit) }
    }
    NovaNoticeDialog(notice, "Fotoğraf", { notice = null })
}

/** Company → sector → focus, once the photos are chosen (iOS `NovaAnalysisIntakePopup`). */
@Composable
internal fun NovaAnalysisIntakePopup(companies: List<NovaAnalysisCompanyOption>, tier: SubscriptionTier?, organization: Boolean,
                                     draft: NovaAnalysisIntakeDraft, onDraft: (NovaAnalysisIntakeDraft) -> Unit, starting: Boolean, onStart: () -> Unit) {
    var step by remember { mutableIntStateOf(0) }
    var query by remember { mutableStateOf("") }
    val needle = NovaSectorMatch.normalize(query)
    val matches = if (needle.isEmpty()) companies else companies.filter { NovaSectorMatch.normalize(it.name).contains(needle) }
    val titles = listOf("Firma seçimi", "Sektör seçimi", "Analiz odağı")
    val hints = listOf("Analizi bir firmaya bağlayabilir ya da firmasız sürdürüp sonradan atayabilirsiniz.",
        "Risk öncelikleri ve öneriler seçtiğiniz sektöre göre uyarlanır.", "En az bir odak seçin. Odak sayısı analizin kapsamını belirler.")
    @Composable fun option(title: String, detail: String, symbol: String, selected: Boolean, tag: String, onClick: () -> Unit) {
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(22.dp)).background(NovaColorToken.surface.color())
            .border(1.dp, if (selected) NovaColorToken.accentInk.color() else androidx.compose.ui.graphics.Color.Transparent, RoundedCornerShape(22.dp))
            .novaRowPress(onClick = onClick).padding(12.dp).testTag(tag), horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically) {
            NovaIcon(symbol, 17.dp, tint = NovaColorToken.textSecondary.color())
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaText(title, style = NovaTypeToken.cardTitle)
                if (detail.isNotEmpty()) NovaText(detail, style = NovaTypeToken.metaQuiet)
            }
            NovaIcon(if (selected) "checkmark.circle.fill" else "circle", 18.dp, tint = if (selected) NovaColorToken.accentInk.color() else NovaColorToken.borderStrong.color())
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (step > 0) Box(Modifier.size(40.dp).clip(CircleShape).novaRowPress(enabled = !starting) { step-- }.semantics { contentDescription = "Geri" }
                .testTag("analysis.intake.back"), contentAlignment = Alignment.Center) { NovaIcon("chevron.left", 14.dp) }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaText(titles[step], style = NovaTypeToken.sheetTitle)
                NovaText("${draft.photoCount} fotoğraf seçildi", style = NovaTypeToken.metaQuiet)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            repeat(3) { index -> Box(Modifier.weight(1f).height(4.dp).clip(CircleShape)
                .background(if (index <= step) NovaColorToken.accent.color() else NovaColorToken.borderMuted.color())) }
        }
        NovaHelpHint(hints[step])
        when (step) {
            0 -> {
                if (companies.size > 4) NovaSearchCapsule(query, "Firma ara", "analysis.intake.owner.search") { query = it }
                option("Firmasız devam et", "Analiz hesabınızda kalır; sonradan bir firmaya atayabilirsiniz.", "person", draft.companyId == null,
                    "analysis.intake.owner.none") { onDraft(draft.chooseOwner(null)) }
                if (companies.isEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                    NovaText("Bu hesapta pilot firma yok. Firmasız devam edebilirsiniz.", style = NovaTypeToken.metaQuiet)
                } else if (matches.isEmpty()) NovaCard(Modifier.fillMaxWidth(), padding = 14) { NovaText("Aramayla eşleşen firma yok.", style = NovaTypeToken.metaQuiet) }
                matches.forEach { company ->
                    val sector = company.sector?.trim().orEmpty()
                    val detail = if (sector.isEmpty()) company.detail else listOf(company.detail, sector + if (NovaSectorMatch.suggestion(sector) == null)
                        " · sektör tanınmadı" else "").filter { it.isNotEmpty() }.joinToString(" · ")
                    option(company.name, detail, "building.2", draft.companyId == company.id, "analysis.intake.owner.${company.id.lowercase()}") {
                        onDraft(draft.chooseOwner(company))
                    }
                }
            }
            1 -> {
                if (draft.sectorCameFromCompany && draft.companyName != null) NovaCard(Modifier.fillMaxWidth().testTag("analysis.intake.sector.auto"), padding = 11,
                    tint = NovaColorToken.statusInfoBg.color()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NovaIcon("sparkle", 14.dp, tint = NovaColorToken.statusInfoInk.color())
                        NovaText("${draft.companyName} firmasının sektörü otomatik seçildi. İsterseniz değiştirebilirsiniz.", style = NovaTypeToken.metaQuiet,
                            color = NovaColorToken.statusInfoInk.color())
                    }
                }
                AnalysisSector.entries.chunked(2).forEach { pair ->
                    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        pair.forEach { sector ->
                            val selected = draft.sectorId == sector.id
                            Column(Modifier.weight(1f).heightIn(min = 70.dp).clip(RoundedCornerShape(22.dp))
                                .background(if (selected) NovaColorToken.statusSuccessBg.color() else NovaColorToken.surface.color())
                                .border(1.dp, if (selected) NovaColorToken.accentInk.color() else androidx.compose.ui.graphics.Color.Transparent, RoundedCornerShape(22.dp))
                                .novaRowPress { onDraft(draft.chooseSector(sector.id)) }.padding(10.dp).testTag("analysis.intake.sector.${sector.id}"),
                                verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                NovaIcon(sectorSymbol(sector), 16.dp, tint = if (selected) NovaColorToken.accentInk.color() else NovaColorToken.textSecondary.color())
                                NovaText(sector.titleTr, style = NovaTypeToken.cardTitle)
                            }
                        }
                        if (pair.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
            else -> AnalysisCanvas.all.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    pair.forEach { focus ->
                        val selected = focus.id in draft.focusIds
                        val locked = !organization && tier?.includes(focus.minTier) != true
                        Column(Modifier.weight(1f).heightIn(min = 94.dp).alpha(if (locked) 0.55f else 1f).clip(RoundedCornerShape(22.dp))
                            .background(if (selected) NovaColorToken.statusSuccessBg.color() else NovaColorToken.surface.color())
                            .border(1.dp, if (selected) NovaColorToken.accentInk.color() else androidx.compose.ui.graphics.Color.Transparent, RoundedCornerShape(22.dp))
                            .novaRowPress(enabled = !locked) { onDraft(draft.toggleFocus(focus.id)) }.padding(10.dp).testTag("analysis.intake.focus.${focus.id}"),
                            verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                NovaIcon(focus.icon, 16.dp, tint = if (selected) NovaColorToken.accentInk.color() else NovaColorToken.textSecondary.color())
                                Spacer(Modifier.weight(1f))
                                NovaIcon(if (selected) "checkmark.square.fill" else "square", 16.dp,
                                    tint = if (selected && !locked) NovaColorToken.accentInk.color() else NovaColorToken.borderStrong.color())
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                NovaText(focus.title, style = NovaTypeToken.cardTitle)
                                if (locked) NovaStatusPill(focus.minTier.name, NovaStatus.Neutral, showsDot = false)
                            }
                            NovaText(focus.body, style = NovaTypeToken.metaQuiet, maxLines = 3)
                        }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
        when (step) {
            0 -> NovaButton("Devam et", { step = 1 }, Modifier.testTag("analysis.intake.continue.owner"), symbol = "chevron.right")
            1 -> NovaButton("Devam et", { step = 2 }, Modifier.testTag("analysis.intake.continue.sector"), symbol = "chevron.right", enabled = draft.sectorId != null)
            else -> Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                NovaButton("Analizi başlat", onStart, Modifier.testTag("analysis.intake.start"), symbol = "sparkles", enabled = draft.isReady, loading = starting)
                if (!draft.isReady) NovaText("Başlatmak için en az bir odak seçin.", style = NovaTypeToken.metaQuiet)
            }
        }
    }
}

/** The waiting page while the pipeline runs (iOS `AnalyzingView`); progress follows the real stage. */
@Composable
internal fun NovaAnalyzingScreen(preview: Bitmap?, photoCount: Int, stage: NovaAnalysisService.Progress?) {
    BackHandler {}
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(stage) { tick = 0; while (true) { delay(1_000); tick++ } }
    val base = when (stage) {
        NovaAnalysisService.Progress.creatingAnalysis -> 12; NovaAnalysisService.Progress.uploadingPhotos -> 24
        NovaAnalysisService.Progress.queued -> 40; NovaAnalysisService.Progress.analyzing -> 55; null -> 5
    }
    val ceiling = if (stage == NovaAnalysisService.Progress.analyzing) 94 else base + 10
    val percent = minOf(ceiling, base + tick / 2)
    val message = when (stage) {
        NovaAnalysisService.Progress.creatingAnalysis -> "Analiz kaydı oluşturuluyor."
        NovaAnalysisService.Progress.uploadingPhotos -> if (photoCount > 1) "Fotoğraflar güvenli depoya yükleniyor." else "Fotoğraf güvenli depoya yükleniyor."
        NovaAnalysisService.Progress.queued -> "Analiz kuyruğa alındı, sonuç düzenli olarak kontrol ediliyor."
        NovaAnalysisService.Progress.analyzing -> "AI, iş güvenliği bulgularını ve risk seviyelerini çıkarıyor."
        null -> "Fotoğraflar analiz için hazırlanıyor."
    }
    val signals = listOf("Görüntü kalitesi okunuyor", "Risk sinyalleri tanımlanıyor", "KKD ve çevresel kontroller", "Bulgular yapılandırılıyor")
    Column(Modifier.fillMaxSize().padding(24.dp).testTag("analysis.analyzing"), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically)) {
        NovaText("Analiz devam ediyor", style = NovaTypeToken.screenTitle)
        Box(Modifier.size(220.dp).clip(RoundedCornerShape(24.dp)).background(NovaColorToken.surfaceMuted.color()), contentAlignment = Alignment.Center) {
            if (preview != null) Image(preview.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            else NovaText("Analiz ediliyor", style = NovaTypeToken.meta)
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                NovaText("%$percent", Modifier.weight(1f), NovaTypeToken.sectionTitle)
                NovaAnalysisFact("photo", "$photoCount fotoğraf")
            }
            Box(Modifier.fillMaxWidth().height(6.dp).clip(CircleShape).background(NovaColorToken.borderMuted.color())
                .semantics { contentDescription = "Analiz ilerleme, %$percent" }) {
                Box(Modifier.fillMaxWidth(percent / 100f).fillMaxHeight().clip(CircleShape).background(NovaColorToken.accent.color()))
            }
            NovaText(message, style = NovaTypeToken.metaQuiet)
        }
        NovaCard(Modifier.fillMaxWidth(), padding = 14) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                signals.forEachIndexed { index, label ->
                    val done = stage == NovaAnalysisService.Progress.analyzing && tick / 6 > index
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        NovaIcon(if (done) "checkmark.circle.fill" else "circle", 14.dp, tint = if (done) NovaColorToken.accentInk.color() else NovaColorToken.borderStrong.color())
                        NovaText(label, style = NovaTypeToken.meta)
                    }
                }
            }
        }
    }
}

/** Decodes the chosen pictures off the main thread for the pipeline. */
internal suspend fun analysisPhotoBytes(images: List<Bitmap>): List<ByteArray> = withContext(Dispatchers.Default) { images.map(::normalizedAnalysisPhoto) }
