package com.riskdetectedan.feature.nova

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.core.content.res.ResourcesCompat
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.format.DateTimeFormatter

/** The personal education certificate as A4 pages (iOS `NovaEducationCertificatePDF`), padded to an even count for duplex printing. */
internal object NovaEducationCertificatePDF {
    private const val RENDERER_VERSION = 1
    private const val WIDTH = 527
    private data class Block(val text: String, val size: Float = 10f, val bold: Boolean = false, val space: Int = 6, val reserved: Int = 0)
    private data class Placed(val layout: StaticLayout, val y: Int)

    private fun hazard(value: String) = mapOf("low" to "Az tehlikeli", "medium" to "Tehlikeli", "high" to "Çok tehlikeli",
        "hazardous" to "Tehlikeli", "very_hazardous" to "Çok tehlikeli")[value] ?: value

    /** A numbered certificate renders once per revision; a draft always renders afresh. */
    fun file(context: Context, certificate: NovaEducationCertificate): File {
        val snapshot = certificate.snapshot
        val folder = File(context.cacheDir, "nova/education/${certificate.ownerId.lowercase()}").apply { check(isDirectory || mkdirs()) }
        val name = certificate.documentId?.let { "${it.lowercase()}-r${certificate.revision ?: 0}-renderer$RENDERER_VERSION" }
            ?: "draft-${snapshot.sourceSessionId}-${snapshot.person.id}"
        val file = File(folder, "$name.pdf")
        if (!snapshot.isDraft && file.exists()) return file
        val temp = File(folder, "$name.tmp")
        temp.writeBytes(render(context, snapshot))
        check(temp.renameTo(file))
        return file
    }

    private fun render(context: Context, snapshot: NovaEducationCertificate.Snapshot): ByteArray {
        val scope = snapshot.scope
        val regular = ResourcesCompat.getFont(context, com.riskdetectedan.core.designsystem.R.font.plus_jakarta_sans_regular)
        val bold = ResourcesCompat.getFont(context, com.riskdetectedan.core.designsystem.R.font.plus_jakarta_sans_bold)
        val logo = snapshot.logoPngBase64?.let { encoded ->
            runCatching { android.util.Base64.decode(encoded, android.util.Base64.DEFAULT).let { BitmapFactory.decodeByteArray(it, 0, it.size) } }.getOrNull()
        }
        fun layout(block: Block, text: String = block.text): StaticLayout {
            val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = block.size; typeface = if (block.bold) bold else regular; color = if (block.bold) Color.rgb(20, 38, 64) else Color.BLACK
            }
            return StaticLayout.Builder.obtain(text, 0, text.length, paint, WIDTH).setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setIncludePad(false).setLineSpacing(2f, 1f).build()
        }
        fun signature(text: String) = Block(text, reserved = layout(Block(text)).height + 64)
        val start = DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm").withZone(NovaEducationClock.zone)
        val end = DateTimeFormatter.ofPattern("HH:mm").withZone(NovaEducationClock.zone)
        val times = scope.lessons.groupBy { NovaEducationClock.date(it.startsAt)?.let(NovaEducationClock::day).orEmpty() }.toSortedMap().values.mapNotNull { list ->
            val sorted = list.sortedBy { it.startsAt }
            val first = NovaEducationClock.date(sorted.first().startsAt) ?: return@mapNotNull null
            val last = sorted.last()
            val lastStart = NovaEducationClock.date(last.startsAt) ?: return@mapNotNull null
            start.format(first) + "–" + end.format(lastStart.plusSeconds((last.instructionMinutes + last.breakMinutes) * 60L))
        }
        val methods = scope.topics.map { it.method }.toSet()
        val total = scope.instructionMinutes + scope.breakMinutes
        val front = mutableListOf(
            Block(scope.legalName, 15f, true, 14),
            Block((if (snapshot.isDraft) "TASLAK · " else "") + snapshot.title, 21f, true, 18),
            Block(snapshot.person.name.orEmpty(), 18f, true),
            Block("Unvan: " + snapshot.person.jobTitle.ifEmpty { "Eksik" }, 11f),
            Block("İşyeri: ${scope.workplaceName} · ${hazard(scope.hazardClass)}"),
            Block("Düzenleyen: ${snapshot.providerName}", 11f),
            Block("Eğitim: ${NovaEducationScope.cycleName(scope.cycle)}", 11f),
            Block("Gerçekleşen gün ve saatler (Europe/Istanbul)\n" + times.joinToString("\n")),
            Block("Süre: ${scope.instructionMinutes} dk öğretim + ${scope.breakMinutes} dk ara = $total dk", 11f, true),
            Block("Yöntem: " + (if (methods.size > 1) "Karma" else NovaTrainingWords.method(methods.firstOrNull() ?: "face_to_face")) +
                " · Konu bazında yöntem arka yüzde gösterilmiştir."),
            Block("Düzenleme: ${snapshot.issuedOn}" + (scope.validUntil?.let { " · Tekrar tarihi: $it" } ?: "")),
            Block(if (snapshot.isDraft) "TASLAK — Belge numarası tahsis edilmemiştir. Eğitim ve belge bilgileri tamamlanmadan başarı belgesi olarak kullanılamaz."
                else "Yukarıda bilgileri bulunan çalışan, belirtilen tarihlerde gerçekleştirilen ve içeriği izleyen sayfalarda yer alan eğitimi başarıyla tamamlamıştır.",
                11f, space = 12),
            Block("Eğiticiler ve imza alanları", 11f, true),
        )
        snapshot.trainers.forEach { trainer ->
            val groups = scope.topics.filter { topic -> topic.trainerIds.any { it.sameId(trainer.id) } }.map { it.group }.distinct().sorted()
            front += signature("${trainer.name} · ${trainer.title}\nKonu kapsamı: ${groups.joinToString(", ")}\nİmza:")
        }
        front += signature((if (scope.employerCapacity == "employer") "İşveren" else "İşveren vekili") + ": ${scope.employerName}\nİmza / kaşe:")
        front += Block("Belge, düzenleyen uzmanın kaydına ve beyanına dayanır. İmza alanları fiziki imza için boş bırakılmıştır.", 8f)
        val back = mutableListOf(Block("EĞİTİM KONULARI VE SÜRELERİ", 16f, true, 12))
        listOf("G1" to "Genel konular", "G2" to "Sağlık konuları", "G3" to "Teknik konular", "G4" to "İşyerine özgü riskler").forEach { (group, title) ->
            val topics = scope.topics.filter { it.group == group }
            if (topics.isEmpty()) return@forEach
            back += Block("$group · $title · ${topics.sumOf { it.instructionMinutes }} dk", 11f, true)
            topics.forEach { topic ->
                val label = if (topic.parentCode == null) topic.title else topic.legalTitle.orEmpty() + ": " + topic.title
                back += Block("${topic.parentCode ?: topic.code}  $label — ${topic.instructionMinutes} dk · ${NovaTrainingWords.method(topic.method)}", 9f, space = 3)
            }
        }
        back += Block("İşyeri / görev bağlamı: ${scope.contextNote}", 9f, space = 8)
        back += Block("Öğretim: ${scope.instructionMinutes} dk · Ara: ${scope.breakMinutes} dk · Toplam: $total dk", 10f, true)
        // Paragraphs split by measured lines, so a long context never clips or shrinks to illegibility.
        val pages = mutableListOf<List<Placed>>()
        fun paginate(blocks: List<Block>) {
            var rows = mutableListOf<Placed>(); var y = 52
            blocks.forEach { block ->
                var text = block.text
                do {
                    val all = layout(block, text); val available = 782 - y
                    if (block.reserved > available || all.getLineBottom(0) > available) { pages += rows; rows = mutableListOf(); y = 52 }
                    else {
                        var lines = 0
                        while (lines < all.lineCount && all.getLineBottom(lines) <= available) lines++
                        val cut = all.getLineEnd(lines - 1); val piece = layout(block, text.substring(0, cut))
                        rows += Placed(piece, y); y += maxOf(piece.height, block.reserved) + block.space; text = text.substring(cut)
                        if (text.isNotEmpty()) { pages += rows; rows = mutableListOf(); y = 52 }
                    }
                } while (text.isNotEmpty())
            }
            if (rows.isNotEmpty()) pages += rows
        }
        if (logo != null) front.add(0, Block(" ", reserved = 60))
        paginate(front); paginate(back)
        if (pages.size % 2 != 0) pages += listOf(Placed(layout(Block("Bu sayfa çift taraflı baskı düzeni için boş bırakılmıştır.", 11f)), 400))
        val document = PdfDocument()
        try {
            pages.forEachIndexed { index, rows ->
                val page = document.startPage(PdfDocument.PageInfo.Builder(595, 842, index + 1).create())
                val canvas = page.canvas
                canvas.drawColor(Color.WHITE)
                canvas.drawRect(34f, 34f, 561f, 36f, Paint().apply { color = Color.rgb(26, 102, 115) })
                if (index == 0 && logo != null && logo.width > 0 && logo.height > 0) {
                    val factor = minOf(120f / logo.width, 50f / logo.height)
                    canvas.drawBitmap(logo, null, RectF(34f, 52f, 34f + logo.width * factor, 52f + logo.height * factor),
                        Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
                }
                rows.forEach { row -> canvas.save(); canvas.translate(34f, row.y.toFloat()); row.layout.draw(canvas); canvas.restore() }
                val footer = "${snapshot.person.name.orEmpty()} · ${if (snapshot.isDraft) "TASLAK" else snapshot.number} · R${snapshot.revision} · ${index + 1}/${pages.size}"
                canvas.save(); canvas.translate(34f, 801f); layout(Block(footer, 8f)).draw(canvas); canvas.restore()
                document.finishPage(page)
            }
            return java.io.ByteArrayOutputStream().also(document::writeTo).toByteArray()
        } finally { document.close(); logo?.recycle() }
    }

    /** Every page as a bitmap for the on-screen preview (iOS `PDFView`). */
    fun pages(file: File): List<Bitmap> = PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)).use { pdf ->
        (0 until pdf.pageCount).map { index ->
            pdf.openPage(index).use { page ->
                Bitmap.createBitmap(page.width * 2, page.height * 2, Bitmap.Config.ARGB_8888).also {
                    it.eraseColor(Color.WHITE); page.render(it, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                }
            }
        }
    }
}

/** Hands the finished PDF to the system print dialog as A4, long-edge duplex. */
private class NovaPdfPrint(private val file: File) : PrintDocumentAdapter() {
    override fun onLayout(oldAttributes: PrintAttributes?, newAttributes: PrintAttributes?, signal: android.os.CancellationSignal,
                          callback: LayoutResultCallback, extras: android.os.Bundle?) {
        if (signal.isCanceled) { callback.onLayoutCancelled(); return }
        callback.onLayoutFinished(PrintDocumentInfo.Builder(file.name).setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT).build(), oldAttributes != newAttributes)
    }
    override fun onWrite(pages: Array<out PageRange>, destination: ParcelFileDescriptor, signal: android.os.CancellationSignal, callback: WriteResultCallback) {
        if (signal.isCanceled) { callback.onWriteCancelled(); return }
        try {
            java.io.FileOutputStream(destination.fileDescriptor).use { out -> file.inputStream().use { it.copyTo(out) } }
            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
        } catch (_: Exception) { callback.onWriteFailed("Belge yazdırılamadı.") }
    }
}

/**
 * One participant's certificate (iOS `NovaEducationCertificateScreen`): a numberless draft
 * preview until every field is complete, then one issue that allocates the number.
 */
@Composable
internal fun NovaEducationCertificateScreen(client: NovaTrainingClient, session: NovaTrainingSession, scopeId: String, personId: String,
                                            canIssue: Boolean, documentId: String?, documentRevision: Int?, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val context = LocalContext.current
    val coroutines = rememberCoroutineScope()
    var current by remember { mutableStateOf(session) }
    var editable by remember { mutableStateOf(session.education?.let { NovaEducationDraft.of(session, it) }) }
    var issued by remember { mutableStateOf(NovaDay.today()) }
    var logo by remember { mutableStateOf<String?>(null) }
    var result by remember { mutableStateOf<NovaEducationCertificate?>(null) }
    var file by remember { mutableStateOf<File?>(null) }
    var pages by remember { mutableStateOf<List<Bitmap>>(emptyList()) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var fieldsOpen by remember { mutableStateOf(false) }
    val fieldsChanged = editable?.let { value -> current.education?.let { value.scopes != it.scopes || value.trainers != it.trainers || value.providerName != it.providerName } } ?: false
    suspend fun load(issue: Boolean) {
        busy = true; error = null
        try {
            val request = if (!issue && documentId != null) NovaEducationCertificateRequest("read", documentId = documentId, revision = documentRevision)
                else NovaEducationCertificateRequest(if (issue) "issue" else "preview", session.id, scopeId, personId, current.version, issued, logoPngBase64 = logo)
            val certificate = client.certificate(request)
            val rendered = withContext(Dispatchers.IO) { NovaEducationCertificatePDF.file(context, certificate).let { it to NovaEducationCertificatePDF.pages(it) } }
            file = rendered.first; pages = rendered.second; result = certificate
        } catch (failure: Exception) { error = NovaTrainingWords.message(failure) }
        busy = false
    }
    val saveLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        val source = file
        if (uri != null && source != null) runCatching {
            context.contentResolver.openOutputStream(uri)?.use { out -> source.inputStream().use { it.copyTo(out) } }
        }.onFailure { error = "Dosya kaydedilemedi." }
    }
    LaunchedEffect(Unit) {
        if (documentId == null) logo = runCatching { client.logo(session.education?.scopes?.firstOrNull { it.id.sameId(scopeId) }?.logoPath) }.getOrNull()
        load(false)
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 24.dp + novaTabBarInset),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        NovaPageHeading("Kişisel eğitim belgesi", backEnabled = !busy, onBack = onClose)
        if (busy) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { NovaSpinner(NovaColorToken.text.color(), size = 24.dp) }
        error?.let { NovaText(it, style = NovaTypeToken.meta, color = NovaColorToken.statusDangerInk.color()) }
        val shown = result
        if (shown == null) {
            if (!busy) NovaButton("Tekrar dene", { coroutines.launch { load(false) } }, variant = NovaButtonVariant.Surface, symbol = "arrow.clockwise")
            return@Column
        }
        shown.issues.forEach { NovaText(NovaTrainingWords.issue(it), style = NovaTypeToken.meta, color = NovaColorToken.statusWarningInk.color()) }
        val edit = editable
        if (edit != null && shown.snapshot.isDraft) {
            NovaCard(Modifier.fillMaxWidth(), padding = 14) {
                Row(Modifier.fillMaxWidth().novaRowPress { fieldsOpen = !fieldsOpen }.testTag("education.certificate.fields"),
                    verticalAlignment = Alignment.CenterVertically) {
                    NovaText("Eksik belge bilgilerini tamamla", Modifier.weight(1f), NovaTypeToken.bodyStrong)
                    NovaIcon(if (fieldsOpen) "chevron.up" else "chevron.down", 12.dp)
                }
                if (fieldsOpen) Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    NovaTextField("Düzenleyici kişi / kurum", edit.providerName, { editable = edit.copy(providerName = it) }, enabled = canIssue)
                    edit.trainers.forEachIndexed { index, trainer ->
                        fun update(value: NovaEducationTrainer) { editable = edit.copy(trainers = edit.trainers.toMutableList().also { it[index] = value }) }
                        NovaTextField("Eğitici adı", trainer.name, { update(trainer.copy(name = it)) }, enabled = canIssue)
                        NovaTextField("Eğitici unvanı", trainer.title, { update(trainer.copy(title = it)) }, enabled = canIssue)
                    }
                    edit.scopes.forEachIndexed { index, scope ->
                        if (!scope.id.sameId(scopeId)) return@forEachIndexed
                        fun update(value: NovaEducationScope) { editable = edit.copy(scopes = edit.scopes.toMutableList().also { it[index] = value }) }
                        NovaTextField("İşveren / vekili", scope.employerName, { update(scope.copy(employerName = it)) }, enabled = canIssue)
                        NovaTextField("İşyeri tam unvanı", scope.legalName, { update(scope.copy(legalName = it)) }, enabled = canIssue)
                        scope.participants.forEachIndexed { personIndex, person ->
                            if (person.id.sameId(personId)) NovaTextField("Belgeye özel personel unvanı", person.jobTitle, { title ->
                                update(scope.copy(participants = scope.participants.toMutableList().also { it[personIndex] = person.copy(jobTitle = title) }))
                            }, enabled = canIssue)
                        }
                    }
                }
            }
            NovaDayField("Düzenleme tarihi", issued, { picked -> if (picked <= NovaDay.today()) issued = picked }, "education.certificate.issued")
            NovaButton("Belge bilgilerini kaydet ve önizlemeyi yenile", {
                coroutines.launch {
                    busy = true; error = null
                    try {
                        val row = client.save(edit).row
                        val education = row?.education ?: throw NovaTrainingException("UNAVAILABLE")
                        current = row; editable = NovaEducationDraft.of(row, education)
                        load(false)
                    } catch (failure: Exception) { error = NovaTrainingWords.message(failure); busy = false }
                }
            }, variant = NovaButtonVariant.Surface, enabled = !busy && canIssue, symbol = "arrow.clockwise")
        }
        if (shown.issues.isNotEmpty()) NovaText("Alanları eğitim formunda tamamlayıp kaydedin. Aşağıdaki çıktı numarasız taslaktır.", style = NovaTypeToken.meta)
        pages.forEachIndexed { index, page ->
            Image(page.asImageBitmap(), "Belge sayfası ${index + 1}", Modifier.fillMaxWidth())
        }
        if (shown.snapshot.isDraft) NovaButton("Belge numarasını al ve sertifika hazırla", { coroutines.launch { load(true) } },
            Modifier.testTag("education.certificate.issue"), enabled = !busy && !fieldsChanged && shown.issues.isEmpty() && canIssue, symbol = "checkmark.seal")
        val ready = file
        if (ready != null) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NovaButton("Paylaş", { novaShareFile(context, ready.readBytes(), ready.name, "application/pdf") }, Modifier.weight(1f),
                variant = NovaButtonVariant.Surface, enabled = !busy, symbol = "square.and.arrow.up", compact = true)
            NovaButton("Kaydet", { saveLauncher.launch(if (shown.snapshot.isDraft) "TASLAK eğitim belgesi.pdf" else shown.snapshot.number.ifEmpty { "Eğitim belgesi" } + ".pdf") },
                Modifier.weight(1f), variant = NovaButtonVariant.Surface, enabled = !busy, symbol = "square.and.arrow.down", compact = true)
            NovaButton("Yazdır", {
                runCatching {
                    (context.getSystemService(Context.PRINT_SERVICE) as PrintManager).print(shown.snapshot.title, NovaPdfPrint(ready),
                        PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A4).setDuplexMode(PrintAttributes.DUPLEX_MODE_LONG_EDGE).build())
                }.onFailure { error = "Yazdırma açılamadı." }
            }, Modifier.weight(1f), variant = NovaButtonVariant.Surface, enabled = !busy, symbol = "printer", compact = true)
        }
    }
}
