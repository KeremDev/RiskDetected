package com.riskdetectedan.feature.nova

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.launch
import java.io.File
import java.util.UUID

/** Uygunsuzluk Ekle: from an analysis, by hand, or by analysing a new photo first. */
@Composable
fun NovaAddFindingScreen(hasCompanies: Boolean, onAnalyses: () -> Unit, onManual: () -> Unit, onNewAnalysis: () -> Unit,
                         onCompanies: () -> Unit, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).padding(bottom = novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaBackButton(onClick = onBack)
            NovaText(NovaDestination.newFinding.title, style = NovaTypeToken.screenTitle)
        }
        NovaHelpHint("Daha önce yaptığınız bir analizin bulgularından seçebilir ya da kaydı kendiniz girebilirsiniz.")
        ChoiceCard("Analiz bulgularından seç", "Bir analizi açın, bulguları seçin ve firmaya uygunsuzluk olarak aktarın.") {
            NovaButton(NovaDestination.analyses.title, onAnalyses, Modifier.testTag("addfinding.analyses"), symbol = "photo.on.rectangle.angled")
        }
        ChoiceCard("Kendim gireceğim", "Fotoğraf, firma, tehlike, skorlama, mevzuat ve sorumlu adım adım sorulur.") {
            NovaButton("Forma geç", onManual, Modifier.testTag("addfinding.manual"), variant = NovaButtonVariant.Surface,
                symbol = "square.and.pencil", enabled = hasCompanies)
            if (!hasCompanies) {
                NovaText("Bu hesapta kayıt açılacak firma yok.", style = NovaTypeToken.metaQuiet)
                NovaButton(NovaDestination.companies.title, onCompanies, Modifier.testTag("addfinding.companies"),
                    variant = NovaButtonVariant.Surface, symbol = "building.2")
            }
        }
        ChoiceCard(NovaDestination.newAnalysis.title, "Elinizde yeni bir fotoğraf varsa önce analiz edin.") {
            NovaButton("Fotoğraf seç", onNewAnalysis, Modifier.testTag("addfinding.photo"), variant = NovaButtonVariant.Surface, symbol = "camera")
        }
    }
}

@Composable
private fun ChoiceCard(title: String, detail: String, actions: @Composable ColumnScope.() -> Unit) {
    NovaCard(Modifier.fillMaxWidth(), padding = 16) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaText(title, style = NovaTypeToken.cardTitle)
            NovaText(detail, style = NovaTypeToken.metaQuiet)
            actions()
        }
    }
}

private fun NovaManualStep.title() = when (this) {
    NovaManualStep.photo -> "Fotoğraf"; NovaManualStep.company -> "Firma"; NovaManualStep.hazard -> "Uygunsuzluk"
    NovaManualStep.scoring -> "Risk metodu ve skorlama"; NovaManualStep.legislation -> "Mevzuat bilgisi"
    NovaManualStep.responsible -> "Firma sorumlusu"
}
private fun NovaManualStep.symbol() = when (this) {
    NovaManualStep.photo -> "camera"; NovaManualStep.company -> "building.2"; NovaManualStep.hazard -> "exclamationmark.triangle"
    NovaManualStep.scoring -> "chart.bar"; NovaManualStep.legislation -> "doc.text"; NovaManualStep.responsible -> "person.crop.rectangle"
}

/**
 * The hand-entered record, one step at a time (iOS `NovaManualNonconformityScreen`).
 * A finished step carries a tick and the bar counts only finished steps.
 */
@Composable
fun NovaManualNonconformityScreen(companies: List<NovaCompanyOption>, workplaces: suspend (String) -> List<NovaNonconformityWorkplace>,
                                  save: suspend (NovaManualDraft, List<Bitmap>) -> String?, onBack: () -> Unit,
                                  isImprovementAllowed: Boolean = true) {
    val context = LocalContext.current
    val coroutines = rememberCoroutineScope()
    var draft by remember { mutableStateOf(NovaManualDraft()) }
    var open by remember { mutableStateOf<NovaManualStep?>(NovaManualStep.photo) }
    var places by remember { mutableStateOf<List<NovaNonconformityWorkplace>>(emptyList()) }
    var loadingPlaces by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val photos = remember { mutableStateListOf<Bitmap>() }
    var choosing by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf<Bitmap?>(null) }
    var cameraFile by remember { mutableStateOf<File?>(null) }
    fun decode(uri: Uri): Bitmap? = runCatching {
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
    }.getOrNull()
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(3)) { uris ->
        uris.take(3 - photos.size).mapNotNull(::decode).forEach(photos::add)
        draft = draft.copy(photoCount = photos.size)
    }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { taken ->
        val file = cameraFile
        if (taken && file != null) BitmapFactory.decodeFile(file.path)?.let { photos.add(it); draft = draft.copy(photoCount = photos.size) }
    }
    fun launchCamera() {
        val file = File(File(context.cacheDir, "nova").apply { mkdirs() }, "capture-${UUID.randomUUID()}.jpg")
        cameraFile = file
        camera.launch(FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file))
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).padding(bottom = novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            NovaBackButton(enabled = !saving, onClick = onBack)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                NovaText("Elle Uygunsuzluk", style = NovaTypeToken.screenTitle, maxLines = 1)
                NovaText("Yapay zekâ kullanılmaz; bilgileri siz girersiniz.", style = NovaTypeToken.metaQuiet)
            }
        }
        NovaCard(Modifier.fillMaxWidth().testTag("manual.progress"), padding = 12) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    NovaText("${draft.completedCount}/${NovaManualStep.entries.size} başlık tamamlandı", Modifier.weight(1f), NovaTypeToken.label)
                    if (draft.canSave) NovaStatusPill("Kaydedilebilir", NovaStatus.Success) else NovaStatusPill("Zorunlu alan eksik", NovaStatus.Warning)
                }
                val progress by animateFloatAsState(draft.progress, NovaMotion.easeOut(NovaMotion.Duration.progress), label = "manual")
                Box(Modifier.fillMaxWidth().height(6.dp).background(NovaColorToken.borderMuted.color(), CircleShape)) {
                    Box(Modifier.fillMaxWidth(progress).fillMaxHeight().background(NovaColorToken.accent.color(), CircleShape))
                }
                NovaText("Fotoğraf, mevzuat, sorumlu ve skorlama isteğe bağlıdır; girildiğinde tamamlandı sayılır.", style = NovaTypeToken.metaQuiet)
            }
        }
        NovaManualStep.entries.forEach { step ->
            NovaCompanyAccordion(step.title(), step.symbol(), open == step, { open = if (it) step else null },
                state = if (draft.isComplete(step)) NovaCompletionState.complete else NovaCompletionState.missing,
                identifier = "manual.step.${step.name}") {
                when (step) {
                    NovaManualStep.photo -> PhotoStep(photos, onAdd = { choosing = true }, onPreview = { preview = it }) { index ->
                        photos.removeAt(index); draft = draft.copy(photoCount = photos.size)
                    }
                    NovaManualStep.company -> {
                        if (companies.isEmpty()) NovaText("Bu hesapta kayıt açılacak firma yok.", style = NovaTypeToken.metaQuiet)
                        companies.forEach { company ->
                            NovaRadioRow(company.name, draft.companyId == company.id, company.detail, "manual.company.${company.id.lowercase()}") {
                                draft = draft.copy(companyId = company.id, workplaceId = null)
                                places = emptyList(); loadingPlaces = true
                                coroutines.launch {
                                    places = runCatching { workplaces(company.id) }.getOrDefault(emptyList())
                                    loadingPlaces = false
                                    // The record lands on a real workplace; the first one is used and named.
                                    draft = draft.copy(workplaceId = places.firstOrNull()?.id)
                                }
                            }
                        }
                        if (draft.companyId != null) {
                            Box(Modifier.fillMaxWidth().height(1.dp).background(NovaColorToken.hairline.color()))
                            NovaText("İşyeri / departman · isteğe bağlı", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
                            when {
                                loadingPlaces -> NovaText("İşyerleri yükleniyor…", style = NovaTypeToken.metaQuiet)
                                places.isEmpty() -> NovaText("Bu firmada kayıt açılacak bir işyeri yok.", style = NovaTypeToken.metaQuiet)
                                places.size == 1 -> NovaText("Kayıt ${places[0].name} işyerine açılacak.", style = NovaTypeToken.micro,
                                    color = NovaColorToken.textTertiary.color())
                                else -> {
                                    places.forEach { place ->
                                        NovaRadioRow(place.name, draft.workplaceId == place.id, identifier = "manual.workplace.${place.id.lowercase()}") {
                                            draft = draft.copy(workplaceId = place.id)
                                        }
                                    }
                                    places.firstOrNull { it.id == draft.workplaceId }?.let {
                                        NovaText("Kayıt ${it.name} işyerine açılacak.", style = NovaTypeToken.micro, color = NovaColorToken.textTertiary.color())
                                    }
                                }
                            }
                        }
                    }
                    NovaManualStep.hazard -> {
                        NovaTextField("Tehlike başlığı", draft.title, { draft = draft.copy(title = it) }, identifier = "manual.field.title")
                        NovaTextField("Açıklama", draft.hazardDescription, { draft = draft.copy(hazardDescription = it) },
                            identifier = "manual.field.description", multiline = true)
                        NovaTextField("Önlem", draft.controlMeasure, { draft = draft.copy(controlMeasure = it) },
                            identifier = "manual.field.measure", multiline = true)
                        NovaText("Önem derecesi", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
                        NovaSegmented(NovaNonconformitySeverity.entries.map { it to NovaNonconformityWords.severity(it) }, draft.severity,
                            { draft = draft.copy(severity = it) }, identifier = "manual.field.severity")
                        if (isImprovementAllowed) {
                            NovaText("Kayıt türü", style = NovaTypeToken.label, color = NovaColorToken.textTertiary.color())
                            NovaSegmented(NovaNonconformityRecordKind.entries.map { it to NovaNonconformityWords.recordKind(it) }, draft.recordKind,
                                { draft = draft.copy(recordKind = it) }, identifier = "manual.field.kind")
                        }
                    }
                    NovaManualStep.scoring -> NovaRiskScoreEditor(draft.score, { draft = draft.copy(score = it) })
                    NovaManualStep.legislation -> NovaTextField("İlgili madde, yönetmelik veya standart", draft.legislation,
                        { draft = draft.copy(legislation = it) }, identifier = "manual.field.legislation", multiline = true)
                    NovaManualStep.responsible -> {
                        NovaTextField("Firmadaki sorumlu kişi", draft.responsible, { draft = draft.copy(responsible = it) },
                            identifier = "manual.field.responsible")
                        NovaText("Bu kişi bir uygulama kullanıcısı değildir; yalnız kayıtta görünür.", style = NovaTypeToken.metaQuiet)
                    }
                }
                val next = if (draft.isComplete(step)) draft.nextIncomplete(step) else null
                if (next != null) NovaButton("Sıradaki: ${next.title()}", { open = next }, Modifier.testTag("manual.next.${step.name}"),
                    variant = NovaButtonVariant.Surface, symbol = "chevron.down")
            }
        }
        error?.let { NovaCard(Modifier.fillMaxWidth(), padding = 14) { NovaText(it, style = NovaTypeToken.metaQuiet, color = NovaColorToken.statusDangerInk.color()) } }
        NovaButton("Kaydı aç", {
            coroutines.launch {
                saving = true; error = null
                error = save(draft, photos.toList())
                saving = false
            }
        }, Modifier.testTag("manual.save"), symbol = "checkmark", enabled = draft.canSave && !saving, loading = saving)
    }
    NovaChoiceDialog(choosing, "Fotoğrafı nereden ekleyelim?", listOf(
        Triple("Kamera", "camera") { launchCamera() },
        Triple("Galeri", "photo") { gallery.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
    )) { choosing = false }
    NovaPopup(preview != null, { preview = null }) {
        preview?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)), contentScale = ContentScale.Fit) }
    }
}

@Composable
private fun PhotoStep(photos: List<Bitmap>, onAdd: () -> Unit, onPreview: (Bitmap) -> Unit, onRemove: (Int) -> Unit) {
    if (photos.isEmpty()) {
        val dash = NovaColorToken.borderStrong.color()
        Column(Modifier.fillMaxWidth().heightIn(min = 104.dp).clip(RoundedCornerShape(16.dp))
            .background(NovaColorToken.surfaceMuted.color(), RoundedCornerShape(16.dp))
            .drawBehind {
                drawRoundRect(dash, cornerRadius = CornerRadius(16.dp.toPx()),
                    style = Stroke(1.4.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))))
            }
            .novaRowPress(onClick = onAdd).testTag("manual.photo.add"),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterVertically)) {
            NovaIcon("camera", 24.dp, tint = NovaColorToken.textTertiary.color())
            NovaText("Fotoğraf çek veya galeriden seç", style = NovaTypeToken.meta, color = NovaColorToken.textTertiary.color())
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            photos.forEachIndexed { index, image ->
                Box(Modifier.weight(1f).height(92.dp).clip(RoundedCornerShape(14.dp)).novaRowPress { onPreview(image) }
                    .testTag("manual.photo.thumbnail.$index")) {
                    Image(image.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    Box(Modifier.align(Alignment.TopEnd).padding(4.dp).size(26.dp).background(NovaColorToken.surface.color().copy(alpha = 0.85f), CircleShape)
                        .novaPress { onRemove(index) }.semantics { contentDescription = "Fotoğrafı çıkar" }, contentAlignment = Alignment.Center) {
                        NovaIcon("xmark", 11.dp)
                    }
                }
            }
            if (photos.size < 3) Box(Modifier.weight(1f).height(92.dp).clip(RoundedCornerShape(14.dp))
                .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(14.dp)).novaRowPress(onClick = onAdd)
                .semantics { contentDescription = "Fotoğraf ekle" }.testTag("manual.photo.add"), contentAlignment = Alignment.Center) {
                NovaIcon("plus", 18.dp, tint = NovaColorToken.textTertiary.color())
            }
            repeat((2 - photos.size).coerceAtLeast(0)) { Spacer(Modifier.weight(1f)) }
        }
    }
}
