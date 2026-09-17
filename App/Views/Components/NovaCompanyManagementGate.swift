import SwiftUI
import PhotosUI

/// The legacy management view remains the fallback when rollout/RPC/auth is unavailable.
struct NovaCompanyManagementGate<Fallback: View>: View {
    let onClose: () -> Void
    @ViewBuilder let fallback: () -> Fallback
    @StateObject private var controller = NovaWorkspaceController()
    @State private var legacyRequested = false
    @State private var sceneRevalidation = NovaSceneRevalidation()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if controller.resolving {
                NovaPageSurface(onEdgeBack: onClose) { VStack(spacing: 18) { ProgressView(); NovaText(text: RDLocalization.string("localizable.nova.company.management.gate.firma.erisimi.dogrulaniyor.3bf732f2", table: .localizable, fallback: "Firma erişimi doğrulanıyor…")); NovaButton(label: RDLocalization.string("localizable.nova.company.management.gate.kapat.3148ed17", table: .localizable, fallback: "Kapat"), symbol: "xmark", variant: .surface, action: onClose) }.padding(18) }
            } else if controller.isAvailable && !legacyRequested {
                NavigationStack {
                    if let scope = controller.scope {
                        NovaCompanyWorkspace(scope: scope, companyName: controller.capability?.company_name ?? "Firma", canWrite: controller.canWrite,
                            personnel: controller.personnelClient, directory: controller.directoryClient,
                            onBack: { controller.select(nil) },
                            loadNonconformities: {
                                try await NovaNonconformityService.live(currentScope: { controller.scope }).list(scope)
                            })
                    } else {
                        VStack(spacing: 0) {
                            NovaCompanyDestination(host: Binding(get: { controller.host }, set: { _ in }),
                                loadCompanies: { try await loadNovaOwnedCompanies(includeArchived: $0) }, includeArchived: true, onSelect: controller.select, onBack: onClose)
                            NovaButton(label: RDLocalization.string("localizable.nova.company.management.gate.firma.ekle.duzenle.005d0121", table: .localizable, fallback: "Firma ekle / düzenle"), symbol: "building.2", variant: .surface) { legacyRequested = true }.padding(18)
                        }.background(NovaColorToken.canvas.color(in: .light))
                    }
                }.id(controller.host.navigation.epoch)
                .preferredColorScheme(.light)
            } else {
                VStack(spacing: 0) {
                    if legacyRequested && controller.isAvailable {
                        NovaButton(label: RDLocalization.string("localizable.nova.company.gate.back.to.management", table: .localizable, fallback: "Personel ve işyeri yönetimine dön"), symbol: "chevron.left", variant: .surface) { legacyRequested = false; controller.select(nil) }.padding(12)
                    }
                    fallback()
                }
            }
        }
        .task { await controller.observe() }
        .onChange(of: scenePhase) { phase in
            if sceneRevalidation.update(isBackground: phase == .background, isActive: phase == .active) { controller.refresh() }
        }
        .onChange(of: controller.host.identity) { _ in legacyRequested = false }
    }
}

struct NovaCompanyWorkspace: View {
    let scope: NovaPersonnelScope
    let companyName: String
    let canWrite: Bool
    let personnel: NovaPersonnelClient
    let directory: NovaDirectoryClient
    let onBack: () -> Void
    var loadSummary: (() async throws -> NovaPilotCompanySummary?)? = nil
    /// The company overview RPC predates the new nonconformity store and does
    /// not own this count. Read the records from their authoritative service.
    var loadNonconformities: (() async throws -> [NovaNonconformityRow])? = nil
    var onOpenNonconformities: (() -> Void)? = nil
    @State private var summary: NovaPilotCompanySummary?
    @State private var summaryFailed = false
    @State private var summaryRevision = UUID()
    @State private var companyRecord: Company?
    @State private var companyRecordLoaded = false
    @State private var companyLogo: UIImage?
    @State private var companyLogoPicker: PhotosPickerItem?
    @State private var companyLogoSaving = false
    @State private var companyLogoError: String?
    @State private var personnelRows: [NovaEmployeeRow] = []
    @State private var personnelQuery = ""
    @State private var personnelLoading = false
    @State private var personnelError: String?
    @State private var nonconformities: [NovaNonconformityRow]?
    @State private var nonconformityError: String?
    @State private var nonconformityExpanded = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.novaCelebrate) private var celebrate
    @State private var sheet: Sheet?
    @State private var personnelPage = false
    @State private var processKind: String?
    @State private var processTracking: NovaModuleTrackingSnapshot?
    @State private var companyExpanded = false
    @State private var completedTrainings: Int?
    @State private var expandedSections = Set<NovaCompanySection>()
    /// The archive's own counts for this company, so a heading and the archive
    /// can never disagree about which files are on it.
    @State private var files: NovaFileLibrary?
    @State private var fileCategories: [NovaFileCategory] = []
    @State private var filesLoading = false
    @State private var fileSection: NovaCompanySection?
    @State private var addingFile = false
    /// A single portfolio read supplies every document heading in this company.
    @State private var documents: NovaDocumentPortfolio?
    @State private var documentsLoading = false
    @State private var documentSection: NovaCompanySection?
    /// Set when a section's own empty-state "Ekle" action opened the archive,
    /// so it can skip straight to the upload form for that category.
    @State private var fileSectionAdding = false
    /// The module's own counts for this company, so the Periyodik Kontroller
    /// heading and the module can never disagree about what is on record.
    @State private var equipment: NovaEquipmentBoard?
    @State private var equipmentLoading = false
    @State private var equipmentSection: NovaCompanySection?
    /// Set when the strip's "Kontrol ekle" action opens the module directly
    /// in equipment selection and control entry.
    @State private var equipmentAdding = false
    /// The risk module's own board for this company (one lightweight fetch:
    /// total, per-state tally and the one row itself), so the heading can
    /// show the real assessment instead of a bare count.
    @State private var riskBoard: NovaRiskBoard?
    /// The appointment actually holding each of these two roles for this
    /// company — a company can have at most one of each at a time — so the
    /// heading can name who it is instead of a bare count.
    @State private var representativeAppointment: NovaAppointmentBoard?
    @State private var supportAppointment: NovaAppointmentBoard?
    /// Set when a section's own empty-state "Ekle" action opened the module,
    /// so it can skip straight to the add form instead of the record list.
    @State private var processAdding = false
    private struct PersonnelRoute: Identifiable { let id: UUID }
    private struct PersonnelLoadKey: Equatable { let query: String; let revision: UUID }
    /// Opened from a role row's own employee name, straight to that person.
    @State private var personnelDetail: PersonnelRoute?
    private var documentIdentity: NovaSessionIdentity { .init(userID: scope.ownerID, sessionID: scope.sessionID) }
    private enum Sheet: Identifiable {
        case personnel, addPersonnel, editCompany, deleteCompany, training, directory(NovaDirectoryKind)
        var id: String { switch self { case .personnel: return "personnel"; case .addPersonnel: return "add-personnel"; case .editCompany: return "edit-company"; case .deleteCompany: return "delete-company"; case .training: return "training"; case .directory(let kind): return kind.rawValue } }
    }
    private var progress: NovaCompanyProgress {
        // Unmeasured sections stay unknown. A record count is not proof that a
        // company's obligation is complete.
        var result = NovaCompanyProgress(states: Dictionary(uniqueKeysWithValues: NovaCompanySection.allCases.map { ($0, NovaCompletionState.unknown) }))
        if companyRecordLoaded { result.states[.logo] = companyRecord?.logoPath?.isEmpty == false ? .complete : .missing }
        if let summary { result.states[.personnel] = summary.personnel_count > 0 ? .complete : .missing }
        if let completedTrainings { result.states[.training] = completedTrainings > 0 ? .complete : .missing }
        for section in NovaCompanySection.allCases where section != .representative && section != .support {
            guard let kind = moduleKind(section) else { continue }
            if let row = processTracking?.summaries.first(where: { $0.id == kind }), row.available {
                result.states[section] = row.total > 0 ? .complete : .missing
            }
        }
        if let representativeAppointment { result.states[.representative] = representativeAppointment.total > 0 ? .complete : .missing }
        if let supportAppointment { result.states[.support] = supportAppointment.total > 0 ? .complete : .missing }
        if let riskBoard { result.states[.risk] = (riskBoard.companies.first { $0.id == scope.companyID }?.total ?? 0) > 0 ? .complete : .missing }
        if let equipment { result.states[.inspections] = equipment.total > 0 ? .complete : .missing }
        if let files, !accidentCategories.isEmpty { result.states[.accidents] = files.counts(forCategories: accidentCategories).values.reduce(0, +) > 0 ? .complete : .missing }
        return result
    }
    private var accidentCategories: [String] { NovaFileSectionMap.categories(for: .accidents, in: fileCategories) }
    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        NovaPageHeading(title: RDLocalization.string("localizable.nova.company.detail.title", table: .localizable, fallback: "Firma Detayı"), onBack: onBack)
                        companyCard
                        companyStats
                        nonconformityCard
                        if !canWrite { NovaCard(padding: 16) { Label(RDLocalization.string("localizable.nova.company.management.gate.salt.okunur.kayitlariniz.korunuyor.2cc72e1b", table: .localizable, fallback: "Salt okunur · kayıtlarınız korunuyor"), systemImage: "lock"); NovaText(text: RDLocalization.string("localizable.nova.company.management.gate.yeni.kayit.ve.duzenleme.su.anda.kullanilamiyor.d83e8253", table: .localizable, fallback: "Yeni kayıt ve düzenleme şu anda kullanılamıyor."), style: .metaQuiet) } }
                        NovaCompanyAccordion(title: RDLocalization.string("localizable.nova.workspace.company.info", table: .localizable, fallback: "Firma Bilgileri"),
                            symbol: "building.2", state: companyRecordLoaded ? progress[.logo] : nil,
                            identifier: "company.section.info", expanded: $companyExpanded) {
                            companyLogoRow
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                            ForEach([NovaDirectoryKind.workplaces, .departments, .jobs, .contractors], id: \.self) { kind in
                                entry(kind.title, kind.symbol, tone: kind == .departments ? .statusWarningInk : .accentInk) { sheet = .directory(kind) }
                            }
                            }
                        }
                        sectionView(.personnel)
                        ForEach(Array(NovaCompanySection.allCases.dropFirst(2))) { section in sectionView(section) }
                    }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 18)
                }
                .task(id: summaryRevision) {
                    summary = nil; summaryFailed = false
                    guard let loadSummary else { return }
                    do { let value = try await loadSummary(); try Task.checkCancellation(); summary = value }
                    catch { if !Task.isCancelled { summaryFailed = true } }
                }
        }.navigationBarBackButtonHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { event in
            if event.object as? UUID == scope.ownerID { summaryRevision = UUID() }
        }
        .onChange(of: processKind) { value in if value == nil { summaryRevision = UUID() } }

        .task(id: summaryRevision) {
            completedTrainings = nil
            let service = NovaTrainingService(identity: .init(userID: scope.ownerID, sessionID: scope.sessionID))
            if let page = try? await service.list(scope.companyID), !Task.isCancelled { completedTrainings = page.completed ?? 0 }
        }
        .task(id: summaryRevision) {
            nonconformityError = nil
            guard let loadNonconformities else { return }
            do {
                let rows = try await loadNonconformities()
                try Task.checkCancellation()
                nonconformities = rows
            } catch is CancellationError {
                return
            } catch {
                nonconformities = nil
                nonconformityError = RDLocalization.string("localizable.nova.company.nonconformity.load.failed", table: .localizable,
                    fallback: "Uygunsuzluk kayıtları alınamadı.")
            }
        }
        .task(id: summaryRevision) {
            processTracking = try? await NovaModuleTrackingLoader.load(identity: documentIdentity, company: scope.companyID)
        }
        .task(id: summaryRevision) { await loadCompanyRecord() }
        .task(id: PersonnelLoadKey(query: personnelQuery, revision: summaryRevision)) {
            await loadPersonnelRows(query: personnelQuery)
        }
        .onChange(of: companyLogoPicker) { item in
            guard let item else { return }
            Task { await saveCompanyLogo(item) }
        }
        .task(id: summaryRevision) {
            filesLoading = true
            defer { filesLoading = false }
            let service = NovaFileLibraryService.live()
            if let answer = try? await service.catalogue(documentIdentity) { fileCategories = answer.categories }
            files = try? await service.library(documentIdentity,
                query: .init(company: scope.companyID, limit: 1))
        }
        .task(id: summaryRevision) {
            documentsLoading = true
            defer { documentsLoading = false }
            let service = NovaDocumentTrackingService.live(currentScope: { scope })
            documents = try? await service.portfolio(documentIdentity, company: scope.companyID, limit: 1)
        }
        .task(id: summaryRevision) {
            equipmentLoading = true
            defer { equipmentLoading = false }
            equipment = try? await NovaEquipmentCheckService.live().board(documentIdentity,
                query: .init(company: scope.companyID, limit: 5))
        }
        .task(id: summaryRevision) {
            riskBoard = try? await NovaRiskAssessmentService.live().board(documentIdentity,
                query: .init(company: scope.companyID, limit: 1))
        }
        .task(id: summaryRevision) {
            representativeAppointment = try? await NovaAppointmentService.live().board(documentIdentity,
                query: .init(company: scope.companyID, role: NovaAppointmentKind.representative.rawValue, limit: 1))
        }
        .task(id: summaryRevision) {
            supportAppointment = try? await NovaAppointmentService.live().board(documentIdentity,
                query: .init(company: scope.companyID, role: NovaAppointmentKind.supportStaff.rawValue, limit: 1))
        }
        .novaFullScreenCover(item: $equipmentSection, onDismiss: {
            summaryRevision = UUID(); equipmentAdding = false
        }) { section in
            NovaPilotEquipmentGate(identity: documentIdentity, canWrite: canWrite,
                initialCompany: scope.companyID, headingOverride: section.title,
                startInAddMode: equipmentAdding,
                onBack: { equipmentSection = nil })
        }
        .novaFullScreenCover(item: $fileSection, onDismiss: { summaryRevision = UUID(); fileSectionAdding = false }) { section in
            NovaPilotFileGate(identity: documentIdentity, canWrite: canWrite,
                initialCompany: scope.companyID,
                initialCategories: NovaFileSectionMap.categories(for: section, in: fileCategories),
                headingOverride: section.title, startInAddMode: fileSectionAdding,
                onBack: { fileSection = nil })
        }
        .novaFullScreenCover(item: $documentSection, onDismiss: { summaryRevision = UUID() }) { section in
            NovaPilotDocumentGate(identity: documentIdentity, scope: scope, canWrite: canWrite,
                select: { _ in }, currentScope: { scope }, onBack: { documentSection = nil },
                onCompanies: { documentSection = nil }, initialCompany: scope.companyID,
                initialKinds: NovaDocumentSectionMap.kinds(for: section), headingOverride: section.title)
        }
        .novaFullScreenCover(isPresented: $addingFile, onDismiss: { summaryRevision = UUID() }) {
            NovaPilotFileGate(identity: documentIdentity, canWrite: canWrite,
                initialCompany: scope.companyID,
                headingOverride: NovaCompanySection.files.title,
                onBack: { addingFile = false })
        }
        .novaFullScreenCover(item: $personnelDetail) { route in
            NovaPersonnelDestination(scope: scope, companyName: companyName, client: personnel,
                onBack: { personnelDetail = nil }, directory: directory, canWrite: canWrite, preview: false,
                initialEmployee: route.id)
        }
        .novaFullScreenCover(isPresented: Binding(get: { processKind != nil }, set: { if !$0 { processKind = nil } }), onDismiss: {
            processAdding = false
        }) {
            if processKind == "risk" {
                NovaPilotRiskGate(identity: documentIdentity, canWrite: canWrite, initialCompany: scope.companyID,
                    startInAddMode: processAdding, onBack: { processKind = nil })
            } else if let kind = processKind {
                NovaTrackedModuleDestination(identity: documentIdentity, kind: kind, company: scope.companyID, canWrite: canWrite,
                    startInAddMode: processAdding, onBack: { processKind = nil })
            }
        }
        .navigationDestination(isPresented: $personnelPage) {
            NovaPersonnelDestination(scope: scope, companyName: companyName, client: personnel,
                onBack: { personnelPage = false }, directory: directory, canWrite: canWrite, preview: false)
        }
        .novaFullScreenCover(item: $sheet, onDismiss: { summaryRevision = UUID() }) { destination in
            NovaPopup {
            NavigationStack {
                switch destination {
                case .training:
                    NovaTrainingCompanyScreen(scope: scope, companyName: companyName, personnel: personnel, canWrite: canWrite)
                case .editCompany:
                    NovaCompanyLiveEditor(company: companyRecord, fallbackID: scope.companyID,
                        fallbackName: summary?.name ?? companyName,
                        fallbackHazard: summary?.hazard_class ?? "medium") { saved in
                            companyRecord = saved
                            companyRecordLoaded = true
                            await loadCompanyLogo(from: saved.logoPath)
                            sheet = nil
                            summaryRevision = UUID()
                        }
                case .deleteCompany:
                    NovaCompanyVisualDelete(name: summary?.name ?? companyName)
                case .addPersonnel:
                    NovaPersonnelCreateSheet(scope: scope, companyName: companyName, client: personnel)
                case .personnel:
                    NovaPersonnelDestination(scope: scope, companyName: companyName, client: personnel,
                        onBack: { sheet = nil }, directory: directory, canWrite: canWrite, preview: true,
                        onShowAll: { sheet = nil; personnelPage = true })
                case .directory(let kind):
                    NovaDirectoryDestination(scope: scope, kind: kind, client: directory,
                        onBack: { sheet = nil }, canWrite: canWrite)
                }
            }
            }
        }
    }
    private func moduleKind(_ section: NovaCompanySection) -> String? {
        switch section {
        case .representative, .support: return "appointment"
        case .emergency: return "emergency_plan"
        case .board: return "board"
        case .handover: return "ppe"
        default: return nil
        }
    }
    private func moduleTag(overdue: Int, upcoming: Int, total: Int) -> (String, NovaStatus)? {
        guard total > 0 else { return nil }
        if overdue > 0 { return (RDLocalization.string("localizable.nova.document.status.expired", table: .localizable, fallback: "Süresi geçti"), .danger) }
        if upcoming > 0 { return (RDLocalization.string("localizable.nova.document.status.due.soon", table: .localizable, fallback: "Yaklaşıyor"), .warning) }
        return (RDLocalization.string("localizable.nova.document.status.valid", table: .localizable, fallback: "Güncel"), .success)
    }
    /// A record is already on file: show what's on it and let the row itself
    /// open the module instead of a generic action button.
    private func moduleFilledRow(summary: String, tag: (String, NovaStatus)?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                NovaText(text: summary, style: .meta).frame(maxWidth: .infinity, alignment: .leading)
                if let tag { NovaStatusPill(label: tag.0, status: tag.1) }
                Image(systemName: "chevron.right").font(.system(size: 11))
            }.frame(minHeight: 40).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    /// Nothing on file yet — say so plainly and offer the one action that
    /// fixes it instead of navigating to an empty list.
    private func moduleEmptyState(addLabel: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaEmptyState(title: RDLocalization.string("localizable.nova.company.module.empty.title", table: .localizable,
                    fallback: "Henüz kayıt yok"),
                message: RDLocalization.string("localizable.nova.company.module.empty.detail", table: .localizable,
                    fallback: "İlk kaydı ekleyerek bu başlığın durumunu ve yaklaşan tarihlerini firma üzerinden takip edebilirsiniz."))
            NovaCompactActionButton(title: addLabel, symbol: "plus", prominent: true,
                enabled: canWrite, action: action)
        }
    }
    private func appointmentStatus(_ state: NovaAppointmentState) -> NovaStatus {
        switch state {
        case .active: return .success
        case .upcoming: return .info
        case .ended: return .danger
        }
    }
    /// Names who actually holds the role, not just how many rows exist. The
    /// name itself is the personnel-detail link; the rest of the row opens it too.
    private func appointmentRow(_ appointment: NovaAppointment) -> some View {
        Button {
            if let employeeID = appointment.employeeID { personnelDetail = .init(id: employeeID) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: appointment.employeeName ?? "Personel", style: .bodyStrong)
                    NovaText(text: "Atanma: " + NovaStatisticsSnapshot.dayLabel(appointment.startsOn), style: .micro)
                    if appointment.assetDownload != nil {
                        NovaText(text: "Evrak eklendi", style: .micro)
                    }
                }
                Spacer(minLength: 0)
                NovaStatusPill(label: appointment.state.title, status: appointmentStatus(appointment.state))
                Image(systemName: "chevron.right").font(.system(size: 11))
            }.frame(minHeight: 40).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(appointment.employeeID == nil)
    }
    private func riskGroupStatus(_ group: NovaRiskGroup) -> NovaStatus {
        switch group {
        case .expired: return .danger
        case .dueSoon: return .warning
        case .untracked: return .info
        case .current: return .success
        }
    }
    /// The server doesn't return a human filename for the attached asset —
    /// only its id — so the id itself stands in for the name, per the
    /// expert's own call on how to label this until a real name exists.
    private func riskRow(_ row: NovaRiskRow) -> some View {
        Button { processKind = "risk" } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if let assetID = row.currentFileAssetID {
                        NovaText(text: "Risk Analizi - " + assetID.uuidString, style: .bodyStrong)
                    } else if let assessedOn = row.currentAssessmentOn {
                        NovaText(text: RDLocalization.string("localizable.nova.company.risk.assessment.prefix", table: .localizable,
                            fallback: "Değerlendirme: ") + NovaStatisticsSnapshot.dayLabel(assessedOn), style: .bodyStrong)
                    } else {
                        NovaText(text: "Risk analizi eklendi", style: .bodyStrong)
                    }
                    if let validUntil = row.validUntil {
                        NovaText(text: RDLocalization.string("localizable.nova.company.risk.validity.prefix", table: .localizable,
                            fallback: "Geçerlilik: ") + NovaStatisticsSnapshot.dayLabel(validUntil), style: .micro)
                    }
                }
                Spacer(minLength: 0)
                NovaStatusPill(label: row.group.title, status: riskGroupStatus(row.group))
                Image(systemName: "chevron.right").font(.system(size: 11))
            }.frame(minHeight: 40).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func statStrip(_ items: [(String, String, Int)], identifier: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    NovaListStat(title: item.0, symbol: item.1, value: item.2).frame(width: 98)
                }
            }.padding(.vertical, 2)
        }.accessibilityIdentifier(identifier)
    }
    private func appointmentStats(_ board: NovaAppointmentBoard) -> some View {
        statStrip([
            ("Aktif", "checkmark.circle", board.count(.active)),
            (RDLocalization.string("localizable.nova.document.status.due.soon", table: .localizable, fallback: "Yaklaşan"), "clock", board.count(.upcoming)),
            ("Sona eren", "calendar.badge.exclamationmark", board.count(.ended))
        ], identifier: "company.section.appointment.stats")
    }
    private func riskStats(_ board: NovaRiskBoard) -> some View {
        statStrip(NovaRiskGroup.allCases.map { ($0.title, $0.symbol, board.count($0)) },
            identifier: "company.section.risk.stats")
    }
    private func trackingStats(_ row: NovaModuleTrackingSnapshot.Summary, identifier: String) -> some View {
        statStrip([
            (RDLocalization.string("localizable.nova.company.metric.records", table: .localizable, fallback: "Kayıt"), "doc.text", row.total),
            (RDLocalization.string("localizable.nova.document.status.expired", table: .localizable, fallback: "Süresi geçti"), "exclamationmark.triangle", row.overdue),
            (RDLocalization.string("localizable.nova.document.status.due.soon", table: .localizable, fallback: "Yaklaşan"), "clock", row.upcoming)
        ], identifier: identifier)
    }
    private func sectionView(_ section: NovaCompanySection, outlinesWhenExpanded: Bool = true) -> some View {
        NovaCompanyAccordion(title: section.title, symbol: section.symbol, state: progress[section],
            identifier: "company.section.\(section.rawValue)",
            outlinesWhenExpanded: outlinesWhenExpanded,
            expanded: Binding(get: { expandedSections.contains(section) }, set: { value in
                if value { expandedSections.insert(section) } else { expandedSections.remove(section) }
            })) {
                // These headings each have a real record behind them, shown
                // as its own row (who/when/status) instead of the generic
                // evrak-takip/dosya-arşivi strips every other heading gets —
                // those track a different, unrelated document obligation.
                let hasDedicatedRow = moduleKind(section) != nil || section == .risk || section == .accidents
                if section == .personnel {
                    personnelSection
                } else if section == .representative || section == .support {
                    let board = section == .representative ? representativeAppointment : supportAppointment
                    if let board {
                        appointmentStats(board)
                        if let appointment = board.rows.first {
                            appointmentRow(appointment)
                        } else {
                            moduleEmptyState(addLabel: section.title + " Ekle") { processAdding = true; processKind = "appointment" }
                        }
                    } else {
                        NovaCompactActionButton(title: RDLocalization.string("localizable.nova.workspace.section.appointments.open", table: .localizable,
                            fallback: "Atamaları aç"), symbol: "person.badge.plus") { processKind = "appointment" }
                    }
                } else if section == .risk {
                    if let riskBoard {
                        riskStats(riskBoard)
                        if let row = riskBoard.rows.first {
                            riskRow(row)
                        } else {
                            moduleEmptyState(addLabel: section.title + " Ekle") { processAdding = true; processKind = "risk" }
                        }
                    } else {
                        NovaCompactActionButton(title: RDLocalization.string("localizable.nova.workspace.section.risk.open", table: .localizable,
                            fallback: "Değerlendirmeleri aç"), symbol: "shield") { processKind = "risk" }
                    }
                } else if section == .accidents, !accidentCategories.isEmpty {
                    if let files {
                        let total = files.counts(forCategories: accidentCategories).values.reduce(0, +)
                        if total > 0 {
                            moduleFilledRow(summary: "\(total) dosya", tag: (RDLocalization.string("localizable.nova.document.status.valid", table: .localizable, fallback: "Güncel"), .success)) { fileSection = .accidents }
                        } else {
                            moduleEmptyState(addLabel: section.title + " Ekle") { fileSectionAdding = true; fileSection = .accidents }
                        }
                    } else {
                        NovaText(text: RDLocalization.string("localizable.nova.file.loading", table: .localizable, fallback: "Dosyalar yükleniyor…"), style: .metaQuiet)
                    }
                } else if section == .training {
                    statStrip([("Tamamlanan", "checkmark.circle", completedTrainings ?? 0)],
                        identifier: "company.section.training.stats")
                    NovaCompactActionButton(title: RDLocalization.string("localizable.nova.workspace.section.training.open", table: .localizable,
                        fallback: "Eğitimleri aç"), symbol: "graduationcap") { sheet = .training }
                }
                if let kind = moduleKind(section), section != .representative, section != .support {
                    if let row = processTracking?.summaries.first(where: { $0.id == kind }), row.available {
                        trackingStats(row, identifier: "company.section.\(section.rawValue).stats")
                        if row.total > 0 {
                            let summary = String(format: RDLocalization.string("localizable.nova.workspace.section.tracking.summary", table: .localizable,
                                fallback: "%1$d kayıt · %2$d tarihi geçmiş · %3$d yaklaşan"), row.total, row.overdue, row.upcoming)
                            moduleFilledRow(summary: summary, tag: moduleTag(overdue: row.overdue, upcoming: row.upcoming, total: row.total)) { processKind = kind }
                        } else {
                            moduleEmptyState(addLabel: section.title + " Ekle") { processAdding = true; processKind = kind }
                        }
                    } else {
                        NovaCompactActionButton(title: RDLocalization.string("localizable.nova.workspace.section.records.open", table: .localizable,
                            fallback: "Kayıtları aç"), symbol: "arrow.right") { processKind = kind }
                    }
                    if section == .emergency {
                        NovaCompactActionButton(title: RDLocalization.string("localizable.nova.workspace.section.drills.open", table: .localizable,
                            fallback: "Tatbikatları aç"), symbol: "figure.run") { processKind = "drill" }
                    }
                }
                // Periodic checks are the whole of this heading, so the
                // inventory comes first and the obligation and file strips
                // follow it.
                if section == .inspections {
                    NovaEquipmentSectionStrip(counts: equipment?.counts ?? [:],
                        rows: equipment?.rows ?? [],
                        isLoading: equipment == nil && equipmentLoading,
                        onOpen: { equipmentSection = section },
                        onAdd: { equipmentAdding = true; equipmentSection = section })
                }
                // Files remain available in their real module. Generic evrak
                // tracker redirects do not belong under company process cards.
                let categories = NovaFileSectionMap.categories(for: section, in: fileCategories)
                if !hasDedicatedRow, !categories.isEmpty {
                    NovaFileSectionStrip(counts: files?.counts(forCategories: categories) ?? [:],
                        isLoading: files == nil && filesLoading) { fileSection = section }
                }
                if !hasDedicatedRow, let kinds = NovaDocumentSectionMap.kinds(for: section) {
                    NovaDocumentSectionStrip(counts: documents?.counts(forKinds: kinds) ?? [:],
                        isLoading: documents == nil && documentsLoading) { documentSection = section }
                }
                if NovaDocumentSectionMap.kinds(for: section) == nil && categories.isEmpty
                    && section != .personnel && section != .training && section != .inspections && section != .risk && moduleKind(section) == nil {
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.workspace.section.pending", table: .localizable, fallback: "Bu bölümün kayıt servisi henüz bağlanmadı. Eksik veya tamamlandı bilgisi doğrulanamıyor."))
                }
            }
    }
    private var personnelSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            statStrip([
                ("Toplam personel", "person.2", summary?.personnel_count ?? personnelRows.count),
                (personnelQuery.isEmpty ? "Listelenen" : "Arama sonucu", "magnifyingglass", personnelRows.count)
            ], identifier: "company.section.personnel.stats")
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.system(size: 15))
                TextField("Personel ara…", text: $personnelQuery)
                    .font(NovaFont.font(.body))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .accessibilityIdentifier("company.personnel.search")
                if !personnelQuery.isEmpty {
                    Button { personnelQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 36, height: 36)
                    }.buttonStyle(.plain).accessibilityLabel(RDLocalization.string("localizable.nova.nonconformity.search.clear", table: .localizable, fallback: "Aramayı temizle"))
                }
            }
            .padding(.horizontal, 12).frame(minHeight: 46)
            .novaControlBackground(cornerRadius: 14)
            if personnelLoading && personnelRows.isEmpty {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    NovaText(text: RDLocalization.string("localizable.nova.company.personnel.loading", table: .localizable,
                        fallback: "Personeller yükleniyor…"), style: .metaQuiet)
                }.frame(maxWidth: .infinity, minHeight: 48)
            } else if let personnelError {
                NovaEmptyState(title: RDLocalization.string("localizable.nova.company.personnel.load.failed", table: .localizable,
                    fallback: "Personel listesi alınamadı"), message: personnelError)
            } else if personnelRows.isEmpty {
                NovaEmptyState(title: personnelQuery.isEmpty
                    ? RDLocalization.string("localizable.nova.personnel.screens.henuz.personel.yok.d4c4f866", table: .localizable, fallback: "Henüz personel yok")
                    : RDLocalization.string("localizable.nova.appointment.form.person.empty", table: .localizable, fallback: "Eşleşen personel yok"),
                    message: personnelQuery.isEmpty
                        ? RDLocalization.string("localizable.nova.company.personnel.empty.detail", table: .localizable,
                            fallback: "Personel ekleyerek eğitim, atama ve zimmet işlemlerinde doğrudan seçim yapabilirsiniz.")
                        : RDLocalization.string("localizable.nova.company.personnel.nomatch.detail", table: .localizable,
                            fallback: "Ad, departman veya görev bilgisiyle farklı bir arama yapabilirsiniz."))
            } else {
                ForEach(personnelRows.prefix(6)) { row in
                    Button { personnelDetail = .init(id: row.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person").font(.system(size: 14)).frame(width: 32, height: 32)
                                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                NovaText(text: row.name, style: .bodyStrong)
                                let detail = [row.departmentName, row.jobTitle].compactMap { $0 }.joined(separator: " · ")
                                NovaText(text: detail.isEmpty
                                    ? RDLocalization.string("localizable.nova.company.personnel.detail.missing", table: .localizable,
                                        fallback: "Departman veya görev belirtilmedi") : detail,
                                    style: .micro, color: NovaColorToken.textMuted.color(in: scheme))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 48)
                        .novaControlBackground(cornerRadius: 13)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                NovaCompactActionButton(title: RDLocalization.string("localizable.nova.company.personnel.all", table: .localizable,
                    fallback: "Tüm personel"), symbol: "person.2") { sheet = .personnel }
                NovaCompactActionButton(title: "Personel ekle", symbol: "plus", prominent: true,
                    enabled: canWrite) { sheet = .addPersonnel }
                    .accessibilityIdentifier("company.personnel.add")
            }
        }
    }
    @MainActor private func loadPersonnelRows(query: String) async {
        if personnelRows.isEmpty { personnelLoading = true }
        personnelError = nil
        defer { personnelLoading = false }
        do {
            try await Task.sleep(nanoseconds: 180_000_000)
            let result = try await personnel.employees(scope, query, false, nil)
            try Task.checkCancellation()
            guard result.rows.count <= 50,
                  result.rows.allSatisfy({ $0.ownerID == scope.ownerID && $0.companyID == scope.companyID && !$0.isArchived }),
                  Set(result.rows.map(\.id)).count == result.rows.count else { throw NovaPersonnelFailure.unavailable }
            personnelRows = result.rows
        } catch is CancellationError {
            return
        } catch {
            personnelError = RDLocalization.string("localizable.nova.company.connection.retry", table: .localizable,
                fallback: "Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
    private var companyCard: some View {
        NovaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            companyMark
                            NovaSizedText(text: summary?.name ?? companyName, size: 17, weight: "Bold")
                        }
                        // Fixed two-column grid: six compact tags in three rows.
                        LazyVGrid(columns: [GridItem(.flexible(minimum: 70), spacing: 6), GridItem(.flexible(minimum: 70), spacing: 6)], alignment: .leading, spacing: 4) {
                            badge("Tehlike", value: summary.flatMap { CompanyHazardClass(rawValue: $0.hazard_class)?.title }, icon: "exclamationmark.triangle", tone: .text)
                            badge(RDLocalization.string("localizable.nova.company.sector", table: .localizable, fallback: "Sektör"), value: summary?.sector, icon: "square.grid.2x2", tone: .text)
                            badge("Personel", value: summary.map { String($0.personnel_count) }, icon: "person.2", tone: .text)
                            badge("Uygunsuzluk", value: nonconformityCount.map(String.init), icon: "checklist", tone: .text)
                            badge("Dosya", value: summary?.document_count.map(String.init), icon: "folder", tone: .text)
                            badge("Tamamlanan", value: "\(progress.completed)/\(progress.total)", icon: "chart.bar", tone: .text)
                        }
                    }
                    Spacer(minLength: 0)
                    NovaCompanyScoreRing(progress: progress).accessibilityIdentifier("company.score.ring")
                }
                if let contact = summary?.responsible_name {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(contact, systemImage: "person").font(NovaFont.font(.body))
                        if let phone = summary?.responsible_phone {
                            Label(phone, systemImage: "phone").font(NovaFont.font(.meta))
                        }
                        if let email = summary?.responsible_email {
                            Label(email, systemImage: "envelope").font(NovaFont.font(.meta))
                        }
                    }.foregroundStyle(NovaColorToken.text.color(in: scheme))
                        .textSelection(.enabled)
                }
                HStack(spacing: 4) {
                    Spacer()
                    Button { sheet = .editCompany } label: { Image(systemName: "pencil").frame(width: 36, height: 30) }
                        .accessibilityLabel(RDLocalization.string("localizable.nova.visual.2", table: .localizable, fallback: "Güncelle")).accessibilityIdentifier("company.edit")
                    Button { sheet = .deleteCompany } label: { Image(systemName: "trash").foregroundStyle(.red).frame(width: 36, height: 30) }
                        .accessibilityLabel(RDLocalization.string("localizable.nova.visual.3", table: .localizable, fallback: "Sil")).accessibilityIdentifier("company.delete")
                }.buttonStyle(.plain)
                if summaryFailed {
                    NovaButton(label: RDLocalization.string("localizable.nova.company.summary.retry", table: .localizable, fallback: "Özeti tekrar yükle"), symbol: "arrow.clockwise", variant: .surface) { summaryRevision = UUID() }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var companyMark: some View {
        if let companyLogo {
            Image(uiImage: companyLogo).resizable().scaledToFit().padding(5)
                .frame(width: 42, height: 42)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                .accessibilityLabel("Firma logosu")
        } else {
            NovaIcon(symbol: "building.2", size: 22).foregroundStyle(Color.black)
                .frame(width: 42, height: 42)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 11))
        }
    }
    private var companyLogoRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaCard(padding: 10) {
                HStack(spacing: 11) {
                    companyMark
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: companyRecord?.logoPath?.isEmpty == false ? "Firma logosu" : "Logo ekleyin", style: .bodyStrong)
                        NovaText(text: companyLogoSaving
                            ? RDLocalization.string("localizable.nova.company.logo.loading", table: .localizable, fallback: "Logo yükleniyor…")
                            : RDLocalization.string("localizable.nova.company.logo.usage", table: .localizable, fallback: "Firma kartında ve raporlarda kullanılır."), style: .micro,
                            color: NovaColorToken.textMuted.color(in: scheme))
                    }
                    Spacer(minLength: 0)
                    if companyLogoSaving {
                        ProgressView().controlSize(.small).frame(width: 44, height: 44)
                    } else {
                        PhotosPicker(selection: $companyLogoPicker, matching: .images) {
                            HStack(spacing: 5) {
                                Image(systemName: companyLogo == nil ? "plus" : "arrow.triangle.2.circlepath")
                                Text(companyLogo == nil
                                    ? RDLocalization.string("localizable.profile.view.logo.sec.4a97bac8", table: .localizable, fallback: "Logo seç")
                                    : RDLocalization.string("localizable.nova.company.logo.change", table: .localizable, fallback: "Değiştir"))
                            }
                            .font(.custom("PlusJakartaSans-SemiBold", size: 10))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .background(NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canWrite || companyRecord == nil)
                        .accessibilityIdentifier("company.logo.picker")
                    }
                }.frame(maxWidth: .infinity, minHeight: 52)
            }
            if let companyLogoError {
                NovaText(text: companyLogoError, style: .micro,
                    color: NovaColorToken.statusDangerInk.color(in: scheme))
            }
        }
    }
    @MainActor private func loadCompanyRecord() async {
        companyRecordLoaded = false
        guard let record = try? await CompanyService.shared.listCompanies(includeArchived: true)
            .first(where: { $0.id == scope.companyID }) else {
            companyRecord = nil; companyLogo = nil; return
        }
        guard !Task.isCancelled else { return }
        companyRecord = record
        companyRecordLoaded = true
        await loadCompanyLogo(from: record.logoPath)
    }
    @MainActor private func loadCompanyLogo(from path: String?) async {
        companyLogo = nil
        guard let path, !path.isEmpty,
              let image = try? await CompanyService.shared.logoImage(path: path), !Task.isCancelled else { return }
        companyLogo = image
    }
    @MainActor private func saveCompanyLogo(_ item: PhotosPickerItem) async {
        guard canWrite, let company = companyRecord else {
            companyLogoError = RDLocalization.string("localizable.nova.company.logo.company.missing", table: .localizable,
                fallback: "Firma kaydı yüklenmeden logo eklenemez.")
            companyLogoPicker = nil
            return
        }
        companyLogoSaving = true; companyLogoError = nil
        defer { companyLogoSaving = false; companyLogoPicker = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { throw NovaPersonnelFailure.validation }
            let path = try await CompanyService.shared.uploadLogo(image, companyID: company.id)
            var draft = CompanyDraft()
            draft.id = company.id; draft.name = company.name; draft.hazardClass = company.hazardClass
            draft.logoPath = path; draft.address = company.address ?? ""
            draft.contactPerson = company.contactPerson ?? ""; draft.department = company.department ?? ""
            draft.defaultResponsible = company.defaultResponsible ?? ""
            draft.defaultDueDaysText = company.defaultDueDays.map(String.init) ?? ""
            let saved = try await CompanyService.shared.saveCompany(draft)
            companyRecord = saved; companyRecordLoaded = true; companyLogo = image
            celebrate(NovaSuccessMessage.companyLogoAdded)
        } catch {
            companyLogoError = RDLocalization.string("localizable.nova.company.logo.save.failed", table: .localizable,
                fallback: "Logo eklenemedi. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
    private func badge(_ label: String, value: String?, icon: String, tone: NovaColorToken) -> some View {
        HStack(spacing: 5) {
            NovaIcon(symbol: icon, size: 13).foregroundStyle(Color.black)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.custom("PlusJakartaSans-Medium", size: 8)).foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                Text(value ?? "—").font(.custom("PlusJakartaSans-SemiBold", size: 10)).lineLimit(1).minimumScaleFactor(0.75)
            }
        }.padding(.vertical, 1).frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) · \(value ?? "—")")
    }
    private var companyStats: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NovaListStat(title: "Personel", symbol: "person.2", value: summary?.personnel_count ?? 0) { sheet = .personnel }.frame(width: 94)
                NovaListStat(title: "Uygunsuzluk", symbol: "checklist",
                    value: nonconformityCount.map(String.init) ?? "—",
                    onTap: onOpenNonconformities).frame(width: 94)
                NovaListStat(title: "Ekipman", symbol: "shippingbox", value: equipment?.total ?? 0) { equipmentSection = .inspections }.frame(width: 94)
                NovaListStat(title: "Kontrol", symbol: "calendar.badge.checkmark",
                    value: max(0, (equipment?.total ?? 0) - (equipment?.counts[.neverInspected] ?? 0))) {
                        equipmentAdding = true; equipmentSection = .inspections
                    }.frame(width: 94)
            }
        }
    }
    private var nonconformityCount: Int? {
        nonconformities.map { rows in rows.filter { $0.kind == .nonconformity }.count }
    }
    private var openNonconformityCount: Int {
        (nonconformities ?? []).filter {
            $0.kind == .nonconformity && !["closed", "cancelled"].contains($0.state)
        }.count
    }
    private var overdueNonconformityCount: Int {
        let today = NovaAnalysisWorkspace.todayISO()
        return (nonconformities ?? []).filter {
            $0.kind == .nonconformity && !["closed", "cancelled"].contains($0.state)
                && ($0.due_on.map { $0 < today } ?? false)
        }.count
    }
    private var nonconformityCard: some View {
        NovaCompanyAccordion(title: "Uygunsuzluklar", symbol: "checklist", state: nil,
            identifier: "company.section.nonconformities", expanded: $nonconformityExpanded) {
            VStack(alignment: .leading, spacing: 9) {
                if let rows = nonconformities {
                    statStrip([
                        ("Toplam", "checklist", nonconformityCount ?? 0),
                        (RDLocalization.string("localizable.nova.nonconformity.state.open", table: .localizable, fallback: "Açık"), "circle.dotted", openNonconformityCount),
                        (RDLocalization.string("localizable.nova.document.status.expired", table: .localizable, fallback: "Süresi geçti"), "exclamationmark.triangle", overdueNonconformityCount)
                    ], identifier: "company.section.nonconformities.stats")
                    let records = rows.filter { $0.kind == .nonconformity }
                    if records.isEmpty {
                        NovaEmptyState(title: RDLocalization.string("localizable.nova.nonconformity.empty", table: .localizable,
                                fallback: "Henüz uygunsuzluk kaydı yok"),
                            message: RDLocalization.string("localizable.nova.company.nonconformity.empty.detail", table: .localizable,
                                fallback: "Analiz bulgularını firmaya aktarabilir veya yeni bir uygunsuzluk kaydı açabilirsiniz."))
                    } else {
                        ForEach(records.prefix(3)) { row in
                            Button { onOpenNonconformities?() } label: {
                                HStack(spacing: 10) {
                                    NovaIcon(symbol: row.camefromFinding ? "sparkles" : "checklist", size: 15)
                                    VStack(alignment: .leading, spacing: 2) {
                                        NovaText(text: row.title, style: .bodyStrong).lineLimit(2)
                                        NovaText(text: "\(NovaNonconformityWords.state(row.state)) · \(row.opened_on)",
                                            style: .micro, color: NovaColorToken.textMuted.color(in: scheme))
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                                }
                                .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 48)
                                .novaControlBackground(cornerRadius: 13).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(onOpenNonconformities == nil)
                        }
                    }
                    if let onOpenNonconformities {
                        NovaCompactActionButton(title: RDLocalization.string("localizable.nova.company.nonconformity.open.all", table: .localizable,
                            fallback: "Tüm uygunsuzlukları aç"), symbol: "arrow.right",
                            action: onOpenNonconformities)
                    }
                } else if let nonconformityError {
                    NovaEmptyState(title: RDLocalization.string("localizable.nova.company.nonconformity.load.failed.title", table: .localizable,
                        fallback: "Uygunsuzluklar yüklenemedi"), message: nonconformityError)
                } else {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        NovaText(text: RDLocalization.string("localizable.nova.company.nonconformity.loading", table: .localizable,
                            fallback: "Uygunsuzluklar yükleniyor…"), style: .metaQuiet)
                    }.frame(maxWidth: .infinity, minHeight: 48)
                }
            }
        }
    }
    private func entry(_ title: String, _ icon: String, tone: NovaColorToken, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaCard(padding: 9) {
                HStack(spacing: 9) {
                    NovaIcon(symbol: icon, size: 19).foregroundStyle(tone.color(in: scheme))
                    Text(title).font(NovaFont.font(.body))
                    Spacer(minLength: 0)
                    NovaIcon(symbol: "chevron.right", size: 12)
                }.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }
}
