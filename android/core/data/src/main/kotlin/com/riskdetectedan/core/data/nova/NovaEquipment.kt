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

/** What the inventory says about one item today; always the server's answer. */
enum class NovaEquipmentState(val wire: String) {
    neverInspected("never_inspected"), periodUnknown("period_unknown"), failed("failed"), overdue("overdue"),
    dueSoon("due_soon"), valid("valid");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

/** Five counters over six states; the same words are filter values the server accepts. */
enum class NovaEquipmentGroup(val wire: String, val title: String, val footer: String, val symbol: String, val states: List<NovaEquipmentState>) {
    overdue("overdue", "Süresi geçti", "tarih geçti", "exclamationmark.triangle", listOf(NovaEquipmentState.overdue)),
    failed("failed", "Olumsuz", "son rapor", "xmark.octagon", listOf(NovaEquipmentState.failed)),
    untracked("untracked", "Takipsiz", "tarih yok", "questionmark.circle", listOf(NovaEquipmentState.neverInspected, NovaEquipmentState.periodUnknown)),
    dueSoon("due_soon", "Yaklaşıyor", "yaklaşan", "clock", listOf(NovaEquipmentState.dueSoon)),
    current("current", "Güncel", "raporlu", "checkmark.circle", listOf(NovaEquipmentState.valid));
    companion object {
        fun of(state: NovaEquipmentState) = entries.firstOrNull { state in it.states } ?: untracked
        fun ofWire(wire: String?) = entries.firstOrNull { it.wire == wire }
    }
}

/** Where a type's period came from; a period is never called a legal requirement on its own. */
enum class NovaEquipmentPeriodSource(val wire: String) {
    manufacturer("manufacturer"), ruleVersion("rule_version"), unapprovedFixture("unapproved_fixture"), regulationDefault("regulation_default");
    val needsReview: Boolean get() = this == unapprovedFixture || this == regulationDefault
    companion object {
        fun of(wire: String?) = entries.firstOrNull { it.wire == wire }
        /** What the expert may pick for themselves; the product default is the server's own label. */
        val choosable = listOf(manufacturer, ruleVersion, unapprovedFixture)
    }
}

enum class NovaEquipmentDueSource(val wire: String) {
    period("period"), expert("expert");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

data class NovaEquipmentAssetDownload(val bucket: String, val path: String)

data class NovaEquipmentRule(val equipmentType: String, val periodMonths: Int, val source: NovaEquipmentPeriodSource,
                             val needsReview: Boolean, val exceptionNote: String?)

data class NovaEquipmentSuggestion(val code: String, val defaultPeriodMonths: Int?, val defaultBasisNote: String?)

data class NovaEquipmentWorkplace(val id: String, val name: String)

data class NovaEquipmentCatalogue(val suggestions: List<NovaEquipmentSuggestion>, val rules: List<NovaEquipmentRule>,
                                  val workplaces: List<NovaEquipmentWorkplace>, val noticeDays: Int)

data class NovaEquipmentInspection(
    val id: String, val performedOn: String, val result: String, val nextDueOn: String?, val periodMonths: Int?,
    val inspector: String?, val externalRef: String?, val note: String?, val evidenceAssetId: String?,
    val evidenceDownload: NovaEquipmentAssetDownload?, val dueSource: NovaEquipmentDueSource?,
    val katipDeclared: Boolean, val katipNote: String?,
)

data class NovaEquipmentItem(
    val id: String, val companyId: String?, val companyName: String?, val workplaceId: String?, val equipmentType: String,
    val serialTag: String, val acquiredOn: String?, val locationNote: String?, val isArchived: Boolean,
    val state: NovaEquipmentState, val periodMonths: Int?, val periodSource: NovaEquipmentPeriodSource?,
    val periodNeedsReview: Boolean?, val periodExceptionNote: String?, val periodDefinedAfterReport: Boolean,
    val lastPerformedOn: String?, val lastResult: String?, val lastInspector: String?, val lastExternalRef: String?,
    val nextDueOn: String?, val dueSource: NovaEquipmentDueSource?, val katipDeclared: Boolean, val katipNote: String?,
    /** Structurally false: nothing in this product reads the official system. */
    val katipOfficialVerification: Boolean, val evidenceAssetId: String?, val evidenceDownload: NovaEquipmentAssetDownload?,
    val inspections: List<NovaEquipmentInspection>,
) {
    val group: NovaEquipmentGroup get() = NovaEquipmentGroup.of(state)
    fun matches(query: String): Boolean {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) return true
        return listOf(serialTag, equipmentType, NovaEquipmentWords.type(equipmentType), companyName.orEmpty(), locationNote.orEmpty(), lastInspector.orEmpty())
            .any { it.lowercase().contains(needle) }
    }
}

data class NovaEquipmentCompanySummary(val id: String, val name: String, val total: Int, val counts: Map<NovaEquipmentState, Int>) {
    fun count(group: NovaEquipmentGroup) = group.states.sumOf { counts[it] ?: 0 }
    val needsAttention: Int get() = (counts[NovaEquipmentState.overdue] ?: 0) + (counts[NovaEquipmentState.failed] ?: 0)
}

data class NovaEquipmentBoard(
    val counts: Map<NovaEquipmentState, Int> = emptyMap(), val companies: List<NovaEquipmentCompanySummary> = emptyList(),
    val typeCounts: Map<String, Map<NovaEquipmentState, Int>> = emptyMap(), val rows: List<NovaEquipmentItem> = emptyList(),
    val total: Int = 0, val hasMore: Boolean = false, val limit: Int = 10, val offset: Int = 0, val today: String = "",
    val noticeDays: Int = 30,
) {
    fun count(group: NovaEquipmentGroup) = group.states.sumOf { counts[it] ?: 0 }
    val needsAttention: Int get() = (counts[NovaEquipmentState.overdue] ?: 0) + (counts[NovaEquipmentState.failed] ?: 0)
}

data class NovaEquipmentQuery(val query: String = "", val state: String? = null, val company: String? = null,
                              val workplace: String? = null, val equipmentType: String? = null, val limit: Int = 10, val offset: Int = 0)

data class NovaEquipmentDraft(val equipmentType: String? = null, val serialTag: String = "", val workplaceId: String? = null,
                              val acquiredOn: String = "", val locationNote: String = "") {
    val isReady: Boolean get() = equipmentType != null && serialTag.isNotBlank()
}

data class NovaEquipmentRuleDraft(val equipmentType: String? = null, val periodMonths: String = "",
                                  val source: NovaEquipmentPeriodSource = NovaEquipmentPeriodSource.manufacturer, val exceptionNote: String = "") {
    val monthsValue: Int? get() = periodMonths.trim().toIntOrNull()
    val isReady: Boolean get() = equipmentType != null && (monthsValue ?: 0) in 1..240
}

data class NovaEquipmentInspectionDraft(
    val performedOn: String = "", val result: String = "pass", val nextDueOn: String = "", val inspector: String = "",
    val externalRef: String = "", val note: String = "", val katipDeclared: Boolean = false, val katipNote: String = "",
    val evidenceAssetId: String? = null, val evidenceTitle: String? = null,
) {
    val isReady: Boolean get() = performedOn.isNotBlank() && result in setOf("pass", "fail", "conditional")
}

enum class NovaEquipmentFailure(val message: String) {
    denied("Bu firmanın ekipman kayıtlarına erişim yok."), planRequired("Kayıt eklemek için Plus veya Pro plan gerekiyor."),
    moduleUnavailable("Periyodik kontroller modülü şu anda açık değil."), conflict("Bu işlem farklı bir içerikle zaten kaydedilmiş."),
    validation("Bilgiler eksik veya geçersiz."), futureReport("Kontrol tarihi bugünden ileri olamaz."),
    duplicateSerial("Bu seri/kod bu firmada zaten kayıtlı."), dueBeforeReport("Sonraki kontrol tarihi, kontrol tarihinden sonra olmalı."),
    dueOnFailedCheck("Olumsuz sonuçlanan kontrole sonraki tarih verilemez."), unavailable("Ekipman servisi şu anda kullanılamıyor."),
}

class NovaEquipmentException(val failure: NovaEquipmentFailure) : Exception(failure.name)

/** The words the module uses, so a state never reads as more than the record says. */
object NovaEquipmentWords {
    fun state(state: NovaEquipmentState) = when (state) {
        NovaEquipmentState.neverInspected -> "Kontrol kaydı yok"; NovaEquipmentState.periodUnknown -> "Süre belirsiz"
        NovaEquipmentState.failed -> "Olumsuz"; NovaEquipmentState.overdue -> "Süresi geçti"
        NovaEquipmentState.dueSoon -> "Yaklaşıyor"; NovaEquipmentState.valid -> "Güncel"
    }

    fun explain(item: NovaEquipmentItem) = when {
        item.state == NovaEquipmentState.neverInspected -> "Bu ekipman için kayıtlı kontrol raporu yok."
        item.state == NovaEquipmentState.periodUnknown && item.periodDefinedAfterReport ->
            "Rapor kaydedildiğinde bu tür için süre tanımlı değildi; sonraki tarih hesaplanmadı. Süre sonradan tanımlandı, eski rapor değiştirilmedi."
        item.state == NovaEquipmentState.periodUnknown ->
            "Bu tür için kontrol süresi tanımlı değil; sonraki kontrol tarihi hesaplanmadı. Süreler ekranından tanımlayabilirsiniz."
        item.state == NovaEquipmentState.failed -> "Son kontrol olumsuz sonuçlandı; sonraki tarih üretilmedi."
        item.state == NovaEquipmentState.overdue -> "Kayıtlı sonraki kontrol tarihi geçmiş."
        item.state == NovaEquipmentState.dueSoon -> "Kayıtlı sonraki kontrol tarihi yaklaşıyor."
        else -> "Kayıtlı sonraki kontrol tarihi henüz gelmedi."
    }

    fun result(value: String?) = when (value) {
        "pass" -> "Uygun"; "fail" -> "Olumsuz"; "conditional" -> "Şartlı uygun"; null -> "—"; else -> value
    }

    fun source(value: NovaEquipmentPeriodSource?) = when (value) {
        NovaEquipmentPeriodSource.manufacturer -> "Üretici/kullanma kılavuzu"
        NovaEquipmentPeriodSource.ruleVersion -> "Uzmanın dayandığı mevzuat"
        NovaEquipmentPeriodSource.unapprovedFixture -> "Uzman tarafından belirlenen"
        NovaEquipmentPeriodSource.regulationDefault -> "Mevzuat eki genel süresi · ürün varsayılanı"
        null -> "Tanımlı değil"
    }

    fun due(value: NovaEquipmentDueSource?) = when (value) {
        NovaEquipmentDueSource.period -> "Süreden hesaplandı"; NovaEquipmentDueSource.expert -> "Uzman tarafından değiştirildi"; null -> ""
    }

    private val types = mapOf(
        "lifting_equipment" to "Kaldırma ekipmanı", "crane" to "Vinç", "forklift" to "Forklift", "pressure_vessel" to "Basınçlı kap",
        "compressor" to "Kompresör", "boiler" to "Kazan", "lift" to "Asansör", "scaffold" to "İskele", "ladder" to "Merdiven",
        "electrical_installation" to "Elektrik tesisatı", "earthing" to "Topraklama", "fire_extinguisher" to "Yangın söndürücü",
        "fire_detection" to "Yangın algılama", "ventilation" to "Havalandırma", "power_tool" to "El aleti", "welding_set" to "Kaynak makinesi",
        "conveyor" to "Konveyör", "press_machine" to "Pres", "lathe" to "Torna", "other_equipment" to "Diğer ekipman")
    fun type(code: String) = types[code] ?: code
}

/** Periyodik kontroller boundary (iOS `NovaEquipmentCheckService` + live adapter). */
@Singleton
class NovaEquipmentService @Inject constructor(private val transport: NovaExpertTransport, private val events: NovaRecordEvents) {
    @Serializable private data class AssetRow(val bucket: String, val path: String)
    @Serializable private data class InspectionRow(
        val id: String, @SerialName("performed_on") val performedOn: String, val result: String,
        @SerialName("next_due_on") val nextDueOn: String? = null, @SerialName("period_months") val periodMonths: Int? = null,
        val inspector: String? = null, @SerialName("external_ref") val externalRef: String? = null, val note: String? = null,
        @SerialName("evidence_asset_id") val evidenceAssetId: String? = null, @SerialName("evidence_download") val evidenceDownload: AssetRow? = null,
        @SerialName("due_source") val dueSource: String? = null, @SerialName("katip_assignment_declared") val katipDeclared: Boolean? = null,
        @SerialName("katip_declared_note") val katipNote: String? = null)
    @Serializable private data class ItemRow(
        val id: String, @SerialName("company_id") val companyId: String? = null, @SerialName("company_name") val companyName: String? = null,
        @SerialName("workplace_id") val workplaceId: String? = null, @SerialName("equipment_type") val equipmentType: String,
        @SerialName("serial_tag") val serialTag: String, @SerialName("acquired_on") val acquiredOn: String? = null,
        @SerialName("location_note") val locationNote: String? = null, @SerialName("is_archived") val isArchived: Boolean, val state: String,
        @SerialName("period_months") val periodMonths: Int? = null, @SerialName("period_source") val periodSource: String? = null,
        @SerialName("period_needs_review") val periodNeedsReview: Boolean? = null,
        @SerialName("period_exception_note") val periodExceptionNote: String? = null,
        @SerialName("period_defined_after_report") val periodDefinedAfterReport: Boolean,
        @SerialName("last_performed_on") val lastPerformedOn: String? = null, @SerialName("last_result") val lastResult: String? = null,
        @SerialName("last_inspector") val lastInspector: String? = null, @SerialName("last_external_ref") val lastExternalRef: String? = null,
        @SerialName("next_due_on") val nextDueOn: String? = null, @SerialName("due_source") val dueSource: String? = null,
        @SerialName("katip_assignment_declared") val katipDeclared: Boolean? = null, @SerialName("katip_declared_note") val katipNote: String? = null,
        @SerialName("katip_official_verification") val katipOfficialVerification: Boolean? = null,
        @SerialName("evidence_asset_id") val evidenceAssetId: String? = null, @SerialName("evidence_download") val evidenceDownload: AssetRow? = null,
        val inspections: List<InspectionRow>? = null)
    @Serializable private data class SuggestionRow(val code: String, val ordinal: Int, @SerialName("default_period_months") val defaultPeriodMonths: Int? = null,
        @SerialName("default_basis_note") val defaultBasisNote: String? = null)
    @Serializable private data class RuleRow(@SerialName("equipment_type") val equipmentType: String, @SerialName("period_months") val periodMonths: Int,
        @SerialName("period_source") val periodSource: String, @SerialName("needs_review") val needsReview: Boolean,
        @SerialName("exception_note") val exceptionNote: String? = null)
    @Serializable private data class WorkplaceRow(val id: String, val name: String)
    @Serializable private data class CatalogEnvelope(val suggestions: List<SuggestionRow>, val rules: List<RuleRow>, val workplaces: List<WorkplaceRow>,
        @SerialName("notice_days") val noticeDays: Int)
    @Serializable private data class CompanyRow(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    @Serializable private data class ListEnvelope(val rows: List<ItemRow>, val companies: List<CompanyRow>, val counts: Map<String, Int>,
        @SerialName("type_counts") val typeCounts: Map<String, Map<String, Int>>, val total: Int, @SerialName("has_more") val hasMore: Boolean,
        val limit: Int, val offset: Int, val today: String, @SerialName("notice_days") val noticeDays: Int)
    @Serializable private data class DetailEnvelope(val row: ItemRow)
    @Serializable private data class MutationEnvelope(@SerialName("equipment_id") val equipmentId: String? = null, val row: ItemRow? = null)
    @Serializable private data class RuleEnvelope(val rule: RuleRow)

    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaEquipmentException(NovaEquipmentFailure.denied)
    }

    /** A serial already on file is refused by a unique index rather than a named error. */
    private fun map(failure: NovaExpertFailure): NovaEquipmentFailure = when {
        failure.sqlState == "23505" -> NovaEquipmentFailure.duplicateSerial
        failure.sqlState !in setOf("P0001", "28000") && failure.code != "ACCESS_DENIED" -> NovaEquipmentFailure.unavailable
        failure.code in setOf("AUTH_REQUIRED", "ACCESS_DENIED") -> NovaEquipmentFailure.denied
        failure.code == "PAID_PLAN_REQUIRED" -> NovaEquipmentFailure.planRequired
        failure.code in setOf("FEATURE_UNAVAILABLE", "MODULE_UNAVAILABLE") -> NovaEquipmentFailure.moduleUnavailable
        failure.code == "PERFORMED_IN_THE_FUTURE" -> NovaEquipmentFailure.futureReport
        failure.code == "DUE_BEFORE_REPORT" -> NovaEquipmentFailure.dueBeforeReport
        failure.code == "DUE_ON_A_FAILED_CHECK" -> NovaEquipmentFailure.dueOnFailedCheck
        failure.code == "IDEMPOTENCY_CONFLICT" -> NovaEquipmentFailure.conflict
        failure.code in setOf("VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED") -> NovaEquipmentFailure.validation
        else -> NovaEquipmentFailure.unavailable
    }

    private suspend fun call(function: String, params: JsonObject): JsonElement = try { transport.execute(function, params) }
        catch (failure: NovaExpertFailure) { currentCoroutineContext().ensureActive(); throw NovaEquipmentException(map(failure)) }

    private fun <T> JsonElement.decode(serializer: KSerializer<T>): T = try { novaJson.decodeFromJsonElement(serializer, this) }
        catch (_: Exception) { throw NovaEquipmentException(NovaEquipmentFailure.unavailable) }

    private fun states(raw: Map<String, Int>) = raw.mapNotNull { (key, value) -> NovaEquipmentState.of(key)?.let { it to value } }.toMap()
    private fun rule(row: RuleRow) = NovaEquipmentRule(row.equipmentType, row.periodMonths,
        NovaEquipmentPeriodSource.of(row.periodSource) ?: NovaEquipmentPeriodSource.unapprovedFixture, row.needsReview, row.exceptionNote)

    /** An unknown state word reads as never inspected rather than the calmest answer. */
    private fun item(row: ItemRow) = NovaEquipmentItem(row.id, row.companyId, row.companyName, row.workplaceId, row.equipmentType, row.serialTag,
        row.acquiredOn, row.locationNote, row.isArchived, NovaEquipmentState.of(row.state) ?: NovaEquipmentState.neverInspected, row.periodMonths,
        NovaEquipmentPeriodSource.of(row.periodSource), row.periodNeedsReview, row.periodExceptionNote, row.periodDefinedAfterReport,
        row.lastPerformedOn, row.lastResult, row.lastInspector, row.lastExternalRef, row.nextDueOn, NovaEquipmentDueSource.of(row.dueSource),
        row.katipDeclared ?: false, row.katipNote, row.katipOfficialVerification ?: false, row.evidenceAssetId,
        row.evidenceDownload?.let { NovaEquipmentAssetDownload(it.bucket, it.path) },
        row.inspections.orEmpty().map { entry ->
            NovaEquipmentInspection(entry.id, entry.performedOn, entry.result, entry.nextDueOn, entry.periodMonths, entry.inspector, entry.externalRef,
                entry.note, entry.evidenceAssetId, entry.evidenceDownload?.let { NovaEquipmentAssetDownload(it.bucket, it.path) },
                NovaEquipmentDueSource.of(entry.dueSource), entry.katipDeclared ?: false, entry.katipNote)
        })

    private suspend fun read(arguments: Map<String, JsonElement>): JsonElement {
        val payload = mutableMapOf<String, JsonElement>("p_company" to JsonNull, "p_kind" to JsonPrimitive("list"), "p_query" to JsonNull,
            "p_state" to JsonNull, "p_workplace" to JsonNull, "p_type" to JsonNull, "p_id" to JsonNull, "p_limit" to JsonNull, "p_offset" to JsonNull)
        payload.putAll(arguments)
        return call("isg_equipment_checks_read_v1", JsonObject(payload))
    }

    private fun text(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull
    private fun trimmed(value: String): JsonElement = value.trim().ifEmpty { null }?.let(::JsonPrimitive) ?: JsonNull

    suspend fun catalogue(identity: IsgWorkspaceIdentity, company: String?): NovaEquipmentCatalogue {
        check(identity)
        val envelope = read(mapOf("p_company" to text(company), "p_kind" to JsonPrimitive("catalog"))).decode(CatalogEnvelope.serializer())
        check(identity)
        return NovaEquipmentCatalogue(envelope.suggestions.sortedBy { it.ordinal }.map { NovaEquipmentSuggestion(it.code, it.defaultPeriodMonths, it.defaultBasisNote) },
            envelope.rules.map(::rule), envelope.workplaces.map { NovaEquipmentWorkplace(it.id, it.name) }, envelope.noticeDays)
    }

    suspend fun board(identity: IsgWorkspaceIdentity, query: NovaEquipmentQuery): NovaEquipmentBoard {
        check(identity)
        val envelope = read(mapOf("p_company" to text(query.company), "p_query" to text(query.query.trim().ifEmpty { null }),
            "p_state" to text(query.state), "p_workplace" to text(query.workplace), "p_type" to text(query.equipmentType),
            "p_limit" to JsonPrimitive(query.limit), "p_offset" to JsonPrimitive(query.offset))).decode(ListEnvelope.serializer())
        check(identity)
        return NovaEquipmentBoard(states(envelope.counts), envelope.companies.map { NovaEquipmentCompanySummary(it.id, it.name, it.total, states(it.counts)) },
            envelope.typeCounts.mapValues { states(it.value) }, envelope.rows.map(::item), envelope.total, envelope.hasMore, envelope.limit,
            envelope.offset, envelope.today, envelope.noticeDays)
    }

    suspend fun detail(identity: IsgWorkspaceIdentity, equipment: String): NovaEquipmentItem {
        check(identity)
        val row = read(mapOf("p_kind" to JsonPrimitive("detail"), "p_id" to JsonPrimitive(equipment))).decode(DetailEnvelope.serializer()).row
        check(identity); return item(row)
    }

    private suspend fun mutate(identity: IsgWorkspaceIdentity, company: String, action: String, payload: JsonObject): JsonElement {
        check(identity)
        val data = call("isg_equipment_checks_mutate_v1", buildJsonObject {
            put("p_company", company); put("p_action", action); put("p_operation", UUID.randomUUID().toString())
            put("p_mutation", UUID.randomUUID().toString()); put("p_payload", payload)
        })
        check(identity)
        events.recordsChanged(identity.userId)
        return data
    }

    private fun JsonElement.row() = decode(MutationEnvelope.serializer()).row?.let(::item) ?: throw NovaEquipmentException(NovaEquipmentFailure.unavailable)

    suspend fun register(identity: IsgWorkspaceIdentity, company: String, draft: NovaEquipmentDraft): NovaEquipmentItem {
        val type = draft.equipmentType
        if (!draft.isReady || type == null) throw NovaEquipmentException(NovaEquipmentFailure.validation)
        return mutate(identity, company, "register_equipment", buildJsonObject {
            put("workplace_id", draft.workplaceId); put("equipment_type", type); put("serial_tag", draft.serialTag.trim())
            put("acquired_on", trimmed(draft.acquiredOn)); put("location_note", trimmed(draft.locationNote))
        }).row()
    }

    suspend fun update(identity: IsgWorkspaceIdentity, equipment: NovaEquipmentItem, draft: NovaEquipmentDraft): NovaEquipmentItem {
        val company = equipment.companyId ?: throw NovaEquipmentException(NovaEquipmentFailure.denied)
        return mutate(identity, company, "update_equipment", buildJsonObject {
            put("equipment_id", equipment.id); draft.workplaceId?.let { put("workplace_id", it) }
            put("serial_tag", draft.serialTag.trim()); put("acquired_on", trimmed(draft.acquiredOn)); put("location_note", trimmed(draft.locationNote))
        }).row()
    }

    suspend fun archive(identity: IsgWorkspaceIdentity, equipment: NovaEquipmentItem) {
        val company = equipment.companyId ?: throw NovaEquipmentException(NovaEquipmentFailure.denied)
        mutate(identity, company, "archive_equipment", buildJsonObject { put("equipment_id", equipment.id) })
    }

    /** The source always travels with the period, so a duration never appears without saying where it came from. */
    suspend fun setRule(identity: IsgWorkspaceIdentity, company: String, draft: NovaEquipmentRuleDraft): NovaEquipmentRule {
        val type = draft.equipmentType; val months = draft.monthsValue
        if (!draft.isReady || type == null || months == null) throw NovaEquipmentException(NovaEquipmentFailure.validation)
        return rule(mutate(identity, company, "set_rule", buildJsonObject {
            put("equipment_type", type); put("period_months", months); put("period_source", draft.source.wire)
            put("exception_note", trimmed(draft.exceptionNote))
        }).decode(RuleEnvelope.serializer()).rule)
    }

    private fun JsonObjectBuilder.report(draft: NovaEquipmentInspectionDraft) {
        put("inspector", trimmed(draft.inspector)); put("external_ref", trimmed(draft.externalRef)); put("note", trimmed(draft.note))
        put("evidence_asset_id", text(draft.evidenceAssetId))
        // Sent only when the expert set one; left out, the server uses the period's own answer.
        put("next_due_on", trimmed(draft.nextDueOn))
        put("katip_declared", draft.katipDeclared); put("katip_note", if (draft.katipDeclared) trimmed(draft.katipNote) else JsonNull)
    }

    /** Corrects a report on file; its date and result are what the report is and stay as they are. */
    suspend fun updateInspection(identity: IsgWorkspaceIdentity, equipment: NovaEquipmentItem, inspection: NovaEquipmentInspection,
                                 draft: NovaEquipmentInspectionDraft): NovaEquipmentItem {
        val company = equipment.companyId ?: throw NovaEquipmentException(NovaEquipmentFailure.denied)
        return mutate(identity, company, "update_inspection", buildJsonObject {
            put("equipment_id", equipment.id); put("inspection_id", inspection.id); report(draft)
        }).row()
    }

    /** One report. The next due date is the server's: a report with no period behind it gets none. */
    suspend fun recordInspection(identity: IsgWorkspaceIdentity, equipment: NovaEquipmentItem, draft: NovaEquipmentInspectionDraft): NovaEquipmentItem {
        val company = equipment.companyId ?: throw NovaEquipmentException(NovaEquipmentFailure.denied)
        if (!draft.isReady) throw NovaEquipmentException(NovaEquipmentFailure.validation)
        return mutate(identity, company, "record_inspection", buildJsonObject {
            put("equipment_id", equipment.id); put("performed_on", draft.performedOn.trim()); put("result", draft.result); report(draft)
        }).row()
    }
}
