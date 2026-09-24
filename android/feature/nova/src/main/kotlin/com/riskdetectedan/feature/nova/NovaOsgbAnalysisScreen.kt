package com.riskdetectedan.feature.nova

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.riskdetectedan.core.data.isg.*
import com.riskdetectedan.core.data.nova.*
import com.riskdetectedan.core.designsystem.isg.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

private fun workspaceDay(value: String?): String = value?.let { raw ->
    runCatching { OffsetDateTime.parse(raw).atZoneSameInstant(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("dd.MM.yyyy")) }
        .getOrDefault(raw.take(10))
}.orEmpty()

private fun workspaceItems(values: JsonArray?): List<NovaAnalysisItem> = values.orEmpty().mapIndexed { index, element ->
    val row = element.jsonObject
    fun text(key: String) = row[key]?.jsonPrimitive?.contentOrNull
    fun double(key: String) = row[key]?.jsonPrimitive?.doubleOrNull
    fun int(key: String) = row[key]?.jsonPrimitive?.intOrNull
    val minutes = int("duration_minutes")
    NovaAnalysisItem(text("id")!!, int("ordinal") ?: int("display_order") ?: (index + 1), text("title").orEmpty(), text("category"),
        text("body") ?: text("description").orEmpty(), text("recommendation") ?: text("recommended_action"), text("references_text"),
        audience = text("audience"), durationLabel = minutes?.let { "Eğitim süresi" }, durationValue = minutes?.let { "$it dk" },
        photoIndices = row["source_photo_indices"]?.jsonArray?.mapNotNull { it.jsonPrimitive.intOrNull }.orEmpty(),
        fineKinney = double("fk_score")?.let { score -> NovaAnalysisScore(text("fk_band"), score, listOfNotNull(
            double("fk_probability")?.let { NovaAnalysisScoreFactor("O", it) }, double("fk_frequency")?.let { NovaAnalysisScoreFactor("F", it) },
            double("fk_severity")?.let { NovaAnalysisScoreFactor("Ş", it) })) },
        matrix = int("m5_score")?.let { score -> NovaAnalysisScore(text("m5_band"), score.toDouble(), listOfNotNull(
            int("m5_probability")?.let { NovaAnalysisScoreFactor("O", it.toDouble()) }, int("m5_severity")?.let { NovaAnalysisScoreFactor("Ş", it.toDouble()) })) })
}

private enum class WorkspacePhase(val title: String, val detail: String) {
    preparing("Fotoğraf hazırlanıyor", "Görüntü güvenli yükleme için düzenleniyor."),
    uploading("Fotoğraf firmaya kaydediliyor", "Kaynak fotoğraf firma dosyalarına bağlanıyor."),
    queued("Analiz sırası hazırlanıyor", "İşlem OSGB analiz hizmetine iletildi."),
    analyzing("İSG analizi yapılıyor", "Riskler, öneriler ve eğitim ihtiyaçları değerlendiriliyor."),
    finalizing("Sonuçlar kaydediliyor", "Analiz kaydı ve bulgular son kez doğrulanıyor."),
}

private class WorkspaceAnalysisFailure(message: String) : Exception(message)

private fun workspaceFailure(error: Throwable): String {
    (error as? WorkspaceAnalysisFailure)?.message?.let { return it }
    val raw = error.message.orEmpty()
    return when {
        "INSUFFICIENT_CREDITS" in raw -> "OSGB analiz kredisi yetersiz. Yetkili hesaptan kredi durumunu kontrol edin."
        "PRICING_NOT_AVAILABLE" in raw -> "Fotoğraf analizi şu anda kullanılamıyor. Biraz sonra tekrar deneyin."
        "SOURCE_NOT_FOUND" in raw -> "Fotoğraf güvenli biçimde kaydedilemedi. Fotoğrafı yeniden seçip tekrar deneyin."
        else -> "Analiz başlatılamadı. Bağlantınızı kontrol edip aynı fotoğrafla tekrar deneyin."
    }
}

/** A JPEG of at most 1600 px (1200 px as a fallback) and 20 MB, as the workspace worker accepts. */
private fun workspaceJpeg(image: Bitmap): ByteArray? {
    for ((maximum, quality) in listOf(1_600 to 82, 1_200 to 62)) {
        val scale = minOf(1f, maximum.toFloat() / maxOf(image.width, image.height).coerceAtLeast(1))
        val scaled = if (scale < 1f) Bitmap.createScaledBitmap(image, maxOf(1, (image.width * scale).toInt()), maxOf(1, (image.height * scale).toInt()), true) else image
        val data = java.io.ByteArrayOutputStream().also { scaled.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
        if (data.size <= 20 * 1_024 * 1_024) return data
    }
    return null
}

/**
 * Analizler for one workspace company (iOS `IsgWorkspaceAnalysisScreen`): every read and action stays inside the
 * selected workspace and company; nothing reads the personal analysis service.
 */
@Composable
fun NovaOsgbAnalysisScreen(scope: NovaOsgbScope, stats: suspend () -> NovaAnalysisListStats, onBack: () -> Unit, startInCreateMode: Boolean = false) {
    val (context, repository, companyId) = Triple(scope.context, scope.repository, scope.companyId)
    val canOperate = context.canOperate
    val celebrate = rememberNovaCelebrate()
    var creating by remember { mutableStateOf(startInCreateMode && canOperate) }
    var images by remember { mutableStateOf<List<Bitmap>>(emptyList()) }
    var running by remember { mutableStateOf<Bitmap?>(null) }
    var selected by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf<String?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    val attempt = remember { IsgWorkspaceMutationAttempt() }
    selected?.let { id ->
        key(id) {
            NovaAnalysisDetailScreen(remember(id) { detailClient(scope, id, attempt) { celebrate(it) } }, onBack = { selected = null; revision++ },
                canWrite = canOperate, canEdit = false, canReact = false, canFileTraining = false, canReport = canOperate,
                reportResultIsArchiveName = false)
        }
        return
    }
    running?.let { image ->
        WorkspacePhotoProgress(image, scope.companyName, scope, onComplete = { id ->
            images = emptyList(); creating = false; running = null; revision++; selected = id
        }) { message -> running = null; notice = message; revision++ }
        return
    }
    if (creating) NovaPhotoIntakeScreen(images, { images = it }, onStart = { if (canOperate) images.firstOrNull()?.let { running = it } },
        onBack = { images = emptyList(); creating = false }, maximum = 1)
    else key(revision) {
        NovaAnalysisListScreen(NovaAnalysisListClient(
            load = { offset ->
                val page = repository.analyses(context, companyId, offset, 10)
                page["rows"]!!.jsonArray.map { it.jsonObject }.map { row ->
                    fun text(key: String) = row[key]?.jsonPrimitive?.contentOrNull
                    NovaAnalysisSummary(text("id")!!, text("title").orEmpty(), workspaceDay(text("created_at")), scope.companyName,
                        row["finding_count"]?.jsonPrimitive?.intOrNull, if (text("kind") == "photo") 1 else 0, highestBand = text("highest_band"),
                        createdAt = NovaAnalysisService.instant(text("created_at")))
                } to (page["has_more"]?.jsonPrimitive?.booleanOrNull == true)
            },
            stats = stats,
            thumbnail = { null }),
            onOpen = { selected = it }, onBack = onBack, onNewPhotoAnalysis = if (canOperate) ({ creating = true }) else null)
    }
    NovaNoticeDialog(notice, "Fotoğraf Analizi", { notice = null })
}

private fun detailClient(scope: NovaOsgbScope, analysisId: String, attempt: IsgWorkspaceMutationAttempt, celebrate: (String) -> Unit): NovaAnalysisDetailClient {
    val (context, repository, companyId) = Triple(scope.context, scope.repository, scope.companyId)
    suspend fun source() = repository.analysis(context, companyId, analysisId)
    return NovaAnalysisDetailClient(
        load = {
            val value = source()
            val header = value["analysis"]!!.jsonObject
            val method = NovaRiskMethod.of(header["primary_method"]?.jsonPrimitive?.contentOrNull) ?: NovaRiskMethod.fineKinney
            NovaAnalysisDetailData(analysisId, header["title"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                workspaceDay(header["created_at"]?.jsonPrimitive?.contentOrNull), NovaNonconformityWords.method(method), method, companyId,
                scope.companyName, listOf(
                    NovaAnalysisSection(NovaAnalysisSectionKind.riskAnalysis, workspaceItems(value["risk_findings"]?.jsonArray), false),
                    NovaAnalysisSection(NovaAnalysisSectionKind.expertRecommendations, workspaceItems(value["expert_items"]?.jsonArray), false),
                    NovaAnalysisSection(NovaAnalysisSectionKind.trainingRecommendations, workspaceItems(value["training_items"]?.jsonArray), false),
                ), false)
        },
        photos = { emptyList() },
        companies = { listOf(NovaAnalysisCompanyOption(companyId, scope.companyName, "", null)) },
        assign = { throw IllegalStateException("assign") },
        workplaces = { requested ->
            if (!requested.equals(companyId, true)) throw IllegalStateException("company")
            repository.ensuredWorkplaces(context, companyId).map { NovaNonconformityWorkplace(it.first, it.second, false) }
        },
        file = { request ->
            if (request.companyId != null && !request.companyId.equals(companyId, true)) NovaFindingOutcome.Refused(NovaNonconformityFailure.denied)
            else try {
                val value = source()
                val unscored = value["expert_items"]?.jsonArray.orEmpty().any {
                    it.jsonObject["id"]?.jsonPrimitive?.contentOrNull.equals(request.item.id, true) &&
                        it.jsonObject["kind"]?.jsonPrimitive?.contentOrNull == "unscored_finding"
                }
                val kind = if (request.section == NovaAnalysisSectionKind.riskAnalysis || unscored) "finding" else "expert_item"
                val openedOn = java.time.LocalDate.now(java.time.ZoneOffset.UTC).toString()
                val mutation = attempt.id("analysis.file", companyId, request.workplaceId.orEmpty(), analysisId, kind, request.item.id, request.severity?.name.orEmpty(), openedOn)
                val created = repository.fileAnalysisItem(context, mutation, companyId, request.workplaceId, analysisId, kind, request.item.id,
                    request.severity?.name, openedOn)
                celebrate(if (created) "Bulgu uygunsuzluk olarak kaydedildi." else "Bu bulgunun uygunsuzluğu zaten vardı.")
                if (created) NovaFindingOutcome.Opened else NovaFindingOutcome.AlreadyOpen
            } catch (cancelled: CancellationException) { throw cancelled } catch (_: Exception) {
                NovaFindingOutcome.Failed("Bu bulgu için kayıt açılamadı. Aynı işlemi tekrar deneyin.")
            }
        },
        edit = { throw IllegalStateException("edit") },
        remove = { throw IllegalStateException("remove") },
        react = { _, _, _ -> throw IllegalStateException("react") },
        report = { request ->
            val value = source()
            fun ids(key: String, filter: (JsonObject) -> Boolean = { true }) =
                value[key]?.jsonArray.orEmpty().map { it.jsonObject }.filter(filter).mapNotNull { it["id"]?.jsonPrimitive?.contentOrNull }
            val findings = ids("risk_findings")
            val expert = ids("expert_items") { it["kind"]?.jsonPrimitive?.contentOrNull == "expert_recommendation" }
            val training = ids("training_items")
            val format = if (request.format == NovaAnalysisReportFormat.excel) "xlsx" else "pdf"
            val mutation = attempt.id("analysis.export", companyId, analysisId, format, findings.joinToString(","), expert.joinToString(","), training.joinToString(","))
            val job = repository.createExport(context, companyId, analysisId, format, mutation, findings, expert, training)
            if (job["row"]?.jsonObject?.get("status")?.jsonPrimitive?.contentOrNull == "succeeded") "Rapor hazırlandı."
            else "Rapor isteği alındı ve hazırlanıyor."
        })
}

/** Uploads the photo into the company, starts the worker and waits for its analysis (iOS `IsgWorkspacePhotoAnalysisProgressScreen`). */
@Composable
private fun WorkspacePhotoProgress(image: Bitmap, companyName: String, scope: NovaOsgbScope, onComplete: (String) -> Unit, onError: (String) -> Unit) {
    BackHandler {}
    var phase by remember { mutableStateOf(WorkspacePhase.preparing) }
    val fileMutation = remember { UUID.randomUUID().toString() }
    val jobMutation = remember { UUID.randomUUID().toString() }
    LaunchedEffect(image) {
        try {
            phase = WorkspacePhase.preparing
            val data = withContext(Dispatchers.Default) { workspaceJpeg(image) }
                ?: throw WorkspaceAnalysisFailure("Fotoğraf hazırlanamadı. Başka bir fotoğraf seçip tekrar deneyin.")
            phase = WorkspacePhase.uploading
            val (_, asset) = scope.repository.uploadFile(scope.context, fileMutation, scope.companyId, "Analiz kaynak fotoğrafı",
                "analiz-$fileMutation.jpg", "inspection_report", data)
            phase = WorkspacePhase.queued
            val job = scope.repository.submitPhotoAnalysis(scope.context, jobMutation, scope.companyId, asset)
            repeat(120) {
                val (status, analysis) = scope.repository.photoAnalysisJob(scope.context, scope.companyId, job)
                when (status) {
                    "succeeded" -> {
                        phase = WorkspacePhase.finalizing
                        onComplete(analysis ?: throw WorkspaceAnalysisFailure("Analiz tamamlandı ancak sonuç kaydı doğrulanamadı. Analizlerim ekranını yenileyin."))
                        return@LaunchedEffect
                    }
                    "queued" -> phase = WorkspacePhase.queued
                    "running" -> phase = WorkspacePhase.analyzing
                    else -> throw WorkspaceAnalysisFailure("Fotoğraf analizi tamamlanamadı. Biraz sonra tekrar deneyin.")
                }
                delay(2_000)
            }
            throw WorkspaceAnalysisFailure("Analiz beklenenden uzun sürüyor. İşlem arka planda devam edebilir; Analizlerim listesini biraz sonra yenileyin.")
        } catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { onError(workspaceFailure(error)) }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp).padding(bottom = novaTabBarInset).testTag("osgb.analysis.progress"),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        NovaText("Fotoğraf Analizi", style = NovaTypeToken.screenTitle)
        Image(image.asImageBitmap(), null, Modifier.fillMaxWidth().height(260.dp).clip(RoundedCornerShape(24.dp))
            .border(1.dp, NovaColorToken.border.color(), RoundedCornerShape(24.dp)), contentScale = ContentScale.Crop)
        NovaCard(Modifier.fillMaxWidth(), padding = 18) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    NovaSpinner(NovaColorToken.text.color(), size = 18.dp)
                    NovaText(phase.title, style = NovaTypeToken.cardTitle)
                }
                NovaText(phase.detail, color = NovaColorToken.textSecondary.color())
                NovaAnalysisFact("building.2", companyName)
            }
        }
        NovaHelpHint("Bu ekran açıkken işlem tamamlandığında analiz otomatik olarak açılır.")
    }
}
