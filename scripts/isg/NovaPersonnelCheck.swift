import Foundation
@main enum NovaPersonnelCheck {
    static func main() {
        let scope = NovaPersonnelScope(ownerID: UUID(), sessionID: UUID(), companyID: UUID(), epoch: "first")
        let other = NovaPersonnelScope(ownerID: scope.ownerID, sessionID: UUID(), companyID: scope.companyID, epoch: "next")
        var state = NovaEmployeeEditorState()
        precondition(state.begin(scope: scope, original: nil) == nil)
        state.name = "Ada Kaya"
        let intent = state.begin(scope: scope, original: nil)!
        precondition(intent.department == .none && intent.expectedVersion == 0 && intent.employeeID == nil)
        precondition(intent.operationID != intent.mutationID && !state.canEdit)
        precondition(state.begin(scope: scope, original: nil) == nil)
        state.uncertain(intent, scope: scope)
        precondition(state.retry(scope: other) == nil)
        precondition(state.retry(scope: scope) == intent)
        let commit = NovaEmployeeCommit(operationID: intent.operationID, id: UUID(), ownerID: scope.ownerID, companyID: scope.companyID, version: 0, isArchived: false)
        precondition(!state.complete(intent, row: commit, scope: other))
        precondition(state.complete(intent, row: commit, scope: scope))
        precondition(state.phase == .committed && state.retry(scope: scope) == nil)
        let department = NovaDepartmentRow(id: UUID(), ownerID: scope.ownerID, companyID: scope.companyID, name: "Bakım")
        let row = NovaEmployeeRow(id: commit.id, ownerID: scope.ownerID, companyID: scope.companyID, name: "Ada", departmentID: department.id, departmentName: department.name, version: 5, isArchived: false)
        state = NovaEmployeeEditorState(); state.name = "Ada Kaya"; state.selectedDepartment = department
        precondition(state.begin(scope: scope, original: row)!.department == .keep)
        state = NovaEmployeeEditorState(); state.name = "Ada Kaya"
        precondition(state.begin(scope: scope, original: row)!.department == .none)
        state = NovaEmployeeEditorState(); state.name = "Ada Kaya"; state.departmentText = " Yeni birim "
        precondition(state.begin(scope: scope, original: nil)!.department == .new("Yeni birim"))
        state = NovaEmployeeEditorState(); state.name = "Ada Kaya"
        let archive = state.begin(scope: scope, original: row, archive: true)!
        precondition(archive.action == .archive && archive.expectedVersion == 5)
        let wrongVersion = NovaEmployeeCommit(operationID: archive.operationID, id: row.id, ownerID: scope.ownerID, companyID: scope.companyID, version: 5, isArchived: true)
        precondition(!state.complete(archive, row: wrongVersion, scope: scope) && state.phase == .uncertain)
        precondition(state.retry(scope: scope) == archive)
        state.reject(archive, scope: scope, denied: true)
        precondition(state.phase == .denied && state.pending == nil && !state.canSubmit)
        state = NovaEmployeeEditorState(); state.name = "Ada"
        state.selectedDepartment = .init(id: UUID(), ownerID: UUID(), companyID: scope.companyID, name: "Foreign")
        precondition(state.begin(scope: scope, original: nil) == nil)
        print("Swift personnel editor: 18 invariant groups PASS")
    }
}
