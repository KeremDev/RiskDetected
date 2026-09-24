package com.riskdetectedan.core.data.nova

import android.content.Context
import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.*
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

enum class NovaChecklistRunState(val wire: String, val title: String, val footer: String, val symbol: String) {
    `open`("open", "Devam eden", "yanıt bekliyor", "square.and.pencil"), submitted("submitted", "Tamamlandı", "kayıtlı", "checkmark.circle"),
    cancelled("cancelled", "İptal edildi", "vazgeçildi", "xmark.circle");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

enum class NovaChecklistResult(val wire: String, val title: String, val symbol: String) {
    conform("compliant", "Uygun", "checkmark.circle"), nonconform("non_compliant", "Uygun değil", "exclamationmark.triangle"),
    notApplicable("not_applicable", "Uygulanamaz", "minus.circle");
    companion object {
        fun of(wire: String?) = when (wire) {
            "compliant", "conform" -> conform; "non_compliant", "nonconform" -> nonconform; "not_applicable" -> notApplicable; else -> null
        }
    }
}

enum class NovaChecklistSeverity(val wire: String, val title: String) {
    low("low", "Düşük"), medium("medium", "Orta"), high("high", "Yüksek"), critical("critical", "Kritik");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

data class NovaChecklistAnswer(
    val itemCode: String, val prompt: String, val position: Int, val atomicItemCode: String?, val sectionTitle: String?, val scopeKey: String?,
    val allowsNotApplicable: Boolean, val verificationMethod: String?, val helpText: String?, val tags: List<String>, val riskTopic: String?,
    val naReasonRequired: Boolean, val evidenceRecommended: Boolean, val photoRequired: Boolean, val result: NovaChecklistResult?,
    val note: String?, val evidenceAssetId: String?, val nonconformityId: String?,
) { val isAnswered: Boolean get() = result != null }

data class NovaChecklistRun(
    val id: String, val companyId: String?, val companyName: String?, val workplaceId: String?, val workplaceName: String?, val templateCode: String,
    val templateTitle: String?, val templateVersion: Int, val state: NovaChecklistRunState, val startedOn: String, val submittedAt: String?,
    val revision: Long, val revisesRunId: String?, val areaLabel: String?, val equipmentLabel: String?, val documentNumber: String?,
    val expected: Int, val answered: Int, val remaining: Int, val conform: Int, val nonconform: Int, val notApplicable: Int,
    val progressPercent: Double?, val coveragePercent: Double?, val applicableCoveragePercent: Double?, val scorePercent: Double?,
    val sourceIds: List<String>, val nonconformitiesOpened: Int, val answers: List<NovaChecklistAnswer>,
) {
    val isPersonal: Boolean get() = companyId == null
}

data class NovaChecklistTemplateItem(
    val itemCode: String, val prompt: String, val position: Int, val atomicItemCode: String?, val sectionTitle: String?, val scopeKey: String?,
    val allowsNotApplicable: Boolean, val verificationMethod: String?, val helpText: String?, val tags: List<String>, val riskTopic: String?,
    val naReasonRequired: Boolean, val evidenceRecommended: Boolean, val photoRequired: Boolean, val sourceIds: List<String>,
)

data class NovaChecklistTemplateVersion(val version: Int, val revision: Long, val status: String, val publishedAt: String?, val approvalNote: String?,
                                        val items: List<NovaChecklistTemplateItem>) {
    val isDraft: Boolean get() = status == "draft"
    val isPublished: Boolean get() = status == "published"
    val statusTitle: String get() = when (status) { "draft" -> "Taslak"; "published" -> "Yayımda"; else -> "Geçmiş" }
}

data class NovaChecklistTemplate(val templateCode: String, val title: String, val isProduct: Boolean, val isArchived: Boolean,
                                 val versions: List<NovaChecklistTemplateVersion>) {
    val draft: NovaChecklistTemplateVersion? get() = versions.firstOrNull { it.isDraft }
    val published: NovaChecklistTemplateVersion? get() = versions.firstOrNull { it.isPublished }
}

data class NovaChecklistStarter(val templateCode: String, val title: String, val version: Int, val items: Int, val isProduct: Boolean,
                                val catalogTemplateCode: String?, val sectorCode: String?, val kind: String?, val scopeNote: String?,
                                val professionalReviewStatus: String?) {
    val kindTitle: String get() = novaChecklistKindTitle(kind) ?: "Genel"
}

fun novaChecklistKindTitle(kind: String?) = when (kind) {
    "sector" -> "Sektör"; "activity" -> "Faaliyet"; "equipment" -> "Ekipman"; "hazard" -> "Tehlike"; null -> null; else -> "Genel"
}

data class NovaChecklistCatalogue(val workplaces: List<Workplace>, val starters: List<NovaChecklistStarter>, val productTemplatesOffered: Boolean,
                                  val catalogVersion: String?, val publicationStatus: String?, val professionalReviewStatus: String?) {
    data class Workplace(val id: String, val name: String, val needsReview: Boolean)
}

data class NovaChecklistLibrarySector(val code: String, val name: String, val count: Int)
data class NovaChecklistLibraryItem(val templateCode: String, val catalogTemplateCode: String, val title: String, val sectorCode: String?,
                                    val sectorName: String?, val kind: String, val aliases: List<String>, val scopeNote: String,
                                    val professionalReviewStatus: String, val items: Int, val sourceIds: List<String>)
data class NovaChecklistLibraryMatch(val atomicItemCode: String, val prompt: String, val verificationMethod: String?, val riskTopic: String?,
                                     val tags: List<String>, val sourceIds: List<String>, val contexts: List<Context>) {
    data class Context(val templateCode: String, val catalogTemplateCode: String, val title: String, val sectorCode: String?, val sectorName: String?,
                       val itemCode: String)
}
data class NovaChecklistLibrary(val catalogVersion: String, val publicationStatus: String, val professionalReviewStatus: String,
                                val sectors: List<NovaChecklistLibrarySector>, val rows: List<NovaChecklistLibraryItem>,
                                val matchedItems: List<NovaChecklistLibraryMatch>, val total: Int, val limit: Int, val offset: Int) {
    val hasMore: Boolean get() = offset + rows.size < total
}

data class NovaChecklistTemplateDetail(val templateCode: String, val catalogTemplateCode: String?, val catalogVersion: String?, val title: String,
                                       val sectorCode: String?, val kind: String?, val aliases: List<String>, val scopeNote: String?,
                                       val sourceIds: List<String>, val isProduct: Boolean, val professionalReviewStatus: String?, val version: Int,
                                       val items: List<NovaChecklistTemplateItem>)

data class NovaChecklistBoard(val rows: List<NovaChecklistRun>, val counts: Map<String, Int>, val total: Int, val hasMore: Boolean, val offset: Int) {
    fun count(state: NovaChecklistRunState) = counts[state.wire] ?: 0
}

data class NovaChecklistQuery(val company: String? = null, val state: String? = NovaChecklistRunState.open.wire, val workplace: String? = null,
                              val template: String? = null, val search: String = "", val limit: Int = 10, val offset: Int = 0)

/** A picked evidence file, uploaded to the archive before the answer is recorded. */
data class NovaChecklistAttachment(val title: String, val fileName: String, val data: ByteArray)

@Serializable
data class NovaChecklistAnswerDraft(
    val runId: String? = null, val itemCode: String = "", val prompt: String = "", val allowsNotApplicable: Boolean = true,
    val verificationMethod: String? = null, val helpText: String? = null, val naReasonRequired: Boolean = false,
    val evidenceRecommended: Boolean = false, val photoRequired: Boolean = false, val result: String = NovaChecklistResult.conform.wire,
    val note: String = "", val evidenceAssetId: String? = null, val openNonconformity: Boolean = false,
    val severity: String = NovaChecklistSeverity.medium.wire, val dueOn: String = "", val expectedRevision: Long = 0,
    @kotlinx.serialization.Transient val attachment: NovaChecklistAttachment? = null,
) {
    val resultValue: NovaChecklistResult get() = NovaChecklistResult.of(result) ?: NovaChecklistResult.conform
}

data class NovaChecklistItemSelection(val sourceTemplateCode: String, val sourceItemCode: String, val sectionTitle: String = "",
                                      val scopeKey: String = "", val allowDuplicate: Boolean = false)

data class NovaChecklistAssignment(val id: String, val companyId: String, val workplaceId: String?, val workplaceName: String?,
                                   val templateCode: String, val templateTitle: String, val templateVersion: Int, val assignedAt: String)

enum class NovaChecklistFailure(val message: String) {
    denied("Bu kayda erişim yok."), planRequired("Bu işlem için Plus veya Pro aboneliği gerekiyor."),
    moduleUnavailable("Kontrol listeleri modülü henüz açık değil."), validation("Girilen bilgiler eksik veya birbiriyle uyumsuz."),
    explanationRequired("Uygun değil ve Uygulanamaz yanıtlarında açıklama zorunludur."),
    conflict("Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin."), runSubmitted("Tamamlanmış kontrol değiştirilemez."),
    runIncomplete("Yanıtlanmamış soru var. Tamamlamak için hepsini yanıtlayın."),
    templatePublished("Yayımlanmış liste değiştirilemez. Değişiklik için yeni sürüm açın."),
    duplicateItem("Bu madde aynı kapsam anahtarıyla listede zaten var. Gerçekten farklı bir alan veya ekipman içinse ayrı bir kapsam adı girin."),
    companyRequired("Kanıt veya uygunsuzluk kaydı için kontrolü bir firmada başlatın."),
    unavailable("Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin."),
}

class NovaChecklistException(val failure: NovaChecklistFailure) : Exception(failure.name)

object NovaChecklistWords {
    /** The entry that opens the checklist wizard. */
    const val openWizard = "Sihirbaz ile liste oluştur"
    const val neverAutomatic = "Olumsuz yanıt kendiliğinden uygunsuzluk kaydı açmaz. Kayıt açmak sizin seçiminizdir."
    const val catalogNotice = "Hazır listeler saha kontrolünü yapılandıran uzman yardımcılarıdır. Mevzuata uygunluk kararı değildir; firma, iş ve ekipman kapsamını uzman doğrular."
    const val selfApproved = "Yayımlamak listenin sizin onayınızdan geçtiği anlamına gelir; mevzuat onayı değildir."
}

/** Kontrol listeleri boundary (iOS `NovaChecklistService` + live adapter). */
@Singleton
class NovaChecklistService @Inject constructor(private val transport: NovaExpertTransport, private val journal: NovaModuleMutationJournal) {
    @Serializable private data class ItemRow(
        @SerialName("item_code") val itemCode: String, val prompt: String, val position: Int, @SerialName("atomic_item_code") val atomicItemCode: String? = null,
        @SerialName("section_title") val sectionTitle: String? = null, @SerialName("scope_key") val scopeKey: String? = null,
        @SerialName("allows_not_applicable") val allowsNotApplicable: Boolean, @SerialName("verification_method") val verificationMethod: String? = null,
        @SerialName("help_text") val helpText: String? = null, val tags: List<String>? = null, @SerialName("risk_topic") val riskTopic: String? = null,
        @SerialName("na_reason_required") val naReasonRequired: Boolean? = null, @SerialName("evidence_recommended") val evidenceRecommended: Boolean? = null,
        @SerialName("photo_required") val photoRequired: Boolean? = null, @SerialName("source_ids") val sourceIds: List<String>? = null,
        val result: String? = null, val answer: String? = null, val note: String? = null, @SerialName("evidence_asset_id") val evidenceAssetId: String? = null,
        @SerialName("nonconformity_id") val nonconformityId: String? = null)
    @Serializable private data class RunRow(
        val id: String, @SerialName("company_id") val companyId: String? = null, @SerialName("company_name") val companyName: String? = null,
        @SerialName("workplace_id") val workplaceId: String? = null, @SerialName("workplace_name") val workplaceName: String? = null,
        @SerialName("template_code") val templateCode: String, @SerialName("template_title") val templateTitle: String? = null,
        @SerialName("template_version") val templateVersion: Int, val state: String, @SerialName("started_on") val startedOn: String,
        @SerialName("submitted_at") val submittedAt: String? = null, val revision: Long? = null, @SerialName("revises_run_id") val revisesRunId: String? = null,
        @SerialName("area_label") val areaLabel: String? = null, @SerialName("equipment_label") val equipmentLabel: String? = null,
        @SerialName("document_number") val documentNumber: String? = null, val expected: Int, val answered: Int, val remaining: Int, val conform: Int,
        val nonconform: Int, @SerialName("not_applicable") val notApplicable: Int, @SerialName("progress_percent") val progressPercent: Double? = null,
        @SerialName("coverage_percent") val coveragePercent: Double? = null, @SerialName("applicable_coverage_percent") val applicableCoveragePercent: Double? = null,
        @SerialName("score_percent") val scorePercent: Double? = null, @SerialName("source_ids") val sourceIds: List<String>? = null,
        @SerialName("nonconformities_opened") val nonconformitiesOpened: Int, val items: List<ItemRow>? = null)
    @Serializable private data class WorkplaceRow(val id: String, val name: String, @SerialName("needs_review") val needsReview: Boolean)
    @Serializable private data class StarterRow(@SerialName("template_code") val templateCode: String, val title: String, val version: Int, val items: Int,
        @SerialName("is_product") val isProduct: Boolean, @SerialName("catalog_template_code") val catalogTemplateCode: String? = null,
        @SerialName("sector_code") val sectorCode: String? = null, val kind: String? = null, @SerialName("scope_note") val scopeNote: String? = null,
        @SerialName("professional_review_status") val professionalReviewStatus: String? = null)
    @Serializable private data class CatalogEnvelope(val workplaces: List<WorkplaceRow>, val templates: List<StarterRow>,
        @SerialName("product_templates_offered") val productTemplatesOffered: Boolean, @SerialName("catalog_version") val catalogVersion: String? = null,
        @SerialName("publication_status") val publicationStatus: String? = null,
        @SerialName("professional_review_status") val professionalReviewStatus: String? = null)
    @Serializable private data class VersionRow(val version: Int, val revision: Long? = null, val status: String, @SerialName("published_at") val publishedAt: String? = null,
        @SerialName("approval_note") val approvalNote: String? = null, val items: List<ItemRow>? = null)
    @Serializable private data class TemplateRow(@SerialName("template_code") val templateCode: String, val title: String, @SerialName("is_product") val isProduct: Boolean,
        @SerialName("is_archived") val isArchived: Boolean, val versions: List<VersionRow>? = null)
    @Serializable private data class TemplatesEnvelope(val rows: List<TemplateRow>)
    @Serializable private data class ListEnvelope(val rows: List<RunRow>, val counts: Map<String, Int>, val total: Int,
        @SerialName("has_more") val hasMore: Boolean, val offset: Int)
    @Serializable private data class DetailEnvelope(val row: RunRow)
    @Serializable private data class MutationEnvelope(@SerialName("run_id") val runId: String? = null, val row: RunRow? = null)
    @Serializable private data class SectorRow(val code: String, val name: String, val count: Int)
    @Serializable private data class LibraryRow(@SerialName("template_code") val templateCode: String, @SerialName("catalog_template_code") val catalogTemplateCode: String,
        val title: String, @SerialName("sector_code") val sectorCode: String? = null, @SerialName("sector_name") val sectorName: String? = null, val kind: String,
        val aliases: List<String> = emptyList(), @SerialName("scope_note") val scopeNote: String, @SerialName("professional_review_status") val professionalReviewStatus: String,
        val items: Int, @SerialName("source_ids") val sourceIds: List<String> = emptyList())
    @Serializable private data class MatchContextRow(@SerialName("template_code") val templateCode: String,
        @SerialName("catalog_template_code") val catalogTemplateCode: String, val title: String, @SerialName("sector_code") val sectorCode: String? = null,
        @SerialName("sector_name") val sectorName: String? = null, @SerialName("item_code") val itemCode: String)
    @Serializable private data class MatchRow(@SerialName("atomic_item_code") val atomicItemCode: String, val prompt: String,
        @SerialName("verification_method") val verificationMethod: String? = null, @SerialName("risk_topic") val riskTopic: String? = null,
        val tags: List<String>? = null, @SerialName("source_ids") val sourceIds: List<String>? = null, val contexts: List<MatchContextRow>)
    @Serializable private data class LibraryEnvelope(@SerialName("catalog_version") val catalogVersion: String, @SerialName("publication_status") val publicationStatus: String,
        @SerialName("professional_review_status") val professionalReviewStatus: String, val sectors: List<SectorRow>, val rows: List<LibraryRow>,
        @SerialName("matched_items") val matchedItems: List<MatchRow>? = null, val total: Int, val limit: Int, val offset: Int)
    @Serializable private data class AssignmentRow(val id: String, @SerialName("company_id") val companyId: String, @SerialName("workplace_id") val workplaceId: String? = null,
        @SerialName("workplace_name") val workplaceName: String? = null, @SerialName("template_code") val templateCode: String,
        @SerialName("template_title") val templateTitle: String, @SerialName("template_version") val templateVersion: Int, @SerialName("assigned_at") val assignedAt: String)
    @Serializable private data class AssignmentsEnvelope(val rows: List<AssignmentRow>)
    @Serializable private data class TemplateDetailRow(@SerialName("template_code") val templateCode: String,
        @SerialName("catalog_template_code") val catalogTemplateCode: String? = null, @SerialName("catalog_version") val catalogVersion: String? = null,
        val title: String, @SerialName("sector_code") val sectorCode: String? = null, val kind: String? = null, val aliases: List<String>? = null,
        @SerialName("scope_note") val scopeNote: String? = null, @SerialName("source_ids") val sourceIds: List<String>? = null,
        @SerialName("is_product") val isProduct: Boolean, @SerialName("professional_review_status") val professionalReviewStatus: String? = null,
        val version: Int, val items: List<ItemRow>)
    @Serializable private data class TemplateDetailEnvelope(val row: TemplateDetailRow)

    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaChecklistException(NovaChecklistFailure.denied)
    }

    private fun map(failure: NovaExpertFailure): NovaChecklistFailure = when {
        failure.sqlState !in setOf("P0001", "28000") && failure.code != "ACCESS_DENIED" -> NovaChecklistFailure.unavailable
        failure.code in setOf("AUTH_REQUIRED", "ACCESS_DENIED") -> NovaChecklistFailure.denied
        failure.code == "PAID_PLAN_REQUIRED" -> NovaChecklistFailure.planRequired
        failure.code == "FEATURE_UNAVAILABLE" -> NovaChecklistFailure.moduleUnavailable
        failure.code == "RUN_SUBMITTED" -> NovaChecklistFailure.runSubmitted
        failure.code == "RUN_INCOMPLETE" -> NovaChecklistFailure.runIncomplete
        failure.code == "TEMPLATE_PUBLISHED" -> NovaChecklistFailure.templatePublished
        failure.code in setOf("IDEMPOTENCY_CONFLICT", "CHECKLIST_CONFLICT") -> NovaChecklistFailure.conflict
        failure.code == "DUPLICATE_CHECKLIST_ITEM" -> NovaChecklistFailure.duplicateItem
        failure.code == "COMPANY_REQUIRED_FOR_NONCONFORMITY" -> NovaChecklistFailure.companyRequired
        failure.code == "EXPLANATION_REQUIRED" -> NovaChecklistFailure.explanationRequired
        failure.code in setOf("VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED") -> NovaChecklistFailure.validation
        else -> NovaChecklistFailure.unavailable
    }

    private suspend fun <T> guarded(block: suspend () -> T): T = try { block() } catch (failure: NovaExpertFailure) {
        currentCoroutineContext().ensureActive(); throw NovaChecklistException(map(failure))
    }

    private fun <T> JsonElement.decode(serializer: KSerializer<T>): T = try { novaJson.decodeFromJsonElement(serializer, this) }
        catch (_: Exception) { throw NovaChecklistException(NovaChecklistFailure.unavailable) }

    private fun templateItem(row: ItemRow) = NovaChecklistTemplateItem(row.itemCode, row.prompt, row.position, row.atomicItemCode, row.sectionTitle,
        row.scopeKey, row.allowsNotApplicable, row.verificationMethod, row.helpText, row.tags.orEmpty(), row.riskTopic, row.naReasonRequired ?: false,
        row.evidenceRecommended ?: false, row.photoRequired ?: false, row.sourceIds.orEmpty())

    private fun run(entry: RunRow) = NovaChecklistRun(entry.id, entry.companyId, entry.companyName, entry.workplaceId, entry.workplaceName,
        entry.templateCode, entry.templateTitle, entry.templateVersion, NovaChecklistRunState.of(entry.state) ?: NovaChecklistRunState.open,
        entry.startedOn, entry.submittedAt, entry.revision ?: 0, entry.revisesRunId, entry.areaLabel, entry.equipmentLabel, entry.documentNumber,
        entry.expected, entry.answered, entry.remaining, entry.conform, entry.nonconform, entry.notApplicable, entry.progressPercent,
        entry.coveragePercent, entry.applicableCoveragePercent, entry.scorePercent, entry.sourceIds.orEmpty(), entry.nonconformitiesOpened,
        entry.items.orEmpty().map {
            NovaChecklistAnswer(it.itemCode, it.prompt, it.position, it.atomicItemCode, it.sectionTitle, it.scopeKey, it.allowsNotApplicable,
                it.verificationMethod, it.helpText, it.tags.orEmpty(), it.riskTopic, it.naReasonRequired ?: false, it.evidenceRecommended ?: false,
                it.photoRequired ?: false, NovaChecklistResult.of(it.answer ?: it.result), it.note, it.evidenceAssetId, it.nonconformityId)
        })

    private suspend fun read(arguments: Map<String, JsonElement>): JsonElement = guarded {
        val payload = mutableMapOf<String, JsonElement>("p_company" to JsonNull, "p_kind" to JsonPrimitive("list"), "p_query" to JsonNull,
            "p_state" to JsonNull, "p_workplace" to JsonNull, "p_template" to JsonNull, "p_id" to JsonNull, "p_limit" to JsonNull, "p_offset" to JsonNull)
        payload.putAll(arguments)
        transport.execute("isg_checklists_read_v1", JsonObject(payload))
    }

    private fun text(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull
    private fun isDay(value: String) = runCatching { java.time.LocalDate.parse(value) }.isSuccess

    suspend fun catalogue(identity: IsgWorkspaceIdentity, company: String?): NovaChecklistCatalogue {
        check(identity)
        val envelope = read(mapOf("p_company" to text(company), "p_kind" to JsonPrimitive("catalog"))).decode(CatalogEnvelope.serializer())
        check(identity)
        return NovaChecklistCatalogue(envelope.workplaces.map { NovaChecklistCatalogue.Workplace(it.id, it.name, it.needsReview) },
            envelope.templates.map { NovaChecklistStarter(it.templateCode, it.title, it.version, it.items, it.isProduct, it.catalogTemplateCode, it.sectorCode,
                it.kind, it.scopeNote, it.professionalReviewStatus) },
            envelope.productTemplatesOffered, envelope.catalogVersion, envelope.publicationStatus, envelope.professionalReviewStatus)
    }

    suspend fun library(identity: IsgWorkspaceIdentity, search: String = "", sector: String? = null, kind: String? = null, limit: Int = 30,
                        offset: Int = 0): NovaChecklistLibrary {
        check(identity)
        val envelope = read(mapOf("p_kind" to JsonPrimitive("library"), "p_query" to text(search.trim().ifEmpty { null }), "p_template" to text(sector),
            "p_state" to text(kind), "p_limit" to JsonPrimitive(limit), "p_offset" to JsonPrimitive(offset))).decode(LibraryEnvelope.serializer())
        check(identity)
        return NovaChecklistLibrary(envelope.catalogVersion, envelope.publicationStatus, envelope.professionalReviewStatus,
            envelope.sectors.map { NovaChecklistLibrarySector(it.code, it.name, it.count) },
            envelope.rows.map { NovaChecklistLibraryItem(it.templateCode, it.catalogTemplateCode, it.title, it.sectorCode, it.sectorName, it.kind, it.aliases,
                it.scopeNote, it.professionalReviewStatus, it.items, it.sourceIds) },
            envelope.matchedItems.orEmpty().map { match ->
                NovaChecklistLibraryMatch(match.atomicItemCode, match.prompt, match.verificationMethod, match.riskTopic, match.tags.orEmpty(), match.sourceIds.orEmpty(),
                    match.contexts.map { NovaChecklistLibraryMatch.Context(it.templateCode, it.catalogTemplateCode, it.title, it.sectorCode, it.sectorName, it.itemCode) })
            }, envelope.total, envelope.limit, envelope.offset)
    }

    suspend fun templateDetail(identity: IsgWorkspaceIdentity, template: String): NovaChecklistTemplateDetail {
        check(identity)
        val row = read(mapOf("p_kind" to JsonPrimitive("template_detail"), "p_template" to JsonPrimitive(template))).decode(TemplateDetailEnvelope.serializer()).row
        check(identity)
        return NovaChecklistTemplateDetail(row.templateCode, row.catalogTemplateCode, row.catalogVersion, row.title, row.sectorCode, row.kind,
            row.aliases.orEmpty(), row.scopeNote, row.sourceIds.orEmpty(), row.isProduct, row.professionalReviewStatus, row.version, row.items.map(::templateItem))
    }

    suspend fun assignments(identity: IsgWorkspaceIdentity, company: String): List<NovaChecklistAssignment> {
        check(identity)
        val rows = read(mapOf("p_company" to JsonPrimitive(company), "p_kind" to JsonPrimitive("assignments"))).decode(AssignmentsEnvelope.serializer()).rows
        check(identity)
        return rows.map { NovaChecklistAssignment(it.id, it.companyId, it.workplaceId, it.workplaceName, it.templateCode, it.templateTitle, it.templateVersion, it.assignedAt) }
    }

    suspend fun templates(identity: IsgWorkspaceIdentity, company: String?): List<NovaChecklistTemplate> {
        check(identity)
        val rows = read(mapOf("p_company" to text(company), "p_kind" to JsonPrimitive("templates"))).decode(TemplatesEnvelope.serializer()).rows
        check(identity)
        return rows.map { entry ->
            NovaChecklistTemplate(entry.templateCode, entry.title, entry.isProduct, entry.isArchived, entry.versions.orEmpty().map { version ->
                NovaChecklistTemplateVersion(version.version, version.revision ?: 0, version.status, version.publishedAt, version.approvalNote,
                    version.items.orEmpty().map(::templateItem))
            })
        }
    }

    suspend fun board(identity: IsgWorkspaceIdentity, query: NovaChecklistQuery): NovaChecklistBoard {
        check(identity)
        val envelope = read(mapOf("p_company" to text(query.company), "p_query" to text(query.search.trim().ifEmpty { null }), "p_state" to text(query.state),
            "p_workplace" to text(query.workplace), "p_template" to text(query.template), "p_limit" to JsonPrimitive(query.limit),
            "p_offset" to JsonPrimitive(query.offset))).decode(ListEnvelope.serializer())
        check(identity)
        return NovaChecklistBoard(envelope.rows.map(::run), envelope.counts, envelope.total, envelope.hasMore, envelope.offset)
    }

    suspend fun detail(identity: IsgWorkspaceIdentity, run: String): NovaChecklistRun {
        check(identity)
        val row = read(mapOf("p_kind" to JsonPrimitive("detail"), "p_id" to JsonPrimitive(run))).decode(DetailEnvelope.serializer()).row
        check(identity); return run(row)
    }

    private suspend fun mutate(identity: IsgWorkspaceIdentity, company: String?, action: String, payload: JsonObject): NovaChecklistRun? {
        check(identity)
        return guarded { journal.run("isg_checklists_mutate_v1", identity, company, action, payload) { it.decode(MutationEnvelope.serializer()).row?.let(::run) } }
    }

    suspend fun draftTemplate(identity: IsgWorkspaceIdentity, company: String?, title: String) {
        mutate(identity, company, "draft_template", buildJsonObject { put("title", title.trim()) })
    }

    suspend fun setItem(identity: IsgWorkspaceIdentity, company: String?, template: String, version: Int, expectedRevision: Long, itemCode: String,
                        prompt: String, allowsNotApplicable: Boolean, position: Int, sectionTitle: String = "", scopeKey: String = "") {
        mutate(identity, company, "set_item", buildJsonObject {
            put("template_code", template); put("version", version); put("item_code", itemCode); put("prompt", prompt.trim())
            put("allows_not_applicable", allowsNotApplicable); put("position", position); put("expected_revision", expectedRevision)
            sectionTitle.trim().takeIf { it.isNotEmpty() }?.let { put("section_title", it) }
            scopeKey.trim().takeIf { it.isNotEmpty() }?.let { put("scope_key", it) }
        })
    }

    suspend fun copyItems(identity: IsgWorkspaceIdentity, company: String?, template: String, version: Int, expectedRevision: Long,
                          items: List<NovaChecklistItemSelection>) {
        mutate(identity, company, "copy_items", buildJsonObject {
            put("template_code", template); put("version", version); put("expected_revision", expectedRevision)
            putJsonArray("items") {
                items.forEach { item ->
                    addJsonObject {
                        put("source_template_code", item.sourceTemplateCode); put("source_item_code", item.sourceItemCode); put("allow_duplicate", item.allowDuplicate)
                        item.sectionTitle.trim().takeIf { it.isNotEmpty() }?.let { put("section_title", it) }
                        item.scopeKey.trim().takeIf { it.isNotEmpty() }?.let { put("scope_key", it) }
                    }
                }
            }
        })
    }

    suspend fun reorderItems(identity: IsgWorkspaceIdentity, company: String?, template: String, version: Int, expectedRevision: Long, itemCodes: List<String>) {
        mutate(identity, company, "reorder_items", buildJsonObject {
            put("template_code", template); put("version", version); put("expected_revision", expectedRevision)
            putJsonArray("item_codes") { itemCodes.forEach { add(it) } }
        })
    }

    suspend fun removeItem(identity: IsgWorkspaceIdentity, company: String?, template: String, version: Int, expectedRevision: Long, itemCode: String) {
        mutate(identity, company, "remove_item", buildJsonObject {
            put("template_code", template); put("version", version); put("expected_revision", expectedRevision); put("item_code", itemCode)
        })
    }

    suspend fun publishTemplate(identity: IsgWorkspaceIdentity, company: String?, template: String, version: Int, expectedRevision: Long, note: String) {
        mutate(identity, company, "publish_template", buildJsonObject {
            put("template_code", template); put("version", version); put("expected_revision", expectedRevision); put("approval_note", note.trim())
        })
    }

    suspend fun copyTemplate(identity: IsgWorkspaceIdentity, company: String?, template: String, title: String? = null) {
        mutate(identity, company, "copy_template", buildJsonObject {
            put("template_code", template); title?.trim()?.takeIf { it.isNotEmpty() }?.let { put("title", it) }
        })
    }

    suspend fun assignTemplate(identity: IsgWorkspaceIdentity, company: String, workplace: String?, template: String) {
        mutate(identity, company, "assign_template", buildJsonObject { put("template_code", template); put("workplace_id", text(workplace)) })
    }

    suspend fun deactivateAssignment(identity: IsgWorkspaceIdentity, company: String, assignment: String) {
        mutate(identity, company, "deactivate_assignment", buildJsonObject { put("assignment_id", assignment) })
    }

    suspend fun startRun(identity: IsgWorkspaceIdentity, company: String?, workplace: String?, template: String, startedOn: String, areaLabel: String = "",
                         equipmentLabel: String = "", documentNumber: String = ""): NovaChecklistRun? =
        mutate(identity, company, "start_run", buildJsonObject {
            put("template_code", template); workplace?.let { put("workplace_id", it) }
            if (isDay(startedOn)) put("started_on", startedOn)
            areaLabel.trim().takeIf { it.isNotEmpty() }?.let { put("area_label", it) }
            equipmentLabel.trim().takeIf { it.isNotEmpty() }?.let { put("equipment_label", it) }
            documentNumber.trim().takeIf { it.isNotEmpty() }?.let { put("document_number", it) }
        })

    suspend fun recordAnswer(identity: IsgWorkspaceIdentity, company: String?, draft: NovaChecklistAnswerDraft): NovaChecklistRun? {
        val run = draft.runId ?: throw NovaChecklistException(NovaChecklistFailure.validation)
        return mutate(identity, company, "record_item", buildJsonObject {
            put("run_id", run); put("item_code", draft.itemCode); put("result", draft.resultValue.wire); put("expected_revision", draft.expectedRevision)
            draft.note.trim().takeIf { it.isNotEmpty() }?.let { put("note", it) }
            draft.evidenceAssetId?.let { put("evidence_asset_id", it) }
            if (draft.resultValue == NovaChecklistResult.nonconform && draft.openNonconformity) {
                put("open_nonconformity", true); put("severity", draft.severity)
                if (isDay(draft.dueOn)) put("due_on", draft.dueOn)
            }
        })
    }

    suspend fun submitRun(identity: IsgWorkspaceIdentity, company: String?, run: String, expectedRevision: Long) =
        mutate(identity, company, "submit_run", buildJsonObject { put("run_id", run); put("expected_revision", expectedRevision) })

    suspend fun cancelRun(identity: IsgWorkspaceIdentity, company: String?, run: String, expectedRevision: Long) =
        mutate(identity, company, "cancel_run", buildJsonObject { put("run_id", run); put("expected_revision", expectedRevision) })

    suspend fun reviseRun(identity: IsgWorkspaceIdentity, company: String?, run: String, expectedRevision: Long, startedOn: String) =
        mutate(identity, company, "revise_run", buildJsonObject {
            put("run_id", run); put("expected_revision", expectedRevision); if (isDay(startedOn)) put("started_on", startedOn)
        })
}

/**
 * Device-only queue for field answers the server could not be reached for
 * (iOS `NovaChecklistOfflineQueue`). It holds no attachment bytes and never
 * invents a server success: an answer stays pending until the same mutation
 * succeeds or the expert answers again after a conflict.
 */
@Singleton
class NovaChecklistOfflineQueue @Inject constructor(@ApplicationContext context: Context) {
    @Serializable private data class Entry(val id: String, val companyId: String?, val draft: NovaChecklistAnswerDraft, val conflict: Boolean = false)

    private val storage = context.getSharedPreferences("nova.checklists.pending.v1", Context.MODE_PRIVATE)
    private val serializer = ListSerializer(Entry.serializer())

    private fun account(identity: IsgWorkspaceIdentity) = identity.userId.lowercase()
    private fun read(identity: IsgWorkspaceIdentity): List<Entry> =
        storage.getString(account(identity), null)?.let { runCatching { novaJson.decodeFromString(serializer, it) }.getOrNull() }.orEmpty()
    private fun write(identity: IsgWorkspaceIdentity, entries: List<Entry>) {
        if (entries.isEmpty()) storage.edit().remove(account(identity)).apply()
        else storage.edit().putString(account(identity), novaJson.encodeToString(serializer, entries)).apply()
    }

    fun count(identity: IsgWorkspaceIdentity) = read(identity).size
    fun conflictCount(identity: IsgWorkspaceIdentity) = read(identity).count { it.conflict }

    fun enqueue(identity: IsgWorkspaceIdentity, company: String?, draft: NovaChecklistAnswerDraft) {
        if (draft.attachment != null || draft.runId == null) throw NovaChecklistException(NovaChecklistFailure.unavailable)
        // The newest local edit replaces an older unsent one for the same question.
        val entries = read(identity).filterNot { it.companyId == company && it.draft.runId == draft.runId && it.draft.itemCode == draft.itemCode }
        write(identity, entries + Entry(UUID.randomUUID().toString(), company, draft))
    }

    /** Conflicts are kept and skipped until the expert answers again; any other failure stops the flush. */
    suspend fun flush(identity: IsgWorkspaceIdentity, send: suspend (String?, NovaChecklistAnswerDraft) -> NovaChecklistRun?): Int {
        val entries = read(identity).toMutableList()
        var index = 0
        while (index < entries.size) {
            val entry = entries[index]
            if (entry.conflict) { index++; continue }
            try {
                val updated = send(entry.companyId, entry.draft)
                entries.removeAt(index)
                updated?.revision?.let { next ->
                    entries.indices.filter { entries[it].draft.runId == entry.draft.runId }.forEach { entries[it] = entries[it].copy(draft = entries[it].draft.copy(expectedRevision = next)) }
                }
            } catch (failure: NovaChecklistException) {
                when (failure.failure) {
                    NovaChecklistFailure.conflict -> { entries[index] = entry.copy(conflict = true); index++ }
                    NovaChecklistFailure.runSubmitted -> entries.removeAt(index)
                    else -> break
                }
            }
        }
        write(identity, entries)
        return entries.size
    }
}
