package com.riskdetectedan.core.data.isg

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import java.time.Instant
import java.time.LocalDate

class IsgWorkspaceGatewayFailure(val code: String): Exception(code)

enum class IsgWorkspaceDomain {
    PERSONNEL, TRAINING, RISK, NONCONFORMITY, CHECKLIST, EMERGENCY_PLAN, DRILL,
    APPOINTMENT, PPE, EQUIPMENT, KATIP, ANNUAL_PLAN, BOARD, WORK_PERMIT, VISIT, FILES
}

enum class IsgWorkspacePersonnelAdvancedKind(val wireValue: String) {
    JOB_ROLES("job_roles"), CONTRACTORS("contractors"), ENGAGEMENTS("engagements"), ASSIGNMENTS("assignments")
}

enum class IsgWorkspaceTrainingAdvancedKind(val wireValue: String) {
    CURRICULA("curricula"), ANNUAL_PLANS("annual_plans"), ANNUAL_ITEMS("annual_items"),
    ATTEMPTS("attempts"), CERTIFICATES("certificates")
}

/**
 * Dark-rollout transport for the OSGB workspace API. Every response is checked
 * against the same workspace revision after suspension; callers never fall back
 * to a personal endpoint when workspace data is unavailable.
 */
class IsgWorkspaceGateway(
    private val transport: suspend (String, JsonObject) -> JsonObject,
    private val isCurrentIdentity: (String, String) -> Boolean,
    private val isCurrentWorkspace: (String, String, Long) -> Boolean,
    // Changes on auth, workspace AND company selection (including A -> B -> A).
    private val currentScopeToken: () -> String?,
) {
    private suspend fun invoke(function: String, arguments: JsonObject): JsonObject {
        currentCoroutineContext().ensureActive()
        val token = currentScopeToken() ?: throw IsgWorkspaceGatewayFailure("STALE_SESSION")
        val result = transport(function, arguments)
        currentCoroutineContext().ensureActive()
        if (currentScopeToken() != token) throw IsgWorkspaceGatewayFailure("STALE_SESSION")
        return result
    }

    suspend fun list(userId: String, sessionId: String): List<IsgWorkspaceContext> {
        checkIdentity(userId, sessionId)
        val response = invoke("isg_workspace_list_v1", buildJsonObject {})
        checkIdentity(userId, sessionId)
        if (response.keys != setOf("schema_version", "user_id", "workspaces") ||
            response.safeLong("schema_version") != 1L || response.text("user_id") != userId) fail()
        val rows = response["workspaces"] as? JsonArray ?: fail()
        val contexts = rows.map { IsgWorkspaceContext.parse(it) ?: fail() }
        if (contexts.any { !it.canRead || it.membership.userId != userId } ||
            contexts.map { it.workspaceId }.toSet().size != contexts.size) fail()
        return contexts
    }

    suspend fun context(userId: String, sessionId: String, workspaceId: String): IsgWorkspaceContext {
        checkIdentity(userId, sessionId)
        val response = invoke("isg_workspace_context_v1", buildJsonObject { put("p_workspace", workspaceId) })
        checkIdentity(userId, sessionId)
        val context = IsgWorkspaceContext.parse(response) ?: fail()
        if (!context.canRead || context.workspaceId != workspaceId || context.membership.userId != userId) fail()
        return context
    }

    suspend fun companies(workspaceId: String, membershipId: String, permissionRevision: Long,
                          after: String? = null, limit: Int = 50): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireLimit(limit, 100)
        val result = invoke("isg_workspace_company_list_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, checkCompany = false)
        if ((result["rows"] as? JsonArray)?.size?.let { it > limit } != false) fail()
        return result
    }

    suspend fun assignments(workspaceId: String, membershipId: String, permissionRevision: Long,
                            companyId: String, status: String = "all", after: String? = null,
                            limit: Int = 100): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if (status !in setOf("all", "current", "ended", "future")) validation()
        requireLimit(limit, 100)
        val result = invoke("isg_workspace_assignment_list_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId); put("p_status", status)
            put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        val rows = result["rows"] as? JsonArray ?: fail()
        if (rows.size > limit || rows.any { row ->
                (row as? JsonObject)?.let {
                    it.text("company_id") == companyId && it.text("workspace_id") == workspaceId &&
                        it.text("assignment_id")?.let(UUID::matches) == true &&
                        it.text("membership_id")?.let(UUID::matches) == true &&
                        it.text("assignment_role") in setOf("primary", "support") &&
                        it.text("starts_at")?.let(::validInstant) == true &&
                        (it["ends_at"] is JsonNull || it.text("ends_at")?.let(::validInstant) == true)
                } != true
            }) fail()
        return result
    }

    suspend fun mutateAssignment(workspaceId: String, membershipId: String, permissionRevision: Long,
                                 canOperate: Boolean, mutationId: String, companyId: String,
                                 action: String, assignmentId: String?, targetMembershipId: String?,
                                 expectedVersion: Long, role: String?, startsAt: String?, endsAt: String?,
                                 reason: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        val cleanReason = reason.trim()
        val create = action == "create" && assignmentId == null && targetMembershipId?.let(UUID::matches) == true &&
            expectedVersion == 0L && role in setOf("primary", "support") && startsAt?.let(::validInstant) == true &&
            (endsAt == null || validInstant(endsAt))
        val end = action == "end" && assignmentId?.let(UUID::matches) == true && targetMembershipId == null &&
            expectedVersion >= 0 && endsAt?.let(::validInstant) == true
        if ((!create && !end) || cleanReason.toByteArray().size !in 1..500) validation()
        val result = invoke("isg_workspace_assignment_mutate_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_company", companyId)
            put("p_assignment", assignmentId?.let(::JsonPrimitive) ?: JsonNull)
            put("p_membership", targetMembershipId?.let(::JsonPrimitive) ?: JsonNull)
            put("p_expected", expectedVersion); put("p_action", action)
            put("p_role", role?.let(::JsonPrimitive) ?: JsonNull)
            put("p_starts_at", startsAt?.let(::JsonPrimitive) ?: JsonNull)
            put("p_ends_at", endsAt?.let(::JsonPrimitive) ?: JsonNull); put("p_reason", cleanReason)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, companyId)
        if (result.text("assignment_id")?.let(UUID::matches) != true ||
            result.text("membership_id")?.let(UUID::matches) != true ||
            result.text("assignment_role") !in setOf("primary", "support") ||
            result.text("starts_at")?.let(::validInstant) != true ||
            !(result["ends_at"] is JsonNull || result.text("ends_at")?.let(::validInstant) == true)) fail()
        if (create && (result.text("membership_id") != targetMembershipId ||
                result.text("assignment_role") != role || result.safeLong("version") != 0L)) fail()
        if (end && (result.text("assignment_id") != assignmentId ||
                result.text("ends_at") == null || expectedVersion == Long.MAX_VALUE ||
                result.safeLong("version") != expectedVersion + 1)) fail()
        return result
    }

    /** Members of the workspace, id-ordered and cursor-paged (`isg_workspace_member_list_v1`). */
    suspend fun members(workspaceId: String, membershipId: String, permissionRevision: Long,
                        status: String = "all", after: String? = null, limit: Int = 100): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if (status !in setOf("all", "active", "suspended", "ended")) validation()
        requireLimit(limit, 100)
        val result = invoke("isg_workspace_member_list_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_status", status)
            put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, checkCompany = false)
        val rows = result["rows"] as? JsonArray ?: fail()
        if (rows.size > limit || rows.any { (it as? JsonObject)?.let(::validMember) != true }) fail()
        return result
    }

    suspend fun invitations(workspaceId: String, membershipId: String, permissionRevision: Long,
                            status: String = "all", after: String? = null, limit: Int = 100): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if (status !in setOf("all", "pending", "accepted", "revoked", "expired")) validation()
        requireLimit(limit, 100)
        val result = invoke("isg_workspace_invitation_list_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_status", status)
            put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, checkCompany = false)
        val rows = result["rows"] as? JsonArray ?: fail()
        if (rows.size > limit || rows.any { row -> (row as? JsonObject)?.let {
                it.text("invitation_id")?.let(UUID::matches) == true && it.text("email")?.contains('@') == true &&
                    it.text("role") in setOf("admin", "expert") && it.text("status") in setOf("pending", "accepted", "revoked", "expired") &&
                    !it.text("expires_at").isNullOrEmpty() && (it.safeLong("version") ?: -1) >= 0
            } != true }) fail()
        return result
    }

    /** Creates an invitation; the one-time code comes back only in this response. */
    suspend fun invite(workspaceId: String, membershipId: String, permissionRevision: Long, mutationId: String,
                       email: String, role: String, expiresAt: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        val clean = email.trim().lowercase()
        if (!Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(clean) || role !in setOf("admin", "expert") || expiresAt.isEmpty()) validation()
        val result = invoke("isg_workspace_invite_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_email", clean); put("p_role", role)
            put("p_expires_at", expiresAt)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        return invitationToken(result, workspaceId, null)
    }

    suspend fun resendInvitation(workspaceId: String, membershipId: String, permissionRevision: Long, mutationId: String,
                                 invitationId: String, expectedVersion: Long, expiresAt: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if (expectedVersion < 0 || expiresAt.isEmpty()) validation()
        val result = invoke("isg_workspace_invitation_resend_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_invitation", invitationId)
            put("p_expected", expectedVersion); put("p_expires_at", expiresAt)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        return invitationToken(result, workspaceId, invitationId)
    }

    suspend fun revokeInvitation(workspaceId: String, membershipId: String, permissionRevision: Long, mutationId: String,
                                 invitationId: String, expectedVersion: Long) {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if (expectedVersion < 0) validation()
        val result = invoke("isg_workspace_invitation_mutate_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_invitation", invitationId)
            put("p_expected_version", expectedVersion); put("p_action", "revoke")
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, checkCompany = false)
        if (result.text("invitation_id") != invitationId || result.text("status") != "revoked" ||
            (result.safeLong("version") ?: -1) <= expectedVersion) fail()
    }

    suspend fun mutateMember(workspaceId: String, membershipId: String, permissionRevision: Long, mutationId: String,
                             targetMembershipId: String, expectedVersion: Long, action: String, value: String? = null,
                             reason: String? = null): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if (expectedVersion < 0 || action !in setOf("suspend", "reactivate", "end", "change_role", "set_practicing", "transfer_owner") ||
            (reason?.toByteArray()?.size ?: 0) > 500) validation()
        val result = invoke("isg_workspace_member_mutate_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_membership", targetMembershipId)
            put("p_expected_version", expectedVersion); put("p_action", action)
            put("p_value", value?.let(::JsonPrimitive) ?: JsonNull); put("p_reason", reason?.let(::JsonPrimitive) ?: JsonNull)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, checkCompany = false)
        val member = result["membership"] as? JsonObject ?: fail()
        if (!validMember(member) || member.text("membership_id") != targetMembershipId) fail()
        return member
    }

    /** Creates (no [companyId]) or renames/reclassifies a company; the profile is a separate mutation. */
    suspend fun saveCompany(workspaceId: String, membershipId: String, permissionRevision: Long, canOperate: Boolean,
                            mutationId: String, companyId: String?, expectedVersion: Long, name: String, hazard: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        val clean = name.trim()
        if (clean.isEmpty() || clean.toByteArray().size > 200 || hazard !in setOf("low", "medium", "high") || expectedVersion < 0) validation()
        val result = invoke(if (companyId == null) "isg_workspace_company_create_v1" else "isg_workspace_company_update_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId)
            if (companyId != null) { put("p_company", companyId); put("p_expected", expectedVersion) }
            put("p_name", clean); put("p_hazard", hazard)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, checkCompany = false)
        if (result.text("company_id")?.let(UUID::matches) != true || (companyId != null && result.text("company_id") != companyId) ||
            result.text("name").isNullOrBlank() || result.text("hazard_class") !in setOf("low", "medium", "high") ||
            (result.safeLong("version") ?: -1) < 0) fail()
        return result
    }

    suspend fun mutateCompanyProfile(workspaceId: String, membershipId: String, permissionRevision: Long, canOperate: Boolean,
                                     mutationId: String, companyId: String, expectedVersion: Long, sector: String, email: String,
                                     employeeCount: Int?, address: String, responsibleName: String, responsiblePhone: String,
                                     responsibleEmail: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        val values = listOf(sector, email, address, responsibleName, responsiblePhone, responsibleEmail).map { it.trim() }
        val responsible = values.subList(3, 6)
        if (expectedVersion < 0 || values[0].isEmpty() || values[0].toByteArray().size > 160 || values[1].toByteArray().size > 320 ||
            values[2].toByteArray().size > 1_000 || values[3].toByteArray().size > 160 || values[4].toByteArray().size > 80 ||
            values[5].toByteArray().size > 320 || (responsible.any { it.isEmpty() } && responsible.any { it.isNotEmpty() })) validation()
        fun optional(value: String) = if (value.isEmpty()) JsonNull else JsonPrimitive(value)
        val result = invoke("isg_workspace_company_profile_mutate_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_company", companyId); put("p_expected", expectedVersion)
            put("p_sector", values[0]); put("p_email", optional(values[1])); put("p_employee_count", employeeCount?.let(::JsonPrimitive) ?: JsonNull)
            put("p_address", optional(values[2])); put("p_responsible_name", optional(values[3]))
            put("p_responsible_phone", optional(values[4])); put("p_responsible_email", optional(values[5]))
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, checkCompany = false)
        if (result.text("company_id") != companyId || result.text("sector").isNullOrEmpty()) fail()
        return result
    }

    suspend fun archiveCompany(workspaceId: String, membershipId: String, permissionRevision: Long, canOperate: Boolean,
                               mutationId: String, companyId: String, expectedVersion: Long, reason: String) {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        val clean = reason.trim()
        if (expectedVersion < 0 || clean.isEmpty() || clean.toByteArray().size > 500) validation()
        val result = invoke("isg_workspace_company_archive_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_company", companyId)
            put("p_expected", expectedVersion); put("p_reason", clean)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, checkCompany = false)
        if (result.text("company_id") != companyId || result.text("status") != "archived" ||
            (result.safeLong("version") ?: -1) <= expectedVersion || result.bool("data_deleted") != false) fail()
    }

    /** Whether a file create mutation already landed, so a retry never uploads twice. */
    suspend fun fileCreateReceipt(workspaceId: String, membershipId: String, permissionRevision: Long, canOperate: Boolean,
                                  companyId: String, mutationId: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        val result = invoke("isg_workspace_file_create_receipt_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId); put("p_mutation", mutationId)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, companyId)
        if (result.bool("found") == null) fail()
        return result
    }

    /** Opens a server-scoped upload intent for one private object path. */
    suspend fun uploadOpen(workspaceId: String, membershipId: String, permissionRevision: Long, canOperate: Boolean, companyId: String,
                           idempotency: String, sha256: String, mediaType: String, extension: String, bytes: Int, expiresAt: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        if (bytes !in 1..52_428_800 || !Regex("^[0-9a-f]{64}$").matches(sha256)) validation()
        val result = invoke("isg_workspace_upload_open_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId); put("p_idempotency", idempotency)
            put("p_request_hash", "\\x$sha256"); put("p_purpose", "workspace_file"); put("p_media_type", mediaType)
            put("p_extension", extension); put("p_expected_bytes", bytes); put("p_expires_at", expiresAt)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, checkCompany = false)
        if (result.text("status") != "open" || result.text("bucket") != "isg-workspace-private" ||
            result.text("object_path")?.startsWith("$workspaceId/") != true || result.bool("credential_returned") != true ||
            result.bool("replayed") != false || result.text("upload_token")?.let { Regex("^[0-9a-f]{64}$").matches(it) } != true) fail()
        return result
    }

    /** Opens a short-lived download of one asset of the workspace. */
    suspend fun downloadOpen(workspaceId: String, membershipId: String, permissionRevision: Long, assetId: String, expiresAt: String): String {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if (!UUID.matches(assetId)) validation()
        val result = invoke("isg_workspace_download_open_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_asset", assetId); put("p_purpose", "workspace_file_preview"); put("p_expires_at", expiresAt)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, checkCompany = false)
        return result.text("download_token")?.takeIf { Regex("^[0-9a-f]{64}$").matches(it) } ?: fail()
    }

    /** Published checklist templates the company may start from. */
    suspend fun checklistTemplates(workspaceId: String, membershipId: String, permissionRevision: Long, companyId: String): JsonArray {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        val result = invoke("isg_workspace_checklist_read_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId); put("p_id", JsonNull); put("p_after", JsonNull); put("p_limit", 1)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        val templates = result["templates"] as? JsonArray ?: fail()
        if (templates.size > 500 || templates.any { row -> (row as? JsonObject)?.let {
                !it.text("code").isNullOrEmpty() && !it.text("title").isNullOrEmpty() &&
                    (it.safeLong("version") ?: 0) in 1..1000 && (it.safeLong("item_count") ?: 0) in 1..500
            } != true }) fail()
        return templates
    }

    /** Equipment type suggestions and the company's control period rules. */
    suspend fun equipmentCatalog(workspaceId: String, membershipId: String, permissionRevision: Long, companyId: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        val result = invoke("isg_workspace_equipment_read_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId); put("p_kind", "catalog"); put("p_id", JsonNull)
            put("p_query", ""); put("p_state", JsonNull); put("p_type", JsonNull); put("p_after", JsonNull); put("p_limit", 100)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        val suggestions = result["suggestions"] as? JsonArray ?: fail()
        val rules = result["rules"] as? JsonArray ?: fail()
        if (suggestions.size > 100 || rules.size > 100 ||
            suggestions.any { (it as? JsonObject)?.let { row -> !row.text("code").isNullOrEmpty() && (row.safeLong("ordinal") ?: 0) > 0 } != true } ||
            rules.any { (it as? JsonObject)?.let { row -> !row.text("equipment_type").isNullOrEmpty() && (row.safeLong("period_months") ?: 0) in 1..240 } != true })
            fail()
        return result
    }

    /** Creates the invisible default workplace of a company that has none yet. */
    suspend fun initializePersonnel(workspaceId: String, membershipId: String, permissionRevision: Long, canOperate: Boolean, companyId: String) {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        val result = invoke("isg_workspace_personnel_initialize_v1", buildJsonObject { put("p_workspace", workspaceId); put("p_company", companyId) })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, companyId)
        if (result.text("workplace_id") == null) fail()
    }

    /** Creates, edits or archives a workplace or department (`isg_workspace_directory_mutate_v1`). */
    suspend fun mutateDirectory(workspaceId: String, membershipId: String, permissionRevision: Long, canOperate: Boolean, mutationId: String,
                                companyId: String, entity: String, action: String, entryId: String?, expectedVersion: Long,
                                workplaceId: String?, code: String?, name: String?): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        if (entity !in setOf("workplace", "department") || action !in setOf("create", "edit", "archive") || expectedVersion < 0 ||
            (action == "create") != (entryId == null) || (action != "archive" && !validDirectoryText(code, name))) validation()
        val result = invoke("isg_workspace_directory_mutate_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_company", companyId); put("p_entity", entity)
            put("p_action", action); put("p_id", entryId?.let(::JsonPrimitive) ?: JsonNull); put("p_expected", expectedVersion)
            put("p_workplace", workplaceId?.let(::JsonPrimitive) ?: JsonNull)
            put("p_code", code?.let(::JsonPrimitive) ?: JsonNull); put("p_name", name?.let(::JsonPrimitive) ?: JsonNull)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, companyId)
        if (result["action"] != null && result.text("action") != action) fail()
        return result
    }

    /** Creates, edits or archives a company employee (`isg_workspace_employee_mutate_v1`). */
    suspend fun mutateEmployee(workspaceId: String, membershipId: String, permissionRevision: Long, canOperate: Boolean, mutationId: String,
                               companyId: String, action: String, employeeId: String?, expectedVersion: Long, code: String?, name: String?,
                               departmentId: String?, hiredOn: String?, endsBefore: String?): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        if (action !in setOf("create", "edit", "archive") || expectedVersion < 0 || (action == "create") != (employeeId == null) ||
            (action != "archive" && !validDirectoryText(code, name)) || hiredOn?.let(::validDay) == false || endsBefore?.let(::validDay) == false ||
            (hiredOn != null && endsBefore != null && hiredOn >= endsBefore)) validation()
        val result = invoke("isg_workspace_employee_mutate_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_company", companyId); put("p_action", action)
            put("p_employee", employeeId?.let(::JsonPrimitive) ?: JsonNull); put("p_expected", expectedVersion)
            put("p_code", code?.let(::JsonPrimitive) ?: JsonNull); put("p_name", name?.let(::JsonPrimitive) ?: JsonNull)
            put("p_department", departmentId?.let(::JsonPrimitive) ?: JsonNull)
            put("p_hired_on", hiredOn?.let(::JsonPrimitive) ?: JsonNull); put("p_ends_before", endsBefore?.let(::JsonPrimitive) ?: JsonNull)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, companyId)
        if (result["action"] != null && result.text("action") != action) fail()
        return result
    }

    private fun validDirectoryText(code: String?, name: String?): Boolean {
        val cleanCode = code?.trim() ?: return false; val cleanName = name?.trim() ?: return false
        return cleanCode.isNotEmpty() && cleanCode.toByteArray().size <= 80 && cleanName.isNotEmpty() && cleanName.toByteArray().size <= 200
    }

    /** One photo analysis job (`isg_workspace_photo_analysis_get_v1`). */
    suspend fun photoAnalysisJob(workspaceId: String, membershipId: String, permissionRevision: Long, companyId: String, jobId: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        val result = invoke("isg_workspace_photo_analysis_get_v1", buildJsonObject { put("p_workspace", workspaceId); put("p_job", jobId) })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        val status = result.text("status")
        if (result.safeLong("schema_version") != 1L || result.text("workspace_id") != workspaceId || result.text("company_id") != companyId ||
            result.text("job_id") != jobId || result.text("feature") != "photo_analysis" ||
            status !in setOf("queued", "running", "succeeded", "failed", "cancelled", "reconcile") ||
            (status == "succeeded" && (result.text("output_asset_id") == null || result.text("analysis_id") == null))) fail()
        return result
    }

    /** Starts a photo analysis on one filed company photo (`isg_workspace_photo_analysis_submit_v1`); returns the job id. */
    suspend fun submitPhotoAnalysis(workspaceId: String, membershipId: String, permissionRevision: Long, canOperate: Boolean, mutationId: String,
                                    companyId: String, assetId: String): String {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        if (!UUID.matches(assetId)) validation()
        val result = invoke("isg_workspace_photo_analysis_submit_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId); put("p_idempotency", mutationId); put("p_source_asset", assetId)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        if (result.text("workspace_id") != workspaceId || result.text("company_id") != companyId) fail()
        return result.text("job_id")?.takeIf(UUID::matches) ?: fail()
    }

    private fun validMember(row: JsonObject): Boolean {
        val role = row.text("role"); val status = row.text("status"); val practicing = row.bool("is_practicing_expert")
        return row.text("membership_id")?.let(UUID::matches) == true && role in setOf("owner", "admin", "expert") &&
            status in setOf("active", "suspended", "ended") && practicing != null &&
            (!practicing || (role == "expert" && status == "active")) && (row.safeLong("version") ?: -1) >= 0 &&
            (row.safeLong("permission_revision") ?: -1) >= 0
    }

    private fun invitationToken(result: JsonObject, workspaceId: String, invitationId: String?): JsonObject {
        requireEnvelope(result, workspaceId, checkCompany = false)
        if ((invitationId != null && result.text("invitation_id") != invitationId) || result.text("invitation_id")?.let(UUID::matches) != true ||
            result.text("status") != "pending" || result.text("role") !in setOf("admin", "expert") ||
            (result.bool("token_persisted") != false && result.bool("token_returned") == false) ||
            result.text("invitation_token")?.let { Regex("^[0-9a-f]{64}$").matches(it) } != true) fail()
        return result
    }

    suspend fun personnelMetrics(workspaceId: String, membershipId: String, permissionRevision: Long,
                                 companyId: String?): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        val result = invoke("isg_workspace_personnel_metrics_v1", scoped(workspaceId, companyId))
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        if (result.bool("measured") != true) fail()
        for (key in setOf("workplaces", "departments", "employees")) {
            val counts = result[key] as? JsonObject ?: fail()
            if (counts.keys != setOf("active", "archived") || counts.values.any { it.jsonPrimitive.longOrNull?.let { n -> n < 0 } != false }) fail()
        }
        return result
    }

    /** One page of workplaces, departments or employees (`isg_workspace_personnel_read_v1`), cursor-paged by id. */
    suspend fun personnelRead(workspaceId: String, membershipId: String, permissionRevision: Long,
                              companyId: String, kind: String, query: String = "", archived: Boolean = false,
                              after: String? = null, id: String? = null, limit: Int = 100): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if (kind !in setOf("workplaces", "departments", "employees")) validation()
        requireLimit(limit, 100)
        val result = invoke("isg_workspace_personnel_read_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId); put("p_kind", kind); put("p_query", query)
            put("p_archived", archived); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull)
            put("p_id", id?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        val rows = result["rows"] as? JsonArray ?: fail()
        if (rows.size > limit || rows.any { it !is JsonObject }) fail()
        return result
    }

    suspend fun personnelAdvanced(workspaceId: String, membershipId: String, permissionRevision: Long,
                                  companyId: String, kind: IsgWorkspacePersonnelAdvancedKind,
                                  limit: Int = 100): JsonObject = advancedRead(
        workspaceId, membershipId, permissionRevision, companyId, kind.wireValue, limit,
        "isg_workspace_personnel_advanced_read_v1"
    )

    suspend fun trainingAdvanced(workspaceId: String, membershipId: String, permissionRevision: Long,
                                 companyId: String, kind: IsgWorkspaceTrainingAdvancedKind,
                                 limit: Int = 100): JsonObject = advancedRead(
        workspaceId, membershipId, permissionRevision, companyId, kind.wireValue, limit,
        "isg_workspace_training_advanced_read_v1"
    )

    suspend fun mutatePersonnelAdvanced(workspaceId: String, membershipId: String,
                                        permissionRevision: Long, canOperate: Boolean,
                                        mutationId: String, companyId: String,
                                        payload: JsonObject): JsonObject = advancedMutation(
        workspaceId, membershipId, permissionRevision, canOperate, mutationId, companyId, payload,
        "isg_workspace_personnel_advanced_mutate_v1"
    )

    suspend fun mutateTrainingAdvanced(workspaceId: String, membershipId: String,
                                       permissionRevision: Long, canOperate: Boolean,
                                       mutationId: String, companyId: String,
                                       payload: JsonObject): JsonObject = advancedMutation(
        workspaceId, membershipId, permissionRevision, canOperate, mutationId, companyId, payload,
        "isg_workspace_training_advanced_mutate_v1"
    )

    suspend fun dashboard(workspaceId: String, membershipId: String, permissionRevision: Long,
                          companyId: String?): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        val result = invoke("isg_workspace_dashboard_v1", scoped(workspaceId, companyId))
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        if (result.bool("measured") != true) fail()
        val required = mapOf("companies" to setOf("total"), "nonconformities" to setOf("open", "overdue"),
            "visits" to setOf("total", "last_30_days"), "training" to setOf("planned", "completed"),
            "deadlines" to setOf("equipment_due_soon", "risk_due_soon"))
        for ((key, fields) in required) {
            val metrics = result[key] as? JsonObject ?: fail()
            if (fields.any { metrics.nonNegative(it) == null }) fail()
        }
        return result
    }

    suspend fun search(workspaceId: String, membershipId: String, permissionRevision: Long,
                       companyId: String, query: String, afterKind: String? = null,
                       afterId: String? = null, limit: Int = 30): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        val clean = query.trim()
        if (clean.toByteArray().size !in 2..120 || (afterKind == null) != (afterId == null)) validation()
        requireLimit(limit, 100)
        val result = invoke("isg_workspace_search_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId); put("p_query", clean)
            put("p_after_kind", afterKind?.let(::JsonPrimitive) ?: JsonNull)
            put("p_after_id", afterId?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        val rows = result["rows"] as? JsonArray ?: fail()
        if (rows.size > limit || result.safeLong("returned") != rows.size.toLong()) fail()
        val allowed = setOf("company", "employee", "nonconformity", "equipment", "training", "file")
        if (rows.any { row -> (row as? JsonObject)?.let { it.text("kind") in allowed && !it.text("title").isNullOrBlank() } != true }) fail()
        return result
    }

    /** D1-D7 read boundary. It mirrors the iOS adapter and never calls a legacy owner-scoped endpoint. */
    suspend fun domain(workspaceId: String, membershipId: String, permissionRevision: Long,
                       companyId: String, domain: IsgWorkspaceDomain, limit: Int = 100): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireLimit(limit, 100)
        var after: String? = null
        var envelope: JsonObject? = null
        val combined = mutableListOf<JsonElement>()
        val seen = mutableSetOf<String>()
        repeat(100) { pageIndex ->
            val (function, arguments) = domainReadRequest(workspaceId, companyId, domain, after, limit)
            val result = invoke(function, arguments)
            checkWorkspace(workspaceId, membershipId, permissionRevision)
            requireEnvelope(result, workspaceId, companyId)
            if (envelope == null) envelope = result
            val rows = result["rows"] as? JsonArray ?: if (result["row"] is JsonObject) {
                JsonArray(listOf(result.getValue("row")))
            } else JsonArray(emptyList())
            if (rows.size > limit) fail()
            for (element in rows) {
                val row = element as? JsonObject ?: fail()
                val id = domainRowId(row) ?: fail()
                if (!seen.add(id)) fail()
                combined += row
            }
            val next = when (val raw = result["next"]) {
                null, JsonNull -> null
                is JsonPrimitive -> raw.content.takeIf(UUID::matches) ?: fail()
                else -> fail()
            }
            if (next == null) return JsonObject(envelope.toMutableMap().apply {
                put("rows", JsonArray(combined)); put("next", JsonNull); remove("row")
                if (containsKey("returned")) put("returned", JsonPrimitive(combined.size))
                if (containsKey("total")) put("total", JsonPrimitive(combined.size))
            })
            if (next == after || rows.size != limit || domainRowId(rows.last() as? JsonObject ?: fail()) != next || pageIndex == 99) fail()
            after = next
        }
        fail()
    }

    /** One record with its full history (iOS `domainDetail`); equipment reads its detail projection. */
    suspend fun domainDetail(workspaceId: String, membershipId: String, permissionRevision: Long,
                             companyId: String, domain: IsgWorkspaceDomain, id: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if (!UUID.matches(id)) validation()
        val (function, base) = domainReadRequest(workspaceId, companyId, domain, null, 1)
        val arguments = JsonObject(base.toMutableMap().apply {
            put("p_id", JsonPrimitive(id)); put("p_after", JsonNull); put("p_limit", JsonPrimitive(1))
            if (domain == IsgWorkspaceDomain.EQUIPMENT) put("p_kind", JsonPrimitive("detail"))
        })
        val result = invoke(function, arguments)
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        val rows = result["rows"] as? JsonArray ?: (result["row"] as? JsonObject)?.let { JsonArray(listOf(it)) } ?: fail()
        val row = rows.singleOrNull() as? JsonObject ?: fail()
        if (domainRowId(row) != id || (result["next"] ?: JsonNull) != JsonNull) fail()
        return row
    }

    suspend fun domainMetrics(workspaceId: String, membershipId: String, permissionRevision: Long,
                              companyId: String, domain: IsgWorkspaceDomain): JsonObject? {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        val request = domainMetricRequest(workspaceId, companyId, domain) ?: return null
        val result = invoke(request.first, request.second)
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        if (result.bool("measured") != true) fail()
        return result
    }

    suspend fun mutateDomain(workspaceId: String, membershipId: String, permissionRevision: Long,
                             canOperate: Boolean, mutationId: String, companyId: String,
                             domain: IsgWorkspaceDomain, payload: JsonObject): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        val function = mutationFunction(domain) ?: validation()
        if (payload.text("action").isNullOrBlank() || payload.toString().toByteArray().size > 65_536) validation()
        val result = invoke(function, buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_company", companyId)
            put("p_payload", payload)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, companyId)
        return result
    }

    suspend fun analyses(workspaceId: String, membershipId: String, permissionRevision: Long,
                         companyId: String, offset: Int = 0, limit: Int = 30): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if (offset !in 0..100_000) validation()
        requireLimit(limit, 100)
        val result = invoke("isg_workspace_analysis_list_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId)
            put("p_offset", offset); put("p_limit", limit)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        val rows = result["rows"] as? JsonArray ?: fail()
        if (result.safeLong("offset") != offset.toLong() || result.safeLong("returned") != rows.size.toLong() ||
            rows.size > limit || result.bool("has_more") == null) fail()
        return result
    }

    suspend fun analysis(workspaceId: String, membershipId: String, permissionRevision: Long,
                         companyId: String, analysisId: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        val result = invoke("isg_workspace_analysis_read_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId); put("p_analysis", analysisId)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        val header = result["analysis"] as? JsonObject ?: fail()
        if (header.text("id") != analysisId || header.text("primary_method") !in setOf("fine_kinney", "matrix_5x5")) fail()
        val counts = result["counts"] as? JsonObject ?: fail()
        for ((count, array) in listOf("risk" to "risk_findings", "expert" to "expert_items", "training" to "training_items")) {
            val rows = result[array] as? JsonArray ?: fail()
            if (counts.safeLong(count) != rows.size.toLong()) fail()
        }
        return result
    }

    suspend fun fileAnalysisItem(workspaceId: String, membershipId: String, permissionRevision: Long,
                                 canOperate: Boolean, mutationId: String, companyId: String,
                                 workplaceId: String, sourceScope: String, analysisId: String,
                                 itemKind: String, itemId: String, severity: String?, openedOn: String,
                                 dueOn: String?): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        if (sourceScope !in setOf("workspace", "personal") || itemKind !in setOf("finding", "expert_item") ||
            severity?.let { it !in setOf("low", "medium", "high", "critical") } == true ||
            !validDay(openedOn) || dueOn?.let { !validDay(it) } == true) validation()
        val result = invoke("isg_workspace_analysis_file_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_company", companyId)
            put("p_workplace", workplaceId); put("p_source_scope", sourceScope); put("p_analysis", analysisId)
            put("p_item_kind", itemKind); put("p_item", itemId)
            put("p_severity", severity?.let(::JsonPrimitive) ?: JsonNull); put("p_opened_on", openedOn)
            put("p_due_on", dueOn?.let(::JsonPrimitive) ?: JsonNull)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, companyId)
        if (result.text("commit_state") != "committed_and_visible" ||
            result.text("success_message_key") !in setOf("analysis_finding_filed", "analysis_finding_already_filed") ||
            result.text("nonconformity_id")?.let(UUID::matches) != true || result.bool("created") == null) fail()
        return result
    }

    suspend fun createExport(workspaceId: String, membershipId: String, permissionRevision: Long,
                             canOperate: Boolean, mutationId: String, companyId: String, analysisId: String,
                             format: String, findingIds: List<String>, expertItemIds: List<String>,
                             trainingItemIds: List<String>): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        if (format !in setOf("pdf", "xlsx") || (findingIds + expertItemIds + trainingItemIds).any { !UUID.matches(it) }) validation()
        val result = invoke("isg_workspace_export_create_v1", buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_company", companyId)
            put("p_analysis", analysisId); put("p_format", format)
            put("p_selection", buildJsonObject {
                put("finding_ids", JsonArray(findingIds.map { JsonPrimitive(it) }))
                put("expert_item_ids", JsonArray(expertItemIds.map { JsonPrimitive(it) }))
                put("training_item_ids", JsonArray(trainingItemIds.map { JsonPrimitive(it) }))
            })
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        return validateExport(result, workspaceId, companyId)
    }

    suspend fun export(workspaceId: String, membershipId: String, permissionRevision: Long,
                       companyId: String, jobId: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        val result = invoke("isg_workspace_export_get_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId); put("p_job", jobId)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if ((result["row"] as? JsonObject)?.text("id") != jobId) fail()
        return validateExport(result, workspaceId, companyId)
    }

    suspend fun changes(workspaceId: String, membershipId: String, permissionRevision: Long,
                        companyId: String?, after: Long = 0, limit: Int = 100): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        if (after < 0) validation()
        requireLimit(limit, 200)
        val result = invoke("isg_workspace_change_read_v1", buildJsonObject {
            put("p_workspace", workspaceId); put("p_company", companyId?.let(::JsonPrimitive) ?: JsonNull)
            put("p_after", after); put("p_limit", limit)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireEnvelope(result, workspaceId, companyId)
        val next = result.safeLong("next") ?: fail()
        val rows = result["rows"] as? JsonArray ?: fail()
        if (next < after || rows.size > limit || rows.any { (it as? JsonObject)?.safeLong("sequence")?.let { n -> n > after && n <= next } != true }) fail()
        return result
    }

    private fun validateExport(result: JsonObject, workspace: String, company: String): JsonObject {
        if (result.safeLong("schema_version") != 1L || result.text("workspace_id") != workspace ||
            result.text("company_id") != company) fail()
        val row = result["row"] as? JsonObject ?: fail()
        val status = row.text("status")
        val output = row.text("output_asset_id")
        if (row.text("id")?.let(UUID::matches) != true || status !in setOf("queued", "running", "succeeded", "failed", "cancelled") ||
            (status == "succeeded") != (output?.let(UUID::matches) == true)) fail()
        return result
    }

    private suspend fun advancedRead(workspaceId: String, membershipId: String, permissionRevision: Long,
                                     companyId: String, kind: String, limit: Int,
                                     function: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision)
        requireLimit(limit, 100)
        var after: String? = null
        var envelope: JsonObject? = null
        val combined = mutableListOf<JsonElement>()
        val seen = mutableSetOf<String>()
        repeat(100) { pageIndex ->
            val result = invoke(function, buildJsonObject {
                put("p_workspace", workspaceId); put("p_company", companyId); put("p_kind", kind)
                put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit)
            })
            checkWorkspace(workspaceId, membershipId, permissionRevision)
            requireEnvelope(result, workspaceId, companyId)
            if (result.text("kind") != kind) fail()
            if (envelope == null) envelope = result
            val rows = result["rows"] as? JsonArray ?: fail()
            if (rows.size > limit) fail()
            for (element in rows) {
                val row = element as? JsonObject ?: fail()
                val id = row.text("id")?.takeIf(UUID::matches) ?: fail()
                if (!seen.add(id) || row.text("kind").isNullOrBlank()) fail()
                combined += row
            }
            val next = when (val raw = result["next"]) {
                null, JsonNull -> null
                is JsonPrimitive -> raw.content.takeIf(UUID::matches) ?: fail()
                else -> fail()
            }
            if (next == null) return JsonObject(envelope.toMutableMap().apply {
                put("rows", JsonArray(combined)); put("next", JsonNull)
            })
            if (next == after || rows.size != limit ||
                (rows.last() as? JsonObject)?.text("id") != next || pageIndex == 99) fail()
            after = next
        }
        fail()
    }

    private suspend fun advancedMutation(workspaceId: String, membershipId: String,
                                         permissionRevision: Long, canOperate: Boolean,
                                         mutationId: String, companyId: String, payload: JsonObject,
                                         function: String): JsonObject {
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        if (!UUID.matches(mutationId) || payload.text("action").isNullOrBlank() ||
            payload.toString().toByteArray().size > 65_536) validation()
        val result = invoke(function, buildJsonObject {
            put("p_mutation", mutationId); put("p_workspace", workspaceId); put("p_company", companyId)
            put("p_payload", payload)
        })
        checkWorkspace(workspaceId, membershipId, permissionRevision, canOperate)
        requireEnvelope(result, workspaceId, companyId)
        if (result.text("action") != payload.text("action") ||
            result.text("entity_id")?.let(UUID::matches) != true || result.safeLong("version") == null) fail()
        return result
    }

    private fun validInstant(value: String): Boolean = runCatching { Instant.parse(value) }.isSuccess

    private fun domainReadRequest(workspace: String, company: String, domain: IsgWorkspaceDomain,
                                  after: String?, limit: Int): Pair<String, JsonObject> {
        val function = when (domain) {
            IsgWorkspaceDomain.PERSONNEL -> "isg_workspace_personnel_read_v1"
            IsgWorkspaceDomain.TRAINING -> "isg_workspace_training_read_v1"
            IsgWorkspaceDomain.RISK -> "isg_workspace_risk_read_v1"
            IsgWorkspaceDomain.NONCONFORMITY -> "isg_workspace_nonconformity_read_v1"
            IsgWorkspaceDomain.CHECKLIST -> "isg_workspace_checklist_read_v1"
            IsgWorkspaceDomain.EMERGENCY_PLAN, IsgWorkspaceDomain.DRILL,
            IsgWorkspaceDomain.APPOINTMENT, IsgWorkspaceDomain.PPE -> "isg_workspace_safety_read_v1"
            IsgWorkspaceDomain.EQUIPMENT -> "isg_workspace_equipment_read_v1"
            IsgWorkspaceDomain.KATIP, IsgWorkspaceDomain.ANNUAL_PLAN, IsgWorkspaceDomain.BOARD,
            IsgWorkspaceDomain.WORK_PERMIT, IsgWorkspaceDomain.VISIT -> "isg_workspace_operations_read_v1"
            IsgWorkspaceDomain.FILES -> "isg_workspace_file_read_v1"
        }
        return function to buildJsonObject {
            put("p_workspace", workspace); put("p_company", company)
            when (domain) {
                IsgWorkspaceDomain.PERSONNEL -> {
                    put("p_kind", "employees"); put("p_query", ""); put("p_archived", false)
                    put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_id", JsonNull); put("p_limit", limit)
                }
                IsgWorkspaceDomain.TRAINING -> { put("p_id", JsonNull); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit) }
                IsgWorkspaceDomain.RISK -> { put("p_id", JsonNull); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit) }
                IsgWorkspaceDomain.NONCONFORMITY -> { put("p_id", JsonNull); put("p_state", JsonNull); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit) }
                IsgWorkspaceDomain.CHECKLIST -> { put("p_id", JsonNull); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit) }
                IsgWorkspaceDomain.EMERGENCY_PLAN, IsgWorkspaceDomain.DRILL,
                IsgWorkspaceDomain.APPOINTMENT, IsgWorkspaceDomain.PPE -> {
                    put("p_kind", when (domain) {
                        IsgWorkspaceDomain.EMERGENCY_PLAN -> "plans"; IsgWorkspaceDomain.DRILL -> "drills"
                        IsgWorkspaceDomain.APPOINTMENT -> "appointments"; else -> "ppe" })
                    put("p_id", JsonNull); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit)
                }
                IsgWorkspaceDomain.EQUIPMENT -> {
                    put("p_kind", "inventory"); put("p_id", JsonNull); put("p_query", "")
                    put("p_state", JsonNull); put("p_type", JsonNull)
                    put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit)
                }
                IsgWorkspaceDomain.KATIP, IsgWorkspaceDomain.ANNUAL_PLAN, IsgWorkspaceDomain.BOARD,
                IsgWorkspaceDomain.WORK_PERMIT, IsgWorkspaceDomain.VISIT -> {
                    put("p_kind", when (domain) {
                        IsgWorkspaceDomain.KATIP -> "katip_contract"; IsgWorkspaceDomain.ANNUAL_PLAN -> "annual_plan"
                        IsgWorkspaceDomain.BOARD -> "board"; IsgWorkspaceDomain.WORK_PERMIT -> "work_permit"
                        else -> "site_visit" })
                    put("p_id", JsonNull); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull); put("p_limit", limit)
                }
                IsgWorkspaceDomain.FILES -> {
                    put("p_id", JsonNull); put("p_query", ""); put("p_category", JsonNull)
                    put("p_include_archived", false); put("p_after", after?.let(::JsonPrimitive) ?: JsonNull)
                    put("p_limit", limit)
                }
            }
        }
    }

    private fun domainRowId(row: JsonObject): String? = listOf(
        "employee_id", "training_id", "assessment_id", "nonconformity_id", "run_id", "plan_id",
        "drill_id", "appointment_id", "handover_id", "equipment_id", "contract_id", "meeting_id",
        "permit_id", "visit_id", "entry_id", "id"
    ).firstNotNullOfOrNull { key -> row.text(key)?.takeIf(UUID::matches) }

    private fun domainMetricRequest(workspace: String, company: String, domain: IsgWorkspaceDomain): Pair<String, JsonObject>? {
        val function = when (domain) {
            IsgWorkspaceDomain.PERSONNEL -> "isg_workspace_personnel_metrics_v1"
            IsgWorkspaceDomain.TRAINING -> "isg_workspace_training_metrics_v1"
            IsgWorkspaceDomain.RISK, IsgWorkspaceDomain.NONCONFORMITY,
            IsgWorkspaceDomain.CHECKLIST -> "isg_workspace_assurance_metrics_v1"
            IsgWorkspaceDomain.EMERGENCY_PLAN, IsgWorkspaceDomain.DRILL,
            IsgWorkspaceDomain.APPOINTMENT, IsgWorkspaceDomain.PPE -> "isg_workspace_safety_metrics_v1"
            IsgWorkspaceDomain.EQUIPMENT -> "isg_workspace_equipment_metrics_v1"
            IsgWorkspaceDomain.KATIP, IsgWorkspaceDomain.ANNUAL_PLAN, IsgWorkspaceDomain.BOARD,
            IsgWorkspaceDomain.WORK_PERMIT, IsgWorkspaceDomain.VISIT -> "isg_workspace_operations_metrics_v1"
            IsgWorkspaceDomain.FILES -> return null
        }
        return function to scoped(workspace, company)
    }

    private fun mutationFunction(domain: IsgWorkspaceDomain): String? = when (domain) {
        IsgWorkspaceDomain.TRAINING -> "isg_workspace_training_mutate_v1"
        IsgWorkspaceDomain.RISK -> "isg_workspace_risk_mutate_v1"
        IsgWorkspaceDomain.NONCONFORMITY -> "isg_workspace_nonconformity_mutate_v1"
        IsgWorkspaceDomain.CHECKLIST -> "isg_workspace_checklist_mutate_v1"
        IsgWorkspaceDomain.EMERGENCY_PLAN, IsgWorkspaceDomain.DRILL,
        IsgWorkspaceDomain.APPOINTMENT, IsgWorkspaceDomain.PPE -> "isg_workspace_safety_mutate_v1"
        IsgWorkspaceDomain.EQUIPMENT -> "isg_workspace_equipment_mutate_v1"
        IsgWorkspaceDomain.KATIP, IsgWorkspaceDomain.ANNUAL_PLAN, IsgWorkspaceDomain.BOARD,
        IsgWorkspaceDomain.WORK_PERMIT, IsgWorkspaceDomain.VISIT -> "isg_workspace_operations_mutate_v1"
        IsgWorkspaceDomain.FILES -> "isg_workspace_file_mutate_v1"
        IsgWorkspaceDomain.PERSONNEL -> null
    }

    private suspend fun checkIdentity(user: String, session: String) {
        currentCoroutineContext().ensureActive()
        if (!isCurrentIdentity(user, session)) throw IsgWorkspaceGatewayFailure("STALE_SESSION")
    }
    private suspend fun checkWorkspace(workspace: String, membership: String, revision: Long,
                                       canOperate: Boolean? = null) {
        currentCoroutineContext().ensureActive()
        if (revision < 0 || canOperate == false || !isCurrentWorkspace(workspace, membership, revision))
            throw IsgWorkspaceGatewayFailure("STALE_WORKSPACE")
    }
    private fun requireEnvelope(value: JsonObject, workspace: String, company: String? = null, checkCompany: Boolean = true) {
        if (value.safeLong("schema_version") != 1L || value.text("workspace_id") != workspace ||
            (checkCompany && value["company_id"] != (company?.let(::JsonPrimitive) ?: JsonNull))) fail()
    }
    private fun scoped(workspace: String, company: String?) = buildJsonObject {
        put("p_workspace", workspace); put("p_company", company?.let(::JsonPrimitive) ?: JsonNull)
    }
    private fun requireLimit(value: Int, maximum: Int) { if (value !in 1..maximum) validation() }
    private fun validDay(value: String) = DAY.matches(value) && runCatching { LocalDate.parse(value) }.isSuccess
    private fun validation(): Nothing = throw IsgWorkspaceGatewayFailure("VALIDATION_ERROR")
    private fun fail(): Nothing = throw IsgWorkspaceGatewayFailure("INVALID_RESPONSE")

    private fun JsonObject.text(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun JsonObject.bool(key: String) = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
    private fun JsonObject.safeLong(key: String) = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull
        ?.takeIf { it in 0..9007199254740991L }
    private fun JsonObject.nonNegative(key: String) = safeLong(key)?.takeIf { it >= 0 }

    private companion object {
        val UUID = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        val DAY = Regex("^\\d{4}-\\d{2}-\\d{2}$")
    }
}
