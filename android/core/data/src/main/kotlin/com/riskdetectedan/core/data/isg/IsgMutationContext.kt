package com.riskdetectedan.core.data.isg

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull

/** Transport validation only; parsed scope is not authorization. */
data class IsgMutationContext(
    val operationId: String,
    val clientMutationId: String,
    val platform: String,
    val clientBuild: Long,
    val expectedVersion: Long,
    val scope: Scope,
) {
    sealed interface Scope {
        data object Personal : Scope
        data class Company(val companyId: String, val workplaceId: String?) : Scope
    }

    companion object {
        private val uuid = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        private val fields = setOf("schema_version", "operation_id", "client_mutation_id", "platform", "client_build", "expected_version", "scope")
        private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
        private fun JsonObject.number(key: String): Long? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.let { value ->
            // JSON 1.0/1e0 and integer 1 have identical numeric semantics across clients.
            value.longOrNull ?: value.content.toDoubleOrNull()?.takeIf { it.isFinite() && it % 1.0 == 0.0 && it >= 0 && it <= 9007199254740991.0 }?.toLong()
        }

        fun parse(input: JsonElement): IsgMutationContext? {
            val obj = input as? JsonObject ?: return null
            if (obj.keys != fields || obj.number("schema_version") != 1L) return null
            val operation = obj.text("operation_id")?.takeIf(uuid::matches) ?: return null
            val mutation = obj.text("client_mutation_id")?.takeIf(uuid::matches) ?: return null
            val platform = obj.text("platform")?.takeIf { it == "ios" || it == "android" } ?: return null
            val build = obj.number("client_build")?.takeIf { it in 1..2147483647L } ?: return null
            val version = obj.number("expected_version")?.takeIf { it in 0..9007199254740991L } ?: return null
            val scopeObject = obj["scope"] as? JsonObject ?: return null
            val scope = when (scopeObject.text("kind")) {
                "personal" -> {
                    if (scopeObject.keys != setOf("kind")) return null
                    Scope.Personal
                }
                "company" -> {
                    if (!setOf("kind", "company_id", "workplace_id").containsAll(scopeObject.keys)) return null
                    val company = scopeObject.text("company_id")?.takeIf(uuid::matches) ?: return null
                    val workplace = if ("workplace_id" in scopeObject) scopeObject.text("workplace_id")?.takeIf(uuid::matches) ?: return null else null
                    Scope.Company(company, workplace)
                }
                else -> return null
            }
            return IsgMutationContext(operation, mutation, platform, build, version, scope)
        }
    }
}

/** Strict transport mirror of isg_workspace_context_v1; never an authorization decision. */
data class IsgWorkspaceContext(
    val workspaceId: String,
    val kind: String,
    val name: String,
    val status: String,
    val timezone: String,
    val workspaceVersion: Long,
    val membership: Membership,
    val canRead: Boolean,
    val canOperate: Boolean,
    val canManageMembers: Boolean,
    val canManageBilling: Boolean,
) {
    data class Membership(
        val membershipId: String, val userId: String, val role: String, val status: String,
        val isPracticingExpert: Boolean, val permissionRevision: Long, val membershipVersion: Long,
    )

    companion object {
        private val uuid = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        private val fields = setOf("schema_version", "workspace_id", "kind", "name", "status", "timezone",
            "workspace_version", "membership", "can_read", "can_operate", "can_manage_members", "can_manage_billing")
        private val memberFields = setOf("membership_id", "user_id", "role", "status", "is_practicing_expert",
            "permission_revision", "membership_version")
        private fun JsonObject.text(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
        private fun JsonObject.bool(key: String) = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
        private fun JsonObject.safeLong(key: String) = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull
            ?.takeIf { it in 0..9007199254740991L }

        fun parse(input: JsonElement): IsgWorkspaceContext? {
            val obj = input as? JsonObject ?: return null
            if (obj.keys != fields || obj.safeLong("schema_version") != 1L) return null
            val workspaceId = obj.text("workspace_id")?.takeIf(uuid::matches) ?: return null
            val kind = obj.text("kind")?.takeIf { it == "personal" || it == "osgb" } ?: return null
            val name = obj.text("name")?.takeIf { it.trim().isNotEmpty() && it.toByteArray().size <= 200 } ?: return null
            val status = obj.text("status")?.takeIf { it in setOf("active", "pending_purchase", "admin_trial", "admin_sponsored", "suspended", "archived") } ?: return null
            val timezone = obj.text("timezone")?.takeIf { it.isNotEmpty() && it.toByteArray().size <= 80 } ?: return null
            val version = obj.safeLong("workspace_version") ?: return null
            val member = obj["membership"] as? JsonObject ?: return null
            if (member.keys != memberFields) return null
            val membership = Membership(
                member.text("membership_id")?.takeIf(uuid::matches) ?: return null,
                member.text("user_id")?.takeIf(uuid::matches) ?: return null,
                member.text("role")?.takeIf { it in setOf("owner", "admin", "expert") } ?: return null,
                member.text("status")?.takeIf { it in setOf("active", "suspended", "ended") } ?: return null,
                member.bool("is_practicing_expert") ?: return null,
                member.safeLong("permission_revision") ?: return null,
                member.safeLong("membership_version") ?: return null,
            )
            val canRead = obj.bool("can_read") ?: return null
            val canOperate = obj.bool("can_operate") ?: return null
            val canManageMembers = obj.bool("can_manage_members") ?: return null
            val canManageBilling = obj.bool("can_manage_billing") ?: return null
            val readable = membership.status == "active" && status in setOf("active", "pending_purchase", "admin_trial", "admin_sponsored")
            val operable = membership.status == "active" && status in setOf("active", "admin_trial", "admin_sponsored")
            if (membership.isPracticingExpert && (kind != "osgb" || membership.status != "active")) return null
            if (kind == "personal" && (membership.role != "owner" || membership.status != "active" || membership.isPracticingExpert)) return null
            if (canRead != readable || canOperate != operable || canManageMembers != (readable && membership.role in setOf("owner", "admin")) ||
                canManageBilling != (readable && membership.role == "owner")) return null
            return IsgWorkspaceContext(workspaceId, kind, name, status, timezone, version, membership,
                canRead, canOperate, canManageMembers, canManageBilling)
        }
    }
}
