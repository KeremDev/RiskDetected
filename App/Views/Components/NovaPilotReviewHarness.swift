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
    @State private var riskPopup = false
    @State private var navigation = NovaNavigationState(epoch: "review-only", available: [.riskAssessments, .emergencyPlans, .statistics, .companies, .findings, .newFinding, .analyses, .newAnalysis, .documentChecklist, .documents, .periodicChecks])
    @State private var draft = NovaAnalysisIntakeDraft()
    @State private var showingReviewReports = false
    @State private var reviewImages: [UIImage] = []
    @State private var reviewRecord: NovaNonconformityEntry?
    @State private var showingReviewDetail = false
    @State private var showingIntake = false
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
    private var reviewRiskRow: NovaRiskRow {
        .init(id: Self.employee, companyID: Self.company, companyName: "Örnek Metal A.Ş.",
            workplaceID: Self.company, workplaceName: "Örnek Metal A.Ş.", currentVersion: CommandLine.arguments.contains("RD_UI_TEST_POPUP_NEW") ? 0 : 1,
            baseAssessmentOn: "2026-01-01", validUntil: "2028-01-01", state: .valid, group: .current,
            noticeDays: 30, currentKind: .full, currentAssessmentOn: "2026-01-01", currentRevisionOn: nil,
            currentFileAssetID: nil, periodYears: 2, periodSource: nil, periodNeedsReview: false,
            dateNeedsReview: false, sourceDrift: false, driftNote: nil, workplaceHazardClass: "high",
            workplaceSuggestedPeriodYears: 2, hasOpenDraft: false, draftVersion: nil, draftKind: nil,
            draftAssessmentOn: nil, draftReason: nil, sourceLinkCount: 0, versions: [])
    }
    private var reviewRiskClient: NovaRiskClient {
        .init(catalogue: { _ in .init(workplaces: [.init(id: Self.company, name: "Merkez", needsReview: false, hazardClass: "high", suggestedPeriodYears: 2)], rules: [], noticeDays: 30, expertPeriodNeedsReview: false) },
            board: { query in
                let matches = (query.company == nil || query.company == Self.company) && (query.state == nil || query.state == "valid" || query.state == "current")
                return .init(rows: matches ? [reviewRiskRow] : [], counts: ["valid": 1], companies: [], total: matches ? 1 : 0, hasMore: false, offset: 0, noticeDays: 30)
            },
            companies: { reviewCompanies }, detail: { _ in reviewRiskRow }, open: { _,_ in reviewRiskRow },
            draft: { _,_ in reviewRiskRow }, finalize: { _,_ in reviewRiskRow }, fileClient: reviewFileClient)
    }
    private var reviewEmergencyClient: NovaEmergencyClient {
        .init(catalogue: { _ in .init(workplaces: [], roles: [], supportStaff: [], noticeDays: 30, periodDefaultsOffered: true) },
            board: { _ in .init(rows: [], counts: [:], companies: [], total: 0, hasMore: false, offset: 0, noticeDays: 30) },
            companies: { reviewCompanies }, detail: { _ in throw NovaEmergencyFailure.unavailable },
            publish: { _,_ in throw NovaEmergencyFailure.unavailable }, fileClient: reviewFileClient)
    }
    var body: some View {
        Group {
        if CommandLine.arguments.contains("RD_UI_TEST_AUDIT_ANALYSIS") {
            analysisReview(.analyses)
        } else if CommandLine.arguments.contains("RD_UI_TEST_AUDIT_FINDING") {
            analysisReview(.findings)
        } else {
        NovaExpertShell(navigation: $navigation, userName: "Tasarım Provası", connectionLabel: "Sentetik veriler · canlı bağlantı yok",
            onCompanyCreate: { create = true },
            onDestination: { destination in if destination == .companies { selected = false } }) { destination in
            if destination == .riskAssessments {
                NovaRiskScreen(client: reviewRiskClient, onBack: { navigation.apply(.navigate(.home), from: navigation.epoch) })
            } else if destination == .emergencyPlans {
                NovaEmergencyPlanScreen(client: reviewEmergencyClient, onBack: { navigation.apply(.navigate(.home), from: navigation.epoch) })
            } else if destination == .statistics {
                NovaStatisticsScreen(load: { company, months in
                    if CommandLine.arguments.contains("RD_UI_TEST_STATISTICS_ERROR") { throw NovaPersonnelFailure.unavailable }
                    return NovaStatisticsReview.snapshot(owner: Self.owner, company: company, months: months,
                        empty: CommandLine.arguments.contains("RD_UI_TEST_STATISTICS_EMPTY"))
                }, onBack: { navigation.apply(.navigate(.home), from: navigation.epoch) },
                    onNavigate: { navigation.apply(.navigate($0), from: navigation.epoch) })
            } else if [.findings, .newFinding, .analyses, .newAnalysis, .documentChecklist, .documents, .periodicChecks].contains(destination) {
                analysisReview(destination)
            } else if selected {
                NovaCompanyWorkspace(scope: scope, companyName: summary.name, canWrite: true, personnel: personnel, directory: directory,
                    onBack: { selected = false }, loadSummary: { summary },
                    loadNonconformities: { reviewEntries.map(\.row) },
                    onOpenNonconformities: { navigation.apply(.navigate(.findings), from: navigation.epoch) })
            } else {
                NovaCompaniesScreen(companies: [.init(id: Self.company.uuidString, name: summary.name, detail: "Metal sanayi · Çok tehlikeli")],
                    isOwnedList: true, onSelect: { _ in selected = true }, onBack: {}, onRetry: {}, onCreate: { create = true })
            }
            }
        }
        }
        .novaPopupCover(isPresented: $create) {
            NovaPopup {
            NovaPilotCompanyCreateView(identity: identity,
                service: .init(rpc: { endpoint, _ in
                    Data("{\"schema_version\":\(endpoint.hasSuffix("v3") ? 3 : 2),\"company\":{\"id\":\"\(Self.company)\",\"user_id\":\"\(Self.owner)\",\"name\":\"Fixture company\",\"hazard_class\":\"medium\",\"is_archived\":false},\"replayed\":false}".utf8)
                }, currentIdentity: { identity }, storage: NovaReviewStorage()), onCreated: { _ in })
            }
        }
        // Opened straight into its create form, so the screen is a NovaPopup
        // from its first frame and arrives like one.
        .novaPopupCover(isPresented: $riskPopup) {
            NovaRiskScreen(client: reviewRiskClient, onBack: { riskPopup = false },
                initialCompany: CommandLine.arguments.contains("RD_UI_TEST_POPUP_SELECTED") ? Self.company : nil,
                startInAddMode: true)
        }
        .modifier(NovaSuccessPresentation())
        .onAppear {
            if CommandLine.arguments.contains("RD_UI_TEST_RISK_LIST") { navigation.apply(.navigate(.riskAssessments), from: navigation.epoch) }
            if CommandLine.arguments.contains("RD_UI_TEST_EMERGENCY_LIST") { navigation.apply(.navigate(.emergencyPlans), from: navigation.epoch) }
            if CommandLine.arguments.contains("RD_UI_TEST_RISK_POPUP") { riskPopup = true }
            if CommandLine.arguments.contains("RD_UI_TEST_USABILITY_POPUP") { create = true }
            if CommandLine.arguments.contains("RD_UI_TEST_STATISTICS") {
                navigation.apply(.navigate(.statistics), from: navigation.epoch)
            } else if CommandLine.arguments.contains("RD_UI_TEST_PERIODIC") {
                navigation.apply(.navigate(.periodicChecks), from: navigation.epoch)
            } else if CommandLine.arguments.contains("RD_UI_TEST_AUDIT_ANALYSIS") {
                navigation.apply(.navigate(.analyses), from: navigation.epoch)
            } else if CommandLine.arguments.contains("RD_UI_TEST_AUDIT_FINDING") {
                navigation.apply(.navigate(.findings), from: navigation.epoch)
            }
        }
    }

    // MARK: synthetic analysis surface

    /// Rendered per destination, exactly the way the drawer reaches them, so
    /// the review build has no menu of its own.
    @ViewBuilder private func analysisReview(_ destination: NovaDestination) -> some View {
        switch destination {
        case .findings:
            NovaNonconformityListScreen(client: .init(load: { reviewEntries },
                thumbnail: { _ in Self.fixturePhoto },
                open: { entry in reviewRecord = entry }, create: { navigation.apply(.navigate(.newFinding), from: navigation.epoch) }),
                companies: reviewCompanies, today: "2026-09-14", onBack: {})
                .novaPopupCover(item: $reviewRecord) { entry in
                    NovaPopup {
                        NovaNonconformityRecordSheet(entry: entry, client: .init(
                            load: { entry.row }, transition: { _, _, _ in entry.row },
                            addAction: { _, _, _ in entry.row }, verify: { _, _ in entry.row },
                            saveDetail: { _ in entry.row }, download: { _, _ in Data() }))
                    }
                }
        case .analyses:
            NovaAnalysisListScreen(load: { _ in (reviewSummaries, false) }, thumbnail: { _ in Self.fixturePhoto },
                onOpen: { _ in showingReviewDetail = true }, onBack: {},
                onReports: { showingReviewReports = true })
                .novaFullScreenCover(isPresented: $showingReviewDetail) {
                    NovaAnalysisDetailScreen(analysisID: Self.analysis, client: reviewDetailClient,
                        onBack: { showingReviewDetail = false })
                }
                .novaFullScreenCover(isPresented: $showingReviewReports) {
                    NovaAnalysisReportsScreen(load: { reviewReports },
                        onBack: { showingReviewReports = false })
                }
        case .newAnalysis:
            NovaPhotoIntakeScreen(images: $reviewImages, onStart: { showingIntake = true }, onBack: {})
                .novaPopupCover(isPresented: $showingIntake) {
                    NovaPopup {
                        NovaAnalysisIntakePopup(companies: reviewCompanies, sectors: NovaPilotFindingsGate.sectorOptions,
                            focuses: reviewFocuses, draft: $draft, onStart: { showingIntake = false })
                            .onAppear { if draft.photoCount == 0 { draft.photoCount = max(1, reviewImages.count) } }
                    }
                }
        case .newFinding:
            NovaManualNonconformityScreen(companies: reviewCompanies,
                workplaces: { _ in reviewWorkplaces }, fileClient: reviewFileClient, save: { _ in nil }, onBack: {})
        case .documentChecklist:
            NovaDocumentTrackingScreen(client: reviewDocumentClient, onBack: {})
        case .documents:
            NovaFileLibraryScreen(client: reviewFileClient, onBack: {})
        case .periodicChecks:
            NovaEquipmentCheckScreen(client: reviewEquipmentClient, onBack: {})
        default:
            NovaAnalysisDetailScreen(analysisID: Self.analysis, client: reviewDetailClient, onBack: {})
        }
    }

    private static let workplace = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
    private static let analysis = UUID(uuidString: "00000000-0000-4000-8000-000000000006")!
    /// A drawn placeholder, never a real site photo.
    private static let fixturePhoto: UIImage = {
        let size = CGSize(width: 400, height: 300)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.82, green: 0.86, blue: 0.88, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.35, green: 0.42, blue: 0.46, alpha: 1).setFill()
            context.fill(CGRect(x: 40, y: 170, width: 320, height: 20))
            context.fill(CGRect(x: 60, y: 90, width: 16, height: 100))
            context.fill(CGRect(x: 300, y: 90, width: 16, height: 100))
        }
    }()

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
    private var reviewEntries: [NovaNonconformityEntry] {
        [.init(row: .init(id: Self.analysis, workplace_id: Self.workplace, title: "Korkuluk eksik",
                severity: "high", state: "open", version: 1, opened_on: "2026-09-10", due_on: "2026-09-12",
                source_kind: "legacy_finding", source_ref: Self.analysis.uuidString,
                record_kind: "nonconformity", risk_band: "high", closed_on: nil, assignee_contact: "Saha şefi",
                detail: .init(description: "Platform kenarında korkuluk yok.", control_measure: "Montaj yapılacak.",
                    legislation_ref: "6331 sayılı Kanun md.4", responsible_contact: "Saha şefi",
                    risk_method: "fine_kinney", fk_probability: 6, fk_frequency: 3, fk_severity: 15,
                    m5_probability: nil, m5_severity: nil, risk_score: 270, risk_band: "high"),
                actions: [.init(id: UUID(), description: "Korkuluk montajı", assignee: "Saha şefi",
                    due_on: "2026-09-20", state: "planned")],
                verifications: []),
               companyID: Self.company, companyName: summary.name, workplaceName: "Merkez tesis"),
         .init(row: .init(id: Self.employee, workplace_id: Self.workplace, title: "Saha turu sıklığı artırılmalı",
                severity: "low", state: "draft", version: 0, opened_on: "2026-09-13", due_on: nil,
                source_kind: "legacy_expert_item", source_ref: Self.employee.uuidString,
                record_kind: "improvement", risk_band: nil, closed_on: nil, assignee_contact: nil,
                detail: nil, actions: [], verifications: []),
               companyID: Self.company, companyName: summary.name, workplaceName: "Merkez tesis")]
    }

    private var reviewSummaries: [NovaAnalysisSummary] {
        [.init(id: Self.analysis, title: "Saha turu · 2 fotoğraf", createdOn: "14 Eylül 2026 · 10:20",
               companyName: nil, findingCount: 3, photoCount: 2, sectorLabel: "İmalat / Fabrika", highestBand: "critical"),
         .init(id: Self.employee, title: "Depo kontrolü", createdOn: "13 Eylül 2026 · 16:05",
               companyName: summary.name, findingCount: 5, photoCount: 1, sectorLabel: "Depo / Lojistik", highestBand: "medium")]
    }
    private var reviewReports: [NovaAnalysisReportEntry] {
        [.init(id: UUID(), title: "Saha turu · Analiz Raporu", fileName: "saha-turu.pdf",
               createdOn: "14 Eylül 2026 · 10:24", companyName: summary.name, format: "pdf",
               methodLabel: "Fine-Kinney", kindLabel: "analysis", fileSize: 284_000,
               analysisID: Self.analysis, createdAt: nil),
         .init(id: UUID(), title: "Depo kontrolü · Risk Tablosu", fileName: "depo-risk.xlsx",
               createdOn: "13 Eylül 2026 · 16:09", companyName: nil, format: "xlsx",
               methodLabel: "5×5 Matris", kindLabel: "risk_table", fileSize: 41_000,
               analysisID: nil, createdAt: nil)]
    }
    private var reviewDetailClient: NovaAnalysisDetailClient {
        .init(load: {
            if CommandLine.arguments.contains("RD_UI_TEST_LEGACY_ANALYSIS_DETAIL") {
                let bundle = try await AnalysisService.shared.result(analysisID: Self.analysis)
                return NovaAnalysisWorkspace.detailData(bundle: bundle, hub: nil,
                    companyName: nil, method: .fineKinney, methodLabel: "Fine-Kinney")
            }
            return reviewDetail
        }, photos: { [Self.fixturePhoto] }, companies: { reviewCompanies },
              assign: { _ in reviewAssigned = true }, workplaces: { _ in reviewWorkplaces },
              file: { _ in .opened }, edit: { _ in }, remove: { _ in }, react: { _, _, _ in },
              report: { _ in "ornek-rapor.pdf" })
    }
    /// A synthetic analysis that deliberately carries one unreadable band and
    /// one unscored section, so both refusals can be seen in review.
    private var reviewDetail: NovaAnalysisDetailData {
        let risk = NovaAnalysisSection(kind: .riskAnalysis, items: [
            scored(1, "Korkuluk eksik", "Yüksekte çalışma", "Platform kenarında korkuluk yok.",
                   "Korkuluk montajı yapılacak.", "6331 sayılı Kanun md.4", band: "high", score: 270,
                   factors: [6, 3, 15], rootCause: "Kenar koruması işe başlamadan tamamlanmamış."),
            scored(2, "Pano önü kapalı", "Elektrik", "Elektrik panosunun önü malzeme ile kapatılmış.",
                   "Pano önü boşaltılacak.", nil, band: "critical", score: 600, factors: [10, 6, 10],
                   rootCause: nil),
            // Deliberately unreadable: the screen must refuse to map it.
            scored(3, "Okunamayan bulgu", nil, "Bandı hesaplanamadı.", nil, nil,
                   band: "unknown", score: nil, factors: [], rootCause: nil),
        ], isTeaser: false)
        let expert = NovaAnalysisSection(kind: .expertRecommendations, items: [
            unscored(1, "Saha turu sıklığı artırılmalı", "Haftalık tur önerilir.", category: nil, audience: nil),
            unscored(2, "Acil çıkış tatbikatı", "Yıllık tatbikat planlanmalı.", category: nil, audience: nil),
        ], isTeaser: false)
        let training = NovaAnalysisSection(kind: .trainingRecommendations, items: [
            unscored(1, "Yüksekte çalışma eğitimi", "Açık kenar ve düşmeye karşı korunma uygulamalı işlenir.",
                     category: "Göreve özgü uygulamalı eğitim", audience: "Tüm çalışanlar"),
        ], isTeaser: true)
        let notebook = NovaAnalysisSection(kind: .approvedNotebook, items: [
            unscored(1, "Onaylı defter kaydı", "Tespit edilen eksiklikler işverene bildirilmiştir.",
                     category: nil, audience: nil),
        ], isTeaser: false)
        return .init(analysisID: Self.analysis, title: "Saha turu · 2 fotoğraf",
            createdOn: "14 Eylül 2026 · 10:20", methodLabel: "Fine-Kinney", method: .fineKinney,
            companyID: reviewAssigned ? Self.company : nil,
            companyName: reviewAssigned ? summary.name : nil, sections: [risk, expert, training, notebook],
            isProjectionMissing: false)
    }
    /// A synthetic scored finding. The two methods carry their own numbers so
    /// the toggle on the detail screen has something real to switch between.
    private func scored(_ ordinal: Int, _ title: String, _ category: String?, _ body: String,
                        _ measure: String?, _ references: String?, band: String, score: Double?,
                        factors: [Double], rootCause: String?) -> NovaAnalysisItem {
        var item = NovaAnalysisItem(id: UUID(), ordinal: ordinal, title: title, category: category,
            body: body, measure: measure, references: references)
        item.rootCause = rootCause
        item.photoIndices = [1]
        item.fineKinney = .init(band: band, value: score, factors: factors.count == 3
            ? [.init(label: "O", value: factors[0]), .init(label: "F", value: factors[1]),
               .init(label: "Ş", value: factors[2])] : [])
        item.matrix = .init(band: band, value: score.map { _ in 20 },
            factors: factors.isEmpty ? [] : [.init(label: "O", value: 4), .init(label: "Ş", value: 5)])
        return item
    }

    private func unscored(_ ordinal: Int, _ title: String, _ body: String,
                          category: String?, audience: String?) -> NovaAnalysisItem {
        var item = NovaAnalysisItem(id: UUID(), ordinal: ordinal, title: title, category: category,
            body: body, measure: nil, references: nil)
        item.audience = audience
        item.photoIndices = [1]
        return item
    }
    // MARK: synthetic document tracking

    /// One obligation of every status, so all four answers can be seen at once.
    /// Drawn fixtures for the equipment module. Every row is a state the server
    /// could genuinely return, including the two that carry no date at all.
    private var reviewEquipmentClient: NovaEquipmentCheckClient {
        .init(catalogue: { _ in (reviewEquipmentTypes, reviewEquipmentRules,
                                 reviewWorkplaces.map { .init(id: $0.id, name: $0.name) }, 30) },
              board: { request in reviewEquipmentBoard(request) },
              companies: { reviewCompanies },
              detail: { id in reviewEquipmentRows.first { $0.id == id } ?? reviewEquipmentRows[0] },
              register: { _, _ in reviewEquipmentRows[0] },
              update: { item, _ in item },
              archive: { _ in },
              setRule: { _, draft in
                  .init(equipmentType: draft.equipmentType ?? "crane",
                        periodMonths: draft.monthsValue ?? 12, source: draft.source,
                        needsReview: draft.source.needsReview, exceptionNote: nil)
              },
              recordInspection: { item, _ in item },
              filedReports: { _ in [] },
              fileClient: reviewFileClient)
    }

    /// Every type starts at the product's own general period, exactly as the
    /// server ships it.
    private var reviewEquipmentTypes: [NovaEquipmentCheckService.Suggestion] {
        ["lifting_equipment", "crane", "forklift", "pressure_vessel", "compressor",
         "electrical_installation", "fire_extinguisher", "ladder", "power_tool", "other_equipment"]
            .map { .init(code: $0, defaultPeriodMonths: 12,
                         defaultBasisNote: "Yönetmelik ekinde aksi belirtilmedikçe genel periyot bir yıldır.") }
    }
    private var reviewEquipmentRules: [NovaEquipmentRule] {
        [.init(equipmentType: "crane", periodMonths: 12, source: .manufacturer,
               needsReview: false, exceptionNote: nil),
         .init(equipmentType: "compressor", periodMonths: 6, source: .unapprovedFixture,
               needsReview: true, exceptionNote: "Uzmanın kendi belirlediği süre; kaynak onaylanmadı."),
         .init(equipmentType: "electrical_installation", periodMonths: 12, source: .regulationDefault,
               needsReview: true,
               exceptionNote: "Yönetmelik ekinde aksi belirtilmedikçe genel periyot bir yıldır.")]
    }

    private var reviewEquipmentRows: [NovaEquipmentItem] {
        func item(_ id: UUID, _ type: String, _ serial: String, _ state: NovaEquipmentState,
                  months: Int?, source: NovaEquipmentPeriodSource?, review: Bool?,
                  last: String?, result: String?, due: String?, late: Bool = false) -> NovaEquipmentItem {
            .init(id: id, companyID: Self.company, companyName: summary.name,
                  workplaceID: Self.workplace, workplaceName: "Merkez tesis",
                  equipmentType: type, serialTag: serial, acquiredOn: "2024-03-01",
                  locationNote: "Montaj hattı", isArchived: false, state: state,
                  periodMonths: months, periodSource: source, periodNeedsReview: review,
                  periodExceptionNote: nil, periodDefinedAfterReport: late,
                  lastPerformedOn: last, lastResult: result, lastInspector: last == nil ? nil : "TSE yetkili kuruluş",
                  lastExternalRef: last == nil ? nil : "RPT-2026-0114", nextDueOn: due,
                  dueSource: due == nil ? nil : .period,
                  katipDeclared: last != nil, katipNote: last == nil ? nil : "Atama yapıldı.",
                  katipOfficialVerification: false,
                  evidenceAssetID: nil,
                  inspections: last == nil ? [] : [.init(id: UUID(), performedOn: last!, result: result ?? "pass",
                      nextDueOn: due, periodMonths: months, inspector: "TSE yetkili kuruluş",
                      externalRef: "RPT-2026-0114", note: nil, evidenceAssetID: nil, evidenceDownload: nil,
                      dueSource: due == nil ? nil : .period, katipDeclared: true,
                      katipNote: "Atama yapıldı.")])
        }
        return [
            item(Self.analysis, "crane", "KRN-001", .overdue, months: 12, source: .manufacturer,
                 review: false, last: "2025-02-10", result: "pass", due: "2026-02-10"),
            item(Self.employee, "compressor", "KMP-004", .failed, months: 6, source: .unapprovedFixture,
                 review: true, last: "2026-09-11", result: "fail", due: nil),
            item(Self.workplace, "lifting_equipment", "VNC-002", .periodUnknown, months: nil,
                 source: nil, review: nil, last: "2026-08-20", result: "pass", due: nil),
            item(Self.company, "ladder", "MRD-007", .neverInspected, months: nil, source: nil,
                 review: nil, last: nil, result: nil, due: nil),
            item(Self.owner, "crane", "KRN-002", .valid, months: 12, source: .manufacturer,
                 review: false, last: "2026-06-01", result: "pass", due: "2027-06-01"),
            item(Self.session, "electrical_installation", "ELK-001", .dueSoon, months: 12,
                 source: .regulationDefault, review: true, last: "2025-10-05", result: "conditional",
                 due: "2026-10-05")]
    }

    private func reviewEquipmentBoard(_ request: NovaEquipmentQuery) -> NovaEquipmentBoard {
        let all = reviewEquipmentRows
        let group = NovaEquipmentGroup(rawValue: request.state ?? "")
        let matching = all.filter { row in
            guard request.equipmentType == nil || row.equipmentType == request.equipmentType else { return false }
            guard group == nil || group?.states.contains(row.state) == true else { return false }
            return row.matches(request.query)
        }
        var counts: [NovaEquipmentState: Int] = [:]
        var typeCounts: [String: [NovaEquipmentState: Int]] = [:]
        for row in all {
            counts[row.state, default: 0] += 1
            typeCounts[row.equipmentType, default: [:]][row.state, default: 0] += 1
        }
        return .init(counts: counts,
                     companies: [.init(id: Self.company, name: summary.name, total: all.count, counts: counts)],
                     typeCounts: typeCounts, rows: matching, total: matching.count,
                     hasMore: false, limit: request.limit, offset: 0,
                     today: "2026-09-15", noticeDays: 30)
    }

    /// Drawn fixtures for the archive, so the design can be reviewed without a
    /// live pilot. Nothing here uploads, inspects or promotes anything: every
    /// row is a state the server could genuinely return.
    private var reviewFileClient: NovaFileLibraryClient {
        .init(catalogue: { (reviewFileCategories, reviewFileAccepts,
                            .init(scanners: ["isg_format_inspector"], malwareScanningAvailable: false)) },
              library: { request in reviewFileLibrary(request) },
              companies: { reviewCompanies },
              file: { _, _, _ in reviewFileRows[0] },
              rename: { entry, _, _, _ in entry },
              archive: { _ in },
              cancel: { _ in },
              recheck: { entry in entry },
              contents: { _ in Data() },
              download: { _, _ in Data() })
    }

    private var reviewFileCategories: [NovaFileCategory] {
        [.init(code: "risk_assessment", ordinal: 1, section: "risk"),
         .init(code: "emergency_plan", ordinal: 2, section: "emergency"),
         .init(code: "training_material", ordinal: 3, section: "training"),
         .init(code: "inspection_report", ordinal: 4, section: "inspections"),
         .init(code: "contract", ordinal: 10, section: "files"),
         .init(code: "other", ordinal: 13, section: "files")]
    }
    private var reviewFileAccepts: [NovaFileAcceptance] {
        [.init(purpose: "company_document", extensions: ["pdf", "doc", "docx", "xls", "xlsx"],
               maxBytes: 52_428_800, limitApproved: false),
         .init(purpose: "evidence_photo", extensions: ["jpg", "jpeg", "png", "heic", "heif", "webp", "avif"],
               maxBytes: 52_428_800, limitApproved: false)]
    }

    private var reviewFileRows: [NovaFileEntry] {
        [.init(id: Self.analysis, companyID: Self.company, companyName: summary.name,
               category: "risk_assessment", section: "risk", title: "Risk değerlendirmesi 2026",
               fileName: "risk-degerlendirmesi-2026.pdf", note: "İşveren nüshası imzalı", version: 2,
               state: .promoted, rejectionCode: nil, fileExtension: "pdf", declaredBytes: 1_842_311,
               receivedBytes: 1_842_311, detectedType: "application/pdf",
               uploadBucket: nil, uploadPath: nil, downloadBucket: "isg-documents",
               downloadPath: "assets/preview/preview", scanner: "isg_format_inspector",
               scanFinding: nil, assurance: "format_inspection", malwareScanned: false,
               createdAt: "2026-09-12T08:14:00Z"),
         .init(id: Self.employee, companyID: Self.company, companyName: summary.name,
               category: "inspection_report", section: "inspections", title: "Vinç periyodik kontrol",
               fileName: "vinc-kontrol.docx", note: nil, version: 1,
               state: .rejected, rejectionCode: "SCAN_REJECTED", fileExtension: "docx",
               declaredBytes: 412_004, receivedBytes: 412_004, detectedType: "application/zip",
               uploadBucket: nil, uploadPath: nil, downloadBucket: nil, downloadPath: nil,
               scanner: "isg_format_inspector", scanFinding: "MACRO_PRESENT",
               assurance: "format_inspection", malwareScanned: false, createdAt: "2026-09-13T15:02:00Z"),
         .init(id: Self.workplace, companyID: Self.company, companyName: summary.name,
               category: "contract", section: "files", title: "İSG hizmet sözleşmesi",
               fileName: "sozlesme.pdf", note: nil, version: 1,
               state: .pending, rejectionCode: nil, fileExtension: "pdf", declaredBytes: 96_500,
               receivedBytes: nil, detectedType: nil, uploadBucket: "isg-quarantine",
               uploadPath: "quarantine/preview/preview", downloadBucket: nil, downloadPath: nil,
               scanner: nil, scanFinding: nil, assurance: nil, malwareScanned: false,
               createdAt: "2026-09-14T09:41:00Z"),
         .init(id: Self.company, companyID: Self.company, companyName: summary.name,
               category: "emergency_plan", section: "emergency", title: "Acil durum planı taslağı",
               fileName: "acil-durum.pdf", note: nil, version: 1,
               state: .scanFailed, rejectionCode: "SCAN_UNAVAILABLE", fileExtension: "pdf",
               declaredBytes: 204_800, receivedBytes: 204_800, detectedType: "application/pdf",
               uploadBucket: nil, uploadPath: nil, downloadBucket: nil, downloadPath: nil,
               scanner: "isg_format_inspector", scanFinding: nil, assurance: "format_inspection",
               malwareScanned: false, createdAt: "2026-09-14T10:05:00Z")]
    }

    private func reviewFileLibrary(_ request: NovaFileQuery) -> NovaFileLibrary {
        let all = reviewFileRows
        let group = NovaFileGroup(rawValue: request.state ?? "")
        let matching = all.filter { row in
            guard request.category == nil || row.category == request.category else { return false }
            guard group == nil || group?.states.contains(row.state) == true else { return false }
            return row.matches(request.query)
        }
        var counts: [NovaFileState: Int] = [:]
        var categoryCounts: [String: [NovaFileState: Int]] = [:]
        for row in all {
            counts[row.state, default: 0] += 1
            categoryCounts[row.category, default: [:]][row.state, default: 0] += 1
        }
        return .init(counts: counts,
                     companies: [.init(id: Self.company, name: summary.name, total: all.count, counts: counts)],
                     categoryCounts: categoryCounts, rows: matching, total: matching.count,
                     hasMore: false, limit: request.limit, offset: 0,
                     assurance: .init(scanners: ["isg_format_inspector"], malwareScanningAvailable: false))
    }

    private var reviewDocumentClient: NovaDocumentTrackingClient {
        .init(portfolio: { request in reviewDocumentPortfolio(request) },
              companies: { reviewCompanies },
              kinds: { _ in reviewDocumentKinds },
              workplaces: { _ in reviewWorkplaces.map { .init(id: $0.id, name: $0.name) } },
              add: { _, _ in reviewDocumentRows[0] },
              update: { entry, _ in entry },
              archive: { _ in },
              recordCopy: { entry, _ in entry },
              removeCopy: { entry, _ in entry })
    }

    private var reviewDocumentKinds: [NovaDocumentKind] {
        [.init(code: "risk_assessment", ordinal: 1, defaultValidityDays: nil),
         .init(code: "emergency_plan", ordinal: 2, defaultValidityDays: nil),
         .init(code: "drill_record", ordinal: 3, defaultValidityDays: 365),
         .init(code: "equipment_inspection", ordinal: 8, defaultValidityDays: 365),
         .init(code: "annual_work_plan", ordinal: 11, defaultValidityDays: 365)]
    }

    private func reviewDocumentPortfolio(_ request: NovaDocumentQuery) -> NovaDocumentPortfolio {
        let all = reviewDocumentRows
        let matching = all.filter { row in
            guard request.status == nil || row.status == request.status else { return false }
            guard request.kinds == nil || request.kinds?.contains(row.kindCode) == true else { return false }
            return row.matches(request.query)
        }
        var counts: [NovaDocumentStatus: Int] = [:]
        var kindCounts: [String: [NovaDocumentStatus: Int]] = [:]
        for row in all {
            counts[row.status, default: 0] += 1
            kindCounts[row.kindCode, default: [:]][row.status, default: 0] += 1
        }
        return .init(counts: counts,
                     companies: [.init(id: Self.company, name: summary.name, total: all.count, counts: counts)],
                     kindCounts: kindCounts,
                     rows: Array(matching.prefix(request.limit)),
                     total: matching.count, hasMore: matching.count > request.limit,
                     today: "2026-09-14", fileStorageAvailable: false)
    }

    private var reviewDocumentRows: [NovaDocumentObligation] {
        [
            document("Risk değerlendirmesi", kind: "risk_assessment", status: .missing,
                     basis: .legal, legalRef: "6331 sayılı Kanun md.10", copies: []),
            document("Periyodik kontrol raporu", kind: "equipment_inspection", status: .expired,
                     basis: .expert, legalRef: nil,
                     copies: [.init(id: UUID(), issuedOn: "2024-08-01", validUntil: "2025-08-01",
                                    documentNo: "PK-2024-017", locationNote: "İşveren dosyası · klasör 2",
                                    recordedAt: nil)]),
            document("Yıllık çalışma planı", kind: "annual_work_plan", status: .dueSoon,
                     basis: .expert, legalRef: nil,
                     copies: [.init(id: UUID(), issuedOn: "2025-10-01", validUntil: "2026-10-01",
                                    documentNo: nil, locationNote: "Ortak sürücü", recordedAt: nil)]),
            document("Tatbikat kaydı", kind: "drill_record", status: .valid,
                     basis: .expert, legalRef: nil,
                     copies: [.init(id: UUID(), issuedOn: "2026-06-12", validUntil: "2027-06-12",
                                    documentNo: "TAT-2026-004", locationNote: nil, recordedAt: nil)]),
        ]
    }

    private func document(_ title: String, kind: String, status: NovaDocumentStatus,
                          basis: NovaDocumentBasis, legalRef: String?,
                          copies: [NovaDocumentCopy]) -> NovaDocumentObligation {
        .init(id: UUID(), companyID: Self.company, companyName: summary.name,
              workplaceID: nil, kindCode: kind, title: title, basis: basis,
              legalRef: legalRef, validityDays: copies.isEmpty ? nil : 365, noticeDays: 30,
              responsibleContact: "İşveren vekili", note: nil, isArchived: false, version: 1,
              status: status, latestIssuedOn: copies.first?.issuedOn,
              latestValidUntil: copies.first?.validUntil, copies: copies,
              fileStored: false, workplaceName: nil)
    }
}
#endif
