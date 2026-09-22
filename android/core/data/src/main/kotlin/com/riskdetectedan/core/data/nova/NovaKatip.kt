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
import kotlinx.serialization.json.*
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

enum class NovaKatipState(val wire: String, val title: String) {
    upcoming("upcoming", "Başlayacak"), active("active", "Yürürlükte"), expiring("expiring", "Bitiyor"),
    expired("expired", "Süresi doldu"), archived("archived", "Arşivlendi");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

enum class NovaKatipGroup(val wire: String, val title: String, val footer: String, val symbol: String, val states: List<NovaKatipState>) {
    expired("expired", "Süresi doldu", "tarih geçti", "exclamationmark.triangle", listOf(NovaKatipState.expired)),
    expiring("expiring", "Bitiyor", "yaklaşan", "clock", listOf(NovaKatipState.expiring)),
    current("current", "Yürürlükte", "sürüyor", "doc.text", listOf(NovaKatipState.upcoming, NovaKatipState.active)),
    archived("archived", "Arşiv", "kapatıldı", "archivebox", listOf(NovaKatipState.archived));
    companion object {
        fun of(state: NovaKatipState) = entries.firstOrNull { state in it.states } ?: current
        fun ofWire(wire: String?) = entries.firstOrNull { it.wire == wire }
    }
}

enum class NovaKatipTerm(val wire: String, val title: String) {
    openEnded("open_ended", "Süresiz"), fixedTerm("fixed_term", "Süreli");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

data class NovaKatipContract(
    val id: String, val companyId: String?, val companyName: String?, val workplaceId: String?, val workplaceName: String?,
    val counterparty: String, val expertContact: String, val scope: String, val startsOn: String, val endsBefore: String?,
    val term: NovaKatipTerm, val state: NovaKatipState, val group: NovaKatipGroup, val noticeDays: Int, val declaredMonthlyMinutes: Int?,
    val declaredNote: String?, val requiredServiceTimeKnown: Boolean, val contractStored: Boolean, val contractLocation: String?,
    val officialIntegration: Boolean, val officialSubmissionMade: Boolean, val fileEntryId: String? = null, val documentVersion: Long = 0,
    val documentTitle: String? = null,
)

data class NovaKatipCatalogue(val workplaces: List<Workplace>, val noticeDays: Int, val officialIntegration: Boolean, val officialStatusChecked: Boolean,
                              val credentialCollection: Boolean, val requiredServiceTimeKnown: Boolean, val contractStorageAvailable: Boolean) {
    data class Workplace(val id: String, val name: String)
}

data class NovaKatipBoard(val rows: List<NovaKatipContract>, val counts: Map<String, Int>, val companies: List<CompanyTally>, val total: Int,
                          val hasMore: Boolean, val offset: Int, val noticeDays: Int) {
    data class CompanyTally(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    fun count(group: NovaKatipGroup) = group.states.sumOf { counts[it.wire] ?: 0 }
}

data class NovaKatipQuery(val company: String? = null, val state: String? = null, val workplace: String? = null,
                          val search: String = "", val limit: Int = 10, val offset: Int = 0)

data class NovaKatipDraft(val workplaceId: String? = null, val counterparty: String = "", val expertContact: String = "", val scope: String = "",
                          val startsOn: String = "", val endsBefore: String = "", val declaredMonthlyMinutes: String = "", val declaredNote: String = "",
                          val contractLocation: String = "")

data class NovaKatipEndDraft(val contractId: String? = null, val counterparty: String = "", val startsOn: String = "", val endsBefore: String = "",
                             val isCorrection: Boolean = false)

enum class NovaKatipFailure(val message: String) {
    denied("Bu kayda erişim yok."), planRequired("Bu işlem için Plus veya Pro aboneliği gerekiyor."),
    featureUnavailable("Modüller henüz açık değil."), moduleUnavailable("İSG-KATİP sözleşme modülü henüz açık değil."),
    validation("Girilen bilgiler eksik veya birbiriyle uyumsuz."), conflict("Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin."),
    endsBeforeStart("Bitiş tarihi başlangıçtan önce olamaz."), archived("Arşivlenmiş sözleşmenin tarihleri değiştirilemez."),
    unavailable("Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin."),
}

class NovaKatipException(val failure: NovaKatipFailure) : Exception(failure.name)

object NovaKatipWords {
    fun service(minutes: Int): String {
        val hours = minutes / 60; val rest = minutes % 60
        return if (rest == 0) "ayda $hours saat" else "ayda $hours saat $rest dakika"
    }
    fun explain(entry: NovaKatipContract) = when (entry.state) {
        NovaKatipState.upcoming -> "${NovaDayText.label(entry.startsOn)} tarihinde başlayacak."
        NovaKatipState.active -> if (entry.term == NovaKatipTerm.openEnded) "Süresiz sözleşme; bitiş tarihi yok."
            else "${NovaDayText.label(entry.endsBefore.orEmpty())} tarihine kadar yürürlükte."
        NovaKatipState.expiring -> "${NovaDayText.label(entry.endsBefore.orEmpty())} tarihinde bitiyor."
        NovaKatipState.expired -> "${NovaDayText.label(entry.endsBefore.orEmpty())} tarihinde sona erdi."
        NovaKatipState.archived -> "Bu sözleşme arşivlendi."
    }
    const val noIntegrationNote = "Uygulama İSG-KATİP üzerinde işlem yapmaz, sorgu çekmez ve şifre istemez. Burası yalnız sizin kendi sözleşme kaydınızdır."
    const val declaredNote = "Bu süre sözleşmenin beyanıdır. Ürün gereken süreyi bilmez ve yeterli olup olmadığını söylemez."
    const val documentNote = "Sözleşme belgesi uygulamada saklanmaz. Burada yalnız aslının nerede tutulduğunu not edersiniz."
}

/**
 * İSG-KATİP Sözleşmeleri boundary (iOS `NovaKatipService`). Unlike the other
 * modules it keeps one pending write per account: a different write while one
 * is unresolved is a conflict, and the screen offers to finish the pending one.
 */
@Singleton
class NovaKatipService @Inject constructor(@ApplicationContext context: Context, private val transport: NovaExpertTransport,
                                           private val events: NovaRecordEvents) {
    private val storage = context.getSharedPreferences("nova.katip.pending.v1", Context.MODE_PRIVATE)

    @Serializable private data class Pending(val company: String, val action: String, val payload: String, val operation: String, val mutation: String)
    @Serializable private data class ContractRow(
        val id: String, @SerialName("company_id") val companyId: String? = null, @SerialName("company_name") val companyName: String? = null,
        @SerialName("workplace_id") val workplaceId: String? = null, @SerialName("workplace_name") val workplaceName: String? = null,
        val counterparty: String, @SerialName("expert_contact") val expertContact: String, val scope: String, @SerialName("starts_on") val startsOn: String,
        @SerialName("ends_before") val endsBefore: String? = null, @SerialName("term_state") val termState: String, val state: String,
        @SerialName("notice_days") val noticeDays: Int, @SerialName("declared_monthly_minutes") val declaredMonthlyMinutes: Int? = null,
        @SerialName("declared_note") val declaredNote: String? = null, @SerialName("required_service_time_known") val requiredServiceTimeKnown: Boolean,
        @SerialName("contract_stored") val contractStored: Boolean, @SerialName("contract_location") val contractLocation: String? = null,
        @SerialName("official_integration") val officialIntegration: Boolean, @SerialName("official_submission_made") val officialSubmissionMade: Boolean,
        @SerialName("file_entry_id") val fileEntryId: String? = null, @SerialName("document_version") val documentVersion: Long? = null,
        @SerialName("document_title") val documentTitle: String? = null)
    @Serializable private data class WorkplaceRow(val id: String, val name: String)
    @Serializable private data class CatalogEnvelope(val workplaces: List<WorkplaceRow>, @SerialName("notice_days") val noticeDays: Int,
        @SerialName("official_integration") val officialIntegration: Boolean, @SerialName("official_status_checked") val officialStatusChecked: Boolean,
        @SerialName("credential_collection") val credentialCollection: Boolean,
        @SerialName("required_service_time_known") val requiredServiceTimeKnown: Boolean,
        @SerialName("contract_storage_available") val contractStorageAvailable: Boolean)
    @Serializable private data class CompanyRow(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    @Serializable private data class ListEnvelope(val rows: List<ContractRow>, val companies: List<CompanyRow>, val counts: Map<String, Int>,
        val total: Int, @SerialName("has_more") val hasMore: Boolean, val offset: Int, @SerialName("notice_days") val noticeDays: Int)
    @Serializable private data class DetailEnvelope(val row: ContractRow)
    @Serializable private data class MutationEnvelope(@SerialName("contract_id") val contractId: String? = null, val row: ContractRow? = null)

    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaKatipException(NovaKatipFailure.denied)
    }

    private fun map(failure: NovaExpertFailure): NovaKatipFailure = when {
        failure.sqlState !in setOf("P0001", "28000") && failure.code != "ACCESS_DENIED" -> NovaKatipFailure.unavailable
        failure.code in setOf("AUTH_REQUIRED", "ACCESS_DENIED") -> NovaKatipFailure.denied
        failure.code == "PAID_PLAN_REQUIRED" -> NovaKatipFailure.planRequired
        failure.code == "FEATURE_UNAVAILABLE" -> NovaKatipFailure.featureUnavailable
        failure.code == "MODULE_UNAVAILABLE" -> NovaKatipFailure.moduleUnavailable
        failure.code == "ENDS_BEFORE_START" -> NovaKatipFailure.endsBeforeStart
        failure.code == "CONTRACT_ARCHIVED" -> NovaKatipFailure.archived
        failure.code == "IDEMPOTENCY_CONFLICT" -> NovaKatipFailure.conflict
        failure.code in setOf("VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED", "VERSION_CONFLICT", "DOCUMENT_NOT_READY") -> NovaKatipFailure.validation
        else -> NovaKatipFailure.unavailable
    }

    private suspend fun <T> guarded(block: suspend () -> T): T = try { block() } catch (failure: NovaExpertFailure) {
        currentCoroutineContext().ensureActive(); throw NovaKatipException(map(failure))
    }

    private fun <T> JsonElement.decode(serializer: KSerializer<T>): T = try { novaJson.decodeFromJsonElement(serializer, this) }
        catch (_: Exception) { throw NovaKatipException(NovaKatipFailure.unavailable) }

    /** An unknown state word reads as expired rather than the calmest answer. */
    private fun contract(entry: ContractRow): NovaKatipContract {
        val state = NovaKatipState.of(entry.state) ?: NovaKatipState.expired
        return NovaKatipContract(entry.id, entry.companyId, entry.companyName, entry.workplaceId, entry.workplaceName, entry.counterparty,
            entry.expertContact, entry.scope, entry.startsOn, entry.endsBefore, NovaKatipTerm.of(entry.termState) ?: NovaKatipTerm.fixedTerm, state,
            NovaKatipGroup.of(state), entry.noticeDays, entry.declaredMonthlyMinutes, entry.declaredNote, entry.requiredServiceTimeKnown,
            entry.contractStored, entry.contractLocation, entry.officialIntegration, entry.officialSubmissionMade, entry.fileEntryId,
            entry.documentVersion ?: 0, entry.documentTitle)
    }

    private suspend fun read(arguments: Map<String, JsonElement>): JsonElement = guarded {
        val payload = mutableMapOf<String, JsonElement>("p_company" to JsonNull, "p_kind" to JsonPrimitive("list"), "p_query" to JsonNull,
            "p_state" to JsonNull, "p_workplace" to JsonNull, "p_id" to JsonNull, "p_limit" to JsonNull, "p_offset" to JsonNull)
        payload.putAll(arguments)
        transport.execute("isg_katip_read_v1", JsonObject(payload))
    }

    private fun text(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull
    private fun isDay(value: String) = runCatching { java.time.LocalDate.parse(value) }.isSuccess

    suspend fun catalogue(identity: IsgWorkspaceIdentity, company: String?): NovaKatipCatalogue {
        check(identity)
        val envelope = read(mapOf("p_company" to text(company), "p_kind" to JsonPrimitive("catalog"))).decode(CatalogEnvelope.serializer())
        check(identity)
        return NovaKatipCatalogue(envelope.workplaces.map { NovaKatipCatalogue.Workplace(it.id, it.name) }, envelope.noticeDays, envelope.officialIntegration,
            envelope.officialStatusChecked, envelope.credentialCollection, envelope.requiredServiceTimeKnown, envelope.contractStorageAvailable)
    }

    suspend fun board(identity: IsgWorkspaceIdentity, query: NovaKatipQuery): NovaKatipBoard {
        check(identity)
        val envelope = read(mapOf("p_company" to text(query.company), "p_query" to text(query.search.trim().ifEmpty { null }),
            "p_state" to text(query.state), "p_workplace" to text(query.workplace), "p_limit" to JsonPrimitive(query.limit),
            "p_offset" to JsonPrimitive(query.offset))).decode(ListEnvelope.serializer())
        check(identity)
        return NovaKatipBoard(envelope.rows.map(::contract), envelope.counts, envelope.companies.map { NovaKatipBoard.CompanyTally(it.id, it.name, it.total, it.counts) },
            envelope.total, envelope.hasMore, envelope.offset, envelope.noticeDays)
    }

    suspend fun detail(identity: IsgWorkspaceIdentity, contract: String): NovaKatipContract {
        check(identity)
        val row = read(mapOf("p_kind" to JsonPrimitive("detail"), "p_id" to JsonPrimitive(contract))).decode(DetailEnvelope.serializer()).row
        check(identity); return contract(row)
    }

    private fun account(identity: IsgWorkspaceIdentity) = identity.userId.lowercase()

    fun hasPending(identity: IsgWorkspaceIdentity): Boolean {
        check(identity)
        return storage.contains(account(identity))
    }

    suspend fun resume(identity: IsgWorkspaceIdentity): NovaKatipContract? {
        check(identity)
        val saved = storage.getString(account(identity), null) ?: return null
        val pending = runCatching { novaJson.decodeFromString(Pending.serializer(), saved) }.getOrNull()
            ?: run { storage.edit().remove(account(identity)).apply(); return null }
        return mutate(identity, pending.company, pending.action, novaJson.parseToJsonElement(pending.payload).jsonObject)
    }

    /** Network, decoding and changed-session outcomes keep the original ids, so a retry never writes twice. */
    private suspend fun mutate(identity: IsgWorkspaceIdentity, company: String, action: String, payload: JsonObject): NovaKatipContract? {
        check(identity)
        val encoded = novaCanonicalJson(payload)
        val key = account(identity)
        val pending = storage.getString(key, null)?.let { saved -> runCatching { novaJson.decodeFromString(Pending.serializer(), saved) }.getOrNull() }?.also {
            if (it.company != company || it.action != action || it.payload != encoded) throw NovaKatipException(NovaKatipFailure.conflict)
        } ?: Pending(company, action, encoded, UUID.randomUUID().toString(), UUID.randomUUID().toString()).also {
            storage.edit().putString(key, novaJson.encodeToString(Pending.serializer(), it)).commit()
        }
        try {
            val data = guarded {
                transport.execute("isg_katip_mutate_v1", buildJsonObject {
                    put("p_company", company); put("p_action", action); put("p_operation", pending.operation); put("p_mutation", pending.mutation)
                    put("p_payload", payload)
                })
            }
            check(identity)
            val row = data.decode(MutationEnvelope.serializer()).row?.let(::contract)
            storage.edit().remove(key).apply()
            events.recordsChanged(identity.userId)
            return row
        } catch (error: NovaKatipException) {
            // A refused request will never succeed on retry; drop it so the next write is not blocked.
            if (error.failure in setOf(NovaKatipFailure.validation, NovaKatipFailure.endsBeforeStart, NovaKatipFailure.archived, NovaKatipFailure.planRequired,
                    NovaKatipFailure.featureUnavailable, NovaKatipFailure.moduleUnavailable)) storage.edit().remove(key).apply()
            throw error
        }
    }

    suspend fun record(identity: IsgWorkspaceIdentity, company: String, draft: NovaKatipDraft): NovaKatipContract? {
        val workplace = draft.workplaceId
        if (workplace == null || !isDay(draft.startsOn) || draft.counterparty.isBlank() || draft.expertContact.isBlank() || draft.scope.isBlank())
            throw NovaKatipException(NovaKatipFailure.validation)
        val end = draft.endsBefore.trim()
        val minutesText = draft.declaredMonthlyMinutes.trim()
        val minutes = minutesText.toIntOrNull()
        if ((end.isNotEmpty() && !isDay(end)) || (minutesText.isNotEmpty() && (minutes == null || minutes !in 1..100000)))
            throw NovaKatipException(NovaKatipFailure.validation)
        if (end.isNotEmpty() && end <= draft.startsOn) throw NovaKatipException(NovaKatipFailure.endsBeforeStart)
        return mutate(identity, company, "record_contract", buildJsonObject {
            put("workplace_id", workplace); put("counterparty", draft.counterparty.trim()); put("expert_contact", draft.expertContact.trim())
            put("scope", draft.scope.trim()); put("starts_on", draft.startsOn)
            if (end.isNotEmpty()) put("ends_before", end)
            minutes?.let { put("declared_monthly_minutes", it) }
            draft.declaredNote.trim().takeIf { it.isNotEmpty() }?.let { put("declared_note", it) }
            draft.contractLocation.trim().takeIf { it.isNotEmpty() }?.let { put("contract_location", it) }
        })
    }

    suspend fun linkDocument(identity: IsgWorkspaceIdentity, contract: NovaKatipContract, file: String?): NovaKatipContract? {
        val company = contract.companyId ?: throw NovaKatipException(NovaKatipFailure.denied)
        return mutate(identity, company, "link_document", buildJsonObject {
            put("contract_id", contract.id); put("file_entry_id", text(file)); put("expected_version", contract.documentVersion)
        })
    }

    suspend fun end(identity: IsgWorkspaceIdentity, company: String, draft: NovaKatipEndDraft): NovaKatipContract? {
        val contract = draft.contractId
        if (contract == null || !isDay(draft.endsBefore)) throw NovaKatipException(NovaKatipFailure.validation)
        return mutate(identity, company, "end_contract", buildJsonObject { put("contract_id", contract); put("ends_before", draft.endsBefore) })
    }

    suspend fun archive(identity: IsgWorkspaceIdentity, company: String, contract: String): NovaKatipContract? =
        mutate(identity, company, "archive_contract", buildJsonObject { put("contract_id", contract) })
}
