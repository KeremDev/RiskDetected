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
