import SwiftUI

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
                NovaPageSurface { VStack(spacing: 18) { ProgressView(); NovaText(text: RDLocalization.string("localizable.nova.company.management.gate.firma.erisimi.dogrulaniyor.3bf732f2", table: .localizable, fallback: "Firma erişimi doğrulanıyor…")); NovaButton(label: RDLocalization.string("localizable.nova.company.management.gate.kapat.3148ed17", table: .localizable, fallback: "Kapat"), symbol: "xmark", variant: .surface, action: onClose) }.padding(18) }
            } else if controller.isAvailable && !legacyRequested {
                NavigationStack {
                    if let scope = controller.scope {
                        NovaCompanyWorkspace(scope: scope, companyName: controller.capability?.company_name ?? "Firma", canWrite: controller.canWrite,
                            personnel: controller.personnelClient, directory: controller.directoryClient, onBack: { controller.select(nil) })
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
    @State private var summary: NovaPilotCompanySummary?
    @State private var summaryFailed = false
    @State private var summaryRevision = UUID()
    @Environment(\.colorScheme) private var scheme
    @State private var sheet: Sheet?
    @State private var personnelPage = false
    @State private var processKind: String?
    @State private var processTracking: NovaModuleTrackingSnapshot?
    @State private var companyExpanded = false
    @State private var completedTrainings = 0
    @State private var expandedSections = Set<NovaCompanySection>()
    /// The tracker's own counts for this company, so a heading and the tracker
    /// can never disagree about what is on file.
    @State private var documents: NovaDocumentPortfolio?
    @State private var documentsLoading = false
    @State private var documentSection: NovaCompanySection?
    /// The archive's own counts for this company, so a heading and the archive
    /// can never disagree about which files are on it.
    @State private var files: NovaFileLibrary?
    @State private var fileCategories: [NovaFileCategory] = []
    @State private var filesLoading = false
    @State private var fileSection: NovaCompanySection?
    @State private var addingFile = false
    /// Set when a section's own empty-state "Ekle" action opened the archive,
    /// so it can skip straight to the upload form for that category.
    @State private var fileSectionAdding = false
    /// The module's own counts for this company, so the Periyodik Kontroller
    /// heading and the module can never disagree about what is on record.
    @State private var equipment: NovaEquipmentBoard?
    @State private var equipmentLoading = false
    @State private var equipmentSection: NovaCompanySection?
    /// Set when the strip's own "Ekipman ekle" action opened the module, so
    /// it can skip straight to the add sheet instead of the inventory.
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
        if let summary { result.states[.personnel] = summary.personnel_count > 0 ? .complete : .missing }
        result.states[.training] = completedTrainings > 0 ? .complete : .missing
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
        NovaPageSurface {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        NovaPageHeading(title: RDLocalization.string("localizable.nova.company.detail.title", table: .localizable, fallback: "Firma Detayı"), onBack: onBack)
                        companyCard
                        HStack(spacing: 10) {
                            NovaButton(label: RDLocalization.string("localizable.nova.company.management.gate.dosya.ekle.b9bb8c93", table: .localizable, fallback: "Dosya Ekle"), symbol: "folder.badge.plus", isEnabled: canWrite) { addingFile = true }
                            NovaButton(label: RDLocalization.string("localizable.nova.company.management.gate.evrak.ekle.386b7009", table: .localizable, fallback: "Evrak Ekle"), symbol: "doc.badge.plus", isEnabled: canWrite) { documentSection = .files }
                        }
                        if !canWrite { NovaCard(padding: 16) { Label(RDLocalization.string("localizable.nova.company.management.gate.salt.okunur.kayitlariniz.korunuyor.2cc72e1b", table: .localizable, fallback: "Salt okunur · kayıtlarınız korunuyor"), systemImage: "lock"); NovaText(text: RDLocalization.string("localizable.nova.company.management.gate.yeni.kayit.ve.duzenleme.su.anda.kullanilamiyor.d83e8253", table: .localizable, fallback: "Yeni kayıt ve düzenleme şu anda kullanılamıyor."), style: .metaQuiet) } }
                        NovaCompanyAccordion(title: RDLocalization.string("localizable.nova.workspace.company.info", table: .localizable, fallback: "Firma Bilgileri"), symbol: "building.2", expanded: $companyExpanded) {
                            ForEach([NovaCompanySection.logo, .personnel]) { section in
                                sectionView(section, outlinesWhenExpanded: false)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                            ForEach([NovaDirectoryKind.workplaces, .departments, .jobs, .contractors], id: \.self) { kind in
                                entry(kind.title, kind.symbol, tone: kind == .departments ? .statusWarningInk : .accentInk) { sheet = .directory(kind) }
                            }
                            }
                        }
                        NovaModuleTrackingCard(identity: documentIdentity, company: scope.companyID, canWrite: canWrite, onLoaded: { processTracking = $0 })
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
            completedTrainings = 0
            let service = NovaTrainingService(identity: .init(userID: scope.ownerID, sessionID: scope.sessionID))
            if let page = try? await service.list(scope.companyID), !Task.isCancelled { completedTrainings = page.completed ?? 0 }
        }
        .task(id: summaryRevision) {
            documentsLoading = true
            defer { documentsLoading = false }
            let service = NovaDocumentTrackingService.live(currentScope: { scope })
            documents = try? await service.portfolio(documentIdentity, company: scope.companyID, limit: 1)
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
            equipmentLoading = true
            defer { equipmentLoading = false }
            equipment = try? await NovaEquipmentCheckService.live().board(documentIdentity,
                query: .init(company: scope.companyID, limit: 1))
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
        .novaFullScreenCover(item: $documentSection) { section in
            NovaPilotDocumentGate(identity: documentIdentity, scope: scope, canWrite: canWrite,
                select: { _ in }, currentScope: { scope },
                onBack: { documentSection = nil }, onCompanies: { documentSection = nil },
                initialCompany: scope.companyID,
                initialKinds: NovaDocumentSectionMap.kinds(for: section),
                headingOverride: section.title)
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
                    NovaCompanyVisualEditor(name: summary?.name ?? companyName, sector: summary?.sector ?? "", email: summary?.email ?? "", hazard: summary?.hazard_class ?? "medium")
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
        if overdue > 0 { return ("Süresi geçti", .danger) }
        if upcoming > 0 { return ("Yaklaşıyor", .warning) }
        return ("Güncel", .success)
    }
    /// A record is already on file: show what's on it and let the row itself
    /// open the module, instead of a generic "aç" button.
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
    /// fixes it, instead of a bare "aç" into an empty list.
    private func moduleEmptyState(addLabel: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.workspace.section.empty", table: .localizable,
                fallback: "Henüz eklenmemiştir, ilgili alandan dosya/bilgi ekleyebilirsiniz."), style: .meta)
            NovaButton(label: addLabel, symbol: "plus", variant: .surface, isEnabled: canWrite, action: action)
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
                        NovaText(text: "Değerlendirme: " + NovaStatisticsSnapshot.dayLabel(assessedOn), style: .bodyStrong)
                    } else {
                        NovaText(text: "Risk analizi eklendi", style: .bodyStrong)
                    }
                    if let validUntil = row.validUntil {
                        NovaText(text: "Geçerlilik: " + NovaStatisticsSnapshot.dayLabel(validUntil), style: .micro)
                    }
                }
                Spacer(minLength: 0)
                NovaStatusPill(label: row.group.title, status: riskGroupStatus(row.group))
                Image(systemName: "chevron.right").font(.system(size: 11))
            }.frame(minHeight: 40).contentShape(Rectangle())
        }.buttonStyle(.plain)
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
                    HStack(spacing: 8) {
                        NovaButton(label: "Personeller", symbol: "person.2", variant: .muted) { sheet = .personnel }
                        NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.personel.ekle.565c83dd", table: .localizable, fallback: "Personel Ekle"), symbol: "plus", isEnabled: canWrite) { sheet = .addPersonnel }
                            .accessibilityIdentifier("company.personnel.add")
                    }
                } else if section == .representative || section == .support {
                    let board = section == .representative ? representativeAppointment : supportAppointment
                    if let board {
                        if let appointment = board.rows.first {
                            appointmentRow(appointment)
                        } else {
                            moduleEmptyState(addLabel: section.title + " Ekle") { processAdding = true; processKind = "appointment" }
                        }
                    } else {
                        NovaButton(label: RDLocalization.string("localizable.nova.workspace.section.appointments.open", table: .localizable, fallback: "Atamaları aç"),
                            symbol: "chevron.right", variant: .surface) { processKind = "appointment" }
                    }
                } else if section == .risk {
                    if let riskBoard {
                        if let row = riskBoard.rows.first {
                            riskRow(row)
                        } else {
                            moduleEmptyState(addLabel: section.title + " Ekle") { processAdding = true; processKind = "risk" }
                        }
                    } else {
                        NovaButton(label: RDLocalization.string("localizable.nova.workspace.section.risk.open", table: .localizable, fallback: "Değerlendirmeleri aç"),
                            symbol: "shield", variant: .surface) { processKind = "risk" }
                    }
                } else if section == .accidents, !accidentCategories.isEmpty {
                    if let files {
                        let total = files.counts(forCategories: accidentCategories).values.reduce(0, +)
                        if total > 0 {
                            moduleFilledRow(summary: "\(total) dosya", tag: ("Güncel", .success)) { fileSection = .accidents }
                        } else {
                            moduleEmptyState(addLabel: section.title + " Ekle") { fileSectionAdding = true; fileSection = .accidents }
                        }
                    } else {
                        NovaText(text: RDLocalization.string("localizable.nova.file.loading", table: .localizable, fallback: "Dosyalar yükleniyor…"), style: .metaQuiet)
                    }
                } else if section == .training {
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.workspace.section.training.hint", table: .localizable,
                        fallback: "Gerçekleşen eğitimleri personel seçerek kaydedin ve eğitim geçmişini görüntüleyin."))
                    NovaButton(label: RDLocalization.string("localizable.nova.workspace.section.training.open", table: .localizable, fallback: "Eğitimleri aç"),
                        symbol: "graduationcap", variant: .surface) { sheet = .training }
                }
                if let kind = moduleKind(section), section != .representative, section != .support {
                    if let row = processTracking?.summaries.first(where: { $0.id == kind }), row.available {
                        if row.total > 0 {
                            let summary = String(format: RDLocalization.string("localizable.nova.workspace.section.tracking.summary", table: .localizable,
                                fallback: "%1$d kayıt · %2$d tarihi geçmiş · %3$d yaklaşan"), row.total, row.overdue, row.upcoming)
                            moduleFilledRow(summary: summary, tag: moduleTag(overdue: row.overdue, upcoming: row.upcoming, total: row.total)) { processKind = kind }
                        } else {
                            moduleEmptyState(addLabel: section.title + " Ekle") { processAdding = true; processKind = kind }
                        }
                    } else {
                        NovaButton(label: RDLocalization.string("localizable.nova.workspace.section.records.open", table: .localizable, fallback: "Kayıtları aç"),
                            symbol: "chevron.right", variant: .surface) { processKind = kind }
                    }
                    if section == .emergency {
                        NovaButton(label: RDLocalization.string("localizable.nova.workspace.section.drills.open", table: .localizable, fallback: "Tatbikatları aç"),
                            symbol: "figure.run", variant: .surface) { processKind = "drill" }
                    }
                }
                // Periodic checks are the whole of this heading, so the
                // inventory comes first and the obligation and file strips
                // follow it.
                if section == .inspections {
                    NovaEquipmentSectionStrip(counts: equipment?.counts ?? [:],
                        isLoading: equipment == nil && equipmentLoading,
                        onOpen: { equipmentSection = section },
                        onAdd: { equipmentAdding = true; equipmentSection = section })
                }
                if !hasDedicatedRow, let kinds = NovaDocumentSectionMap.kinds(for: section) {
                    NovaDocumentSectionStrip(counts: documents?.counts(forKinds: kinds) ?? [:],
                        isLoading: documents == nil && documentsLoading) { documentSection = section }
                }
                // The archive is a second, separate thing from the tracker: the
                // tracker says what is owed, the archive holds the files that
                // were actually filed under this heading.
                let categories = NovaFileSectionMap.categories(for: section, in: fileCategories)
                if !hasDedicatedRow, !categories.isEmpty {
                    NovaFileSectionStrip(counts: files?.counts(forCategories: categories) ?? [:],
                        isLoading: files == nil && filesLoading) { fileSection = section }
                }
                if NovaDocumentSectionMap.kinds(for: section) == nil && categories.isEmpty
                    && section != .personnel && section != .training && section != .inspections && section != .risk && moduleKind(section) == nil {
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.workspace.section.pending", table: .localizable, fallback: "Bu bölümün kayıt servisi henüz bağlanmadı. Eksik veya tamamlandı bilgisi doğrulanamıyor."))
                }
            }
    }
    private var companyCard: some View {
        NovaCard(padding: 14, tint: NovaColorToken.surfaceMuted.color(in: scheme)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            NovaIcon(symbol: "building.2", size: 24).foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                            NovaSizedText(text: summary?.name ?? companyName, size: 17, weight: "Bold")
                        }
                        // Fixed two-column grid: six compact tags in three rows.
                        LazyVGrid(columns: [GridItem(.flexible(minimum: 70), spacing: 6), GridItem(.flexible(minimum: 70), spacing: 6)], alignment: .leading, spacing: 4) {
                            badge("Tehlike", value: summary.flatMap { CompanyHazardClass(rawValue: $0.hazard_class)?.title }, icon: "exclamationmark.triangle", tone: .statusWarningInk)
                            badge(RDLocalization.string("localizable.nova.company.sector", table: .localizable, fallback: "Sektör"), value: summary?.sector, icon: "square.grid.2x2", tone: .statusInfoInk)
                            badge("Personel", value: summary.map { String($0.personnel_count) }, icon: "person.2", tone: .accentInk)
                            badge("Uygunsuzluk", value: summary?.finding_count.map(String.init), icon: "risk", tone: .statusDangerInk)
                            badge("Evrak", value: summary?.document_count.map(String.init), icon: "doc.text", tone: .statusInfoInk)
                            badge("Tamamlanma", value: progress.score.map(String.init), icon: "chart.bar", tone: .statusSuccessInk)
                        }
                    }
                    Spacer(minLength: 0)
                    NovaCompanyScoreRing(progress: progress).accessibilityIdentifier("company.score.ring")
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
    private func badge(_ label: String, value: String?, icon: String, tone: NovaColorToken) -> some View {
        HStack(spacing: 5) {
            NovaIcon(symbol: icon, size: 14).foregroundStyle(tone.color(in: scheme))
            Text(value ?? "—").font(.custom("PlusJakartaSans-Medium", size: 10)).lineLimit(1).minimumScaleFactor(0.75)
        }.padding(.vertical, 1).frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) · \(value ?? "—")")
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
