package com.riskdetectedan.feature.profile

import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OsgbWorkspaceStateTest {
    @Test fun companyProjectionUsesOnlyTenantRowsAndKeepsServerVersion() {
        val response = buildJsonObject {
            put("rows", buildJsonArray {
                add(buildJsonObject {
                    put("company_id", "11111111-1111-4111-8111-111111111111")
                    put("name", "Staging Firma")
                    put("hazard_class", "high")
                    put("version", 7)
                })
                add(buildJsonObject { put("name", "Kimliksiz satır") })
                add(JsonPrimitive("bozuk"))
            })
        }
        val rows = parseOsgbCompanies(response)
        assertEquals(1, rows.size)
        assertEquals("Staging Firma", rows.single().name)
        assertEquals("high", rows.single().hazardClass)
        assertEquals(7L, rows.single().version)
    }

    @Test fun workspaceEntryVisibilityWaitsForLoadAndRequiresOsgbMembership() {
        assertNull(OsgbWorkspaceUiState(loading = true).hasWorkspace)
        assertFalse(OsgbWorkspaceUiState(loading = false).hasWorkspace!!)
        val fake = com.riskdetectedan.core.data.isg.IsgWorkspaceContext(
            workspaceId = "11111111-1111-4111-8111-111111111111", kind = "osgb", name = "OSGB",
            status = "admin_trial", timezone = "Europe/Istanbul", workspaceVersion = 0,
            canRead = true, canOperate = true, canManageMembers = true, canManageBilling = true,
            membership = com.riskdetectedan.core.data.isg.IsgWorkspaceContext.Membership(
                membershipId = "22222222-2222-4222-8222-222222222222",
                userId = "33333333-3333-4333-8333-333333333333", role = "owner", status = "active",
                isPracticingExpert = false, permissionRevision = 0, membershipVersion = 0,
            ),
        )
        assertTrue(OsgbWorkspaceUiState(loading = false, workspaces = listOf(fake)).hasWorkspace!!)
    }
}
