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

/** What a drill says about itself today. A passed date reads overdue, never performed. */
enum class NovaDrillState(val wire: String, val title: String) {
    overdue("overdue", "Tarihi geçti"), dueSoon("due_soon", "Yaklaşıyor"), scheduled("scheduled", "Planlandı"),
    performed("performed", "Yapıldı"), cancelled("cancelled", "İptal edildi");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

enum class NovaDrillGroup(val wire: String, val title: String, val footer: String, val symbol: String, val states: List<NovaDrillState>) {
    overdue("overdue", "Geçti", "yapılmadı", "exclamationmark.triangle", listOf(NovaDrillState.overdue)),
    dueSoon("due_soon", "Yaklaşıyor", "yaklaşan", "clock", listOf(NovaDrillState.dueSoon)),
    scheduled("scheduled", "Planlı", "ileri tarihli", "calendar", listOf(NovaDrillState.scheduled)),
    closed("closed", "Kapandı", "yapıldı / iptal", "checkmark.circle", listOf(NovaDrillState.performed, NovaDrillState.cancelled));
    companion object {
        fun of(state: NovaDrillState) = entries.firstOrNull { state in it.states } ?: scheduled
        fun ofWire(wire: String?) = entries.firstOrNull { it.wire == wire }
    }
}

data class NovaDrillParticipant(val id: String, val fullName: String)

data class NovaDrill(
    val id: String, val companyId: String?, val companyName: String?, val workplaceId: String?, val workplaceName: String?,
    val planId: String, val planVersion: Int, val planScope: String?, val planVersionSuperseded: Boolean, val plannedOn: String,
    val performedOn: String?, val state: NovaDrillState, val group: NovaDrillGroup, val noticeDays: Int,
    /** Read from the record, never inferred from a date going by. */
    val performed: Boolean, val observation: String?, val improvement: String?, val cancelledReason: String?,
    val participants: List<NovaDrillParticipant>, val participantCount: Int, val participantsSnapshotted: Boolean,
) {
    val explain: String get() = when (state) {
        NovaDrillState.overdue -> "Planlanan tarih geçti ve tatbikat kaydı girilmedi."
        NovaDrillState.dueSoon -> "Planlanan tarih uyarı penceresinin içinde."
        NovaDrillState.scheduled -> "İleri bir tarihe planlandı. Planlamak yapmak değildir."
        NovaDrillState.performed -> "$participantCount katılımcıyla yapıldı."
        NovaDrillState.cancelled -> cancelledReason ?: "Bu tatbikattan vazgeçildi."
    }
}

data class NovaDrillPlanOption(val planId: String, val version: Int, val scope: String, val workplaceId: String, val workplaceName: String,
                               val validUntil: String?)

data class NovaDrillCatalogue(val plans: List<NovaDrillPlanOption>, val employees: List<NovaDrillParticipant>, val noticeDays: Int,
                              val periodDefaultsOffered: Boolean)

data class NovaDrillBoard(val rows: List<NovaDrill>, val counts: Map<String, Int>, val companies: List<CompanyTally>, val total: Int,
                          val hasMore: Boolean, val offset: Int, val noticeDays: Int) {
    data class CompanyTally(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    fun count(group: NovaDrillGroup) = group.states.sumOf { counts[it.wire] ?: 0 }
}

data class NovaDrillQuery(val company: String? = null, val state: String? = null, val workplace: String? = null,
                          val search: String = "", val limit: Int = 10, val offset: Int = 0)

data class NovaDrillPlanDraft(val planId: String? = null, val plannedOn: String = "")

data class NovaDrillResultDraft(val drillId: String? = null, val planScope: String = "", val performedOn: String = "",
                                val participants: Set<String> = emptySet(), val observation: String = "", val improvement: String = "")

enum class NovaDrillFailure(val message: String) {
    denied("Bu kayda erişim yok."), planRequired("Bu işlem için Plus veya Pro aboneliği gerekiyor."),
    featureUnavailable("Modüller henüz açık değil."), moduleUnavailable("Tatbikat modülü henüz açık değil."),
    validation("Girilen bilgiler eksik veya birbiriyle uyumsuz."), conflict("Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin."),
    performedInFuture("Tatbikat tarihi bugünden ileri olamaz."), participantOutOfScope("Katılımcılardan biri bu firmanın personeli değil."),
    alreadyPerformed("Yapılmış tatbikat iptal edilemez veya yeniden yazılamaz."), unavailable("Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin."),
}

class NovaDrillException(val failure: NovaDrillFailure) : Exception(failure.name)

object NovaDrillWords {
    const val planningIsNotPerforming = "Planlamak yapmak değildir. Tarihi geçen tatbikat yapılmış sayılmaz; kaydı siz girersiniz."
    const val snapshotNote = "Katılımcılar kaydettiğiniz andaki adlarıyla donar. Personel kaydı sonradan değişse de bu tatbikat değişmez."
    const val pinnedNote = "Tatbikat, prova ettiği plan sürümüne sabitlidir. Sonradan yayımlanan plan bu kaydı taşımaz."
    const val noPlan = "Önce bir acil durum planı yayımlayın; tatbikat bir plan sürümünü prova eder."
}

/** Tatbikatlar boundary (iOS `NovaDrillService` + live adapter). */
@Singleton
class NovaDrillService @Inject constructor(private val transport: NovaExpertTransport, private val journal: NovaModuleMutationJournal) {
    @Serializable private data class ParticipantRow(val id: String, @SerialName("full_name") val fullName: String)
    @Serializable private data class DrillRow(
        val id: String, @SerialName("company_id") val companyId: String? = null, @SerialName("company_name") val companyName: String? = null,
        @SerialName("workplace_id") val workplaceId: String? = null, @SerialName("workplace_name") val workplaceName: String? = null,
        @SerialName("plan_id") val planId: String, @SerialName("plan_version") val planVersion: Int, @SerialName("plan_scope") val planScope: String? = null,
        @SerialName("plan_version_superseded") val planVersionSuperseded: Boolean, @SerialName("planned_on") val plannedOn: String,
        @SerialName("performed_on") val performedOn: String? = null, val state: String, @SerialName("notice_days") val noticeDays: Int,
        val performed: Boolean, val observation: String? = null, val improvement: String? = null,
        @SerialName("cancelled_reason") val cancelledReason: String? = null, val participants: List<ParticipantRow>? = null,
        @SerialName("participant_count") val participantCount: Int, @SerialName("participants_snapshotted") val participantsSnapshotted: Boolean)
    @Serializable private data class PlanOptionRow(@SerialName("plan_id") val planId: String, val version: Int, val scope: String,
        @SerialName("workplace_id") val workplaceId: String, @SerialName("workplace_name") val workplaceName: String,
        @SerialName("valid_until") val validUntil: String? = null)
    @Serializable private data class CatalogEnvelope(val plans: List<PlanOptionRow>, val employees: List<ParticipantRow>,
        @SerialName("notice_days") val noticeDays: Int, @SerialName("period_defaults_offered") val periodDefaultsOffered: Boolean)
    @Serializable private data class CompanyRow(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    @Serializable private data class ListEnvelope(val rows: List<DrillRow>, val companies: List<CompanyRow>, val counts: Map<String, Int>,
        val total: Int, @SerialName("has_more") val hasMore: Boolean, val offset: Int, @SerialName("notice_days") val noticeDays: Int)
    @Serializable private data class DetailEnvelope(val row: DrillRow)
    @Serializable private data class MutationEnvelope(@SerialName("drill_id") val drillId: String? = null, val row: DrillRow? = null)

    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaDrillException(NovaDrillFailure.denied)
    }

    private fun map(failure: NovaExpertFailure): NovaDrillFailure = when {
        failure.sqlState !in setOf("P0001", "28000") && failure.code != "ACCESS_DENIED" -> NovaDrillFailure.unavailable
        failure.code in setOf("AUTH_REQUIRED", "ACCESS_DENIED") -> NovaDrillFailure.denied
        failure.code == "PAID_PLAN_REQUIRED" -> NovaDrillFailure.planRequired
        failure.code == "FEATURE_UNAVAILABLE" -> NovaDrillFailure.featureUnavailable
        failure.code == "MODULE_UNAVAILABLE" -> NovaDrillFailure.moduleUnavailable
        failure.code == "PERFORMED_IN_THE_FUTURE" -> NovaDrillFailure.performedInFuture
        failure.code == "PARTICIPANT_OUT_OF_SCOPE" -> NovaDrillFailure.participantOutOfScope
        failure.code == "DRILL_PERFORMED" -> NovaDrillFailure.alreadyPerformed
        failure.code == "IDEMPOTENCY_CONFLICT" -> NovaDrillFailure.conflict
        failure.code in setOf("VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED") -> NovaDrillFailure.validation
        else -> NovaDrillFailure.unavailable
    }

    private suspend fun <T> guarded(block: suspend () -> T): T = try { block() } catch (failure: NovaExpertFailure) {
        currentCoroutineContext().ensureActive(); throw NovaDrillException(map(failure))
    }

    private fun <T> JsonElement.decode(serializer: KSerializer<T>): T = try { novaJson.decodeFromJsonElement(serializer, this) }
        catch (_: Exception) { throw NovaDrillException(NovaDrillFailure.unavailable) }

    /** An unknown state word reads as overdue rather than the calmest answer. */
    private fun drill(entry: DrillRow): NovaDrill {
        val state = NovaDrillState.of(entry.state) ?: NovaDrillState.overdue
        return NovaDrill(entry.id, entry.companyId, entry.companyName, entry.workplaceId, entry.workplaceName, entry.planId, entry.planVersion,
            entry.planScope, entry.planVersionSuperseded, entry.plannedOn, entry.performedOn, state, NovaDrillGroup.of(state), entry.noticeDays,
            entry.performed, entry.observation, entry.improvement, entry.cancelledReason,
            entry.participants.orEmpty().map { NovaDrillParticipant(it.id, it.fullName) }, entry.participantCount, entry.participantsSnapshotted)
    }

    private suspend fun read(arguments: Map<String, JsonElement>): JsonElement = guarded {
        val payload = mutableMapOf<String, JsonElement>("p_company" to JsonNull, "p_kind" to JsonPrimitive("list"), "p_query" to JsonNull,
            "p_state" to JsonNull, "p_workplace" to JsonNull, "p_id" to JsonNull, "p_limit" to JsonNull, "p_offset" to JsonNull)
        payload.putAll(arguments)
        transport.execute("isg_drills_read_v1", JsonObject(payload))
    }

    private fun text(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull
    private fun isDay(value: String) = runCatching { java.time.LocalDate.parse(value) }.isSuccess

    /** An empty plan list is the honest answer: a drill has nowhere to point without one. */
    suspend fun catalogue(identity: IsgWorkspaceIdentity, company: String?): NovaDrillCatalogue {
        check(identity)
        val envelope = read(mapOf("p_company" to text(company), "p_kind" to JsonPrimitive("catalog"))).decode(CatalogEnvelope.serializer())
        check(identity)
        return NovaDrillCatalogue(envelope.plans.map { NovaDrillPlanOption(it.planId, it.version, it.scope, it.workplaceId, it.workplaceName, it.validUntil) },
            envelope.employees.map { NovaDrillParticipant(it.id, it.fullName) }, envelope.noticeDays, envelope.periodDefaultsOffered)
    }

    suspend fun board(identity: IsgWorkspaceIdentity, query: NovaDrillQuery): NovaDrillBoard {
        check(identity)
        val envelope = read(mapOf("p_company" to text(query.company), "p_query" to text(query.search.trim().ifEmpty { null }),
            "p_state" to text(query.state), "p_workplace" to text(query.workplace), "p_limit" to JsonPrimitive(query.limit),
            "p_offset" to JsonPrimitive(query.offset))).decode(ListEnvelope.serializer())
        check(identity)
        return NovaDrillBoard(envelope.rows.map(::drill), envelope.counts, envelope.companies.map { NovaDrillBoard.CompanyTally(it.id, it.name, it.total, it.counts) },
            envelope.total, envelope.hasMore, envelope.offset, envelope.noticeDays)
    }

    suspend fun detail(identity: IsgWorkspaceIdentity, drill: String): NovaDrill {
        check(identity)
        val row = read(mapOf("p_kind" to JsonPrimitive("detail"), "p_id" to JsonPrimitive(drill))).decode(DetailEnvelope.serializer()).row
        check(identity); return drill(row)
    }

    private suspend fun mutate(identity: IsgWorkspaceIdentity, company: String, action: String, payload: JsonObject): NovaDrill? {
        check(identity)
        return guarded { journal.run("isg_drills_mutate_v1", identity, company, action, payload) { it.decode(MutationEnvelope.serializer()).row?.let(::drill) } }
    }

    /** Planning names a plan, never a version: the server pins the one in force. */
    suspend fun plan(identity: IsgWorkspaceIdentity, company: String, draft: NovaDrillPlanDraft): NovaDrill? {
        val plan = draft.planId
        if (plan == null || !isDay(draft.plannedOn)) throw NovaDrillException(NovaDrillFailure.validation)
        return mutate(identity, company, "plan_drill", buildJsonObject { put("plan_id", plan); put("planned_on", draft.plannedOn) })
    }

    suspend fun record(identity: IsgWorkspaceIdentity, company: String, draft: NovaDrillResultDraft): NovaDrill? {
        val drill = draft.drillId
        if (drill == null || draft.participants.isEmpty() || !isDay(draft.performedOn)) throw NovaDrillException(NovaDrillFailure.validation)
        return mutate(identity, company, "record_result", buildJsonObject {
            put("drill_id", drill); put("performed_on", draft.performedOn)
            // Sorted, so a retried save hashes to the same durable request.
            putJsonArray("participants") { draft.participants.sorted().forEach { add(it) } }
            draft.observation.trim().takeIf { it.isNotEmpty() }?.let { put("observation", it) }
            draft.improvement.trim().takeIf { it.isNotEmpty() }?.let { put("improvement", it) }
        })
    }

    /** Only a planned drill can be withdrawn, and only with a reason. */
    suspend fun cancel(identity: IsgWorkspaceIdentity, company: String, drill: String, reason: String): NovaDrill? {
        val trimmed = reason.trim()
        if (trimmed.isEmpty()) throw NovaDrillException(NovaDrillFailure.validation)
        return mutate(identity, company, "cancel_drill", buildJsonObject { put("drill_id", drill); put("reason", trimmed) })
    }
}
