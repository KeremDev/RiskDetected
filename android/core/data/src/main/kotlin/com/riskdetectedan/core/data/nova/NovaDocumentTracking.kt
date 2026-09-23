package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import javax.inject.Inject
import javax.inject.Singleton

/**
 * What the tracker says about one obligation today (iOS `NovaDocumentStatus`). The value always
 * comes from the server; nothing here recomputes it from the dates.
 */
enum class NovaDocumentStatus(val wire: String, val title: String, val symbol: String) {
    missing("missing", "Eksik", "questionmark.circle"),
    dueSoon("due_soon", "Yaklaşıyor", "clock"),
    expired("expired", "Süresi doldu", "exclamationmark.circle"),
    valid("valid", "Güncel", "checkmark.circle");

    companion object {
        /** An unknown word is reported as missing, so the expert looks at the row instead of trusting a guess. */
        fun of(wire: String) = entries.firstOrNull { it.wire == wire } ?: missing
    }
}

/** Who says the document is owed: the expert's own decision, or the legal reference they rely on. */
enum class NovaDocumentBasis(val wire: String, val title: String) {
    expert("expert", "Uzman kararı"), legal("legal", "Mevzuat dayanağı");
    companion object { fun of(wire: String) = entries.firstOrNull { it.wire == wire } ?: expert }
}

/** One copy the company holds. The file itself is not stored; what is kept is where the original is. */
data class NovaDocumentCopy(val id: String, val issuedOn: String, val validUntil: String?, val documentNo: String?,
                            val locationNote: String?, val recordedAt: String?)

data class NovaDocumentObligation(
    val id: String, val companyId: String?, val companyName: String?, val workplaceId: String?, val kindCode: String,
    val title: String, val basis: NovaDocumentBasis, val legalRef: String?, val validityDays: Int?, val noticeDays: Int,
    val responsibleContact: String?, val note: String?, val isArchived: Boolean, val version: Int,
    val status: NovaDocumentStatus, val latestIssuedOn: String?, val latestValidUntil: String?, val copies: List<NovaDocumentCopy>,
    val fileStored: Boolean,
)

/** One company's share of the portfolio, as the server counted it. */
data class NovaDocumentCompanySummary(val id: String, val name: String, val total: Int, val counts: Map<NovaDocumentStatus, Int>) {
    fun count(status: NovaDocumentStatus) = counts[status] ?: 0
}

/**
 * The whole account in one answer (iOS `NovaDocumentPortfolio`): the tally, the per-company
 * summary and one page of rows. The tally covers everything tracked, before any filter.
 */
data class NovaDocumentPortfolio(
    val counts: Map<NovaDocumentStatus, Int> = emptyMap(),
    val companies: List<NovaDocumentCompanySummary> = emptyList(),
    val rows: List<NovaDocumentObligation> = emptyList(),
    val total: Int = 0,
    val hasMore: Boolean = false,
    val today: String = "",
) {
    fun count(status: NovaDocumentStatus) = counts[status] ?: 0
}

/** What the portfolio page is asking for right now; ten rows at a time. */
data class NovaDocumentQuery(val query: String = "", val status: NovaDocumentStatus? = null, val company: String? = null,
                             val limit: Int = 10, val offset: Int = 0)

class NovaDocumentFailure(val reason: Reason) : Exception(reason.name) {
    enum class Reason(val message: String) {
        denied("Bu firmanın evrak takibine erişiminiz yok."),
        planRequired("Evrak takibi için Plus veya Pro plan gerekir."),
        unavailable("Evrak takibi şu anda kullanılamıyor."),
    }
}

/** The tracker's words for the catalogue codes (iOS `NovaDocumentWords`). */
object NovaDocumentWords {
    fun kind(code: String) = when (code) {
        "risk_assessment" -> "Risk değerlendirmesi"
        "emergency_plan" -> "Acil durum planı"
        "drill_record" -> "Tatbikat kaydı"
        "training_record" -> "Eğitim kaydı"
        "board_minutes" -> "Kurul tutanağı"
        "appointment_letter" -> "Görevlendirme yazısı"
        "ppe_handover" -> "KKD zimmet formu"
        "equipment_inspection" -> "Periyodik kontrol raporu"
        "measurement_report" -> "Ortam ölçüm raporu"
        "service_contract" -> "İSG hizmet sözleşmesi"
        "annual_work_plan" -> "Yıllık çalışma planı"
        "annual_training_plan" -> "Yıllık eğitim planı"
        "permit_form" -> "Çalışma izni formu"
        "contractor_file" -> "Taşeron evrak dosyası"
        "approved_notebook" -> "Onaylı defter"
        else -> "Diğer belge"
    }

    fun kindSymbol(code: String) = when (code) {
        "risk_assessment" -> "exclamationmark.triangle"
        "emergency_plan" -> "figure.run"
        "drill_record" -> "flame"
        "training_record", "annual_training_plan" -> "graduationcap.fill"
        "board_minutes" -> "person.3"
        "appointment_letter" -> "signature"
        "ppe_handover" -> "shield"
        "equipment_inspection" -> "wrench.and.screwdriver"
        "measurement_report" -> "waveform.path.ecg"
        "service_contract" -> "doc.plaintext"
        "annual_work_plan" -> "calendar"
        "permit_form" -> "checkmark.seal"
        "contractor_file" -> "building.2"
        "approved_notebook" -> "book"
        else -> "doc.text"
    }
}

/** Reads the pre-follow-up document tracker (`isg_document_portfolio_v1`), which the pilot shows read-only. */
@Singleton
class NovaDocumentTrackingService @Inject constructor(private val transport: NovaExpertTransport) {
    @Serializable private data class CopyRow(val id: String, @SerialName("issued_on") val issuedOn: String,
        @SerialName("valid_until") val validUntil: String? = null, @SerialName("document_no") val documentNo: String? = null,
        @SerialName("location_note") val locationNote: String? = null, @SerialName("recorded_at") val recordedAt: String? = null)
    @Serializable private data class ObligationRow(val id: String, @SerialName("company_id") val companyId: String? = null,
        @SerialName("company_name") val companyName: String? = null, @SerialName("workplace_id") val workplaceId: String? = null,
        @SerialName("kind_code") val kindCode: String, val title: String, val basis: String,
        @SerialName("legal_ref") val legalRef: String? = null, @SerialName("validity_days") val validityDays: Int? = null,
        @SerialName("notice_days") val noticeDays: Int, @SerialName("responsible_contact") val responsibleContact: String? = null,
        val note: String? = null, @SerialName("is_archived") val isArchived: Boolean, val version: Int, val status: String,
        @SerialName("latest_issued_on") val latestIssuedOn: String? = null, @SerialName("latest_valid_until") val latestValidUntil: String? = null,
        val records: List<CopyRow>, @SerialName("file_stored") val fileStored: Boolean)
    @Serializable private data class CompanyRow(val id: String, val name: String, val total: Int, val counts: Map<String, Int>)
    @Serializable private data class PortfolioEnvelope(val rows: List<ObligationRow>, val companies: List<CompanyRow>,
        val counts: Map<String, Int>,
        val total: Int, @SerialName("has_more") val hasMore: Boolean, val today: String)

    private fun statuses(raw: Map<String, Int>) =
        raw.mapNotNull { (key, value) -> NovaDocumentStatus.entries.firstOrNull { it.wire == key }?.let { it to value } }.toMap()

    /** The whole account in one call; it is not company-scoped, so the session is checked on both sides. */
    suspend fun portfolio(identity: IsgWorkspaceIdentity, request: NovaDocumentQuery): NovaDocumentPortfolio {
        if (transport.identityNow() != identity) throw NovaDocumentFailure(NovaDocumentFailure.Reason.denied)
        val data = try {
            transport.execute("isg_document_portfolio_v1", buildJsonObject {
                put("p_query", request.query.ifEmpty { null }?.let(::JsonPrimitive) ?: JsonNull)
                put("p_status", request.status?.let { JsonPrimitive(it.wire) } ?: JsonNull)
                put("p_company", request.company?.let(::JsonPrimitive) ?: JsonNull)
                put("p_kinds", JsonNull)
                put("p_limit", request.limit); put("p_offset", request.offset)
            })
        } catch (failure: NovaExpertFailure) {
            currentCoroutineContext().ensureActive()
            throw NovaDocumentFailure(when (failure.code) {
                "AUTH_REQUIRED", "ACCESS_DENIED" -> NovaDocumentFailure.Reason.denied
                "PAID_PLAN_REQUIRED" -> NovaDocumentFailure.Reason.planRequired
                else -> NovaDocumentFailure.Reason.unavailable
            })
        }
        if (transport.identityNow() != identity) throw NovaDocumentFailure(NovaDocumentFailure.Reason.denied)
        val envelope = runCatching { novaJson.decodeFromJsonElement(PortfolioEnvelope.serializer(), data) }.getOrNull()
            ?: throw NovaDocumentFailure(NovaDocumentFailure.Reason.unavailable)
        return NovaDocumentPortfolio(
            counts = statuses(envelope.counts),
            companies = envelope.companies.map { NovaDocumentCompanySummary(it.id, it.name, it.total, statuses(it.counts)) },
            rows = envelope.rows.map { row ->
                NovaDocumentObligation(row.id, row.companyId, row.companyName, row.workplaceId, row.kindCode, row.title,
                    NovaDocumentBasis.of(row.basis), row.legalRef, row.validityDays, row.noticeDays, row.responsibleContact, row.note,
                    row.isArchived, row.version, NovaDocumentStatus.of(row.status), row.latestIssuedOn, row.latestValidUntil,
                    row.records.map { NovaDocumentCopy(it.id, it.issuedOn, it.validUntil, it.documentNo, it.locationNote, it.recordedAt) },
                    row.fileStored)
            },
            total = envelope.total, hasMore = envelope.hasMore, today = envelope.today,
        )
    }
}
