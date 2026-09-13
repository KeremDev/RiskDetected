package com.riskdetectedan.core.data.company

import com.riskdetectedan.core.data.isg.IsgMutationContext
import java.text.Normalizer
import kotlinx.serialization.json.*

/** Name-only company intake, without implied authorization or network writes. */
data class IsgEmployeeCreate(val context: IsgMutationContext, val fullName: String, val department: Department?) {
    sealed interface Department {
        data class Existing(val id: String) : Department
        data class New(val name: String) : Department
    }
    companion object {
        private val uuid = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        private fun JsonElement?.string() = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
        private fun text(input: String?, limit: Int): String? {
            if (input == null || input.toByteArray(Charsets.UTF_8).size > 4096) return null
            val value = Normalizer.normalize(input, Normalizer.Form.NFC).replace(Regex("[ \\t\\r\\n]+"), " ").trim(' ')
            return value.takeIf { it.isNotBlank() && it.toByteArray(Charsets.UTF_8).size <= limit && it.none { c -> c.code < 32 || c.code == 127 || c.code == 0x200B || c.code == 0xFEFF } }
        }
        fun parse(input: JsonElement): IsgEmployeeCreate? {
            val obj = input as? JsonObject ?: return null
            if (!setOf("context", "full_name", "department").containsAll(obj.keys)) return null
            val context = IsgMutationContext.parse(obj["context"] ?: return null) ?: return null
            val scope = context.scope as? IsgMutationContext.Scope.Company ?: return null
            if (scope.workplaceId != null || context.expectedVersion != 0L) return null
            val name = text(obj["full_name"].string(), 200) ?: return null
            val d = obj["department"]
            val department = if (d == null || d == JsonNull) null else {
                val value = d as? JsonObject ?: return null
                when (value["kind"].string()) {
                    "existing" -> {
                        if (value.keys != setOf("kind", "id")) return null
                        Department.Existing(value["id"].string()?.takeIf(uuid::matches) ?: return null)
                    }
                    "new" -> {
                        if (value.keys != setOf("kind", "name")) return null
                        Department.New(text(value["name"].string(), 120) ?: return null)
                    }
                    else -> return null
                }
            }
            return IsgEmployeeCreate(context, name, department)
        }
    }
}
