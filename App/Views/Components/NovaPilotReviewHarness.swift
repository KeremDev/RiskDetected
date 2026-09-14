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
    @State private var navigation = NovaNavigationState(epoch: "review-only", available: [.companies, .findings, .newFinding])
    @State private var analysisRoute: AnalysisReviewRoute = .intake
    @State private var draft = NovaAnalysisIntakeDraft()
    /// Review-only: assigning in the fixture flips the same screen into its
    /// with-a-company shape, so the transfer step can be seen as well.
    @State private var reviewAssigned = false
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
            onDestination: { destination in if destination == .companies { selected = false } }) { destination in
            if destination == .findings || destination == .newFinding {
                analysisReview
            } else if selected {
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

    // MARK: synthetic analysis surface

    enum AnalysisReviewRoute: String, CaseIterable, Identifiable {
        case intake, detail, manual, list
        var id: String { rawValue }
        var title: String {
            switch self {
            case .intake: return "Fotoğraf akışı"
            case .detail: return "Analiz detayı"
            case .manual: return "Elle giriş"
            case .list: return "Analizlerim"
            }
        }
    }

    private static let workplace = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
    private static let analysis = UUID(uuidString: "00000000-0000-4000-8000-000000000006")!

    @ViewBuilder private var analysisReview: some View {
        VStack(spacing: 0) {
            Picker("", selection: $analysisRoute) {
                ForEach(AnalysisReviewRoute.allCases) { route in Text(verbatim: route.title).tag(route) }
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 8)
            switch analysisRoute {
            case .intake:
                NovaAnalysisIntakeScreen(companies: reviewCompanies, sectors: NovaPilotFindingsGate.sectorOptions,
                    focuses: reviewFocuses, draft: $draft, onCancel: {}, onStart: {})
                    .onAppear { if draft.photoCount == 0 { draft.photoCount = 2 } }
            case .detail:
                NovaAnalysisDetailScreen(analysisID: Self.analysis, client: reviewDetailClient, onBack: {})
            case .manual:
                NovaManualNonconformityScreen(workplaces: reviewWorkplaces, save: { _ in nil }, onBack: {})
            case .list:
                NovaAnalysisListScreen(load: { reviewSummaries }, onOpen: { _ in analysisRoute = .detail }, onBack: {})
            }
        }
    }

    private var reviewCompanies: [NovaAnalysisCompanyOption] {
        [.init(id: Self.company, name: summary.name, detail: "1 işyeri · 1 personel", sector: "İmalat / Fabrika"),
         .init(id: Self.employee, name: "Bilinmeyen Sektör Ltd.", detail: "2 işyeri · 8 personel", sector: "Tekstil")]
    }
    private var reviewFocuses: [NovaAnalysisFocusOption] {
        AnalysisCanvas.all.prefix(6).map { canvas in
            .init(id: canvas.id, title: canvas.title, detail: canvas.body, symbol: canvas.icon,
                  isLocked: canvas.minTier != .free, lockLabel: canvas.minTier.title)
        }
    }
    private var reviewWorkplaces: [NovaNonconformityWorkplace] {
        [.init(id: Self.workplace, name: "Merkez tesis", needs_review: false)]
    }
    private var reviewSummaries: [NovaAnalysisSummary] {
        [.init(id: Self.analysis, title: "Saha turu · 2 fotoğraf", createdOn: "14 Eylül 2026 · 10:20",
               companyName: nil, findingCount: 3),
         .init(id: Self.employee, title: "Depo kontrolü", createdOn: "13 Eylül 2026 · 16:05",
               companyName: summary.name, findingCount: 5)]
    }
    private var reviewDetailClient: NovaAnalysisDetailClient {
        .init(load: { reviewDetail }, companies: { reviewCompanies }, assign: { _ in reviewAssigned = true },
              workplaces: { _ in reviewWorkplaces }, file: { _ in .opened }, edit: { _ in },
              report: { _ in "ornek-rapor.pdf" })
    }
    /// A synthetic analysis that deliberately carries one unreadable band and
    /// one unscored section, so both refusals can be seen in review.
    private var reviewDetail: NovaAnalysisDetailData {
        let risk = NovaAnalysisSection(kind: .riskAnalysis, items: [
            .init(id: UUID(), ordinal: 1, title: "Korkuluk eksik", category: "Yüksekte çalışma",
                  body: "Platform kenarında korkuluk yok.", measure: "Korkuluk montajı yapılacak.",
                  references: "6331 sayılı Kanun md.4", band: "high", score: 270),
            .init(id: UUID(), ordinal: 2, title: "Pano önü kapalı", category: "Elektrik",
                  body: "Elektrik panosunun önü malzeme ile kapatılmış.", measure: "Pano önü boşaltılacak.",
                  references: nil, band: "critical", score: 600),
            .init(id: UUID(), ordinal: 3, title: "Okunamayan bulgu", category: nil,
                  body: "Bandı hesaplanamadı.", measure: nil, references: nil, band: "unknown", score: nil),
        ], isTeaser: false)
        let expert = NovaAnalysisSection(kind: .expertRecommendations, items: [
            .init(id: UUID(), ordinal: 1, title: "Saha turu sıklığı artırılmalı", category: nil,
                  body: "Haftalık tur önerilir.", measure: nil, references: nil, band: nil, score: nil),
            .init(id: UUID(), ordinal: 2, title: "Acil çıkış tatbikatı", category: nil,
                  body: "Yıllık tatbikat planlanmalı.", measure: nil, references: nil, band: nil, score: nil),
        ], isTeaser: false)
        let training = NovaAnalysisSection(kind: .trainingRecommendations, items: [
            .init(id: UUID(), ordinal: 1, title: "Yüksekte çalışma eğitimi", category: nil,
                  body: "16 saat · temel", measure: nil, references: nil, band: nil, score: nil),
        ], isTeaser: true)
        let notebook = NovaAnalysisSection(kind: .approvedNotebook, items: [
            .init(id: UUID(), ordinal: 1, title: "Onaylı defter kaydı", category: nil,
                  body: "Tespit edilen eksiklikler işverene bildirilmiştir.", measure: nil,
                  references: nil, band: nil, score: nil),
        ], isTeaser: false)
        return .init(analysisID: Self.analysis, title: "Saha turu · 2 fotoğraf",
            createdOn: "14 Eylül 2026 · 10:20", methodLabel: "Fine-Kinney", method: .fineKinney,
            companyID: reviewAssigned ? Self.company : nil,
            companyName: reviewAssigned ? summary.name : nil, sections: [risk, expert, training, notebook],
            isProjectionMissing: false)
    }
}
#endif
