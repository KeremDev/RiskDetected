package com.riskdetectedan.core.data.company

import com.riskdetectedan.core.data.isg.IsgMutationContext
import kotlinx.serialization.json.*

/** Domain request validation only, no implied authorization or remote mutation. */
data class IsgAssignmentMove(val context: IsgMutationContext, val employeeId: String,
    val previousAssignmentId: String?, val departmentId: String, val jobRoleId: String, val startsOn: String) {
    companion object {
        private val fields = setOf("context","employee_id","previous_assignment_id","department_id","job_role_id","starts_on")
        private val uuid = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        private fun JsonObject.text(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
        fun parse(input: JsonElement): IsgAssignmentMove? {
            val obj = input as? JsonObject ?: return null
            if (obj.keys != fields) return null
            val context = IsgMutationContext.parse(obj.getValue("context")) ?: return null
            val scope = context.scope as? IsgMutationContext.Scope.Company ?: return null
            if (scope.workplaceId == null || context.expectedVersion >= 9007199254740991L) return null
            val employee = obj.text("employee_id")?.takeIf(uuid::matches) ?: return null
            val department = obj.text("department_id")?.takeIf(uuid::matches) ?: return null
            val job = obj.text("job_role_id")?.takeIf(uuid::matches) ?: return null
            val previous = if (obj["previous_assignment_id"] == JsonNull) null else obj.text("previous_assignment_id")?.takeIf(uuid::matches) ?: return null
            val date = obj.text("starts_on")?.takeIf(::validDate) ?: return null
            return IsgAssignmentMove(context,employee,previous,department,job,date)
        }
        private fun validDate(value: String): Boolean {
            if (!Regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$").matches(value)) return false
            val (y,m,d) = value.split('-').map(String::toInt)
            if (y < 1 || m !in 1..12) return false
            val leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
            return d in 1..intArrayOf(31,if(leap) 29 else 28,31,30,31,30,31,31,30,31,30,31)[m-1]
        }
    }
}
