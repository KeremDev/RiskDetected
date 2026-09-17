import Foundation

struct NovaPersonnelScope: Equatable, Hashable, Codable {
    let ownerID: UUID
    let sessionID: UUID
    let companyID: UUID
    let epoch: String
}
struct NovaEmployeeRow: Equatable, Identifiable {
    let id: UUID
    let ownerID: UUID
    let companyID: UUID
    let name: String
    let departmentID: UUID?
    let departmentName: String?
    /// Optional until the assignment endpoint is wired; the pilot UI can still preview it.
    var jobTitle: String? = nil
    let version: Int64
    let isArchived: Bool
    var fullName: String { name }
}
struct NovaDepartmentRow: Equatable, Identifiable {
    let id: UUID
    let ownerID: UUID
    let companyID: UUID
    let name: String
}
struct NovaEmployeePage { let rows: [NovaEmployeeRow]; let next: UUID? }
struct NovaDepartmentPage { let rows: [NovaDepartmentRow]; let next: UUID? }
enum NovaEmployeeDepartment: Equatable, Codable { case keep, none, existing(UUID), new(String) }
struct NovaEmployeeCommit: Equatable {
    let operationID: UUID
    let id: UUID; let ownerID: UUID; let companyID: UUID; let version: Int64; let isArchived: Bool
}
struct NovaEmployeeIntent: Equatable, Codable {
    enum Action: String, Codable { case create, edit, archive, restore }
    let operationID: UUID
    let mutationID: UUID
    let scope: NovaPersonnelScope
    let action: Action
    let employeeID: UUID?
    let expectedVersion: Int64
    let name: String
    let department: NovaEmployeeDepartment
}
enum NovaPersonnelFailure: Error { case denied, validation, conflict, selectionRequired, unavailable }

/// Closure-based boundary; a production adapter or an explicitly synthetic test repository is injected.
@MainActor struct NovaPersonnelClient {
    let employees: (NovaPersonnelScope, String, Bool, UUID?) async throws -> NovaEmployeePage
    let departments: (NovaPersonnelScope, String, UUID?) async throws -> NovaDepartmentPage
    let detail: (NovaPersonnelScope, UUID) async throws -> NovaEmployeeRow
    let save: (NovaEmployeeIntent) async throws -> NovaEmployeeCommit
    var pending: (NovaPersonnelScope) async throws -> NovaEmployeeIntent? = { _ in nil }
}

struct NovaEmployeeEditorState {
    enum Phase: Equatable { case editing, submitting, uncertain, committed, denied }
    var name = ""
    var departmentText = ""
    var selectedDepartment: NovaDepartmentRow?
    private(set) var phase: Phase = .editing
    private(set) var pending: NovaEmployeeIntent?
    private(set) var saved: NovaEmployeeCommit?
    var canEdit: Bool { phase == .editing }
    var canSubmit: Bool { canEdit && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    mutating func begin(scope: NovaPersonnelScope, original: NovaEmployeeRow?, archive: Bool = false, restore: Bool = false) -> NovaEmployeeIntent? {
        guard canEdit, archive || canSubmit else { return nil }
        guard !archive || original != nil else { return nil }
        guard !restore || (original?.isArchived == true && !archive) else { return nil }
        if let original, original.ownerID != scope.ownerID || original.companyID != scope.companyID || (original.isArchived && !restore) { return nil }
        if let original, original.version < 0 || original.version >= 9007199254740991 { return nil }
        if let selectedDepartment, selectedDepartment.ownerID != scope.ownerID || selectedDepartment.companyID != scope.companyID { return nil }
        let department: NovaEmployeeDepartment
        if let original, selectedDepartment?.id == original.departmentID, departmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            department = .keep
        } else if let selectedDepartment {
            guard selectedDepartment.ownerID == scope.ownerID, selectedDepartment.companyID == scope.companyID else { return nil }
            department = .existing(selectedDepartment.id)
        } else {
            let text = departmentText.trimmingCharacters(in: .whitespacesAndNewlines)
            department = text.isEmpty ? .none : .new(text)
        }
        let intent = NovaEmployeeIntent(operationID: UUID(), mutationID: UUID(), scope: scope,
            action: restore ? .restore : archive ? .archive : original == nil ? .create : .edit, employeeID: original?.id,
            expectedVersion: original?.version ?? 0, name: name, department: restore ? .keep : department)
        pending = intent; phase = .submitting
        return intent
    }
    mutating func retry(scope: NovaPersonnelScope) -> NovaEmployeeIntent? {
        guard phase == .uncertain, let pending, pending.scope == scope else { return nil }
        phase = .submitting
        return pending // A transport failure must never silently allocate a second employee.
    }
    mutating func complete(_ intent: NovaEmployeeIntent, row: NovaEmployeeCommit, scope: NovaPersonnelScope) -> Bool {
        guard phase == .submitting, pending == intent, scope == intent.scope, row.operationID == intent.operationID,
              row.ownerID == scope.ownerID, row.companyID == scope.companyID,
              intent.employeeID == nil || intent.employeeID == row.id else { return false }
        let expected = intent.action == .create ? 0 : intent.expectedVersion + 1
        guard row.version == expected, row.isArchived == (intent.action == .archive) else { uncertain(intent, scope: scope); return false }
        saved = row; phase = .committed; return true
    }
    mutating func uncertain(_ intent: NovaEmployeeIntent, scope: NovaPersonnelScope) {
        guard pending == intent, scope == intent.scope, phase == .submitting else { return }
        phase = .uncertain
    }
    mutating func reject(_ intent: NovaEmployeeIntent, scope: NovaPersonnelScope, denied: Bool) {
        guard pending == intent, scope == intent.scope, phase == .submitting else { return }
        pending = nil; phase = denied ? .denied : .editing
    }
}
