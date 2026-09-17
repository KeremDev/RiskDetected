package com.riskdetectedan.core.data.isg

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class IsgWorkspaceGatewayTest {
    private val workspace = "22000000-0000-4000-8000-000000000001"
    private val company = "24000000-0000-4000-8000-000000000001"
    private val job = "29000000-0000-4000-8000-000000000001"
    private val assignment = "2a000000-0000-4000-8000-000000000001"
    private val targetMembership = "2b000000-0000-4000-8000-000000000001"
    private fun response(includeScope: Boolean = true) = buildJsonObject {
        put("schema_version", 1)
        if (includeScope) { put("workspace_id", workspace); put("company_id", company) }
        put("row", buildJsonObject { put("id", job); put("status", "queued"); put("output_asset_id", JsonNull) })
    }
    private suspend fun rejected(code: String, action: suspend () -> Unit) {
        try { action(); fail("Response should be rejected: $code") }
        catch (failure: IsgWorkspaceGatewayFailure) { assertEquals(code, failure.code) }
    }
    @Test fun scopeEpochChangeRejectsSameMembershipResponse() = runBlocking {
        var token = "session1-workspaceA-companyA-epoch1"
        val gateway = IsgWorkspaceGateway({ _, _ -> token = "session1-workspaceA-companyA-epoch3"; response() },
            { _, _ -> true }, { _, _, _ -> true }, { token })
        rejected("STALE_SESSION") { gateway.export(workspace,"member",1,company,job) }
    }
    @Test fun missingScopeCannotBeAcceptedAsExport() = runBlocking {
        val gateway = IsgWorkspaceGateway({ _, _ -> response(false) }, { _, _ -> true }, { _, _, _ -> true }, { "current" })
        rejected("INVALID_RESPONSE") { gateway.export(workspace,"member",1,company,job) }
    }
    @Test fun exportMustMatchRequestedJob() = runBlocking {
        val gateway = IsgWorkspaceGateway({ _, _ -> response() }, { _, _ -> true }, { _, _, _ -> true }, { "current" })
        rejected("INVALID_RESPONSE") { gateway.export(workspace,"member",1,company,"30000000-0000-4000-8000-000000000001") }
        assertEquals(job, gateway.export(workspace,"member",1,company,job)["row"]!!.jsonObject["id"]!!.jsonPrimitive.content)
    }
    @Test fun signedOutDoesNotStartTransport() = runBlocking {
        var invoked = false
        val gateway = IsgWorkspaceGateway({ _, _ -> invoked = true; response() }, { _, _ -> true }, { _, _, _ -> true }, { null })
        rejected("STALE_SESSION") { gateway.export(workspace,"member",1,company,job) }
        assertFalse(invoked)
    }

    @Test fun d1ThroughD7ReadsUseOnlyWorkspaceFunctions() = runBlocking {
        val called = mutableListOf<String>()
        val gateway = IsgWorkspaceGateway({ function, _ ->
            called += function
            buildJsonObject {
                put("schema_version", 1); put("workspace_id", workspace); put("company_id", company)
                put("rows", buildJsonArray {})
            }
        }, { _, _ -> true }, { _, _, _ -> true }, { "current" })
        IsgWorkspaceDomain.entries.forEach { gateway.domain(workspace, "member", 1, company, it) }
        assertEquals(IsgWorkspaceDomain.entries.size, called.size)
        assertTrue(called.all { it.startsWith("isg_workspace_") && it.endsWith("_read_v1") })
        assertFalse(called.any { it.contains("legacy") || it.contains("personal") })
    }

    @Test fun domainMutationRequiresOperateAndKeepsScope() = runBlocking {
        var called: String? = null
        val gateway = IsgWorkspaceGateway({ function, arguments ->
            called = function
            assertEquals(workspace, arguments["p_workspace"]!!.jsonPrimitive.content)
            assertEquals(company, arguments["p_company"]!!.jsonPrimitive.content)
            buildJsonObject { put("schema_version", 1); put("workspace_id", workspace); put("company_id", company) }
        }, { _, _ -> true }, { _, _, _ -> true }, { "current" })
        rejected("STALE_WORKSPACE") {
            gateway.mutateDomain(workspace, "member", 1, false, job, company,
                IsgWorkspaceDomain.TRAINING, buildJsonObject { put("action", "create") })
        }
        gateway.mutateDomain(workspace, "member", 1, true, job, company,
            IsgWorkspaceDomain.TRAINING, buildJsonObject { put("action", "create") })
        assertEquals("isg_workspace_training_mutate_v1", called)
    }

    @Test fun analysisListValidatesTenantEnvelopeAndPage() = runBlocking {
        val gateway = IsgWorkspaceGateway({ function, _ ->
            assertEquals("isg_workspace_analysis_list_v1", function)
            buildJsonObject {
                put("schema_version", 1); put("workspace_id", workspace); put("company_id", company)
                put("offset", 0); put("returned", 0); put("has_more", false); put("rows", buildJsonArray {})
            }
        }, { _, _ -> true }, { _, _, _ -> true }, { "current" })
        assertEquals(0, gateway.analyses(workspace, "member", 1, company)["returned"]!!.jsonPrimitive.int)
    }

    @Test fun assignmentListValidatesScopeAndRows() = runBlocking {
        val gateway = IsgWorkspaceGateway({ function, arguments ->
            assertEquals("isg_workspace_assignment_list_v1", function)
            assertEquals("current", arguments["p_status"]!!.jsonPrimitive.content)
            buildJsonObject {
                put("schema_version", 1); put("workspace_id", workspace); put("company_id", company)
                put("rows", buildJsonArray { add(buildJsonObject {
                    put("assignment_id", assignment); put("workspace_id", workspace); put("company_id", company)
                    put("membership_id", targetMembership); put("assignment_role", "primary")
                    put("starts_at", "2026-09-17T08:00:00Z"); put("ends_at", JsonNull); put("version", 0)
                }) }); put("next", JsonNull)
            }
        }, { _, _ -> true }, { _, _, _ -> true }, { "current" })
        val result = gateway.assignments(workspace, "member", 1, company, "current")
        assertEquals(1, result["rows"]!!.jsonArray.size)
    }

    @Test fun assignmentMutationRequiresOperateAndKeepsTenantEnvelope() = runBlocking {
        var calls = 0
        val gateway = IsgWorkspaceGateway({ function, arguments ->
            calls += 1
            assertEquals("isg_workspace_assignment_mutate_v1", function)
            assertEquals(targetMembership, arguments["p_membership"]!!.jsonPrimitive.content)
            buildJsonObject {
                put("schema_version", 1); put("workspace_id", workspace); put("company_id", company)
                put("assignment_id", assignment); put("membership_id", targetMembership)
                put("assignment_role", "support"); put("starts_at", "2026-09-17T08:00:00Z")
                put("ends_at", JsonNull); put("version", 0)
            }
        }, { _, _ -> true }, { _, _, _ -> true }, { "current" })
        rejected("STALE_WORKSPACE") {
            gateway.mutateAssignment(workspace, "member", 1, false, job, company, "create",
                null, targetMembership, 0, "support", "2026-09-17T08:00:00Z", null, "atama")
        }
        gateway.mutateAssignment(workspace, "member", 1, true, job, company, "create",
            null, targetMembership, 0, "support", "2026-09-17T08:00:00Z", null, "atama")
        assertEquals(1, calls)
    }
}
