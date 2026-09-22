package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import javax.inject.Inject
import javax.inject.Singleton

/** Where an appointment stands today; every state is its own counter. */
enum class NovaAppointmentState(val wire: String, val title: String, val footer: String, val symbol: String) {
    active("active", "Görevde", "yürürlükte", "person.badge.shield.checkmark"),
    upcoming("upcoming", "Başlayacak", "ileri tarihli", "calendar.badge.clock"),
    ended("ended", "Sona erdi", "geçmiş", "person.badge.minus");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

/** The roles the schema fixes. */
enum class NovaAppointmentKind(val wire: String, val title: String) {
    representative("representative", "Çalışan temsilcisi"), supportStaff("support_staff", "Destek elemanı"),
    teamMember("team_member", "Ekip üyesi"), firstAid("first_aid", "İlk yardımcı"), fireTeam("fire_team", "Yangın ekibi");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

/** Why this person holds the role: elected by the workers or appointed by the employer. */
enum class NovaAppointmentBasis(val wire: String, val title: String, val symbol: String) {
    elected("elected", "Seçimle", "hand.raised"), appointed("appointed", "Atamayla", "signature");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

data class NovaAppointmentAssetDownload(val bucket: String, val path: String)

data class NovaAppointment(
    val id: String, val companyId: String?, val companyName: String?, val employeeId: String?, val employeeName: String?,
    val employeeArchived: Boolean, val workplaceId: String?, val workplaceName: String?, val kind: NovaAppointmentKind,
    val usualBasis: NovaAppointmentBasis?, val startsOn: String, val endsBefore: String?, val state: NovaAppointmentState,
    val basis: NovaAppointmentBasis?, val basisNote: String?, val assetId: String?, val assetDownload: NovaAppointmentAssetDownload?,
    /** Nothing legal was checked, and there is nowhere to record that it was. */
    val qualificationVerified: Boolean,
)

data class NovaAppointmentCatalogue(val roles: List<Role>, val bases: List<NovaAppointmentBasis>, val workplaces: List<Workplace>,
                                    val employees: List<Employee>, val requiredCountKnown: Boolean, val qualificationCheckAvailable: Boolean) {
    data class Workplace(val id: String, val name: String)
    data class Employee(val id: String, val fullName: String)
    data class Role(val kind: NovaAppointmentKind, val usualBasis: NovaAppointmentBasis)
}

data class NovaAppointmentBoard(val rows: List<NovaAppointment>, val counts: Map<String, Int>, val companies: List<CompanyTally>, val total: Int,
                                val hasMore: Boolean, val offset: Int) {
    data class CompanyTally(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    fun count(state: NovaAppointmentState) = counts[state.wire] ?: 0
}

data class NovaAppointmentQuery(val company: String? = null, val state: String? = null, val workplace: String? = null, val role: String? = null,
                                val search: String = "", val limit: Int = 10, val offset: Int = 0)

data class NovaAppointmentDraft(val employeeId: String? = null, val workplaceId: String? = null,
                                val kind: NovaAppointmentKind = NovaAppointmentKind.representative,
                                val basis: NovaAppointmentBasis = NovaAppointmentBasis.elected, val startsOn: String = "", val endsBefore: String = "",
                                val basisNote: String = "",
                                /** Opaque archive reference to the appointment letter; the file itself is never sent here. */
                                val letterLocation: String = "")

data class NovaAppointmentEndDraft(val appointmentId: String? = null, val employeeName: String = "", val startsOn: String = "",
                                   val endsBefore: String = "", val isCorrection: Boolean = false)

enum class NovaAppointmentFailure(val message: String) {
    denied("Bu kayda erişim yok."), planRequired("Bu işlem için Plus veya Pro aboneliği gerekiyor."),
    featureUnavailable("Modüller henüz açık değil."), moduleUnavailable("Atama modülü henüz açık değil."),
    validation("Girilen bilgiler eksik veya birbiriyle uyumsuz."), conflict("Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin."),
    overlap("Aynı kişi aynı görevi aynı işyerinde çakışan tarihlerde üstlenemez."),
    basisRequired("Görevin seçimle mi atamayla mı verildiğini belirtin."), unavailable("Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin."),
}

class NovaAppointmentException(val failure: NovaAppointmentFailure) : Exception(failure.name)

object NovaAppointmentWords {
    fun explain(entry: NovaAppointment) = when (entry.state) {
        NovaAppointmentState.active -> entry.endsBefore?.let { "${NovaDayText.label(it)} tarihine kadar görevde." } ?: "Bitiş tarihi girilmemiş; görev sürüyor."
        NovaAppointmentState.upcoming -> "${NovaDayText.label(entry.startsOn)} tarihinde başlayacak."
        NovaAppointmentState.ended -> "${NovaDayText.label(entry.endsBefore ?: entry.startsOn)} tarihinde sona erdi."
    }
    const val noQualificationNote = "Görevi üstlenmek yeterli olmak demek değildir. Uygulama hiçbir yasal şartı doğrulamaz ve kimseye yeterli etiketi koymaz."
    const val noRequiredCountNote = "Ürün bir işyeri için kaç kişi gerektiğini söylemez; onaylanmış bir sayı kataloğu yok."
    const val letterNote = "Atama yazısının kendisi burada tutulmaz; yalnızca arşivdeki konumu kaydedilir."
}

/** ISO day text for data-layer sentences; 2026-09-22 reads 22.09.2026. */
object NovaDayText {
    fun label(value: String): String {
        val parts = value.split('-')
        return if (parts.size == 3) "${parts[2]}.${parts[1]}.${parts[0]}" else value
    }
}

/** Atama ve Temsilciler boundary (iOS `NovaAppointmentService` + live adapter). */
@Singleton
class NovaAppointmentService @Inject constructor(private val transport: NovaExpertTransport, private val journal: NovaModuleMutationJournal) {
    @Serializable private data class AssetRow(val bucket: String, val path: String)
    @Serializable private data class AppointmentRow(
        val id: String, @SerialName("company_id") val companyId: String? = null, @SerialName("company_name") val companyName: String? = null,
        @SerialName("employee_id") val employeeId: String? = null, @SerialName("employee_name") val employeeName: String? = null,
        @SerialName("employee_archived") val employeeArchived: Boolean, @SerialName("workplace_id") val workplaceId: String? = null,
        @SerialName("workplace_name") val workplaceName: String? = null, val kind: String, @SerialName("usual_basis") val usualBasis: String? = null,
        @SerialName("starts_on") val startsOn: String, @SerialName("ends_before") val endsBefore: String? = null, val state: String,
        val basis: String? = null, @SerialName("basis_note") val basisNote: String? = null, @SerialName("asset_id") val assetId: String? = null,
        @SerialName("asset_download") val assetDownload: AssetRow? = null, @SerialName("qualification_verified") val qualificationVerified: Boolean)
    @Serializable private data class KindRow(val code: String, val ordinal: Int, @SerialName("usual_basis") val usualBasis: String)
    @Serializable private data class WorkplaceRow(val id: String, val name: String)
    @Serializable private data class EmployeeRow(val id: String, @SerialName("full_name") val fullName: String)
    @Serializable private data class CatalogEnvelope(val kinds: List<KindRow>, val bases: List<String>, val workplaces: List<WorkplaceRow>,
        val employees: List<EmployeeRow>, @SerialName("required_count_known") val requiredCountKnown: Boolean,
        @SerialName("qualification_check_available") val qualificationCheckAvailable: Boolean)
    @Serializable private data class CompanyRow(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    @Serializable private data class ListEnvelope(val rows: List<AppointmentRow>, val companies: List<CompanyRow>, val counts: Map<String, Int>,
        val total: Int, @SerialName("has_more") val hasMore: Boolean, val offset: Int)
    @Serializable private data class DetailEnvelope(val row: AppointmentRow)
    @Serializable private data class MutationEnvelope(@SerialName("appointment_id") val appointmentId: String? = null, val row: AppointmentRow? = null)

    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaAppointmentException(NovaAppointmentFailure.denied)
    }

    private fun map(failure: NovaExpertFailure): NovaAppointmentFailure = when {
        failure.sqlState !in setOf("P0001", "28000") && failure.code != "ACCESS_DENIED" -> NovaAppointmentFailure.unavailable
        failure.code in setOf("AUTH_REQUIRED", "ACCESS_DENIED") -> NovaAppointmentFailure.denied
        failure.code == "PAID_PLAN_REQUIRED" -> NovaAppointmentFailure.planRequired
        failure.code == "FEATURE_UNAVAILABLE" -> NovaAppointmentFailure.featureUnavailable
        failure.code == "MODULE_UNAVAILABLE" -> NovaAppointmentFailure.moduleUnavailable
        failure.code == "APPOINTMENT_OVERLAP" -> NovaAppointmentFailure.overlap
        failure.code == "BASIS_REQUIRED" -> NovaAppointmentFailure.basisRequired
        failure.code == "IDEMPOTENCY_CONFLICT" -> NovaAppointmentFailure.conflict
        failure.code in setOf("VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED") -> NovaAppointmentFailure.validation
        else -> NovaAppointmentFailure.unavailable
    }

    private suspend fun <T> guarded(block: suspend () -> T): T = try { block() } catch (failure: NovaExpertFailure) {
        currentCoroutineContext().ensureActive(); throw NovaAppointmentException(map(failure))
    }

    private fun <T> JsonElement.decode(serializer: KSerializer<T>): T = try { novaJson.decodeFromJsonElement(serializer, this) }
        catch (_: Exception) { throw NovaAppointmentException(NovaAppointmentFailure.unavailable) }

    /** An unknown state word reads as active rather than the calmest answer. */
    private fun appointment(entry: AppointmentRow) = NovaAppointment(entry.id, entry.companyId, entry.companyName, entry.employeeId, entry.employeeName,
        entry.employeeArchived, entry.workplaceId, entry.workplaceName, NovaAppointmentKind.of(entry.kind) ?: NovaAppointmentKind.representative,
        NovaAppointmentBasis.of(entry.usualBasis), entry.startsOn, entry.endsBefore, NovaAppointmentState.of(entry.state) ?: NovaAppointmentState.active,
        NovaAppointmentBasis.of(entry.basis), entry.basisNote, entry.assetId, entry.assetDownload?.let { NovaAppointmentAssetDownload(it.bucket, it.path) },
        entry.qualificationVerified)

    private suspend fun read(arguments: Map<String, JsonElement>): JsonElement = guarded {
        val payload = mutableMapOf<String, JsonElement>("p_company" to JsonNull, "p_kind" to JsonPrimitive("list"), "p_query" to JsonNull,
            "p_state" to JsonNull, "p_workplace" to JsonNull, "p_role" to JsonNull, "p_id" to JsonNull, "p_limit" to JsonNull, "p_offset" to JsonNull)
        payload.putAll(arguments)
        transport.execute("isg_appointments_read_v1", JsonObject(payload))
    }

    private fun text(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull
    private fun isDay(value: String) = runCatching { java.time.LocalDate.parse(value) }.isSuccess

    suspend fun catalogue(identity: IsgWorkspaceIdentity, company: String?): NovaAppointmentCatalogue {
        check(identity)
        val envelope = read(mapOf("p_company" to text(company), "p_kind" to JsonPrimitive("catalog"))).decode(CatalogEnvelope.serializer())
        check(identity)
        return NovaAppointmentCatalogue(
            envelope.kinds.sortedBy { it.ordinal }.mapNotNull { row ->
                val kind = NovaAppointmentKind.of(row.code); val basis = NovaAppointmentBasis.of(row.usualBasis)
                if (kind != null && basis != null) NovaAppointmentCatalogue.Role(kind, basis) else null
            },
            envelope.bases.mapNotNull { NovaAppointmentBasis.of(it) }, envelope.workplaces.map { NovaAppointmentCatalogue.Workplace(it.id, it.name) },
            envelope.employees.map { NovaAppointmentCatalogue.Employee(it.id, it.fullName) }, envelope.requiredCountKnown, envelope.qualificationCheckAvailable)
    }

    suspend fun board(identity: IsgWorkspaceIdentity, query: NovaAppointmentQuery): NovaAppointmentBoard {
        check(identity)
        val envelope = read(mapOf("p_company" to text(query.company), "p_query" to text(query.search.trim().ifEmpty { null }),
            "p_state" to text(query.state), "p_workplace" to text(query.workplace), "p_role" to text(query.role),
            "p_limit" to JsonPrimitive(query.limit), "p_offset" to JsonPrimitive(query.offset))).decode(ListEnvelope.serializer())
        check(identity)
        return NovaAppointmentBoard(envelope.rows.map(::appointment), envelope.counts,
            envelope.companies.map { NovaAppointmentBoard.CompanyTally(it.id, it.name, it.total, it.counts) }, envelope.total, envelope.hasMore, envelope.offset)
    }

    suspend fun detail(identity: IsgWorkspaceIdentity, appointment: String): NovaAppointment {
        check(identity)
        val row = read(mapOf("p_kind" to JsonPrimitive("detail"), "p_id" to JsonPrimitive(appointment))).decode(DetailEnvelope.serializer()).row
        check(identity); return appointment(row)
    }

    private suspend fun mutate(identity: IsgWorkspaceIdentity, company: String, action: String, payload: JsonObject): NovaAppointment? {
        check(identity)
        return guarded { journal.run("isg_appointments_mutate_v1", identity, company, action, payload) { it.decode(MutationEnvelope.serializer()).row?.let(::appointment) } }
    }

    /** Saying why the person holds the role is required; there is no field for claiming they are qualified. */
    suspend fun record(identity: IsgWorkspaceIdentity, company: String, draft: NovaAppointmentDraft): NovaAppointment? {
        val employee = draft.employeeId; val workplace = draft.workplaceId
        if (employee == null || workplace == null || !isDay(draft.startsOn)) throw NovaAppointmentException(NovaAppointmentFailure.validation)
        return mutate(identity, company, "record_appointment", buildJsonObject {
            put("employee_id", employee); put("workplace_id", workplace); put("kind", draft.kind.wire); put("basis", draft.basis.wire)
            put("starts_on", draft.startsOn)
            if (isDay(draft.endsBefore)) put("ends_before", draft.endsBefore)
            draft.basisNote.trim().takeIf { it.isNotEmpty() }?.let { put("basis_note", it) }
            draft.letterLocation.trim().takeIf { it.isNotEmpty() }?.let { put("letter_location", it) }
        })
    }

    /** Ending it, or correcting the date it ended; the exclusion constraint guards the next appointment. */
    suspend fun end(identity: IsgWorkspaceIdentity, company: String, draft: NovaAppointmentEndDraft): NovaAppointment? {
        val appointment = draft.appointmentId
        if (appointment == null || !isDay(draft.endsBefore)) throw NovaAppointmentException(NovaAppointmentFailure.validation)
        return mutate(identity, company, "end_appointment", buildJsonObject { put("appointment_id", appointment); put("ends_before", draft.endsBefore) })
    }
}
