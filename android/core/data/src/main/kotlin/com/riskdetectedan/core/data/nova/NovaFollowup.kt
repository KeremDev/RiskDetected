package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.*
import javax.inject.Inject
import javax.inject.Singleton

/** Evrak Takibi: every dated record across the modules in one list (iOS `NovaFollowupPage`). */
@Serializable data class NovaFollowupPage(
    @SerialName("schema_version") val schemaVersion: Int, @SerialName("owner_id") val ownerId: String,
    @SerialName("company_id") val companyId: String? = null, val current: Int, val soon: Int, val expired: Int, val undated: Int,
    @SerialName("has_more") val hasMore: Boolean, val rows: List<Row>,
) {
    @Serializable data class Row(val kind: String, @SerialName("company_id") val companyId: String, @SerialName("company_name") val companyName: String,
                                 @SerialName("record_id") val recordId: String, @SerialName("source_id") val sourceId: String? = null, val title: String,
                                 @SerialName("recorded_on") val recordedOn: String? = null,
                                 @SerialName("due_on") val dueOn: String? = null, val status: String,
                                 @SerialName("file_category") val fileCategory: String? = null,
                                 @SerialName("equipment_type") val equipmentType: String? = null,
                                 @SerialName("equipment_type_label") val equipmentTypeLabel: String? = null) {
        val key: String get() = kind + recordId
        val typeTitle: String get() = NovaFollowupPage.typeTitle(kind)
    }

    companion object {
        /** The record type as Evrak Takibi names it; the home cards use the same words. */
        fun typeTitle(kind: String): String = when (kind) {
            "training" -> "Eğitim"; "equipment" -> "Periyodik kontrol"; "risk_assessment" -> "Risk analizi"
            "emergency_plan" -> "Acil durum planı"; "appointment" -> "Atama"; "document" -> "Önceki evrak kaydı"; "file" -> "Dosya"
            else -> NovaProcessKind.get(kind).title
        }
        fun statusTitle(status: String) = mapOf("current" to "Güncel", "soon" to "Yaklaşıyor", "expired" to "Süresi doldu", "undated" to "Süre takibi yok")[status] ?: status
        val kindOptions = listOf(
            "risk_assessment" to "Risk analizi", "training" to "Eğitim", "equipment" to "Periyodik kontrol",
            "emergency_plan" to "Acil durum planı", "file" to "Yüklenen dosya", "document" to "Önceki evrak kaydı",
            "personnel_certificate" to "Personel belgesi", "completed_drill" to "Tatbikat",
            "appointment" to "Atama", "katip_contract" to "İSG-KATİP sözleşmesi",
        )
        fun kindTitle(kind: String?) = kindOptions.firstOrNull { it.first == kind }?.second ?: "Tüm evrak türleri"
    }
}

class NovaFollowupException : Exception("FOLLOWUP_UNAVAILABLE")

@Singleton
class NovaFollowupService @Inject constructor(private val transport: NovaExpertTransport) {
    private fun check(identity: IsgWorkspaceIdentity) {
        if (transport.identityNow() != identity) throw NovaFollowupException()
    }

    private suspend fun call(identity: IsgWorkspaceIdentity, function: String, params: JsonObject): JsonElement {
        check(identity)
        val data = try { transport.execute(function, params) } catch (_: NovaExpertFailure) {
            currentCoroutineContext().ensureActive(); throw NovaFollowupException()
        }
        check(identity); return data
    }

    /** A page that does not answer for this owner and company is refused rather than shown. */
    suspend fun load(identity: IsgWorkspaceIdentity, company: String?, status: String? = null,
                     kind: String? = null, query: String = "", offset: Int = 0): NovaFollowupPage {
        val data = call(identity, "isg_pilot_followup_v2", buildJsonObject {
            put("p_company", company?.let(::JsonPrimitive) ?: JsonNull); put("p_status", status?.let(::JsonPrimitive) ?: JsonNull)
            put("p_kind", kind?.let(::JsonPrimitive) ?: JsonNull)
            put("p_query", query); put("p_offset", offset)
        })
        val page = runCatching { novaJson.decodeFromJsonElement(NovaFollowupPage.serializer(), data) }.getOrNull() ?: throw NovaFollowupException()
        if (page.schemaVersion != 2 || !page.ownerId.equals(identity.userId, true) || !page.companyId.equals(company, true)) throw NovaFollowupException()
        return page
    }

    /** The records a filed document is attached to; every link must belong to the file's own company. */
    suspend fun fileSources(identity: IsgWorkspaceIdentity, entry: NovaFileEntry): List<NovaFollowupPage.Row> {
        val data = call(identity, "isg_pilot_file_sources_v1", buildJsonObject { put("p_entry", entry.id) })
        val links = runCatching { novaJson.decodeFromJsonElement(ListSerializer(NovaFollowupPage.Row.serializer()), data) }.getOrNull() ?: throw NovaFollowupException()
        if (links.any { !it.companyId.equals(entry.companyId, true) }) throw NovaFollowupException()
        return links
    }
}
