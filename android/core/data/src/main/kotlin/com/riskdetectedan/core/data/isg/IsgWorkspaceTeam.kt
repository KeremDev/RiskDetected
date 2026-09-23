package com.riskdetectedan.core.data.isg

import kotlinx.serialization.json.*
import java.time.Instant
import java.util.UUID

/** One workspace membership (iOS `IsgWorkspaceMember`). */
data class IsgWorkspaceMember(val id: String, val userId: String?, val role: String, val status: String, val isPracticingExpert: Boolean,
                              val permissionRevision: Long, val version: Long, val activeCompanyCount: Long) {
    companion object {
        fun parse(row: JsonObject) = IsgWorkspaceMember(row.text("membership_id")!!, row.text("user_id"), row.text("role")!!,
            row.text("status")!!, row["is_practicing_expert"]!!.jsonPrimitive.boolean, row.long("permission_revision"), row.long("version"),
            row.long("active_company_count"))
    }
}

data class IsgWorkspaceInvitation(val id: String, val email: String, val role: String, val status: String, val expiresAt: String, val version: Long) {
    companion object {
        fun parse(row: JsonObject) = IsgWorkspaceInvitation(row.text("invitation_id")!!, row.text("email")!!, row.text("role")!!,
            row.text("status")!!, row.text("expires_at")!!, row.long("version"))
    }
}

/** The one-time invitation code; it is shown once and never stored on the device. */
data class IsgWorkspaceInvitationToken(val invitationId: String, val role: String, val expiresAt: String, val token: String) {
    companion object {
        fun parse(row: JsonObject) = IsgWorkspaceInvitationToken(row.text("invitation_id")!!, row.text("role")!!,
            row.text("expires_at").orEmpty(), row.text("invitation_token")!!)
    }
}

/** A company-to-expert assignment (iOS `IsgWorkspaceCompanyAssignment`). */
data class IsgWorkspaceAssignment(val id: String, val companyId: String, val membershipId: String, val assignmentRole: String,
                                  val startsAt: String, val endsAt: String?, val version: Long) {
    enum class Period { current, future, ended }

    /** A cancelled future assignment is retained as an empty interval. */
    fun period(now: Instant = Instant.now()): Period {
        val start = runCatching { Instant.parse(startsAt) }.getOrNull() ?: return Period.ended
        val end = endsAt?.let { runCatching { Instant.parse(it) }.getOrNull() }
        if (end != null && (end <= start || end <= now)) return Period.ended
        return if (start > now) Period.future else Period.current
    }

    companion object {
        fun parse(row: JsonObject) = IsgWorkspaceAssignment(row.text("assignment_id")!!, row.text("company_id")!!,
            row.text("membership_id")!!, row.text("assignment_role")!!, row.text("starts_at")!!, row.text("ends_at"), row.long("version"))
    }
}

data class IsgWorkspaceChecklistTemplate(val code: String, val version: Int, val title: String, val itemCount: Int) {
    val id: String get() = "$code:$version"
}

data class IsgWorkspaceEquipmentCatalog(val suggestions: List<Suggestion>, val rules: List<Rule>) {
    data class Suggestion(val code: String, val ordinal: Int, val defaultPeriodMonths: Int?, val defaultBasisNote: String?)
    data class Rule(val equipmentType: String, val periodMonths: Int, val periodSource: String, val needsReview: Boolean, val exceptionNote: String?)
}

/** A personnel or training record of the advanced surfaces (iOS `IsgWorkspaceAdvancedRecord`). */
data class IsgWorkspaceAdvancedRecord(val id: String, val kind: String, val title: String, val subtitle: String?, val status: String?,
                                      val version: Long, val fields: Map<String, String>, val topics: List<Topic>) {
    data class Topic(val id: String, val position: Int, val title: String, val description: String, val durationMinutes: Int)

    fun text(key: String) = fields[key]
    fun flag(key: String) = fields[key] == "true"

    companion object {
        fun parse(row: JsonObject): IsgWorkspaceAdvancedRecord {
            val fields = row.mapNotNull { (key, value) ->
                val primitive = value as? JsonPrimitive ?: return@mapNotNull null
                if (primitive is JsonNull) null else key to primitive.content
            }.toMap()
            val kind = fields["kind"] ?: error("kind")
            val title = fields["title"] ?: fields["name"] ?: fields["employee_name"] ?: fields["training_title"] ?: fields["certificate_no"] ?: kind
            val subtitle = fields["code"] ?: fields["contractor_name"] ?: fields["workplace_name"] ?: fields["employer_name"] ?: fields["employee_name"]
            val status = fields["state"] ?: fields["verification_state"] ?: if (fields["is_current"] == "true") "active" else null
            val topics = (row["topics"] as? JsonArray).orEmpty().map { item ->
                val topic = item.jsonObject
                Topic(topic.text("id")!!, topic.long("position").toInt(), topic.text("title")!!, topic.text("description").orEmpty(),
                    topic.long("duration_minutes").toInt())
            }.sortedBy { it.position }
            return IsgWorkspaceAdvancedRecord(fields["id"] ?: error("id"), kind, title, subtitle, status, row.long("version"), fields, topics)
        }
    }
}

/** The company fields the manager editor saves (iOS `IsgWorkspaceCompanyDraft`). */
data class IsgWorkspaceCompanyDraft(val name: String, val hazardClass: String, val sector: String, val email: String, val employeeCount: Int?,
                                    val address: String, val responsibleName: String, val responsiblePhone: String, val responsibleEmail: String)

/**
 * Keeps one mutation id while the request content stays the same (iOS `IsgWorkspaceMutationAttempt`), so a
 * retry after a lost response replays instead of writing twice; any change of content mints a new id.
 */
class IsgWorkspaceMutationAttempt {
    private var signature: String? = null
    private var mutationId = UUID.randomUUID().toString()

    fun id(namespace: String, vararg components: String): String {
        val value = (listOf(namespace) + components).joinToString("|") { "${it.toByteArray().size}:$it" }
        if (signature != value) { signature = value; mutationId = UUID.randomUUID().toString() }
        return mutationId
    }
}

/** The record a domain mutation wrote (iOS `IsgWorkspaceMutationResult`). */
object IsgWorkspaceMutations {
    private val idKeys = listOf("id", "meeting_id", "plan_id", "appointment_id", "assessment_id", "training_id", "nonconformity_id", "run_id",
        "drill_id", "handover_id", "equipment_id", "contract_id", "permit_id", "visit_id", "entry_id")

    fun recordId(result: JsonObject): String? {
        val record = result["row"] as? JsonObject ?: result
        return idKeys.firstNotNullOfOrNull { key -> record.text(key)?.takeIf { runCatching { UUID.fromString(it) }.isSuccess } }
    }

    fun version(result: JsonObject): Long? = ((result["row"] as? JsonObject ?: result)["version"] as? JsonPrimitive)?.longOrNull
}

private fun JsonObject.text(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
private fun JsonObject.long(key: String) = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull ?: 0
