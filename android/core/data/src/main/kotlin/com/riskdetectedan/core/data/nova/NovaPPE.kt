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
import kotlin.math.roundToLong

/** What a handover says about itself; counted from the returns at read time. */
enum class NovaPPEState(val wire: String, val title: String, val footer: String, val symbol: String) {
    outstanding("outstanding", "Zimmette", "hiç iade yok", "shippingbox"),
    partial("partial", "Kısmen iade", "bir kısmı dönmedi", "arrow.uturn.backward"),
    closed("closed", "Kapandı", "tamamı iade", "checkmark.circle");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

enum class NovaPPEUnit(val wire: String, val title: String) {
    piece("piece", "Adet"), pair("pair", "Çift"), set("set", "Takım"), metre("metre", "Metre"), litre("litre", "Litre");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

enum class NovaPPECondition(val wire: String, val title: String, val symbol: String) {
    reusable("reusable", "Kullanılabilir", "checkmark.circle"), worn("worn", "Yıpranmış", "exclamationmark.circle"),
    damaged("damaged", "Hasarlı", "xmark.octagon"), lost("lost", "Kayıp", "questionmark.circle");
    companion object { fun of(wire: String?) = entries.firstOrNull { it.wire == wire } }
}

data class NovaPPEReturn(val id: String, val quantity: Double, val returnedOn: String, val condition: NovaPPECondition, val note: String?)

data class NovaPPEHandover(
    val id: String, val companyId: String?, val companyName: String?, val employeeId: String?, val employeeName: String?,
    val employeeArchived: Boolean, val item: String, val quantity: Double, val unit: NovaPPEUnit, val handedOn: String,
    val externalRef: String?, val state: NovaPPEState, val returnedQuantity: Double, val outstanding: Double, val lostQuantity: Double,
    /** The product holds no file, so this is always false; only where the form is kept is recorded. */
    val signedCopyStored: Boolean, val signedCopyLocation: String?, val returns: List<NovaPPEReturn>,
)

data class NovaPPECatalogue(val employees: List<Employee>, val units: List<NovaPPEUnit>, val conditions: List<NovaPPECondition>,
                            val itemCatalogueOffered: Boolean, val signedCopyStorageAvailable: Boolean) {
    data class Employee(val id: String, val fullName: String)
}

data class NovaPPEBoard(val rows: List<NovaPPEHandover>, val counts: Map<String, Int>, val companies: List<CompanyTally>, val total: Int,
                        val hasMore: Boolean, val offset: Int) {
    data class CompanyTally(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    fun count(state: NovaPPEState) = counts[state.wire] ?: 0
}

data class NovaPPEQuery(val company: String? = null, val state: String? = null, val employee: String? = null,
                        val search: String = "", val limit: Int = 10, val offset: Int = 0)

data class NovaPPEHandoverDraft(val employeeId: String? = null, val item: String = "", val quantity: String = "1",
                                val unit: NovaPPEUnit = NovaPPEUnit.piece, val handedOn: String = "", val externalRef: String = "",
                                val signedCopyLocation: String = "")

data class NovaPPEReturnDraft(val handoverId: String? = null, val item: String = "", val outstanding: Double = 0.0,
                              val unit: NovaPPEUnit = NovaPPEUnit.piece, val quantity: String = "", val returnedOn: String = "",
                              val condition: NovaPPECondition = NovaPPECondition.reusable, val note: String = "")

enum class NovaPPEFailure(val message: String) {
    denied("Bu kayda erişim yok."), planRequired("Bu işlem için Plus veya Pro aboneliği gerekiyor."),
    featureUnavailable("Modüller henüz açık değil."), moduleUnavailable("KKD zimmet modülü henüz açık değil."),
    validation("Girilen bilgiler eksik veya birbiriyle uyumsuz."), conflict("Kayıt bu sırada başka bir yerden değişti. Yenileyip tekrar deneyin."),
    handedInFuture("Zimmet tarihi bugünden ileri olamaz."), returnedInFuture("İade tarihi bugünden ileri olamaz."),
    returnBeforeHandover("İade tarihi zimmet tarihinden önce olamaz."), returnExceedsHandover("İade miktarı zimmetten fazla olamaz."),
    unavailable("Kayıt alınamadı. Bağlantıyı kontrol edip tekrar deneyin."),
}

class NovaPPEException(val failure: NovaPPEFailure) : Exception(failure.name)

object NovaPPEWords {
    /** Quantities come back as decimals; a whole number is shown as one. */
    fun amount(value: Double, unit: NovaPPEUnit): String {
        val rounded = (value * 1000).roundToLong() / 1000.0
        val text = if (rounded == Math.rint(rounded)) rounded.toLong().toString() else String.format(java.util.Locale.ROOT, "%.3f", rounded).replace('.', ',')
        return "$text ${unit.title}"
    }
    fun explain(handover: NovaPPEHandover) = when (handover.state) {
        NovaPPEState.outstanding -> "${amount(handover.outstanding, handover.unit)} hâlâ zimmette."
        NovaPPEState.partial -> "${amount(handover.returnedQuantity, handover.unit)} iade edildi, ${amount(handover.outstanding, handover.unit)} hâlâ zimmette."
        NovaPPEState.closed -> "Tamamı iade edildi."
    }
    const val signedCopyNote = "İmzalı zimmet formu uygulamada saklanmaz. Burada yalnız aslının nerede tutulduğunu not edersiniz."
    const val noCatalogueNote = "Ürün hazır KKD listesi göndermez; ekipmanı siz adlandırırsınız."
}

/** KKD Zimmetleri boundary (iOS `NovaPPEService` + live adapter). */
@Singleton
class NovaPPEService @Inject constructor(private val transport: NovaExpertTransport, private val journal: NovaModuleMutationJournal) {
    @Serializable private data class ReturnRow(val id: String, val quantity: Double, @SerialName("returned_on") val returnedOn: String,
        val condition: String, val note: String? = null)
    @Serializable private data class HandoverRow(
        val id: String, @SerialName("company_id") val companyId: String? = null, @SerialName("company_name") val companyName: String? = null,
        @SerialName("employee_id") val employeeId: String? = null, @SerialName("employee_name") val employeeName: String? = null,
        @SerialName("employee_archived") val employeeArchived: Boolean, val item: String, val quantity: Double, val unit: String,
        @SerialName("handed_on") val handedOn: String, @SerialName("external_ref") val externalRef: String? = null, val state: String,
        @SerialName("returned_quantity") val returnedQuantity: Double, val outstanding: Double, @SerialName("lost_quantity") val lostQuantity: Double,
        @SerialName("signed_copy_stored") val signedCopyStored: Boolean, @SerialName("signed_copy_location") val signedCopyLocation: String? = null,
        val returns: List<ReturnRow>? = null)
    @Serializable private data class EmployeeRow(val id: String, @SerialName("full_name") val fullName: String)
    @Serializable private data class CatalogEnvelope(val employees: List<EmployeeRow>, val units: List<String>, val conditions: List<String>,
        @SerialName("item_catalogue_offered") val itemCatalogueOffered: Boolean,
        @SerialName("signed_copy_storage_available") val signedCopyStorageAvailable: Boolean)
    @Serializable private data class CompanyRow(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    @Serializable private data class ListEnvelope(val rows: List<HandoverRow>, val companies: List<CompanyRow>, val counts: Map<String, Int>,
        val total: Int, @SerialName("has_more") val hasMore: Boolean, val offset: Int)
    @Serializable private data class DetailEnvelope(val row: HandoverRow)
    @Serializable private data class MutationEnvelope(@SerialName("handover_id") val handoverId: String? = null, val row: HandoverRow? = null)

    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaPPEException(NovaPPEFailure.denied)
    }

    private fun map(failure: NovaExpertFailure): NovaPPEFailure = when {
        failure.sqlState !in setOf("P0001", "28000") && failure.code != "ACCESS_DENIED" -> NovaPPEFailure.unavailable
        failure.code in setOf("AUTH_REQUIRED", "ACCESS_DENIED") -> NovaPPEFailure.denied
        failure.code == "PAID_PLAN_REQUIRED" -> NovaPPEFailure.planRequired
        failure.code == "FEATURE_UNAVAILABLE" -> NovaPPEFailure.featureUnavailable
        failure.code == "MODULE_UNAVAILABLE" -> NovaPPEFailure.moduleUnavailable
        failure.code == "HANDED_IN_THE_FUTURE" -> NovaPPEFailure.handedInFuture
        failure.code == "RETURNED_IN_THE_FUTURE" -> NovaPPEFailure.returnedInFuture
        failure.code == "RETURN_BEFORE_HANDOVER" -> NovaPPEFailure.returnBeforeHandover
        failure.code == "RETURN_EXCEEDS_HANDOVER" -> NovaPPEFailure.returnExceedsHandover
        failure.code == "IDEMPOTENCY_CONFLICT" -> NovaPPEFailure.conflict
        failure.code in setOf("VALIDATION_ERROR", "PAYLOAD_NOT_ALLOWED") -> NovaPPEFailure.validation
        else -> NovaPPEFailure.unavailable
    }

    private suspend fun <T> guarded(block: suspend () -> T): T = try { block() } catch (failure: NovaExpertFailure) {
        currentCoroutineContext().ensureActive(); throw NovaPPEException(map(failure))
    }

    private fun <T> JsonElement.decode(serializer: KSerializer<T>): T = try { novaJson.decodeFromJsonElement(serializer, this) }
        catch (_: Exception) { throw NovaPPEException(NovaPPEFailure.unavailable) }

    /** An unknown state word reads as outstanding rather than the calmest answer. */
    private fun handover(entry: HandoverRow) = NovaPPEHandover(entry.id, entry.companyId, entry.companyName, entry.employeeId, entry.employeeName,
        entry.employeeArchived, entry.item, entry.quantity, NovaPPEUnit.of(entry.unit) ?: NovaPPEUnit.piece, entry.handedOn, entry.externalRef,
        NovaPPEState.of(entry.state) ?: NovaPPEState.outstanding, entry.returnedQuantity, entry.outstanding, entry.lostQuantity,
        entry.signedCopyStored, entry.signedCopyLocation,
        entry.returns.orEmpty().map { NovaPPEReturn(it.id, it.quantity, it.returnedOn, NovaPPECondition.of(it.condition) ?: NovaPPECondition.reusable, it.note) })

    private suspend fun read(arguments: Map<String, JsonElement>): JsonElement = guarded {
        val payload = mutableMapOf<String, JsonElement>("p_company" to JsonNull, "p_kind" to JsonPrimitive("list"), "p_query" to JsonNull,
            "p_state" to JsonNull, "p_employee" to JsonNull, "p_id" to JsonNull, "p_limit" to JsonNull, "p_offset" to JsonNull)
        payload.putAll(arguments)
        transport.execute("isg_ppe_read_v1", JsonObject(payload))
    }

    private fun text(value: String?): JsonElement = value?.let(::JsonPrimitive) ?: JsonNull
    private fun isDay(value: String) = runCatching { java.time.LocalDate.parse(value) }.isSuccess
    private fun decimal(value: String) = value.replace(',', '.').trim().toDoubleOrNull()

    suspend fun catalogue(identity: IsgWorkspaceIdentity, company: String?): NovaPPECatalogue {
        check(identity)
        val envelope = read(mapOf("p_company" to text(company), "p_kind" to JsonPrimitive("catalog"))).decode(CatalogEnvelope.serializer())
        check(identity)
        return NovaPPECatalogue(envelope.employees.map { NovaPPECatalogue.Employee(it.id, it.fullName) }, envelope.units.mapNotNull { NovaPPEUnit.of(it) },
            envelope.conditions.mapNotNull { NovaPPECondition.of(it) }, envelope.itemCatalogueOffered, envelope.signedCopyStorageAvailable)
    }

    suspend fun board(identity: IsgWorkspaceIdentity, query: NovaPPEQuery): NovaPPEBoard {
        check(identity)
        val envelope = read(mapOf("p_company" to text(query.company), "p_query" to text(query.search.trim().ifEmpty { null }),
            "p_state" to text(query.state), "p_employee" to text(query.employee), "p_limit" to JsonPrimitive(query.limit),
            "p_offset" to JsonPrimitive(query.offset))).decode(ListEnvelope.serializer())
        check(identity)
        return NovaPPEBoard(envelope.rows.map(::handover), envelope.counts, envelope.companies.map { NovaPPEBoard.CompanyTally(it.id, it.name, it.total, it.counts) },
            envelope.total, envelope.hasMore, envelope.offset)
    }

    suspend fun detail(identity: IsgWorkspaceIdentity, handover: String): NovaPPEHandover {
        check(identity)
        val row = read(mapOf("p_kind" to JsonPrimitive("detail"), "p_id" to JsonPrimitive(handover))).decode(DetailEnvelope.serializer()).row
        check(identity); return handover(row)
    }

    private suspend fun mutate(identity: IsgWorkspaceIdentity, company: String, action: String, payload: JsonObject): NovaPPEHandover? {
        check(identity)
        return guarded { journal.run("isg_ppe_mutate_v1", identity, company, action, payload) { it.decode(MutationEnvelope.serializer()).row?.let(::handover) } }
    }

    /** The signed copy flag is never sent: the product holds no file. What is sent is where the form is kept. */
    suspend fun recordHandover(identity: IsgWorkspaceIdentity, company: String, draft: NovaPPEHandoverDraft): NovaPPEHandover? {
        val employee = draft.employeeId; val quantity = decimal(draft.quantity)
        if (employee == null || quantity == null || quantity <= 0 || !isDay(draft.handedOn) || draft.item.isBlank())
            throw NovaPPEException(NovaPPEFailure.validation)
        return mutate(identity, company, "record_handover", buildJsonObject {
            put("employee_id", employee); put("item", draft.item.trim()); put("quantity", quantity.toString()); put("unit", draft.unit.wire)
            put("handed_on", draft.handedOn)
            draft.externalRef.trim().takeIf { it.isNotEmpty() }?.let { put("external_ref", it) }
            draft.signedCopyLocation.trim().takeIf { it.isNotEmpty() }?.let { put("signed_copy_location", it) }
        })
    }

    suspend fun recordReturn(identity: IsgWorkspaceIdentity, company: String, draft: NovaPPEReturnDraft): NovaPPEHandover? {
        val handover = draft.handoverId; val quantity = decimal(draft.quantity)
        if (handover == null || quantity == null || quantity <= 0 || !isDay(draft.returnedOn)) throw NovaPPEException(NovaPPEFailure.validation)
        return mutate(identity, company, "record_return", buildJsonObject {
            put("handover_id", handover); put("quantity", quantity.toString()); put("returned_on", draft.returnedOn); put("condition", draft.condition.wire)
            draft.note.trim().takeIf { it.isNotEmpty() }?.let { put("note", it) }
        })
    }

    /** Taking back a return entered by mistake; what is still out is recounted at the next read. */
    suspend fun removeReturn(identity: IsgWorkspaceIdentity, company: String, handover: String, entry: String): NovaPPEHandover? =
        mutate(identity, company, "remove_return", buildJsonObject { put("handover_id", handover); put("return_id", entry) })
}
