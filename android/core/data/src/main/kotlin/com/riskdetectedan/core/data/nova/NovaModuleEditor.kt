package com.riskdetectedan.core.data.nova

import com.riskdetectedan.core.data.isg.IsgWorkspaceIdentity
import com.riskdetectedan.core.data.isg.NovaExpertFailure
import com.riskdetectedan.core.data.isg.NovaExpertTransport
import kotlinx.serialization.json.*
import javax.inject.Inject
import javax.inject.Singleton

/** One choice the editor offers: a workplace, a person or an active emergency plan. */
data class NovaModuleEditorOption(val id: String, val name: String)

/**
 * A module record as the editor reads it (iOS `NovaModuleEditor.Envelope`): the stored values,
 * the fingerprint a save must match, and the company's own choices.
 */
data class NovaModuleEditorRecord(
    val snapshot: JsonObject,
    val expected: String,
    val companyName: String,
    val workplaces: List<NovaModuleEditorOption>,
    val employees: List<NovaModuleEditorOption>,
    val plans: List<NovaModuleEditorOption>,
)

/**
 * Edits or removes one appointment, emergency plan or drill after it was recorded
 * (`isg_pilot_module_editor_v1` / `isg_pilot_module_mutate_v1`, iOS `NovaModuleEditor`).
 */
@Singleton
class NovaModuleEditorService @Inject constructor(
    private val transport: NovaExpertTransport,
    private val journal: NovaModuleMutationJournal,
) {
    /** The keys each module sends back, exactly as iOS does. */
    fun keys(module: String): List<String> = when (module) {
        "emergency_plan" -> listOf("workplace_id", "scope", "prepared_on", "valid_until", "review_note", "team_snapshot")
        "drill" -> listOf("plan_id", "planned_on", "performed_on", "participants", "observation", "improvement")
        else -> listOf("employee_id", "kind", "scope_workplace_id", "starts_on", "ends_before", "basis", "basis_note", "asset_id")
    }

    suspend fun load(identity: IsgWorkspaceIdentity, module: String, company: String, record: String): NovaModuleEditorRecord {
        if (transport.identityNow() != identity) throw NovaExpertFailure("STALE_SESSION")
        val data = transport.executeObject("isg_pilot_module_editor_v1", buildJsonObject {
            put("p_module", module); put("p_company", company); put("p_id", record)
        })
        if (transport.identityNow() != identity) throw NovaExpertFailure("STALE_SESSION")
        fun options(key: String) = (data[key] as? JsonArray).orEmpty().mapNotNull { item ->
            val row = item as? JsonObject ?: return@mapNotNull null
            val id = (row["id"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
            NovaModuleEditorOption(id.lowercase(), (row["name"] as? JsonPrimitive)?.contentOrNull.orEmpty())
        }
        return NovaModuleEditorRecord(
            snapshot = data["snapshot"] as? JsonObject ?: throw NovaExpertFailure("UNAVAILABLE"),
            expected = (data["expected"] as? JsonPrimitive)?.contentOrNull ?: throw NovaExpertFailure("UNAVAILABLE"),
            companyName = (data["company_name"] as? JsonPrimitive)?.contentOrNull.orEmpty(),
            workplaces = options("workplaces"), employees = options("employees"), plans = options("plans"),
        )
    }

    /** [action] is `update` or `delete`; the stored document link travels unchanged. */
    suspend fun save(identity: IsgWorkspaceIdentity, module: String, company: String, record: String, loaded: NovaModuleEditorRecord,
                     values: Map<String, JsonElement>, action: String) {
        val payload = buildJsonObject {
            put("module", module); put("id", record); put("expected", loaded.expected)
            put("values", buildJsonObject { keys(module).forEach { key -> put(key, wire(values[key] ?: JsonNull)) } })
            val document = (loaded.snapshot["document_id"] as? JsonPrimitive)?.contentOrNull.orEmpty()
            put("document_id", if (document.isEmpty()) JsonNull else JsonPrimitive(document))
        }
        journal.run("isg_pilot_module_mutate_v1", identity, company, action, payload) { it }
    }

    /** iOS sends numbers and flags as strings; nested lists and objects keep their shape. */
    private fun wire(value: JsonElement): JsonElement = when (value) {
        is JsonNull -> JsonNull
        is JsonPrimitive -> if (value.isString) value else JsonPrimitive(value.booleanOrNull?.toString() ?: value.doubleOrNull?.toString() ?: value.content)
        is JsonArray -> JsonArray(value.map(::wire))
        is JsonObject -> JsonObject(value.mapValues { wire(it.value) })
    }

    companion object {
        /** The iOS editor's words for each refusal. */
        fun message(error: Throwable): String = when {
            error !is NovaExpertFailure -> "İşlem tamamlanamadı. Bağlantınızı kontrol edip yeniden deneyin."
            error.code == "VERSION_CONFLICT" -> "Kayıt değişmiş. Kapatıp yeniden açarak güncel bilgilerle deneyin."
            error.code == "DEPENDENT_RECORDS" -> "Bu plana bağlı tatbikat var. Önce bağlı tatbikatı kaldırın."
            error.code == "RETURN_CONFLICT" -> "Teslim bilgileri kayıtlı iadelerle çelişiyor."
            error.code == "ACCESS_DENIED" -> "Firma, personel, işyeri veya evrak bu kayda uygun değil."
            error.sqlState != null -> "Bilgileri kontrol edin. Kayıt güncellenemedi."
            else -> "İşlem tamamlanamadı. Bağlantınızı kontrol edip yeniden deneyin."
        }
    }
}
