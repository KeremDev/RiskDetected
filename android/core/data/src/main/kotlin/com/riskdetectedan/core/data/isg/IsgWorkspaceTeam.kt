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
