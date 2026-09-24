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
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** What the record says about one workplace today; always the server's answer. */
enum class NovaRiskState(val wire: String, val title: String) {
    neverAssessed("never_assessed", "Değerlendirilmemiş"), periodUnknown("period_unknown", "Süre bilinmiyor"),
    expired("expired", "Süresi doldu"), dueSoon("due_soon", "Yaklaşıyor"), valid("valid", "Yürürlükte");
    companion object { fun of(wire: String) = entries.firstOrNull { it.wire == wire } }
}

/** The four counters over five states; the same words are server filter values. */
enum class NovaRiskGroup(val wire: String, val title: String, val footer: String, val symbol: String, val states: List<NovaRiskState>) {
    expired("expired", "Süresi doldu", "tarih geçti", "exclamationmark.triangle", listOf(NovaRiskState.expired)),
    untracked("untracked", "Takipsiz", "belge yok", "questionmark.circle", listOf(NovaRiskState.neverAssessed, NovaRiskState.periodUnknown)),
    dueSoon("due_soon", "Yaklaşıyor", "yaklaşan", "clock", listOf(NovaRiskState.dueSoon)),
    current("current", "Güncel", "yürürlükte", "checkmark.circle", listOf(NovaRiskState.valid));
    companion object {
        fun of(state: NovaRiskState) = entries.firstOrNull { state in it.states } ?: untracked
        fun ofWire(wire: String?) = entries.firstOrNull { it.wire == wire }
    }
}

enum class NovaRiskKind(val title: String, val explain: String) {
    full("Tam yenileme", "Yeni bir değerlendirme tarihi taşır ve süreyi yeniden başlatır."),
    partial("Kısmi revizyon", "Belirli bölümleri günceller. Değerlendirme tarihini ve süreyi değiştirmez."),
    metadata("Bilgi düzeltmesi", "Yanlış yazılmış bilgiyi düzeltir. Değerlendirme tarihini ve süreyi değiştirmez."),
    rescan("Yeniden tarama", "Aynı belgenin daha iyi bir kopyasını ekler. Yenileme sayılmaz.");
    /** Only a full renewal carries a date of its own; the server refuses one on the others. */
    val carriesAssessmentDate: Boolean get() = this == full
    val needsReason: Boolean get() = this == partial || this == metadata
    val needsScope: Boolean get() = this == partial
    companion object { fun of(wire: String?) = entries.firstOrNull { it.name == wire } }
}

enum class NovaRiskPeriodSource(val wire: String, val title: String) {
    ruleVersion("rule_version", "Yayımlanmış kural"), unapprovedFixture("unapproved_fixture", "Uzman tarafından belirlenen"),
    hazardClass("hazard_class", "Tehlike sınıfına göre otomatik");
    val needsReview: Boolean get() = this == unapprovedFixture
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

data class NovaRiskSource(val id: String, val analysisId: String, val findingId: String, val sourceVersion: Int, val selectedAt: String?)

data class NovaRiskImpact(val id: String, val targetKind: String, val targetRef: String, val action: String, val note: String?) {
    val actionTitle: String get() = when (action) { "review" -> "Gözden geçirilecek"; "reschedule" -> "Yeniden planlanacak"; else -> "Değişiklik yok" }
}

data class NovaRiskVersion(
    val version: Int, val kind: NovaRiskKind, val previousVersion: Int?, val assessmentOn: String, val revisionOn: String?,
    val scope: List<String>, val reason: String?, val state: String, val finalizedAt: String?, val periodYears: Int?,
    val periodSource: NovaRiskPeriodSource?, val periodNeedsReview: Boolean, val dateNeedsReview: Boolean, val validUntil: String?,
    val sourceDrift: Boolean, val driftNote: String?, val fileAssetId: String?, val sources: List<NovaRiskSource>,
    val impacts: List<NovaRiskImpact>, val editRevision: Int = 0, val cancellationNote: String? = null,
) {
    val isDraft: Boolean get() = state == "draft"
    val isFinal: Boolean get() = state == "final"
}

data class NovaRiskRow(
    val id: String, val companyId: String?, val companyName: String?, val workplaceId: String?, val workplaceName: String?,
    val currentVersion: Int, val baseAssessmentOn: String?, val validUntil: String?, val state: NovaRiskState, val group: NovaRiskGroup,
    val noticeDays: Int, val currentKind: NovaRiskKind?, val currentAssessmentOn: String?, val currentRevisionOn: String?,
    val currentFileAssetId: String?, val periodYears: Int?, val periodSource: NovaRiskPeriodSource?, val periodNeedsReview: Boolean?,
    val dateNeedsReview: Boolean, val sourceDrift: Boolean, val driftNote: String?, val workplaceHazardClass: String?,
    val workplaceSuggestedPeriodYears: Int?, val hasOpenDraft: Boolean, val draftVersion: Int?, val draftKind: NovaRiskKind?,
    val draftAssessmentOn: String?, val draftReason: String?, val sourceLinkCount: Int, val versions: List<NovaRiskVersion>,
) {
    /** Why the row reads the way it does; every state has a reason. */
    val explain: String get() = when (state) {
        NovaRiskState.neverAssessed -> "Bu işyeri için tamamlanmış bir risk değerlendirmesi kaydı yok."
        NovaRiskState.periodUnknown -> "Belge var ama geçerlilik süresi kayıtlı değil. Süre girilene kadar tarih üretilmez."
        NovaRiskState.expired -> "Geçerlilik tarihi geçti."
        NovaRiskState.dueSoon -> "Geçerlilik tarihi uyarı penceresinin içinde."
        NovaRiskState.valid -> "Belge yürürlükte."
    }
}

data class NovaRiskCatalogue(val workplaces: List<Workplace>, val rules: List<Rule>, val noticeDays: Int, val expertPeriodNeedsReview: Boolean) {
    data class Workplace(val id: String, val name: String, val needsReview: Boolean, val hazardClass: String?, val suggestedPeriodYears: Int?)
    data class Rule(val ruleCode: String, val periodKind: String, val periodLength: Int?)
}

data class NovaRiskBoard(val rows: List<NovaRiskRow>, val counts: Map<String, Int>, val companies: List<CompanyTally>, val total: Int,
                         val hasMore: Boolean, val offset: Int, val noticeDays: Int) {
    data class CompanyTally(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    fun count(group: NovaRiskGroup) = group.states.sumOf { counts[it.wire] ?: 0 }
    val needsAttention: Int get() = count(NovaRiskGroup.expired) + count(NovaRiskGroup.dueSoon) + count(NovaRiskGroup.untracked)
}

data class NovaRiskQuery(val company: String? = null, val state: String? = null, val workplace: String? = null,
                         val search: String = "", val limit: Int = 10, val offset: Int = 0)

data class NovaRiskVersionDraft(val assessmentId: String? = null, val kind: NovaRiskKind = NovaRiskKind.full, val assessmentOn: String = "",
                                val revisionOn: String = "", val scope: List<String> = emptyList(), val reason: String = "",
                                val expectedCurrent: Int = 0, val versionToEdit: Int? = null, val editRevision: Int = 0,
                                val fileAssetId: String? = null)

data class NovaRiskFinalizeDraft(val assessmentId: String? = null, val version: Int = 0, val expectedCurrent: Int = 0,
                                 val ruleCode: String = "", val periodYears: String = "", val kind: NovaRiskKind = NovaRiskKind.full,
                                 val editRevision: Int = 0, val suggestedYears: Int? = null)

enum class NovaRiskFailure(val message: String) {
    denied("Bu kayda erişim yok."), planRequired("Bu işlem için Plus veya Pro aboneliği gerekiyor."),
    moduleUnavailable("Risk değerlendirmesi modülü henüz açık değil."), validation("Girilen bilgiler eksik veya birbiriyle uyumsuz."),
    conflict("Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin."),
    dateInFuture("Değerlendirme tarihi bugünden ileri olamaz."), dateImmutable("Değerlendirme tarihi yalnızca tam yenilemede değişir."),
    draftOpen("Bu değerlendirmede zaten açık bir taslak var. Önce onu tamamlayın."),
    versionFinalized("Tamamlanmış sürüm değiştirilemez."),
    ruleNeedsReview("Seçilen kural yayımlanmış değil. Süreyi kendiniz belirleyebilirsiniz."),
    unavailable("Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin."),
}

class NovaRiskException(val failure: NovaRiskFailure) : Exception(failure.name)

object NovaRiskWords {
    const val periodAttribution = "Süre kaynağı her satırda yazılıdır. Uzmanın kendi belirlediği süre mevzuat gereği olarak sunulmaz."
    const val analysisNotAssessment = "Fotoğraf analizi kaynak olarak kullanılabilir; tek başına risk değerlendirmesi sayılmaz."
}

/** The risk assessment boundary (iOS `NovaRiskAssessmentService`). */
@Singleton
class NovaRiskService @Inject constructor(private val transport: NovaExpertTransport, private val journal: NovaModuleMutationJournal,
                                          private val events: NovaRecordEvents) {
    @Serializable private data class SourceRow(val id: String, @SerialName("analysis_id") val analysisId: String,
        @SerialName("finding_id") val findingId: String, @SerialName("source_version") val sourceVersion: Int,
        @SerialName("selected_at") val selectedAt: String? = null)
    @Serializable private data class ImpactRow(val id: String, @SerialName("target_kind") val targetKind: String,
        @SerialName("target_ref") val targetRef: String, val action: String, val note: String? = null)
    @Serializable private data class VersionRow(
        val version: Int, val kind: String, @SerialName("edit_revision") val editRevision: Int? = null,
        @SerialName("cancellation_note") val cancellationNote: String? = null, @SerialName("previous_version") val previousVersion: Int? = null,
        @SerialName("assessment_on") val assessmentOn: String, @SerialName("revision_on") val revisionOn: String? = null,
        val scope: List<String>? = null, val reason: String? = null, val state: String, @SerialName("finalized_at") val finalizedAt: String? = null,
        @SerialName("period_years") val periodYears: Int? = null, @SerialName("period_source") val periodSource: String? = null,
        @SerialName("period_needs_review") val periodNeedsReview: Boolean? = null, @SerialName("date_needs_review") val dateNeedsReview: Boolean? = null,
        @SerialName("valid_until") val validUntil: String? = null, @SerialName("source_drift") val sourceDrift: Boolean? = null,
        @SerialName("drift_note") val driftNote: String? = null, @SerialName("file_asset_id") val fileAssetId: String? = null,
        val sources: List<SourceRow>? = null, val impacts: List<ImpactRow>? = null)
    @Serializable private data class AssessmentRow(
        val id: String, @SerialName("company_id") val companyId: String? = null, @SerialName("company_name") val companyName: String? = null,
        @SerialName("workplace_id") val workplaceId: String? = null, @SerialName("workplace_name") val workplaceName: String? = null,
        @SerialName("current_version") val currentVersion: Int, @SerialName("base_assessment_on") val baseAssessmentOn: String? = null,
        @SerialName("valid_until") val validUntil: String? = null, val state: String, @SerialName("notice_days") val noticeDays: Int,
        @SerialName("current_kind") val currentKind: String? = null, @SerialName("current_assessment_on") val currentAssessmentOn: String? = null,
        @SerialName("current_revision_on") val currentRevisionOn: String? = null,
        @SerialName("current_file_asset_id") val currentFileAssetId: String? = null, @SerialName("period_years") val periodYears: Int? = null,
        @SerialName("period_source") val periodSource: String? = null, @SerialName("period_needs_review") val periodNeedsReview: Boolean? = null,
        @SerialName("date_needs_review") val dateNeedsReview: Boolean? = null, @SerialName("source_drift") val sourceDrift: Boolean? = null,
        @SerialName("drift_note") val driftNote: String? = null, @SerialName("workplace_hazard_class") val workplaceHazardClass: String? = null,
        @SerialName("workplace_suggested_period_years") val workplaceSuggestedPeriodYears: Int? = null,
        @SerialName("has_open_draft") val hasOpenDraft: Boolean, @SerialName("draft_version") val draftVersion: Int? = null,
        @SerialName("draft_kind") val draftKind: String? = null, @SerialName("draft_assessment_on") val draftAssessmentOn: String? = null,
        @SerialName("draft_reason") val draftReason: String? = null, @SerialName("source_link_count") val sourceLinkCount: Int? = null,
        val versions: List<VersionRow>? = null)
    @Serializable private data class WorkplaceRow(val id: String, val name: String, @SerialName("needs_review") val needsReview: Boolean,
        @SerialName("hazard_class") val hazardClass: String? = null, @SerialName("suggested_period_years") val suggestedPeriodYears: Int? = null)
    @Serializable private data class RuleRow(@SerialName("rule_code") val ruleCode: String, @SerialName("period_kind") val periodKind: String,
        @SerialName("period_length") val periodLength: Int? = null)
    @Serializable private data class CatalogEnvelope(val workplaces: List<WorkplaceRow>, val rules: List<RuleRow>,
        @SerialName("notice_days") val noticeDays: Int, @SerialName("expert_period_needs_review") val expertPeriodNeedsReview: Boolean)
    @Serializable private data class CompanyRow(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    @Serializable private data class ListEnvelope(val rows: List<AssessmentRow>, val companies: List<CompanyRow>, val counts: Map<String, Int>,
        val total: Int, @SerialName("has_more") val hasMore: Boolean, val offset: Int, @SerialName("notice_days") val noticeDays: Int)
    @Serializable private data class DetailEnvelope(val row: AssessmentRow)
    @Serializable private data class MutationEnvelope(@SerialName("assessment_id") val assessmentId: String? = null, val row: AssessmentRow? = null)

    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaRiskException(NovaRiskFailure.denied)
    }

    private fun map(failure: NovaExpertFailure): NovaRiskFailure = when {
        failure.sqlState !in setOf("P0001", "28000") && failure.code != "ACCESS_DENIED" -> NovaRiskFailure.unavailable
        failure.code in setOf("AUTH_REQUIRED", "ACCESS_DENIED") -> NovaRiskFailure.denied
        failure.code == "PAID_PLAN_REQUIRED" -> NovaRiskFailure.planRequired
        failure.code == "FEATURE_UNAVAILABLE" -> NovaRiskFailure.moduleUnavailable
        failure.code in setOf("VERSION_CONFLICT", "IDEMPOTENCY_CONFLICT") -> NovaRiskFailure.conflict
        failure.code == "ASSESSMENT_DATE_IN_FUTURE" -> NovaRiskFailure.dateInFuture
        failure.code == "ASSESSMENT_DATE_IMMUTABLE" -> NovaRiskFailure.dateImmutable
        failure.code == "DRAFT_ALREADY_OPEN" -> NovaRiskFailure.draftOpen
        failure.code == "VERSION_FINALIZED" -> NovaRiskFailure.versionFinalized
        failure.code == "RULE_NEEDS_REVIEW" -> NovaRiskFailure.ruleNeedsReview
        failure.code in setOf("VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED") -> NovaRiskFailure.validation
        else -> NovaRiskFailure.unavailable
    }

    private suspend fun <T> guarded(block: suspend () -> T): T = try { block() } catch (failure: NovaExpertFailure) {
        currentCoroutineContext().ensureActive(); throw NovaRiskException(map(failure))
    }

    private fun <T> JsonElement.decode(serializer: KSerializer<T>): T = try { novaJson.decodeFromJsonElement(serializer, this) }
        catch (_: Exception) { throw NovaRiskException(NovaRiskFailure.unavailable) }

    private fun version(entry: VersionRow) = NovaRiskVersion(entry.version, NovaRiskKind.of(entry.kind) ?: NovaRiskKind.full,
        entry.previousVersion, entry.assessmentOn, entry.revisionOn, entry.scope.orEmpty(), entry.reason, entry.state, entry.finalizedAt,
        entry.periodYears, NovaRiskPeriodSource.of(entry.periodSource), entry.periodNeedsReview ?: false, entry.dateNeedsReview ?: false,
        entry.validUntil, entry.sourceDrift ?: false, entry.driftNote, entry.fileAssetId,
        entry.sources.orEmpty().map { NovaRiskSource(it.id, it.analysisId, it.findingId, it.sourceVersion, it.selectedAt) },
        entry.impacts.orEmpty().map { NovaRiskImpact(it.id, it.targetKind, it.targetRef, it.action, it.note) },
        entry.editRevision ?: 0, entry.cancellationNote)

    /** An unknown state word reads as never assessed rather than the calmest answer. */
    private fun row(entry: AssessmentRow): NovaRiskRow {
        val state = NovaRiskState.of(entry.state) ?: NovaRiskState.neverAssessed
        return NovaRiskRow(entry.id, entry.companyId, entry.companyName, entry.workplaceId, entry.workplaceName, entry.currentVersion,
            entry.baseAssessmentOn, entry.validUntil, state, NovaRiskGroup.of(state), entry.noticeDays, NovaRiskKind.of(entry.currentKind),
            entry.currentAssessmentOn, entry.currentRevisionOn, entry.currentFileAssetId, entry.periodYears,
            NovaRiskPeriodSource.of(entry.periodSource), entry.periodNeedsReview, entry.dateNeedsReview ?: false, entry.sourceDrift ?: false,
            entry.driftNote, entry.workplaceHazardClass, entry.workplaceSuggestedPeriodYears, entry.hasOpenDraft, entry.draftVersion,
            NovaRiskKind.of(entry.draftKind), entry.draftAssessmentOn, entry.draftReason, entry.sourceLinkCount ?: 0,
            entry.versions.orEmpty().map(::version))
    }

    private suspend fun read(arguments: Map<String, JsonElement>): JsonElement = guarded {
        val payload = mutableMapOf<String, JsonElement>("p_company" to JsonNull, "p_kind" to JsonPrimitive("list"), "p_query" to JsonNull,
            "p_state" to JsonNull, "p_workplace" to JsonNull, "p_id" to JsonNull, "p_limit" to JsonNull, "p_offset" to JsonNull)
        payload.putAll(arguments)
        transport.execute("isg_risk_versions_read_v1", JsonObject(payload))
    }

    private fun id(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull

    suspend fun catalogue(identity: IsgWorkspaceIdentity, company: String?): NovaRiskCatalogue {
        check(identity)
        val envelope = read(mapOf("p_company" to id(company), "p_kind" to JsonPrimitive("catalog"))).decode(CatalogEnvelope.serializer())
        check(identity)
        return NovaRiskCatalogue(envelope.workplaces.map { NovaRiskCatalogue.Workplace(it.id, it.name, it.needsReview, it.hazardClass, it.suggestedPeriodYears) },
            envelope.rules.map { NovaRiskCatalogue.Rule(it.ruleCode, it.periodKind, it.periodLength) }, envelope.noticeDays, envelope.expertPeriodNeedsReview)
    }

    suspend fun board(identity: IsgWorkspaceIdentity, query: NovaRiskQuery): NovaRiskBoard {
        check(identity)
        val needle = query.search.trim()
        val envelope = read(mapOf("p_company" to id(query.company), "p_query" to id(needle.ifEmpty { null }), "p_state" to id(query.state),
            "p_workplace" to id(query.workplace), "p_limit" to JsonPrimitive(query.limit), "p_offset" to JsonPrimitive(query.offset)))
            .decode(ListEnvelope.serializer())
        check(identity)
        return NovaRiskBoard(envelope.rows.map(::row), envelope.counts, envelope.companies.map { NovaRiskBoard.CompanyTally(it.id, it.name, it.total, it.counts) },
            envelope.total, envelope.hasMore, envelope.offset, envelope.noticeDays)
    }

    suspend fun detail(identity: IsgWorkspaceIdentity, assessment: String): NovaRiskRow {
        check(identity)
        val row = read(mapOf("p_kind" to JsonPrimitive("detail"), "p_id" to JsonPrimitive(assessment))).decode(DetailEnvelope.serializer()).row
        check(identity); return row(row)
    }

    private suspend fun mutate(identity: IsgWorkspaceIdentity, company: String, action: String, payload: JsonObject): NovaRiskRow? = guarded {
        journal.run("isg_risk_versions_mutate_v1", identity, company, action, payload) { it.decode(MutationEnvelope.serializer()).row?.let(::row) }
    }

    /** Opening a workplace's record twice is the same record; no durable receipt is needed. */
    suspend fun open(identity: IsgWorkspaceIdentity, company: String, workplace: String?): NovaRiskRow? = guarded {
        check(identity)
        val data = transport.execute("isg_risk_versions_mutate_v1", buildJsonObject {
            put("p_company", company); put("p_action", "open_assessment"); put("p_operation", UUID.randomUUID().toString())
            put("p_mutation", UUID.randomUUID().toString()); putJsonObject("p_payload") { put("workplace_id", workplace) }
        })
        check(identity)
        events.recordsChanged(identity.userId)
        data.decode(MutationEnvelope.serializer()).row?.let(::row)
    }

    suspend fun draft(identity: IsgWorkspaceIdentity, company: String, draft: NovaRiskVersionDraft): NovaRiskRow? {
        val assessment = draft.assessmentId ?: throw NovaRiskException(NovaRiskFailure.validation)
        val payload = buildJsonObject {
            put("assessment_id", assessment)
            if (draft.versionToEdit == null) put("kind", draft.kind.name)
            put("expected_current", draft.expectedCurrent)
            // Sending a date on anything but a renewal is what the server calls ASSESSMENT_DATE_IMMUTABLE.
            if (draft.kind.carriesAssessmentDate && runCatching { java.time.LocalDate.parse(draft.assessmentOn) }.isSuccess) put("assessment_on", draft.assessmentOn)
            if (runCatching { java.time.LocalDate.parse(draft.revisionOn) }.isSuccess) put("revision_on", draft.revisionOn)
            if (draft.kind.needsScope) putJsonArray("scope") { draft.scope.forEach { add(it) } }
            draft.reason.trim().takeIf { it.isNotEmpty() }?.let { put("reason", it) }
            draft.fileAssetId?.let { put("file_asset_id", it) }
            draft.versionToEdit?.let { put("version", it); put("expected_edit_revision", draft.editRevision) }
        }
        return mutate(identity, company, if (draft.versionToEdit != null) "edit_draft" else "draft_version", payload)
    }

    suspend fun cancelDraft(identity: IsgWorkspaceIdentity, company: String, row: NovaRiskRow, version: NovaRiskVersion, reason: String) =
        mutate(identity, company, "cancel_draft", buildJsonObject {
            put("assessment_id", row.id); put("version", version.version); put("expected_current", row.currentVersion)
            put("expected_edit_revision", version.editRevision); put("cancellation_note", reason)
        })

    /** The verification is the signed-in expert's own; there is no field for naming someone else. */
    suspend fun finalize(identity: IsgWorkspaceIdentity, company: String, draft: NovaRiskFinalizeDraft): NovaRiskRow? {
        val assessment = draft.assessmentId ?: throw NovaRiskException(NovaRiskFailure.validation)
        return mutate(identity, company, "finalize_version", buildJsonObject {
            put("assessment_id", assessment); put("version", draft.version); put("expected_current", draft.expectedCurrent)
            put("expected_edit_revision", draft.editRevision)
            val rule = draft.ruleCode.trim()
            if (rule.isNotEmpty()) put("rule_code", rule) else draft.periodYears.trim().toIntOrNull()?.let { put("period_years", it) }
        })
    }
}
