package com.riskdetectedan.core.data.isg

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
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
