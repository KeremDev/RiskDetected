package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import javax.inject.Inject
import javax.inject.Singleton

internal val novaJson = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = false }

internal fun <T> JsonElement.decodeAs(serializer: KSerializer<T>): T = try {
    novaJson.decodeFromJsonElement(serializer, this)
} catch (_: Exception) {
    throw NovaExpertFailure("UNAVAILABLE")
}

internal fun JsonObjectBuilder.putId(key: String, value: String?) { put(key, value?.let(::JsonPrimitive) ?: JsonNull) }

/** One company as the pilot overview reports it (iOS `NovaPilotCompanySummary`). */
@Serializable
data class NovaCompanySummary(
    val id: String,
    @SerialName("owner_id") val ownerId: String,
    val name: String,
    @SerialName("hazard_class") val hazardClass: String,
    @SerialName("is_archived") val isArchived: Boolean,
    val sector: String? = null,
    val email: String? = null,
    @SerialName("declared_employee_count") val declaredEmployeeCount: Int? = null,
    @SerialName("responsible_employee_id") val responsibleEmployeeId: String? = null,
    @SerialName("personnel_count") val personnelCount: Int,
    @SerialName("workplace_count") val workplaceCount: Int,
    @SerialName("department_count") val departmentCount: Int,
    @SerialName("finding_count") val findingCount: Int? = null,
    @SerialName("document_count") val documentCount: Int? = null,
    @SerialName("completion_score") val completionScore: Double? = null,
    @SerialName("responsible_name") val responsibleName: String? = null,
    @SerialName("responsible_phone") val responsiblePhone: String? = null,
    @SerialName("responsible_email") val responsibleEmail: String? = null,
)

@Singleton
class NovaOverviewService @Inject constructor(private val transport: NovaExpertTransport) {
    @Serializable
    private data class Response(
        @SerialName("schema_version") val schemaVersion: Int,
        @SerialName("owner_id") val ownerId: String,
        @SerialName("company_id") val companyId: String? = null,
        val companies: List<NovaCompanySummary>,
    )

    /** Account-wide when [companyId] is null, one company otherwise. */
    suspend fun overview(identity: IsgWorkspaceIdentity, companyId: String? = null): List<NovaCompanySummary> {
        if (transport.identityNow() != identity) throw NovaExpertFailure("ACCESS_DENIED")
        val response = transport.execute("isg_pilot_overview_v2", buildJsonObject { putId("p_company", companyId) },
            maxBytes = 1_048_576).decodeAs(Response.serializer())
        if (transport.identityNow() != identity) throw NovaExpertFailure("ACCESS_DENIED")
        val valid = response.schemaVersion == 2 && response.ownerId == identity.userId && response.companyId == companyId &&
            response.companies.map { it.id }.toSet().size == response.companies.size &&
            response.companies.all {
                it.ownerId == identity.userId && (companyId == null || it.id == companyId) && it.personnelCount >= 0 &&
                    it.workplaceCount >= 0 && it.departmentCount >= 0 && it.hazardClass in setOf("low", "medium", "high")
            }
        if (!valid) throw NovaExpertFailure("ACCESS_DENIED")
        return response.companies
    }
}

enum class NovaNoticeKind(val wire: String, val title: String, val symbol: String) {
    katipContract("katip_contract", "İSG-KATİP sözleşmesi", "doc.text.magnifyingglass"),
    appointment("appointment", "Atama", "person.badge.shield.checkmark"),
    emergencyPlan("emergency_plan", "Acil durum planı", "light.beacon.max"),
    drill("drill", "Tatbikat", "figure.run"),
    annualWorkItem("annual_work_item", "Yıllık plan işi", "calendar"),
    board("board", "Kurul toplantısı", "person.3"),
    boardDecision("board_decision", "Kurul kararı", "checkmark.seal"),
    riskAssessment("risk_assessment", "Risk değerlendirmesi", "shield.lefthalf.filled"),
    equipment("equipment", "Periyodik kontrol", "checkmark.shield"),
    document("document", "Evrak", "doc.text"),
    personnelCertificate("personnel_certificate", "Personel belgesi", "person.text.rectangle"),
    training("training", "Eğitim", "graduationcap");
    companion object { fun of(wire: String) = entries.firstOrNull { it.wire == wire } }
}

enum class NovaNoticeSeverity { overdue, soon }

enum class NovaNoticeScope(val title: String) { active("Açık"), unread("Okunmamış"), all("Gizlenenler dahil") }

/** One situation that is due, rebuilt from the record every time the bell opens. */
data class NovaNoticeEntry(
    val key: String, val kind: NovaNoticeKind, val destination: String, val companyId: String?,
    val companyName: String?, val recordId: String?, val title: String, val dueOn: String, val days: Int,
    val severity: NovaNoticeSeverity, val unread: Boolean, val dismissed: Boolean,
)

data class NovaNoticeFeed(
    val rows: List<NovaNoticeEntry>, val unread: Int, val overdue: Int, val total: Int, val dismissed: Int,
    val hasMore: Boolean, val pushDeliveryClaimed: Boolean, val dismissIsPermanent: Boolean,
) {
    companion object { val empty = NovaNoticeFeed(emptyList(), 0, 0, 0, 0, false, false, false) }
}

object NovaNoticeWords {
    fun explain(entry: NovaNoticeEntry): String = when (entry.severity) {
        NovaNoticeSeverity.overdue -> "${entry.dueOn} tarihini ${-entry.days} gün geçti."
        NovaNoticeSeverity.soon -> if (entry.days == 0) "Bugün: ${entry.dueOn}." else "${entry.dueOn} tarihine ${entry.days} gün kaldı."
    }
    fun badge(entry: NovaNoticeEntry): String = when {
        entry.severity == NovaNoticeSeverity.overdue -> "${-entry.days} gün geçti"
        entry.days == 0 -> "bugün"
        else -> "${entry.days} gün"
    }
    const val dismissNote = "Silmek bildirimi listeden kaldırır; kaydı silmez. Tarih değişirse bildirim yeniden görünür."
    const val noPushNote = "Bu liste kayıtlarınızın tarihlerinden hesaplanır. Telefon bildirimi gönderildiğini ya da okunduğunu göstermez."
}

/** The header bell's data (iOS `NovaNoticeService`). */
@Singleton
class NovaNoticeService @Inject constructor(private val transport: NovaExpertTransport) {
    @Serializable
    private data class Row(
        @SerialName("notice_key") val key: String, val kind: String, val destination: String,
        @SerialName("company_id") val companyId: String? = null, @SerialName("company_name") val companyName: String? = null,
        @SerialName("record_id") val recordId: String? = null, val title: String, @SerialName("due_on") val dueOn: String,
        val days: Int, val severity: String, val unread: Boolean, val dismissed: Boolean,
    )
    @Serializable
    private data class Envelope(
        val rows: List<Row>, val unread: Int, val overdue: Int, val total: Int, val dismissed: Int,
        @SerialName("has_more") val hasMore: Boolean, @SerialName("push_delivery_claimed") val pushDeliveryClaimed: Boolean,
        @SerialName("dismiss_is_permanent") val dismissIsPermanent: Boolean,
    )

    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaExpertFailure("ACCESS_DENIED")
    }

    /** A row whose kind or severity this build does not know is dropped, never shown as something else. */
    suspend fun feed(identity: IsgWorkspaceIdentity, companyId: String? = null, scope: NovaNoticeScope = NovaNoticeScope.active,
                     limit: Int = 50): NovaNoticeFeed {
        check(identity)
        val envelope = transport.execute("isg_pilot_notice_feed_v1", buildJsonObject {
            putId("p_company", companyId); put("p_scope", scope.name); put("p_limit", limit)
        }).decodeAs(Envelope.serializer())
        check(identity)
        return NovaNoticeFeed(envelope.rows.mapNotNull { row ->
            val kind = NovaNoticeKind.of(row.kind) ?: return@mapNotNull null
            val severity = runCatching { NovaNoticeSeverity.valueOf(row.severity) }.getOrNull() ?: return@mapNotNull null
            NovaNoticeEntry(row.key, kind, row.destination, row.companyId, row.companyName, row.recordId, row.title,
                row.dueOn, row.days, severity, row.unread, row.dismissed)
        }, envelope.unread, envelope.overdue, envelope.total, envelope.dismissed, envelope.hasMore,
            envelope.pushDeliveryClaimed, envelope.dismissIsPermanent)
    }

    private suspend fun mark(identity: IsgWorkspaceIdentity, action: String, keys: List<String>?) {
        check(identity)
        transport.execute("isg_pilot_notice_mark_v1", buildJsonObject {
            put("p_action", action)
            // Bulk actions carry no list; the server refuses one.
            if (keys != null) putJsonArray("p_keys") { keys.forEach { add(it) } }
        })
    }

    suspend fun read(identity: IsgWorkspaceIdentity, key: String) = mark(identity, "read", listOf(key))
    suspend fun readAll(identity: IsgWorkspaceIdentity) = mark(identity, "read_all", null)
    /** Deleting a notice hides the situation; it never touches the record. */
    suspend fun dismiss(identity: IsgWorkspaceIdentity, key: String) = mark(identity, "dismiss", listOf(key))
    suspend fun dismissAll(identity: IsgWorkspaceIdentity) = mark(identity, "dismiss_all", null)
    suspend fun restore(identity: IsgWorkspaceIdentity, key: String) = mark(identity, "restore", listOf(key))
}
