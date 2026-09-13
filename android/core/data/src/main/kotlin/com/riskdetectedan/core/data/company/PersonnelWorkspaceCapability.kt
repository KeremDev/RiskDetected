package com.riskdetectedan.core.data.company

import kotlinx.serialization.json.*
import java.util.UUID

data class PersonnelWorkspaceIdentity(val ownerID: UUID, val sessionID: UUID)

/** A presentation hint with strict response correlation; not a cached authorization grant. */
data class PersonnelWorkspaceCapability(val companyID: UUID?, val companyName: String?, val archived: Boolean?, val canRead: Boolean, val canWrite: Boolean) {
    companion object {
        fun decode(raw: JsonObject, identity: PersonnelWorkspaceIdentity, company: UUID?): PersonnelWorkspaceCapability {
            require(raw["schema_version"] == JsonPrimitive(1) && raw["owner_id"] == JsonPrimitive(identity.ownerID.toString()))
            require(raw["company_id"] == (company?.toString()?.let(::JsonPrimitive) ?: JsonNull))
            fun bool(key: String): Boolean = raw.getValue(key).jsonPrimitive.let { require(!it.isString); it.boolean }
            val read = bool("can_read"); val write = bool("can_write")
            val name = raw.getValue("company_name").let { if (it == JsonNull) null else it.jsonPrimitive.let { p -> require(p.isString && p.content.isNotBlank()); p.content } }
            val archived = if (raw.getValue("is_archived") == JsonNull) null else bool("is_archived")
            require(!write || (read && company != null && archived == false))
            require(!read || company == null || (name != null && archived != null))
            require(company != null || (name == null && archived == null && !write))
            return PersonnelWorkspaceCapability(company, name, archived, read, write)
        }
    }
}
