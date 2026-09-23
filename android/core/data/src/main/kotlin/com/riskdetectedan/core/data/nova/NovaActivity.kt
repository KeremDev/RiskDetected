package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import javax.inject.Inject
import javax.inject.Singleton

/** Active time from the server's presence ledger (iOS `UsageSummary`). */
@Serializable data class NovaUsageSummary(
    @SerialName("today_seconds") val todaySeconds: Double, @SerialName("week_seconds") val weekSeconds: Double,
    @SerialName("month_seconds") val monthSeconds: Double, @SerialName("total_seconds") val totalSeconds: Double,
    @SerialName("workspace_seconds") val workspaceSeconds: Double = 0.0, @SerialName("session_seconds") val sessionSeconds: Double,
    @SerialName("login_count") val loginCount: Int, @SerialName("last_login_at") val lastLoginAt: String? = null,
    @SerialName("last_active_at") val lastActiveAt: String? = null,
) {
    companion object {
        fun duration(seconds: Double): String {
            if (!seconds.isFinite() || seconds <= 0) return "0 dk"
            val minutes = minOf(seconds / 60, (Int.MAX_VALUE / 60).toDouble()).toInt()
            return when { minutes < 1 -> "1 dk'dan az"; minutes < 60 -> "$minutes dk"; else -> "${minutes / 60} sa ${minutes % 60} dk" }
        }
    }
}

@Serializable data class NovaActivityItem(
    val id: Long, val action: String, @SerialName("entity_type") val entityType: String, @SerialName("entity_id") val entityId: String? = null,
    @SerialName("company_id") val companyId: String? = null, @SerialName("company_name") val companyName: String? = null,
    @SerialName("created_at") val createdAt: String,
) {
    val title get() = NovaActivityWords.title(action, entityType)
}

@Serializable data class NovaActivityDetail(
    val id: Long, val action: String, @SerialName("entity_type") val entityType: String, @SerialName("entity_id") val entityId: String? = null,
    @SerialName("company_id") val companyId: String? = null, @SerialName("created_at") val createdAt: String,
    val changes: List<Change> = emptyList(), val stages: List<Stage>? = null,
    @SerialName("link_company_id") val linkCompanyId: String? = null, @SerialName("link_workspace_id") val linkWorkspaceId: String? = null,
) {
    @Serializable data class Stage(val status: String, val at: String)
    @Serializable data class Change(val field: String, val before: JsonElement? = null, val after: JsonElement? = null)
}

@Serializable data class NovaActivityPage(
    @SerialName("schema_version") val schemaVersion: Int, val summary: NovaUsageSummary, val items: List<NovaActivityItem>,
    @SerialName("next_cursor") val nextCursor: Long? = null, val actions: List<String>? = null, val companies: List<Company>? = null,
) {
    @Serializable data class Company(val id: String, val name: String)
}

object NovaActivityWords {
    private val domains = mapOf("company" to "Firma", "personnel" to "Personel", "employee" to "Personel", "analysis" to "Analiz",
        "nonconformity" to "Uygunsuzluk", "training" to "Eğitim", "report" to "Rapor", "export" to "Rapor", "visit" to "Ziyaret",
        "personal_note" to "Kişisel not", "assignment" to "Atama", "file" to "Dosya", "risk" to "Risk değerlendirmesi", "workplace" to "İşyeri",
        "department" to "Departman", "job_role" to "Görev", "checklist" to "Denetim", "document" to "Belge", "drill" to "Tatbikat",
        "emergency" to "Acil durum planı", "equipment" to "Ekipman", "inspection" to "Periyodik kontrol", "ppe" to "KKD", "plan" to "Yıllık plan",
        "board" to "Kurul", "contract" to "Sözleşme", "permit" to "Çalışma izni", "contractor" to "Alt işveren", "certificate" to "Sertifika",
        "training_session" to "Eğitim")
    private val verbs = mapOf("create" to "oluşturuldu", "created" to "oluşturuldu", "update" to "düzenlendi", "updated" to "düzenlendi",
        "archive" to "arşivlendi", "delete" to "silindi", "commit" to "kaydedildi", "complete" to "tamamlandı", "assign" to "atandı",
        "queued" to "sıraya alındı", "running" to "işleniyor", "processing" to "işleniyor", "succeeded" to "tamamlandı", "completed" to "tamamlandı",
        "failed" to "başarısız oldu", "cancelled" to "iptal edildi")

    fun title(action: String, entity: String? = null): String {
        val domain = domains[entity ?: action.substringBefore('.')] ?: "İşlem"
        return "$domain ${verbs[action.substringAfterLast('.')] ?: "kaydedildi"}"
    }

    fun field(key: String) = mapOf("status" to "Durum", "state" to "Durum", "version" to "Sürüm", "role" to "Rol", "hazard_class" to "Tehlike sınıfı",
        "is_primary" to "Birincil uzman", "starts_on" to "Başlangıç", "ends_on" to "Bitiş", "ends_before" to "Bitiş", "due_on" to "Son tarih",
        "completed_at" to "Tamamlanma", "employee_count" to "Çalışan sayısı", "declared_employee_count" to "Çalışan sayısı",
        "duration_minutes" to "Süre (dakika)", "valid_until" to "Geçerlilik", "planned_on" to "Planlanan tarih", "performed_on" to "Gerçekleşme",
        "held_on" to "Tarih", "visited_on" to "Ziyaret tarihi", "quantity" to "Miktar", "is_archived" to "Arşivlendi", "is_deleted" to "Silindi",
        "severity" to "Önem", "protected_details" to "Korunan kayıt bilgileri değiştirildi")[key] ?: "Alan"

    fun value(element: JsonElement?): String = when {
        element == null || element is JsonNull -> "—"
        element is JsonPrimitive && element.booleanOrNull != null -> if (element.boolean) "Evet" else "Hayır"
        element is JsonPrimitive -> element.content
        else -> element.toString()
    }
}

class NovaActivityException : Exception("ACTIVITY_UNAVAILABLE")

/** The activity log (iOS `ExpertActivityService`): one's own, or a member's inside a workspace the manager can inspect. */
@Singleton
class NovaActivityService @Inject constructor(private val client: SupabaseClient, private val transport: NovaExpertTransport) {
    private suspend fun rpc(identity: IsgWorkspaceIdentity, function: String, params: JsonObject, maxBytes: Int): JsonElement {
        if (transport.identityNow() != identity) throw NovaActivityException()
        val raw = try { client.postgrest.rpc(function, params).data } catch (error: Exception) {
            currentCoroutineContext().ensureActive(); throw NovaActivityException()
        }
        if (transport.identityNow() != identity || raw.length >= maxBytes) throw NovaActivityException()
        return runCatching { Json.parseToJsonElement(raw) }.getOrNull() ?: throw NovaActivityException()
    }

    suspend fun page(identity: IsgWorkspaceIdentity, workspace: String? = null, member: String? = null, after: Long? = null, from: String? = null,
                     action: String? = null, company: String? = null): NovaActivityPage {
        // Absent values are omitted, as iOS's Encodable query does: isg_activity_self_v1 has no
        // p_workspace/p_user, and PostgREST matches a function by the argument names it is sent.
        val data = rpc(identity, if (workspace == null) "isg_activity_self_v1" else "isg_workspace_member_activity_v1", buildJsonObject {
            workspace?.let { put("p_workspace", it) }; member?.let { put("p_user", it) }
            after?.let { put("p_after", it) }; from?.let { put("p_from", it) }
            action?.let { put("p_action", it) }; company?.let { put("p_company", it) }
        }, 2_000_000)
        val page = runCatching { novaJson.decodeFromJsonElement(NovaActivityPage.serializer(), data) }.getOrNull() ?: throw NovaActivityException()
        if (page.schemaVersion != 1 || page.items.size > 30) throw NovaActivityException()
        return page
    }

    suspend fun detail(identity: IsgWorkspaceIdentity, event: Long, workspace: String?): NovaActivityDetail {
        val data = rpc(identity, "isg_activity_event_detail_v1", buildJsonObject {
            put("p_event", event); put("p_workspace", workspace?.let(::JsonPrimitive) ?: JsonNull)
        }, 100_000)
        return runCatching { novaJson.decodeFromJsonElement(NovaActivityDetail.serializer(), data) }.getOrNull() ?: throw NovaActivityException()
    }
}

/**
 * Active-time presence (iOS `ExpertUsagePresence`): a start, then a heartbeat a minute while the app is in
 * front, and a stop when it leaves. There is no offline queue: a failed request is never replayed as active time,
 * and the server drops any interval longer than its 90-second boundary.
 */
@Singleton
class NovaUsagePresence @Inject constructor(private val client: SupabaseClient, private val transport: NovaExpertTransport) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var loop: Job? = null
    private var pendingStop: Job? = null
    private var workspace: String? = null
    private var identity: IsgWorkspaceIdentity? = null

    @Synchronized fun foreground(current: IsgWorkspaceIdentity, workspace: String?) {
        if (loop?.isActive == true && this.workspace == workspace && identity == current) return
        val previous = this.workspace
        val previousIdentity = identity
        val wasRunning = loop?.isActive == true
        loop?.cancel()
        this.workspace = workspace
        identity = current
        val stopping = pendingStop
        loop = scope.launch {
            stopping?.join()
            if (wasRunning && previousIdentity != null) send("stop", previous, previousIdentity)
            var baseline = send("start", workspace, current)
            while (isActive) {
                delay(60_000)
                if (transport.identityNow() != current) return@launch
                baseline = send(if (baseline) "heartbeat" else "start", workspace, current)
            }
        }
    }

    @Synchronized fun background() {
        val previous = workspace
        val previousIdentity = identity
        val wasRunning = loop?.isActive == true
        loop?.cancel(); loop = null; workspace = null; identity = null
        if (wasRunning && previousIdentity != null) pendingStop = scope.launch { send("stop", previous, previousIdentity) }
    }

    private suspend fun send(action: String, workspace: String?, identity: IsgWorkspaceIdentity): Boolean {
        if (transport.identityNow() != identity) return false
        return runCatching {
            client.postgrest.rpc("isg_usage_presence_v1", buildJsonObject {
                put("p_action", action); put("p_workspace", workspace?.let(::JsonPrimitive) ?: JsonNull)
            })
        }.isSuccess
    }
}
