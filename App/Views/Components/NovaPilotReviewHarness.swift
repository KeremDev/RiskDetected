#if DEBUG && NOVA_PILOT_BUILD && targetEnvironment(simulator)
import SwiftUI

/// Explicit simulator-only visual fixture. No SDK, network, Keychain or real records.
@MainActor private final class NovaReviewStorage: PersonnelPendingStorage {
    var values: [String: Data] = [:]
    func read(account: String) throws -> Data? { values[account] }
    func write(_ data: Data, account: String) throws { values[account] = data }
    func remove(account: String) throws { values[account] = nil }
}

struct NovaPilotReviewHarness: View {
    private static let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private static let session = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    private static let company = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    private static let employee = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    @State private var selected = false
    @State private var create = false
    @State private var navigation = NovaNavigationState(epoch: "review-only", available: [.companies])
    private var identity: NovaSessionIdentity { .init(userID: Self.owner, sessionID: Self.session) }
    private var scope: NovaPersonnelScope { .init(ownerID: Self.owner, sessionID: Self.session, companyID: Self.company, epoch: "review-only") }
    private var row: NovaEmployeeRow { .init(id: Self.employee, ownerID: Self.owner, companyID: Self.company, name: "Ada Kaya", departmentID: nil, departmentName: nil, version: 0, isArchived: false) }
    private var personnel: NovaPersonnelClient {
        .init(employees: { _, _, _, _ in .init(rows: [row], next: nil) }, departments: { _, _, _ in .init(rows: [], next: nil) },
              detail: { _, _ in row }, save: { _ in throw NovaPersonnelFailure.unavailable })
    }
    private var directory: NovaDirectoryClient {
        .init(read: { _, kind, _, _, _ in
            let rows: [NovaDirectoryRow] = kind == .workplaces ? [.init(id: Self.company,
                fields: ["name": .string("Merkez"), "code": .string("W-hidden-internal-code")])] : []
            return .init(rows: rows, next: nil, parentVersion: nil)
        },
              save: { _ in throw NovaPersonnelFailure.unavailable }, pending: { _ in nil })
    }
    private var summary: NovaPilotCompanySummary {
        .init(id: Self.company, owner_id: Self.owner, name: "Örnek Metal A.Ş.", hazard_class: "high", is_archived: false,
              sector: "Metal sanayi", email: "info@example.test", declared_employee_count: 25, responsible_employee_id: Self.employee,
              personnel_count: 1, workplace_count: 1, department_count: 0, finding_count: nil, document_count: nil, completion_score: nil)
    }
    var body: some View {
        NovaExpertShell(navigation: $navigation, userName: "Tasarım Provası", connectionLabel: "Sentetik veriler · canlı bağlantı yok",
            onCompanyCreate: { create = true },
            onDestination: { destination in if destination == .companies { selected = false } }) { _ in
            if selected {
                NovaCompanyWorkspace(scope: scope, companyName: summary.name, canWrite: true, personnel: personnel, directory: directory,
                    onBack: { selected = false }, loadSummary: { summary })
            } else {
                NovaCompaniesScreen(companies: [.init(id: Self.company.uuidString, name: summary.name, detail: "Metal sanayi · Çok tehlikeli")],
                    isOwnedList: true, onSelect: { _ in selected = true }, onBack: {}, onRetry: {}, onCreate: { create = true })
            }
        }
        .fullScreenCover(isPresented: $create) {
            NovaPopup {
            NovaPilotCompanyCreateView(identity: identity,
                service: .init(rpc: { _, _ in
                    Data("{\"schema_version\":2,\"company\":{\"id\":\"\(Self.company)\",\"user_id\":\"\(Self.owner)\",\"name\":\"Fixture company\",\"hazard_class\":\"medium\",\"is_archived\":false},\"replayed\":false}".utf8)
                }, currentIdentity: { identity }, storage: NovaReviewStorage()), onCreated: { _ in })
            }
        }
        .modifier(NovaSuccessPresentation())
    }
}
#endif
