package com.riskdetectedan.core.data.company

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class PersonnelWorkspaceCapabilityTest {
    private val identity = PersonnelWorkspaceIdentity(UUID.randomUUID(), UUID.randomUUID())
    private val company = UUID.randomUUID()
    private fun payload(selected: Boolean = true) = buildJsonObject {
        put("schema_version", 1); put("owner_id", identity.ownerID.toString())
        put("company_id", if (selected) JsonPrimitive(company.toString()) else JsonNull)
        put("company_name", if (selected) JsonPrimitive("Firma") else JsonNull)
        put("is_archived", if (selected) JsonPrimitive(false) else JsonNull)
        put("can_read", true); put("can_write", selected)
    }
    @Test fun paidAndGlobalCapabilities() {
        assertTrue(PersonnelWorkspaceCapability.decode(payload(), identity, company).canWrite)
        assertFalse(PersonnelWorkspaceCapability.decode(payload(false), identity, null).canWrite)
    }
    @Test fun invalidPayloadMatrix() {
        val changes = listOf("schema_version" to JsonPrimitive(2), "owner_id" to JsonPrimitive(UUID.randomUUID().toString()),
            "company_id" to JsonNull, "company_name" to JsonNull, "company_name" to JsonPrimitive("  "),
            "is_archived" to JsonNull, "is_archived" to JsonPrimitive(true), "can_read" to JsonPrimitive(false),
            "can_write" to JsonPrimitive("true"), "can_read" to JsonPrimitive(1))
        changes.forEach { (key, value) ->
            assertThrows("Rejected $key=$value", Exception::class.java) { PersonnelWorkspaceCapability.decode(JsonObject(payload() + (key to value)), identity, company) }
        }
    }
    @Test fun archivedAndDisabledRemainReadOnly() {
        val archived = JsonObject(payload() + mapOf("is_archived" to JsonPrimitive(true), "can_write" to JsonPrimitive(false)))
        assertTrue(PersonnelWorkspaceCapability.decode(archived, identity, company).canRead)
        val off = JsonObject(payload(false) + ("can_read" to JsonPrimitive(false)))
        assertFalse(PersonnelWorkspaceCapability.decode(off, identity, null).canRead)
    }
    @Test fun globalCannotCarrySelectedCompanyInformation() {
        assertThrows(Exception::class.java) { PersonnelWorkspaceCapability.decode(JsonObject(payload(false) + ("company_name" to JsonPrimitive("Firma"))), identity, null) }
    }
}
