package com.riskdetectedan.feature.nova

import android.graphics.Bitmap
import androidx.lifecycle.ViewModel
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.nova.*
import dagger.hilt.android.lifecycle.HiltViewModel
import java.io.ByteArrayOutputStream
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject

/** Words the nonconformity surfaces share, so a band never reads two ways. */
object NovaNonconformityWords {
    fun severity(value: NovaNonconformitySeverity) = band(value.name)
    fun band(value: String?): String = when (value) {
        "critical" -> "Kritik"; "high" -> "Yüksek"; "medium" -> "Orta"; "low" -> "Düşük"; else -> "Bilinmiyor"
    }
    /** An unreadable band is its own tone, never the calmest one. */
    fun tone(value: String?): com.riskdetectedan.core.designsystem.isg.NovaStatus = when (value) {
        "critical", "high" -> com.riskdetectedan.core.designsystem.isg.NovaStatus.Danger
        "medium" -> com.riskdetectedan.core.designsystem.isg.NovaStatus.Warning
        "low" -> com.riskdetectedan.core.designsystem.isg.NovaStatus.Neutral
        else -> com.riskdetectedan.core.designsystem.isg.NovaStatus.Info
    }
    fun state(value: String): String = when (value) {
        "open" -> "Açık"; "assigned" -> "Atandı"; "in_progress" -> "Devam ediyor"; "pending_verification" -> "Doğrulama bekliyor"
        "closed" -> "Kapandı"; "reopened" -> "Yeniden açıldı"; "cancelled" -> "İptal edildi"; else -> "Taslak"
    }
    fun recordKind(value: NovaNonconformityRecordKind) = when (value) {
        NovaNonconformityRecordKind.nonconformity -> "Uygunsuzluk"
        NovaNonconformityRecordKind.improvement -> "Geliştirme önerisi"
    }
    fun method(value: NovaRiskMethod) = when (value) {
        NovaRiskMethod.fineKinney -> "Fine-Kinney"
        NovaRiskMethod.matrix5x5 -> "5×5 Matris"
    }
    /** No trailing zeros: 270 reads 270, 1.2 reads 1,2. */
    fun score(value: Double): String {
        val format = java.text.NumberFormat.getNumberInstance(java.util.Locale.forLanguageTag("tr-TR"))
        format.minimumFractionDigits = 0; format.maximumFractionDigits = 2
        return format.format(value)
    }
    fun failure(value: NovaNonconformityFailure): String = when (value) {
        NovaNonconformityFailure.denied -> "Bu firma için uygunsuzluk kaydına erişiminiz yok."
        NovaNonconformityFailure.severityUnknown -> "Bulgunun risk bandı okunamadı. Önem derecesini kendiniz seçin."
        NovaNonconformityFailure.conflict -> "Kayıt bu sırada değişti. Listeyi yenileyip tekrar deneyin."
        NovaNonconformityFailure.riskInputIncomplete -> "Seçtiğiniz risk metodunun tüm değerlerini girin."
        NovaNonconformityFailure.validation, NovaNonconformityFailure.payloadRejected -> "Gönderilen bilgiler kabul edilmedi. Alanları kontrol edin."
        NovaNonconformityFailure.unavailable -> "Uygunsuzluk modülü şu anda kullanılamıyor."
    }
    fun message(error: Throwable, fallback: String): String =
        (error as? NovaNonconformityException)?.let { failure(it.failure) } ?: fallback
}

/** Today in Europe/Istanbul as an ISO day, so "overdue" is one calendar answer. */
fun novaTodayIso(): String = LocalDate.now(ZoneId.of("Europe/Istanbul")).toString()

/** Encodes a picture for evidence the way iOS does (JPEG, 0.85), capped so uploads stay reasonable. */
fun novaJpeg(bitmap: Bitmap, maxSide: Int = 2048): ByteArray {
    val scale = maxOf(bitmap.width, bitmap.height).toFloat() / maxSide
    val sized = if (scale > 1f) Bitmap.createScaledBitmap(bitmap, (bitmap.width / scale).toInt(), (bitmap.height / scale).toInt(), true) else bitmap
    return ByteArrayOutputStream().use { out -> sized.compress(Bitmap.CompressFormat.JPEG, 85, out); out.toByteArray() }
}

/** Holds the nonconformity calls for the Denetim surfaces (iOS `NovaPilotFindingsGate`). */
@HiltViewModel
class NovaFindingsViewModel @Inject constructor(
    val service: NovaNonconformityService,
    val files: NovaFileLibraryService,
    val analysis: com.riskdetectedan.core.data.nova.NovaAnalysisService,
) : ViewModel() {
    suspend fun board(identity: IsgWorkspaceIdentity) = service.board(identity)
    suspend fun companies(identity: IsgWorkspaceIdentity) = runCatching { service.companyOptions(identity) }.getOrDefault(emptyList())

    fun recordClient(identity: IsgWorkspaceIdentity, entry: NovaNonconformityEntry): NovaRecordClient {
        val scope = NovaCompanyScope(identity, entry.companyId)
        return NovaRecordClient(
            load = { service.detail(scope, entry.id) },
            transition = { state, reason, assignee ->
                val current = service.detail(scope, entry.id)
                service.transition(scope, entry.id, state, current.version, reason, assignee)
            },
            addAction = { description, assignee -> service.addAction(scope, entry.id, description, assignee, null) },
            verify = { accepted, note -> service.verify(scope, entry.id, accepted, note) },
            saveDetail = { draft -> service.setDetail(scope, entry.id, draft) },
            download = { bucket, path -> files.download(identity, bucket, path) },
        )
    }

    /** Returns null when the record was opened and verified on the list, the reason otherwise. */
    suspend fun saveManual(identity: IsgWorkspaceIdentity, draft: NovaManualDraft, photos: List<Bitmap>): String? {
        val company = draft.companyId ?: return NovaNonconformityWords.failure(NovaNonconformityFailure.validation)
        val workplace = draft.workplaceId ?: return NovaNonconformityWords.failure(NovaNonconformityFailure.validation)
        var evidence = emptyList<String>()
        if (photos.isNotEmpty()) {
            evidence = files.fileEvidence(identity, company, photos.map { novaJpeg(it) }, "Uygunsuzluk fotoğrafı",
                "nonconformity_evidence")
            if (evidence.isEmpty()) return "Fotoğraflar yüklenemedi. Bağlantıyı kontrol edip tekrar deneyin."
        }
        val scope = NovaCompanyScope(identity, company)
        return try {
            val result = service.open(scope, NovaNonconformityIntent(NovaNonconformityIntent.Origin.detailed, workplace,
                draft.title.trim(), severity = draft.severity, recordKind = draft.recordKind,
                hazardDescription = draft.hazardDescription, controlMeasure = draft.controlMeasure,
                legislation = draft.legislation, responsible = draft.responsible, score = draft.score,
                evidenceAssetIds = evidence))
            // Do not celebrate a write until the board's own read path can see it.
            if (service.list(scope).none { it.id == result.row.id })
                "Kayıt oluşturuldu ancak listede doğrulanamadı. Listeyi yenileyip tekrar kontrol edin."
            else null
        } catch (error: Exception) {
            NovaNonconformityWords.message(error, "Kayıt açılamadı. Bilgileri kontrol edip aynı işlemi tekrar deneyin.")
        }
    }
}

class NovaRecordClient(
    val load: suspend () -> NovaNonconformityRow,
    val transition: suspend (NovaNonconformityState, String, String) -> NovaNonconformityRow,
    val addAction: suspend (String, String) -> NovaNonconformityRow,
    val verify: suspend (Boolean, String) -> NovaNonconformityRow,
    val saveDetail: suspend (NovaNonconformityDetailDraft) -> NovaNonconformityRow,
    val download: suspend (String, String) -> ByteArray,
)
