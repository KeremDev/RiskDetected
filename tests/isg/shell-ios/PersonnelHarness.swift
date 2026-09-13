import SwiftUI

#if !targetEnvironment(simulator)
#error("Synthetic personnel repository is simulator-only")
#endif

/// Isolated QA storage; never imported by the production app.
@MainActor final class PersonnelHarness: ObservableObject {
    private var rows: [UUID: NovaEmployeeRow] = [:]
    private var receipts: [UUID: NovaEmployeeCommit] = [:]
    private var departments: [NovaDepartmentRow] = []
    private var failed = false
    private let sampleID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private func sample(_ scope: NovaPersonnelScope) -> NovaEmployeeRow {
        .init(id: sampleID, ownerID: scope.ownerID, companyID: scope.companyID, name: "Ada Kaya", departmentID: nil, departmentName: nil, version: 0, isArchived: false)
    }
    var directory: NovaDirectoryClient {
        .init(read: { scope, kind, parent, _, _ in
            guard [.assignments, .employers].contains(kind), let id = parent,
                  (self.rows[id] ?? (id == self.sampleID ? self.sample(scope) : nil))?.companyID == scope.companyID else { throw NovaPersonnelFailure.denied }
            return .init(rows: [], next: nil, parentVersion: 0)
        }, save: { _ in throw NovaPersonnelFailure.denied }, pending: { _ in nil })
    }
    var client: NovaPersonnelClient {
        NovaPersonnelClient(employees: { scope, query, archived, _ in
            if ProcessInfo.processInfo.arguments.contains("--personnel-readonly") { return .init(rows: [self.sample(scope)], next: nil) }
            return .init(rows: self.rows.values.filter { $0.ownerID == scope.ownerID && $0.companyID == scope.companyID && (archived || !$0.isArchived) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }.sorted { $0.id.uuidString < $1.id.uuidString }, next: nil)
        }, departments: { scope, _, _ in
            .init(rows: self.departments.filter { $0.companyID == scope.companyID && $0.ownerID == scope.ownerID }, next: nil)
        }, detail: { scope, id in
            if ProcessInfo.processInfo.arguments.contains("--personnel-readonly"), id == self.sampleID { return self.sample(scope) }
            guard let row = self.rows[id], row.companyID == scope.companyID, row.ownerID == scope.ownerID else { throw NovaPersonnelFailure.denied }
            return row
        }, save: { intent in
            if let receipt = self.receipts[intent.mutationID] { return receipt }
            let old = intent.employeeID.flatMap { self.rows[$0] }
            let id = intent.employeeID ?? UUID()
            var depID = old?.departmentID, depName = old?.departmentName
            switch intent.department {
            case .keep: break
            case .none: depID = nil; depName = nil
            case .existing(let id):
                let d = self.departments.first { $0.id == id }; depID = d?.id; depName = d?.name
            case .new(let name):
                let d = self.departments.first { $0.name == name } ?? .init(id: UUID(), ownerID: intent.scope.ownerID, companyID: intent.scope.companyID, name: name)
                if !self.departments.contains(where: { $0.id == d.id }) { self.departments.append(d) }
                depID = d.id; depName = d.name
            }
            let version: Int64 = intent.action == .create ? 0 : intent.expectedVersion + 1
            let row = NovaEmployeeRow(id: id, ownerID: intent.scope.ownerID, companyID: intent.scope.companyID,
                name: intent.action == .archive ? old!.name : intent.name, departmentID: depID, departmentName: depName,
                version: version, isArchived: intent.action == .archive)
            self.rows[id] = row
            let receipt = NovaEmployeeCommit(operationID: intent.operationID, id: id, ownerID: row.ownerID, companyID: row.companyID, version: version, isArchived: row.isArchived)
            self.receipts[intent.mutationID] = receipt
            // Commit followed by lost response, not a no-op failure.
            if ProcessInfo.processInfo.arguments.contains("--personnel-retry") && !self.failed { self.failed = true; throw NovaPersonnelFailure.unavailable }
            return receipt
        })
    }
}
