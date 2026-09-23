package com.riskdetectedan.core.designsystem.isg

import java.util.UUID

data class NovaPersonnelScope(val ownerID: UUID, val sessionID: UUID, val companyID: UUID, val epoch: String)
data class NovaEmployeeRow(val id: UUID, val ownerID: UUID, val companyID: UUID, val name: String,
    val departmentID: UUID?, val departmentName: String?, val version: Long, val isArchived: Boolean, val jobTitle: String? = null)
data class NovaDepartmentRow(val id: UUID, val ownerID: UUID, val companyID: UUID, val name: String)
data class NovaEmployeePage(val rows: List<NovaEmployeeRow>, val next: UUID?)
data class NovaDepartmentPage(val rows: List<NovaDepartmentRow>, val next: UUID?)
sealed interface NovaEmployeeDepartment {
    data object Keep: NovaEmployeeDepartment
    data object None: NovaEmployeeDepartment
    data class Existing(val id: UUID): NovaEmployeeDepartment
    data class New(val name: String): NovaEmployeeDepartment
}
data class NovaEmployeeCommit(val operationID: UUID, val id: UUID, val ownerID: UUID, val companyID: UUID, val version: Long, val isArchived: Boolean)
data class NovaEmployeeIntent(val operationID: UUID, val mutationID: UUID, val scope: NovaPersonnelScope,
    val action: Action, val employeeID: UUID?, val expectedVersion: Long, val name: String, val department: NovaEmployeeDepartment) {
    enum class Action { create, edit, archive, restore }
}
class NovaPersonnelFailure(val kind: Kind): Exception() {
    enum class Kind { denied, validation, conflict, selectionRequired, unavailable }
}
class NovaPersonnelClient(
    val employees: suspend (NovaPersonnelScope, String, Boolean, UUID?) -> NovaEmployeePage,
    val departments: suspend (NovaPersonnelScope, String, UUID?) -> NovaDepartmentPage,
    val detail: suspend (NovaPersonnelScope, UUID) -> NovaEmployeeRow,
    val save: suspend (NovaEmployeeIntent) -> NovaEmployeeCommit,
    val pending: suspend (NovaPersonnelScope) -> NovaEmployeeIntent? = { null },
)
data class NovaEmployeeEditorState(val name: String = "", val departmentText: String = "",
    val selectedDepartment: NovaDepartmentRow? = null, val phase: Phase = Phase.editing,
    val pending: NovaEmployeeIntent? = null, val saved: NovaEmployeeCommit? = null) {
    enum class Phase { editing, submitting, uncertain, committed, denied }
    val canEdit get() = phase == Phase.editing
    val canSubmit get() = canEdit && name.isNotBlank()
    fun begin(scope: NovaPersonnelScope, original: NovaEmployeeRow?, archive: Boolean = false, restore: Boolean = false): NovaEmployeeEditorState {
        if (!canEdit || (!archive && !canSubmit)) return this
        if (archive && original == null) return this
        if (restore && (original?.isArchived != true || archive)) return this
        if (original != null && (original.ownerID != scope.ownerID || original.companyID != scope.companyID || (original.isArchived && !restore))) return this
        if (original != null && (original.version < 0 || original.version >= 9007199254740991L)) return this
        val selected = selectedDepartment
        if (selected != null && (selected.ownerID != scope.ownerID || selected.companyID != scope.companyID)) return this
        val department = if (original != null && selected?.id == original.departmentID && departmentText.isBlank()) NovaEmployeeDepartment.Keep else selected?.let { NovaEmployeeDepartment.Existing(it.id) }
            ?: departmentText.trim().takeIf { it.isNotEmpty() }?.let { NovaEmployeeDepartment.New(it) } ?: NovaEmployeeDepartment.None
        return copy(phase = Phase.submitting, pending = NovaEmployeeIntent(UUID.randomUUID(), UUID.randomUUID(), scope,
            if (restore) NovaEmployeeIntent.Action.restore else if (archive) NovaEmployeeIntent.Action.archive else if (original == null) NovaEmployeeIntent.Action.create else NovaEmployeeIntent.Action.edit,
            original?.id, original?.version ?: 0, name, if (restore) NovaEmployeeDepartment.Keep else department))
    }
    fun retry(scope: NovaPersonnelScope) = if (phase == Phase.uncertain && pending?.scope == scope) copy(phase = Phase.submitting) else this
    fun complete(intent: NovaEmployeeIntent, row: NovaEmployeeCommit, scope: NovaPersonnelScope): NovaEmployeeEditorState {
        if (phase != Phase.submitting || pending != intent || scope != intent.scope || row.operationID != intent.operationID || row.ownerID != scope.ownerID || row.companyID != scope.companyID || (intent.employeeID != null && intent.employeeID != row.id)) return this
        val expected = if (intent.action == NovaEmployeeIntent.Action.create) 0 else intent.expectedVersion + 1
        if (row.version != expected || row.isArchived != (intent.action == NovaEmployeeIntent.Action.archive)) return uncertain(intent, scope)
        return copy(phase = Phase.committed, saved = row)
    }
    fun uncertain(intent: NovaEmployeeIntent, scope: NovaPersonnelScope) = if (pending == intent && scope == intent.scope && phase == Phase.submitting) copy(phase = Phase.uncertain) else this
    fun reject(intent: NovaEmployeeIntent, scope: NovaPersonnelScope, denied: Boolean) = if (pending == intent && scope == intent.scope && phase == Phase.submitting)
        copy(pending = null, phase = if (denied) Phase.denied else Phase.editing) else this
}
