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

/** What a plan says about itself today; always the server's answer. */
enum class NovaEmergencyState(val wire: String, val title: String) {
    neverPublished("never_published", "Plan yok"), periodUnknown("period_unknown", "Süre yazılmamış"),
    expired("expired", "Süresi doldu"), dueSoon("due_soon", "Yaklaşıyor"), valid("valid", "Yürürlükte");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

enum class NovaEmergencyGroup(val wire: String, val title: String, val footer: String, val symbol: String, val states: List<NovaEmergencyState>) {
    expired("expired", "Süresi doldu", "tarih geçti", "exclamationmark.triangle", listOf(NovaEmergencyState.expired)),
    untracked("untracked", "Takipsiz", "süre yazılmamış", "questionmark.circle", listOf(NovaEmergencyState.neverPublished, NovaEmergencyState.periodUnknown)),
    dueSoon("due_soon", "Yaklaşıyor", "yaklaşan", "clock", listOf(NovaEmergencyState.dueSoon)),
    current("current", "Güncel", "yürürlükte", "checkmark.circle", listOf(NovaEmergencyState.valid));
    companion object {
        fun of(state: NovaEmergencyState) = entries.firstOrNull { state in it.states } ?: untracked
        fun ofWire(wire: String?) = entries.firstOrNull { it.wire == wire }
    }
}

/** The roles a team entry may carry; the set lives in the schema. */
enum class NovaEmergencyRole(val wire: String, val title: String, val symbol: String) {
    coordinator("coordinator", "Koordinatör", "person.badge.shield.checkmark"), fire("fire", "Yangın", "flame"),
    firstAid("first_aid", "İlk yardım", "cross.case"), evacuation("evacuation", "Tahliye", "figure.walk.departure"),
    other("other", "Diğer", "person");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

/** One person frozen into a plan: a snapshot, never a link to personnel. */
data class NovaEmergencyMember(val fullName: String, val role: NovaEmergencyRole, val contact: String?) {
    val key: String get() = fullName + role.wire
}

data class NovaEmergencyAssetDownload(val bucket: String, val path: String)

data class NovaEmergencyVersion(val version: Int, val state: String, val scope: String, val preparedOn: String, val validUntil: String?,
                                val needsReview: Boolean, val reviewNote: String?, val team: List<NovaEmergencyMember>, val assetId: String?,
                                val createdAt: String?) {
    val isActive: Boolean get() = state == "active"
}

data class NovaEmergencyPlan(
    val id: String, val companyId: String?, val companyName: String?, val workplaceId: String?, val workplaceName: String?,
    val version: Int, val versionsTotal: Int, val scope: String, val preparedOn: String, val validUntil: String?,
    val state: NovaEmergencyState, val group: NovaEmergencyGroup, val noticeDays: Int,
    /** Forced by the absence of a written basis; nothing on this side can set it. */
    val needsReview: Boolean, val reviewNote: String?, val team: List<NovaEmergencyMember>, val teamSize: Int,
    val assetId: String?, val assetDownload: NovaEmergencyAssetDownload?, val versions: List<NovaEmergencyVersion>,
) {
    val explain: String get() = when (state) {
        NovaEmergencyState.neverPublished -> "Bu işyeri için yayımlanmış plan yok."
        NovaEmergencyState.periodUnknown -> "Plan var ama geçerlilik bitişi yazılmamış. Tarih girilene kadar takip üretilmez."
        NovaEmergencyState.expired -> "Geçerlilik tarihi geçti."
        NovaEmergencyState.dueSoon -> "Geçerlilik tarihi uyarı penceresinin içinde."
        NovaEmergencyState.valid -> "Plan yürürlükte."
    }
}

data class NovaEmergencyCatalogue(val workplaces: List<Workplace>, val roles: List<NovaEmergencyRole>, val supportStaff: List<SupportStaff>,
                                  val noticeDays: Int, val periodDefaultsOffered: Boolean) {
    data class Workplace(val id: String, val name: String, val needsReview: Boolean, val hazardClass: String?, val suggestedPeriodYears: Int?)
    /** Who the company already lists as destek elemanı; a suggestion only. */
    data class SupportStaff(val id: String, val fullName: String, val workplaceName: String?)
}

data class NovaEmergencyBoard(val rows: List<NovaEmergencyPlan>, val counts: Map<String, Int>, val companies: List<CompanyTally>,
                              val total: Int, val hasMore: Boolean, val offset: Int, val noticeDays: Int) {
    data class CompanyTally(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    fun count(group: NovaEmergencyGroup) = group.states.sumOf { counts[it.wire] ?: 0 }
}

data class NovaEmergencyQuery(val company: String? = null, val state: String? = null, val workplace: String? = null,
                              val search: String = "", val limit: Int = 10, val offset: Int = 0)

/** Publishing a plan or its next version; a published version is never edited. */
data class NovaEmergencyPlanDraft(val planId: String? = null, val workplaceId: String? = null, val scope: String = "Acil Durum Planı",
                                  val preparedOn: String = "", val validUntil: String = "", val reviewNote: String = "",
                                  val team: List<NovaEmergencyMember> = emptyList(), val assetId: String? = null) {
    val isRenewal: Boolean get() = planId != null
}

enum class NovaEmergencyFailure(val message: String) {
    denied("Bu kayda erişim yok."), planRequired("Bu işlem için Plus veya Pro aboneliği gerekiyor."),
    featureUnavailable("Modüller henüz açık değil."), moduleUnavailable("Acil durum planları modülü henüz açık değil."),
    validation("Girilen bilgiler eksik veya birbiriyle uyumsuz."), conflict("Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin."),
    preparedInFuture("Hazırlanma tarihi bugünden ileri olamaz."), roleUnknown("Ekip görevi tanınmadı."),
    unavailable("Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin."),
}

class NovaEmergencyException(val failure: NovaEmergencyFailure) : Exception(failure.name)

object NovaEmergencyWords {
    const val periodAttribution = "Ürün yenileme süresi önermez. Yazdığınız tarih uzmanın kendi kararı olarak kaydedilir."
    const val reviewNote = "Dayanağını yazmadığınız plan gözden geçirilecek olarak işaretlenir. Bu işaret elle kaldırılamaz."
    const val renewalNote = "Yenileme yeni bir sürüm açar. Önceki sürüm kendi ekibi, tarihleri ve kapsamıyla kayıtta kalır."
}

/** Acil durum planları boundary (iOS `NovaEmergencyPlanService` + live adapter). */
@Singleton
class NovaEmergencyService @Inject constructor(private val transport: NovaExpertTransport, private val journal: NovaModuleMutationJournal) {
    @Serializable private data class MemberRow(@SerialName("full_name") val fullName: String, val role: String, val contact: String? = null)
    @Serializable private data class VersionRow(val version: Int, val state: String, val scope: String, @SerialName("prepared_on") val preparedOn: String,
        @SerialName("valid_until") val validUntil: String? = null, @SerialName("needs_review") val needsReview: Boolean,
        @SerialName("review_note") val reviewNote: String? = null, val team: List<MemberRow>? = null, @SerialName("asset_id") val assetId: String? = null,
        @SerialName("created_at") val createdAt: String? = null)
    @Serializable private data class AssetRow(val bucket: String, val path: String)
    @Serializable private data class PlanRow(
        val id: String, @SerialName("company_id") val companyId: String? = null, @SerialName("company_name") val companyName: String? = null,
        @SerialName("workplace_id") val workplaceId: String? = null, @SerialName("workplace_name") val workplaceName: String? = null,
        val version: Int, @SerialName("versions_total") val versionsTotal: Int, val scope: String, @SerialName("prepared_on") val preparedOn: String,
        @SerialName("valid_until") val validUntil: String? = null, val state: String, @SerialName("notice_days") val noticeDays: Int,
        @SerialName("needs_review") val needsReview: Boolean, @SerialName("review_note") val reviewNote: String? = null,
        val team: List<MemberRow>? = null, @SerialName("team_size") val teamSize: Int, @SerialName("asset_id") val assetId: String? = null,
        @SerialName("asset_download") val assetDownload: AssetRow? = null, val versions: List<VersionRow>? = null)
    @Serializable private data class WorkplaceRow(val id: String, val name: String, @SerialName("needs_review") val needsReview: Boolean,
        @SerialName("hazard_class") val hazardClass: String? = null, @SerialName("suggested_period_years") val suggestedPeriodYears: Int? = null)
    @Serializable private data class RoleRow(val code: String, val ordinal: Int)
    @Serializable private data class StaffRow(@SerialName("employee_id") val employeeId: String, @SerialName("full_name") val fullName: String,
        @SerialName("workplace_name") val workplaceName: String? = null)
    @Serializable private data class CatalogEnvelope(val workplaces: List<WorkplaceRow>, @SerialName("team_roles") val teamRoles: List<RoleRow>,
        @SerialName("support_staff") val supportStaff: List<StaffRow>? = null, @SerialName("notice_days") val noticeDays: Int,
        @SerialName("period_defaults_offered") val periodDefaultsOffered: Boolean)
    @Serializable private data class CompanyRow(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    @Serializable private data class ListEnvelope(val rows: List<PlanRow>, val companies: List<CompanyRow>, val counts: Map<String, Int>,
        val total: Int, @SerialName("has_more") val hasMore: Boolean, val offset: Int, @SerialName("notice_days") val noticeDays: Int)
    @Serializable private data class DetailEnvelope(val row: PlanRow)
    @Serializable private data class MutationEnvelope(@SerialName("plan_id") val planId: String? = null, val row: PlanRow? = null)

    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaEmergencyException(NovaEmergencyFailure.denied)
    }

    private fun map(failure: NovaExpertFailure): NovaEmergencyFailure = when {
        failure.sqlState !in setOf("P0001", "28000") && failure.code != "ACCESS_DENIED" -> NovaEmergencyFailure.unavailable
        failure.code in setOf("AUTH_REQUIRED", "ACCESS_DENIED") -> NovaEmergencyFailure.denied
        failure.code == "PAID_PLAN_REQUIRED" -> NovaEmergencyFailure.planRequired
        failure.code == "FEATURE_UNAVAILABLE" -> NovaEmergencyFailure.featureUnavailable
        failure.code == "MODULE_UNAVAILABLE" -> NovaEmergencyFailure.moduleUnavailable
        failure.code == "PREPARED_IN_THE_FUTURE" -> NovaEmergencyFailure.preparedInFuture
        failure.code == "TEAM_ROLE_UNKNOWN" -> NovaEmergencyFailure.roleUnknown
        failure.code == "IDEMPOTENCY_CONFLICT" -> NovaEmergencyFailure.conflict
        failure.code in setOf("VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED") -> NovaEmergencyFailure.validation
        else -> NovaEmergencyFailure.unavailable
    }

    private suspend fun <T> guarded(block: suspend () -> T): T = try { block() } catch (failure: NovaExpertFailure) {
        currentCoroutineContext().ensureActive(); throw NovaEmergencyException(map(failure))
    }

    private fun <T> JsonElement.decode(serializer: KSerializer<T>): T = try { novaJson.decodeFromJsonElement(serializer, this) }
        catch (_: Exception) { throw NovaEmergencyException(NovaEmergencyFailure.unavailable) }

    private fun members(rows: List<MemberRow>?) = rows.orEmpty().mapNotNull { entry ->
        NovaEmergencyRole.of(entry.role)?.let { NovaEmergencyMember(entry.fullName, it, entry.contact) }
    }

    /** An unknown state word reads as never published rather than the calmest answer. */
    private fun plan(entry: PlanRow): NovaEmergencyPlan {
        val state = NovaEmergencyState.of(entry.state) ?: NovaEmergencyState.neverPublished
        return NovaEmergencyPlan(entry.id, entry.companyId, entry.companyName, entry.workplaceId, entry.workplaceName, entry.version,
            entry.versionsTotal, entry.scope, entry.preparedOn, entry.validUntil, state, NovaEmergencyGroup.of(state), entry.noticeDays,
            entry.needsReview, entry.reviewNote, members(entry.team), entry.teamSize, entry.assetId,
            entry.assetDownload?.let { NovaEmergencyAssetDownload(it.bucket, it.path) },
            entry.versions.orEmpty().map { NovaEmergencyVersion(it.version, it.state, it.scope, it.preparedOn, it.validUntil, it.needsReview,
                it.reviewNote, members(it.team), it.assetId, it.createdAt) })
    }

    private suspend fun read(arguments: Map<String, JsonElement>): JsonElement = guarded {
        val payload = mutableMapOf<String, JsonElement>("p_company" to JsonNull, "p_kind" to JsonPrimitive("list"), "p_query" to JsonNull,
            "p_state" to JsonNull, "p_workplace" to JsonNull, "p_id" to JsonNull, "p_limit" to JsonNull, "p_offset" to JsonNull)
        payload.putAll(arguments)
        transport.execute("isg_emergency_plans_read_v1", JsonObject(payload))
    }

    private fun text(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull

    suspend fun catalogue(identity: IsgWorkspaceIdentity, company: String?): NovaEmergencyCatalogue {
        check(identity)
        val envelope = read(mapOf("p_company" to text(company), "p_kind" to JsonPrimitive("catalog"))).decode(CatalogEnvelope.serializer())
        check(identity)
        return NovaEmergencyCatalogue(
            envelope.workplaces.map { NovaEmergencyCatalogue.Workplace(it.id, it.name, it.needsReview, it.hazardClass, it.suggestedPeriodYears) },
            envelope.teamRoles.sortedBy { it.ordinal }.mapNotNull { NovaEmergencyRole.of(it.code) },
            envelope.supportStaff.orEmpty().map { NovaEmergencyCatalogue.SupportStaff(it.employeeId, it.fullName, it.workplaceName) },
            envelope.noticeDays, envelope.periodDefaultsOffered)
    }

    suspend fun board(identity: IsgWorkspaceIdentity, query: NovaEmergencyQuery): NovaEmergencyBoard {
        check(identity)
        val envelope = read(mapOf("p_company" to text(query.company), "p_query" to text(query.search.trim().ifEmpty { null }),
            "p_state" to text(query.state), "p_workplace" to text(query.workplace), "p_limit" to JsonPrimitive(query.limit),
            "p_offset" to JsonPrimitive(query.offset))).decode(ListEnvelope.serializer())
        check(identity)
        return NovaEmergencyBoard(envelope.rows.map(::plan), envelope.counts,
            envelope.companies.map { NovaEmergencyBoard.CompanyTally(it.id, it.name, it.total, it.counts) }, envelope.total, envelope.hasMore,
            envelope.offset, envelope.noticeDays)
    }

    suspend fun detail(identity: IsgWorkspaceIdentity, plan: String): NovaEmergencyPlan {
        check(identity)
        val row = read(mapOf("p_kind" to JsonPrimitive("detail"), "p_id" to JsonPrimitive(plan))).decode(DetailEnvelope.serializer()).row
        check(identity); return plan(row)
    }

    /** Publishing is the only write; correcting a plan means publishing the next version. */
    suspend fun publish(identity: IsgWorkspaceIdentity, company: String, draft: NovaEmergencyPlanDraft): NovaEmergencyPlan? {
        val workplace = draft.workplaceId
        if (workplace == null || draft.team.isEmpty()) throw NovaEmergencyException(NovaEmergencyFailure.validation)
        val payload = buildJsonObject {
            put("workplace_id", workplace); put("scope", draft.scope.trim()); put("prepared_on", draft.preparedOn)
            // Only the three keys the server's snapshot check accepts.
            putJsonArray("team") {
                draft.team.forEach { member ->
                    addJsonObject {
                        put("full_name", member.fullName); put("role", member.role.wire)
                        member.contact?.takeIf { it.isNotEmpty() }?.let { put("contact", it) }
                    }
                }
            }
            draft.planId?.let { put("plan_id", it) }
            if (runCatching { java.time.LocalDate.parse(draft.validUntil) }.isSuccess) put("valid_until", draft.validUntil)
            draft.assetId?.let { put("asset_id", it) }
            draft.reviewNote.trim().takeIf { it.isNotEmpty() }?.let { put("review_note", it) }
        }
        check(identity)
        return guarded {
            journal.run("isg_emergency_plans_mutate_v1", identity, company, "publish_plan", payload) { it.decode(MutationEnvelope.serializer()).row?.let(::plan) }
        }
    }
}
