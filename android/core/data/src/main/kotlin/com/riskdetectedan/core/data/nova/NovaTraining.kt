package com.riskdetectedan.core.data.nova

import android.content.Context
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.storage.storage
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.roundToLong

/** Record ids travel as written by either platform, so the same UUID can arrive in either case. */
fun String.sameId(other: String?) = other != null && equals(other, ignoreCase = true)

@Serializable data class NovaTrainingParticipant(val id: String, val name: String, val attended: Boolean)

/** One realized training across the companies that attended it (iOS `NovaTrainingSession`). */
@Serializable data class NovaTrainingSession(
    val id: String, @SerialName("owner_id") val ownerId: String, val title: String, val trainer: String = "", val method: String = "face_to_face",
    @SerialName("held_on") val heldOn: String = "", val location: String = "", val notes: String = "", val version: Long,
    val companies: List<Company>, val education: NovaEducationRecord? = null,
) {
    @Serializable data class Company(
        val id: String, @SerialName("company_id") val companyId: String, @SerialName("owner_id") val ownerId: String,
        @SerialName("company_name") val companyName: String, @SerialName("hazard_class") val hazardClass: String = "",
        @SerialName("duration_minutes") val durationMinutes: Int, @SerialName("valid_until") val validUntil: String? = null,
        val state: String, val participants: List<NovaTrainingParticipant>,
    )
    val isLegacyPlan get() = companies.any { it.state == "planned" }
    val count get() = companies.sumOf { it.participants.size }
}

@Serializable data class NovaEducationTopic(
    val code: String, val group: String, val title: String, @SerialName("instruction_minutes") val instructionMinutes: Int,
    val method: String = "face_to_face", @SerialName("trainer_ids") val trainerIds: List<String> = emptyList(),
    @SerialName("parent_code") val parentCode: String? = null, @SerialName("legal_title") val legalTitle: String? = null,
)

@Serializable data class NovaEducationTrainer(val id: String = UUID.randomUUID().toString(), val name: String = "", val title: String = "")

@Serializable data class NovaEducationPerson(val id: String, val name: String? = null, @SerialName("job_title") val jobTitle: String = "",
                                             val department: String? = null)

@Serializable data class NovaEducationLesson(
    val id: String = UUID.randomUUID().toString(), @SerialName("starts_at") val startsAt: String,
    @SerialName("instruction_minutes") val instructionMinutes: Int, @SerialName("break_minutes") val breakMinutes: Int = 15,
    val allocations: List<Allocation>,
) {
    @Serializable data class Allocation(@SerialName("topic_code") val topicCode: String, val minutes: Int)
}

/**
 * One scheduled day. `starts` keeps the iOS encoding (seconds since 2001-01-01),
 * so a draft saved on either platform reads the same on the other.
 */
@Serializable data class NovaEducationDay(
    val id: String = UUID.randomUUID().toString(), val starts: Double, val lessonCount: Int = 8,
    val extraBreakAfter: Int = 4, val extraBreakMinutes: Int = 0,
) {
    val instant: Instant get() = Instant.ofEpochMilli(((starts + REFERENCE) * 1000).roundToLong())
    fun at(value: Instant) = copy(starts = value.toEpochMilli() / 1000.0 - REFERENCE)
    companion object {
        private const val REFERENCE = 978_307_200.0
        fun of(value: Instant, lessonCount: Int = 8) = NovaEducationDay(starts = value.toEpochMilli() / 1000.0 - REFERENCE, lessonCount = lessonCount)
    }
}

@Serializable data class NovaEducationScope(
    val id: String = UUID.randomUUID().toString(), @SerialName("company_id") val companyId: String, @SerialName("workplace_id") val workplaceId: String? = null,
    @SerialName("logo_path") val logoPath: String? = null, @SerialName("company_name") val companyName: String? = null,
    @SerialName("workplace_name") val workplaceName: String? = null, @SerialName("hazard_class") val hazardClass: String? = null,
    @SerialName("group_name") val groupName: String = "Genel", val cycle: String = "initial", @SerialName("context_note") val contextNote: String = "",
    @SerialName("legal_name") val legalName: String = "", @SerialName("employer_name") val employerName: String = "",
    @SerialName("employer_capacity") val employerCapacity: String = "representative", val location: String = "",
    @SerialName("renewal_months") val renewalMonths: Int = 0, val topics: List<NovaEducationTopic> = emptyList(),
    val lessons: List<NovaEducationLesson> = emptyList(), val participants: List<NovaEducationPerson> = emptyList(),
    @SerialName("draft_days") val draftDays: List<NovaEducationDay>? = null, @SerialName("preset_code") val presetCode: String? = null,
    @SerialName("starts_at") val startsAt: String? = null, @SerialName("ends_at") val endsAt: String? = null,
    @SerialName("held_on") val heldOn: String? = null, @SerialName("valid_until") val validUntil: String? = null,
    @SerialName("instruction_minutes") val instructionMinutes: Int? = null, @SerialName("break_minutes") val breakMinutes: Int? = null,
    @SerialName("lesson_units") val lessonUnits: Int? = null, @SerialName("group4_minutes") val group4Minutes: Int? = null,
    val issues: List<String>? = null,
) {
    val net get() = topics.sumOf { it.instructionMinutes }
    val group4 get() = topics.filter { it.group == "G4" }.sumOf { it.instructionMinutes }
    val breakTotal get() = lessons.sumOf { it.breakMinutes }
    val cycleName get() = cycleName(cycle)
    companion object {
        val cycles = listOf("initial" to "İlk Temel Eğitim", "periodic_repeat" to "Tekrar Temel Eğitimi", "onboarding" to "İşe Başlama Eğitimi",
            "knowledge_refresh" to "Bilgi Yenileme", "additional" to "İlave Eğitim", "workplace_specific" to "Yeni İşyerine Özgü Eğitim",
            "custom" to "Özel Eğitim")
        fun cycleName(cycle: String) = cycles.firstOrNull { it.first == cycle }?.second ?: cycle
    }
}

@Serializable data class NovaEducationRecord(
    @SerialName("schema_version") val schemaVersion: Int = 1, @SerialName("completion_basis") val completionBasis: String = "expert_record",
    @SerialName("provider_name") val providerName: String = "", val trainers: List<NovaEducationTrainer> = emptyList(),
    val scopes: List<NovaEducationScope> = emptyList(),
)

/** The title starts empty: a placeholder must never make the first step read as finished. */
@Serializable data class NovaEducationDraft(
    val action: String = "save", val id: String? = null, @SerialName("expected_version") val expectedVersion: Long = 0,
    val title: String = "", @SerialName("provider_name") val providerName: String = "", val notes: String = "",
    val trainers: List<NovaEducationTrainer> = emptyList(), val scopes: List<NovaEducationScope> = emptyList(),
) {
    /** One record carries one hazard class, and every company/workplace in it needs its own minutes, lessons and people. */
    fun isComplete(step: NovaEducationStep): Boolean = when (step) {
        NovaEducationStep.companies -> scopes.firstOrNull()?.hazardClass?.let { hazard -> scopes.all { it.hazardClass == hazard } } ?: false
        NovaEducationStep.info -> title.isNotBlank() && providerName.isNotBlank()
        NovaEducationStep.topics -> title.isNotBlank() && scopes.isNotEmpty() && scopes.all { it.net > 0 }
        NovaEducationStep.schedule -> title.isNotBlank() && scopes.isNotEmpty() && scopes.all { it.lessons.isNotEmpty() }
        NovaEducationStep.trainers -> trainers.isNotEmpty() && trainers.size <= 20 && trainers.all {
            val name = it.name.trim()
            name.isNotEmpty() && name.length <= 200 && it.title.length <= 200
        } && trainers.map { it.id }.toSet().size == trainers.size
        NovaEducationStep.participants -> scopes.isNotEmpty() && scopes.all { it.participants.isNotEmpty() }
        NovaEducationStep.review -> NovaEducationStep.entries.dropLast(1).all(::isComplete)
    }
    val completedCount get() = NovaEducationStep.entries.count(::isComplete)

    /** Empty add rows are form placeholders, not trainers; every remaining trainer covers the shared topics. */
    fun preparedForSave(): NovaEducationDraft {
        val kept = trainers.map { it.copy(name = it.name.trim(), title = it.title.trim()) }.filter { it.name.isNotEmpty() || it.title.isNotEmpty() }
        val ids = kept.map { it.id }
        return copy(trainers = kept, scopes = scopes.map { scope -> scope.copy(topics = scope.topics.map { it.copy(trainerIds = ids) }) })
    }
    val progress get() = completedCount.toFloat() / NovaEducationStep.entries.size

    companion object {
        fun of(row: NovaTrainingSession, education: NovaEducationRecord) = NovaEducationDraft(id = row.id, expectedVersion = row.version,
            title = row.title, providerName = education.providerName, notes = row.notes, trainers = education.trainers, scopes = education.scopes)
    }
}

/** The guided editor's steps, in the order they are asked; the last one is an explicit review checkpoint. */
enum class NovaEducationStep(val title: String, val symbol: String) {
    companies("Firmalar ve işyerleri", "building.2"), info("Eğitim ve düzenleyici", "text.book.closed"),
    topics("Konular ve dakikalar", "list.bullet.clipboard"), schedule("Tarih, saat ve yer", "calendar.badge.clock"),
    trainers("Eğiticiler", "person.crop.rectangle"), participants("Katılımcılar", "person.3"), review("Kontrol ve kaydet", "checkmark.circle"),
}

@Serializable data class NovaEducationCurriculum(
    val topics: List<NovaEducationTopic>, @SerialName("context_note") val contextNote: String = "", val cycle: String,
    @SerialName("group_name") val groupName: String = "Genel", @SerialName("hazard_class") val hazardClass: String,
)

@Serializable data class NovaEducationPackage(val topics: List<Topic>, val presets: List<Preset>) {
    @Serializable data class Topic(val code: String, @SerialName("group_code") val groupCode: String, @SerialName("legal_label") val legalLabel: String)
    @Serializable data class Preset(
        val code: String, val label: String, val cycle: String, @SerialName("hazard_class") val hazardClass: String,
        @SerialName("topic_instruction_minutes") val topicInstructionMinutes: Map<String, Int> = emptyMap(), val group4: G4,
        @SerialName("default_instruction_minutes") val defaultInstructionMinutes: Int = 0,
        @SerialName("common_groups_review_guard") val commonGroupsReviewGuard: CommonGroupsReviewGuard? = null,
    ) {
        @Serializable data class CommonGroupsReviewGuard(@SerialName("reference_instruction_minutes") val referenceInstructionMinutes: Int)
        @Serializable data class G4(val topics: List<G4Topic> = emptyList(),
                                    @SerialName("budget_instruction_minutes") val budgetInstructionMinutes: Int = 0)
        @Serializable data class G4Topic(@SerialName("local_key") val localKey: String, val title: String,
                                         @SerialName("instruction_minutes") val instructionMinutes: Int)
    }

    fun preset(cycle: String, hazard: String): Preset? {
        val wire = when (hazard) { "high" -> "very_hazardous"; "medium" -> "hazardous"; else -> hazard }
        return presets.firstOrNull { it.cycle == cycle && it.hazardClass == wire }
    }

    /** An official profile lists every legal topic; anything else starts from one editable topic. */
    fun topics(cycle: String, hazard: String): List<NovaEducationTopic> {
        val preset = preset(cycle, hazard) ?: return listOf(NovaEducationTopic("CUSTOM-1", "G4",
            if (cycle == "onboarding") "İşe ve göreve özgü uygulamalar" else "Eğitim konusu", if (cycle == "onboarding") 120 else 60))
        return topics.map { NovaEducationTopic(it.code, it.groupCode, it.legalLabel, preset.topicInstructionMinutes[it.code] ?: 0) } +
            preset.group4.topics.map { NovaEducationTopic(it.localKey, "G4", it.title, it.instructionMinutes) }
    }
}

@Serializable data class NovaEducationContext(
    val certificates: List<Certificate> = emptyList(), @SerialName("schema_version") val schemaVersion: Int, @SerialName("owner_id") val ownerId: String,
    val row: NovaTrainingSession? = null, val `package`: NovaEducationPackage, val workplaces: List<Workplace>, val curricula: List<Curriculum> = emptyList(),
    @SerialName("catalog_enabled") val catalogEnabled: Boolean = false, @SerialName("certificate_enabled") val certificateEnabled: Boolean = false,
) {
    @Serializable data class Certificate(@SerialName("document_id") val documentId: String, val revision: Int, @SerialName("scope_id") val scopeId: String,
                                         @SerialName("person_id") val personId: String,
                                         @SerialName("source_session_revision") val sourceSessionRevision: Long)
    @Serializable data class Workplace(val id: String, @SerialName("company_id") val companyId: String, val name: String,
                                       @SerialName("hazard_class") val hazardClass: String)
    @Serializable data class Curriculum(val id: String, @SerialName("company_id") val companyId: String, @SerialName("workplace_id") val workplaceId: String? = null,
                                        val education: NovaEducationCurriculum)

    /** The company's saved default for this workplace, cycle and hazard class, if any. */
    fun curriculum(scope: NovaEducationScope, cycle: String, hazard: String?, group: String? = null) = curricula.firstOrNull {
        it.companyId.sameId(scope.companyId) && (it.workplaceId?.sameId(scope.workplaceId) ?: (scope.workplaceId == null)) && it.education.cycle == cycle &&
            it.education.hazardClass == hazard && (group == null || it.education.groupName == group)
    }
}

/** A personal certificate; the server intentionally leaves the other participants out. */
@Serializable data class NovaEducationCertificate(
    @SerialName("schema_version") val schemaVersion: Int, @SerialName("owner_id") val ownerId: String, val ready: Boolean = false,
    val issues: List<String> = emptyList(), @SerialName("document_id") val documentId: String? = null, val revision: Int? = null,
    val snapshot: Snapshot,
) {
    @Serializable data class Snapshot(
        @SerialName("schema_version") val schemaVersion: Int, @SerialName("template_version") val templateVersion: Int,
        @SerialName("theme_version") val themeVersion: Int, @SerialName("completion_basis") val completionBasis: String,
        @SerialName("source_session_id") val sourceSessionId: String, @SerialName("source_session_revision") val sourceSessionRevision: Long,
        val person: NovaEducationPerson, val scope: Scope, val trainers: List<NovaEducationTrainer>, @SerialName("provider_name") val providerName: String,
        @SerialName("logo_png_base64") val logoPngBase64: String? = null, val title: String, @SerialName("issued_on") val issuedOn: String,
        @SerialName("is_draft") val isDraft: Boolean, val number: String = "", val revision: Int = 0,
    )
    @Serializable data class Scope(
        val id: String, @SerialName("legal_name") val legalName: String, @SerialName("company_name") val companyName: String = "",
        @SerialName("workplace_name") val workplaceName: String? = null, @SerialName("hazard_class") val hazardClass: String, val cycle: String,
        @SerialName("context_note") val contextNote: String = "", val topics: List<NovaEducationTopic>, val lessons: List<NovaEducationLesson>,
        @SerialName("employer_name") val employerName: String = "", @SerialName("employer_capacity") val employerCapacity: String = "",
        @SerialName("instruction_minutes") val instructionMinutes: Int, @SerialName("break_minutes") val breakMinutes: Int,
        @SerialName("valid_until") val validUntil: String? = null,
    )
}

@Serializable data class NovaEducationCertificateRequest(
    val action: String = "preview", @SerialName("session_id") val sessionId: String? = null, @SerialName("scope_id") val scopeId: String? = null,
    @SerialName("person_id") val personId: String? = null, @SerialName("expected_version") val expectedVersion: Long? = null,
    @SerialName("issued_on") val issuedOn: String? = null, @SerialName("mutation_id") val mutationId: String? = null,
    @SerialName("document_id") val documentId: String? = null, val revision: Int? = null,
    @SerialName("logo_png_base64") val logoPngBase64: String? = null,
)

/** Istanbul-time lesson placement (iOS `NovaEducationClock`): 45-minute basic units with 15-minute breaks. */
object NovaEducationClock {
    val zone: ZoneId = ZoneId.of("Europe/Istanbul")

    fun iso(value: Instant): String = DateTimeFormatter.ISO_INSTANT.format(value.truncatedTo(ChronoUnit.SECONDS))
    fun date(value: String): Instant? = runCatching { OffsetDateTime.parse(value).toInstant() }.getOrNull()
    fun day(value: Instant): String = value.atZone(zone).toLocalDate().toString()

    /** Whole 45-minute basic units (iOS `lessonUnits`); eight units fill a day, ending yesterday at the latest. */
    fun units(minutes: Int, basic: Boolean) = if (basic) maxOf(1, minutes / 45) else 1

    /** The recommended days for [minutes], back-dated so a fresh record describes a training that already happened. */
    fun initialDays(minutes: Int, basic: Boolean): List<NovaEducationDay> {
        val count = units(minutes, basic)
        val dayCount = maxOf(1, (count + 7) / 8)
        val first = java.time.LocalDate.now(zone).minusDays(dayCount.toLong())
        return (0 until dayCount).map { n ->
            NovaEducationDay.of(first.plusDays(n.toLong()).atTime(9, 0).atZone(zone).toInstant(), minOf(8, count - n * 8))
        }
    }

    fun days(lessons: List<NovaEducationLesson>): List<NovaEducationDay> =
        lessons.groupBy { day(date(it.startsAt) ?: Instant.now()) }.toSortedMap().values.mapNotNull { list ->
            val first = list.minByOrNull { it.startsAt } ?: return@mapNotNull null
            date(first.startsAt)?.let { NovaEducationDay.of(it, list.size) }
        }

    fun distribute(topics: List<NovaEducationTopic>, days: List<NovaEducationDay>, basic: Boolean): List<NovaEducationLesson> {
        val positive = topics.filter { it.instructionMinutes > 0 }
        val total = positive.sumOf { it.instructionMinutes }
        val count = days.sumOf { maxOf(0, it.lessonCount) }
        if (total <= 0 || count <= 0 || count > 200) return emptyList()
        var topic = 0; var left = positive[0].instructionMinutes; var used = 0
        val output = mutableListOf<NovaEducationLesson>()
        for (day in days.sortedBy { it.starts }) {
            var start = day.instant
            for (local in 0 until maxOf(0, day.lessonCount)) {
                val amount = if (output.size == count - 1) total - used else minOf(if (basic) 45 else total / count, maxOf(0, total - used))
                if (amount <= 0) continue
                var remaining = amount
                val allocations = mutableListOf<NovaEducationLesson.Allocation>()
                while (remaining > 0 && topic < positive.size) {
                    val minutes = minOf(remaining, left)
                    allocations += NovaEducationLesson.Allocation(positive[topic].code, minutes); remaining -= minutes; left -= minutes
                    if (left == 0) { topic++; if (topic < positive.size) left = positive[topic].instructionMinutes }
                }
                val rest = (if (basic) 15 else 0) + (if (local + 1 == day.extraBreakAfter) day.extraBreakMinutes else 0)
                output += NovaEducationLesson(startsAt = iso(start), instructionMinutes = amount, breakMinutes = rest, allocations = allocations)
                used += amount; start = start.plusSeconds((amount + rest) * 60L)
            }
        }
        return output
    }
}

class NovaTrainingException(val code: String, val sqlState: String? = null) : Exception(code)

object NovaTrainingWords {
    fun hazard(value: String?) = when (value) { "low" -> "az tehlikeli"; "medium", "hazardous" -> "tehlikeli"; "high", "very_hazardous" -> "çok tehlikeli"; else -> value.orEmpty() }
    fun method(value: String) = when (value) { "online" -> "Online"; "mixed" -> "Karma"; else -> "Yüz yüze" }

    fun issue(code: String) = mapOf(
        "TOPIC_MINUTES_MISSING" to "Süresi eksik konu var.", "TRAINER_SCOPE_MISSING" to "Konuların eğiticilerini seçin.",
        "FACE_TO_FACE_REQUIRED" to "Bu kapsamın işyerine özgü bölümünü yüz yüze düzenleyin.", "REQUIRED_TOPIC_MISSING" to "Zorunlu konu eksik.",
        "TOTAL_TOO_SHORT" to "Öğretim süresi profilin altında.", "GROUP4_TOO_SHORT" to "İşyerine özgü öğretim süresi eksik.",
        "COMMON_GROUPS_TOO_SHORT" to "İlk eğitimin G1–G3 referans süresi eksik.", "GROUP4_CONTEXT_MISSING" to "Eğitimi yeniden kaydedin; işyerine özgü konu kapsamı otomatik aktarılır.",
        "LESSON_TOPIC_MISMATCH" to "Ders dağılımı konu dakikalarıyla eşleşmiyor. Saatleri yeniden dağıtın.",
        "LESSON_BREAK_INVALID" to "Temel eğitim dersleri en az 45 dakika ve araları en az 15 dakika olmalı.",
        "EMPLOYER_MISSING" to "İşveren / vekili adını doldurun.", "EMPLOYER_CAPACITY_MISSING" to "İşveren / vekili sıfatını seçin.",
        "JOB_TITLE_MISSING" to "Personelin belgeye yazılacak unvanı eksik.", "PROVIDER_MISSING" to "Düzenleyici kişi / kurum eksik.",
        "TRAINER_TITLE_MISSING" to "Eğitici unvanı eksik.",
    )[code] ?: code

    /** A refusal that names one section of the form (iOS `NovaEducationService.correction`). */
    fun correction(error: Throwable): Pair<NovaEducationStep, String>? = when ((error as? NovaTrainingException)?.code) {
        "TRAINER_INVALID" -> NovaEducationStep.trainers to "Eğitici adlarını ve konu dağılımını kontrol edin. Boş ek satır kaydedilmez."
        "TOPIC_INVALID", "TOPIC_HIERARCHY_INVALID" -> NovaEducationStep.topics to "Konu başlıklarını ve dakikalarını kontrol edin."
        "LESSON_INVALID", "LESSON_ALLOCATION_INVALID", "LESSON_OVERLAP_OR_FUTURE" ->
            NovaEducationStep.schedule to "Eğitim günlerini, ders sürelerini ve bitiş saatlerini kontrol edin."
        "SCOPE_INVALID", "TRAINING_HAZARD_MISMATCH", "WORKPLACE_REQUIRED" -> NovaEducationStep.companies to "Firma ve işyeri seçimlerini kontrol edin."
        "PARTICIPANT_DUPLICATE" -> NovaEducationStep.participants to "Aynı personeli birden fazla kez seçmeyin."
        else -> null
    }

    /** iOS `NovaEducationService.message` → `NovaTrainingSessionService.message` → `NovaTrainingService.message`, in that order. */
    fun message(error: Throwable): String = when ((error as? NovaTrainingException)?.code) {
        "FEATURE_UNAVAILABLE" -> "Yeni eğitim modülü bu hesap için henüz açılmadı."
        "VERSION_CONFLICT" -> "Kayıt başka bir cihazda değişti. Kapatıp güncel kaydı açın; form taslağınız korunur."
        "TRAINING_DATE_INVALID", "LESSON_OVERLAP_OR_FUTURE" -> "Ders saatleri çakışmamalı ve eğitimin tamamı geçmişte olmalı."
        "PARTICIPANT_DUPLICATE" -> "Bir personeli yalnız bir eğitim kapsamına ekleyin."
        "TRAINING_HAZARD_MISMATCH" -> "Farklı tehlike sınıfındaki firmalar aynı eğitim dosyasında yer alamaz. Ayrı kayıt oluşturun."
        "WORKPLACE_REQUIRED" -> "Firmaya ait işyeri seçin."
        "TRAINER_INVALID" -> "En az bir eğitici adı girin ve konu dağılımlarını kontrol edin."
        "FACE_TO_FACE_REQUIRED" -> "İşe başlama eğitimi yüz yüze verilmelidir."
        "WORKPLACE_FACE_TO_FACE_REQUIRED" -> "Tehlikeli/çok tehlikeli işyerlerinde işe özgü bölüm yüz yüze olmalı. Karma veya yüz yüze yöntemi seçin."
        "PARTICIPANT_REQUIRED" -> "Seçilen her firmadan en az bir katılımcı seçin."
        "CATALOG_REQUIRED" -> "Kayıtlı bir eğitim seçin veya yeni eğitim başlığı oluşturun."
        "RULE_DATE_UNSUPPORTED" -> "Hazır katalog 2 Nisan 2026 sonrası eğitimler içindir. Daha eski kayıt için tarihli kural incelemesi gerekir."
        "VALIDATION_ERROR" -> "Geçmiş/bugünkü eğitim tarihini, eğitmeni ve katılımcıları kontrol edin."
        "UPGRADE_REQUIRED" -> "Yeni eğitim akışı için uygulamayı güncelleyin."
        "TRAINING_NOT_ENDED" -> "Eğitim henüz bitmedi. Bitiş saatinden sonra tamamlayabilirsiniz."
        "ATTENDANCE_REQUIRED" -> "Tamamlamak için en az bir katılımcının yoklamasını işaretleyip kaydedin."
        "FUTURE_ATTENDANCE" -> "Gelecekteki eğitim için katılım işaretlenemez."
        "PARTICIPANT_UNAVAILABLE" -> "Seçilen personel artık aktif değil. Katılımcı listesini güncelleyin."
        "TRAINING_LOCKED" -> "Kayıt değişti veya kapatıldı. Listeyi yenileyip tekrar açın."
        "ACCESS_DENIED", "AUTH_REQUIRED", "PAID_PLAN_REQUIRED" -> "Bu firma için eğitim erişimi doğrulanamadı. Oturumunuzu ve pilot erişiminizi kontrol edin."
        else -> "İşlem doğrulanamadı. Bağlantınızı kontrol edip tekrar deneyin; bekleyen kayıt aynı işlemle sürdürülecek."
    }
}

/**
 * Eğitimler boundary (iOS `NovaTrainingSessionService` list + `NovaEducationService`).
 * The editor autosaves one draft per record, a save keeps its mutation id until
 * the server answers, and an issued certificate keeps its request until then.
 */
@Singleton
class NovaTrainingService @Inject constructor(@ApplicationContext context: Context, private val transport: NovaExpertTransport,
                                              private val events: NovaRecordEvents, private val client: SupabaseClient) {
    private val storage = context.getSharedPreferences("nova.education.v3", Context.MODE_PRIVATE)
    private val json = Json(novaJson) { encodeDefaults = true }

    data class Page(val rows: List<NovaTrainingSession>, val nextId: String?, val writableCompanies: Set<String>)
    data class Receipt(val row: NovaTrainingSession?, val curriculumSaved: Boolean)

    @Serializable private data class PageEnvelope(@SerialName("schema_version") val schemaVersion: Int, @SerialName("owner_id") val ownerId: String,
        val rows: List<NovaTrainingSession>, @SerialName("next_id") val nextId: String? = null,
        @SerialName("writable_companies") val writableCompanies: List<String> = emptyList())
    @Serializable private data class ReceiptEnvelope(@SerialName("schema_version") val schemaVersion: Int, @SerialName("owner_id") val ownerId: String,
        @SerialName("mutation_id") val mutationId: String, val row: NovaTrainingSession? = null,
        @SerialName("curriculum_saved") val curriculumSaved: Boolean? = null)
    @Serializable private data class Pending(val mutation: String, val draft: NovaEducationDraft)

    fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaTrainingException("SESSION_CHANGED")
    }

    private fun key(identity: IsgWorkspaceIdentity, suffix: String) =
        (transport.capture()?.access?.storageNamespace ?: identity.userId) + ":" + suffix

    private fun draftKey(identity: IsgWorkspaceIdentity, id: String?) = key(identity, "draft:" + (id?.lowercase() ?: "new"))

    private suspend fun rpc(identity: IsgWorkspaceIdentity, function: String, params: JsonObject): JsonElement {
        check(identity)
        val data = try { transport.execute(function, params) } catch (failure: NovaExpertFailure) {
            currentCoroutineContext().ensureActive(); throw NovaTrainingException(failure.code, failure.sqlState)
        }
        check(identity)
        return data
    }

    private fun <T> JsonElement.decode(serializer: KSerializer<T>): T = try { json.decodeFromJsonElement(serializer, this) }
        catch (_: Exception) { throw NovaTrainingException("UNAVAILABLE") }

    private fun owned(identity: IsgWorkspaceIdentity, row: NovaTrainingSession?) = row == null || row.ownerId.sameId(identity.userId)

    suspend fun list(identity: IsgWorkspaceIdentity, company: String? = null, after: String? = null): Page {
        val page = rpc(identity, "isg_pilot_training_sessions_v2", buildJsonObject {
            put("p_company", company?.let(::JsonPrimitive) ?: JsonNull); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull)
        }).decode(PageEnvelope.serializer())
        if (page.schemaVersion != 2 || !page.ownerId.sameId(identity.userId) || page.rows.size > 30 ||
            page.rows.any { row -> !owned(identity, row) || row.companies.isEmpty() || row.companies.any { !it.ownerId.sameId(identity.userId) } })
            throw NovaTrainingException("ACCESS_DENIED")
        return Page(page.rows, page.nextId, page.writableCompanies.map { it.lowercase() }.toSet())
    }

    @Serializable private data class CompanyTrainingPage(@SerialName("schema_version") val schemaVersion: Int,
        @SerialName("owner_id") val ownerId: String, @SerialName("company_id") val companyId: String, val completed: Int? = null)

    /** Completed trainings of one company, as the company page counts them (iOS `NovaTrainingService.list(company).completed`). */
    suspend fun completed(identity: IsgWorkspaceIdentity, company: String): Int {
        val page = rpc(identity, "isg_pilot_training_read_v1", buildJsonObject {
            put("p_company", company); put("p_id", JsonNull); put("p_after", JsonNull)
        }).decode(CompanyTrainingPage.serializer())
        if (page.schemaVersion != 1 || !page.ownerId.sameId(identity.userId) || !page.companyId.sameId(company)) throw NovaTrainingException("ACCESS_DENIED")
        return page.completed ?: 0
    }

    suspend fun context(identity: IsgWorkspaceIdentity, id: String?): NovaEducationContext {
        val result = rpc(identity, "isg_pilot_training_detail_v3", buildJsonObject { put("p_id", id?.let(::JsonPrimitive) ?: JsonNull) })
            .decode(NovaEducationContext.serializer())
        if (result.schemaVersion != 3 || !result.ownerId.sameId(identity.userId) || !owned(identity, result.row)) throw NovaTrainingException("ACCESS_DENIED")
        return result
    }

    fun draft(identity: IsgWorkspaceIdentity, id: String?): NovaEducationDraft? {
        check(identity)
        return storage.getString(draftKey(identity, id), null)?.let { runCatching { json.decodeFromString(NovaEducationDraft.serializer(), it) }.getOrNull() }
    }

    fun preserve(identity: IsgWorkspaceIdentity, draft: NovaEducationDraft) {
        check(identity)
        storage.edit().putString(draftKey(identity, draft.id), json.encodeToString(NovaEducationDraft.serializer(), draft)).apply()
    }

    /** Drops the autosave so the next open starts genuinely fresh. */
    fun discardDraft(identity: IsgWorkspaceIdentity, id: String?) {
        check(identity)
        storage.edit().remove(draftKey(identity, id)).apply()
    }

    fun pending(identity: IsgWorkspaceIdentity): NovaEducationDraft? {
        check(identity)
        return storage.getString(key(identity, "pending"), null)?.let { runCatching { json.decodeFromString(Pending.serializer(), it).draft }.getOrNull() }
    }

    suspend fun save(identity: IsgWorkspaceIdentity, draft: NovaEducationDraft): Receipt {
        check(identity)
        val pendingKey = key(identity, "pending")
        val pending = storage.getString(pendingKey, null)?.let { json.decodeFromString(Pending.serializer(), it) }?.also {
            if (it.draft != draft) throw NovaTrainingException("PENDING_CONFLICT")
        } ?: Pending(UUID.randomUUID().toString(), draft).also {
            storage.edit().putString(pendingKey, json.encodeToString(Pending.serializer(), it)).commit()
        }
        try {
            val result = rpc(identity, "isg_pilot_training_record_v3", buildJsonObject {
                put("p_mutation", pending.mutation); put("p_payload", json.encodeToJsonElement(NovaEducationDraft.serializer(), pending.draft))
            }).decode(ReceiptEnvelope.serializer())
            if (result.schemaVersion != 3 || !result.ownerId.sameId(identity.userId) || !result.mutationId.sameId(pending.mutation) || !owned(identity, result.row))
                throw NovaTrainingException("ACCESS_DENIED")
            val editor = storage.edit().remove(pendingKey)
            if (draft.action != "curriculum") editor.remove(draftKey(identity, draft.id))
            editor.apply()
            events.recordsChanged(identity.userId)
            events.succeeded(identity.userId, when (draft.action) {
                "delete" -> "Eğitim başarıyla kaldırıldı!"
                "curriculum" -> NovaSuccessWords.recordSaved("Firma müfredatı")
                else -> "Eğitim başarıyla kaydedildi!"
            })
            return Receipt(result.row, result.curriculumSaved == true)
        } catch (error: NovaTrainingException) {
            if (error.sqlState in setOf("P0001", "28000", "22007", "22008", "22P02", "23514", "23502")) storage.edit().remove(pendingKey).apply()
            throw error
        }
    }

    /** An issue request keeps its mutation id per person until the server answers, so a retry never numbers twice. */
    suspend fun certificate(identity: IsgWorkspaceIdentity, request: NovaEducationCertificateRequest): NovaEducationCertificate {
        check(identity)
        val account = key(identity, "certificate:${request.sessionId.orEmpty()}:${request.scopeId.orEmpty()}:${request.personId.orEmpty()}".lowercase())
        val sent = if (request.action == "issue") {
            storage.getString(account, null)?.let { json.decodeFromString(NovaEducationCertificateRequest.serializer(), it) }?.also {
                if (it.expectedVersion != request.expectedVersion) throw NovaTrainingException("PENDING_CONFLICT")
            } ?: request.copy(mutationId = UUID.randomUUID().toString()).also {
                storage.edit().putString(account, json.encodeToString(NovaEducationCertificateRequest.serializer(), it)).commit()
            }
        } else request
        try {
            val result = rpc(identity, "isg_pilot_training_certificate_v1", buildJsonObject {
                put("p_payload", json.encodeToJsonElement(NovaEducationCertificateRequest.serializer(), sent))
            }).decode(NovaEducationCertificate.serializer())
            val snapshot = result.snapshot
            if (result.schemaVersion != 1 || !result.ownerId.sameId(identity.userId) || snapshot.completionBasis != "expert_record" ||
                snapshot.schemaVersion != 1 || snapshot.templateVersion != 1 || snapshot.themeVersion != 1 ||
                (sent.personId != null && !snapshot.person.id.sameId(sent.personId))) throw NovaTrainingException("ACCESS_DENIED")
            if (sent.action == "issue") storage.edit().remove(account).apply()
            return result
        } catch (error: NovaTrainingException) {
            if (sent.action == "issue" && error.sqlState in setOf("P0001", "28000", "22P02")) storage.edit().remove(account).apply()
            throw error
        }
    }

    /**
     * The company logo a draft certificate prints, as a PNG no larger than 256 px and 256 KB.
     * Only this account's own company logos are read; anything else prints without one.
     */
    suspend fun logo(identity: IsgWorkspaceIdentity, path: String?): String? {
        if (path == null || !path.lowercase().startsWith(identity.userId.lowercase() + "/companies/")) return null
        check(identity)
        val data = runCatching { client.storage.from("logos").downloadAuthenticated(path) }.getOrNull() ?: return null
        check(identity)
        if (data.size > 4_194_304) return null
        val bitmap = android.graphics.BitmapFactory.decodeByteArray(data, 0, data.size) ?: return null
        val ratio = minOf(256f / bitmap.width, 256f / bitmap.height, 1f)
        val resized = android.graphics.Bitmap.createScaledBitmap(bitmap, maxOf(1, (bitmap.width * ratio).toInt()), maxOf(1, (bitmap.height * ratio).toInt()), true)
        val bytes = java.io.ByteArrayOutputStream().also { resized.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        if (resized !== bitmap) resized.recycle()
        bitmap.recycle()
        return if (bytes.size <= 262_144) android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP) else null
    }
}
