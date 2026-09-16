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
    /// The module's own counts for this company, so the Periyodik Kontroller
    /// heading and the module can never disagree about what is on record.
    @State private var equipment: NovaEquipmentBoard?
    @State private var equipmentLoading = false
    @State private var equipmentSection: NovaCompanySection?
    /// Set when the strip's own "Ekipman ekle" action opened the module, so
    /// it can skip straight to the add sheet instead of the inventory.
    @State private var equipmentAdding = false
    /// The risk module's own per-company tally (state → count), fetched the
    /// same lightweight way as equipment/documents/files, so the heading
    /// never claims "Eksik" while a record actually exists.
    @State private var riskSummary: (total: Int, counts: [String: Int])?
    /// Set when a section's own empty-state "Ekle" action opened the module,
    /// so it can skip straight to the add form instead of the record list.
    @State private var processAdding = false
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
        for section in NovaCompanySection.allCases {
            guard let kind = moduleKind(section) else { continue }
            if let row = processTracking?.summaries.first(where: { $0.id == kind }), row.available {
                result.states[section] = row.total > 0 ? .complete : .missing
            }
        }
        if let riskSummary { result.states[.risk] = riskSummary.total > 0 ? .complete : .missing }
        if let equipment { result.states[.inspections] = equipment.total > 0 ? .complete : .missing }
        return result
    }
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
            let board = try? await NovaRiskAssessmentService.live().board(documentIdentity,
                query: .init(company: scope.companyID, limit: 1))
            let mine = board?.companies.first { $0.id == scope.companyID }
            riskSummary = board.map { _ in (mine?.total ?? 0, mine?.counts ?? [:]) }
        }
        .novaFullScreenCover(item: $equipmentSection, onDismiss: {
            summaryRevision = UUID(); equipmentAdding = false
        }) { section in
            NovaPilotEquipmentGate(identity: documentIdentity, canWrite: canWrite,
                initialCompany: scope.companyID, headingOverride: section.title,
                startInAddMode: equipmentAdding,
                onBack: { equipmentSection = nil })
        }
        .novaFullScreenCover(item: $fileSection, onDismiss: { summaryRevision = UUID() }) { section in
            NovaPilotFileGate(identity: documentIdentity, canWrite: canWrite,
                initialCompany: scope.companyID,
                initialCategories: NovaFileSectionMap.categories(for: section, in: fileCategories),
                headingOverride: section.title,
                onBack: { fileSection = nil })
        }
        .novaFullScreenCover(isPresented: $addingFile, onDismiss: { summaryRevision = UUID() }) {
            NovaPilotFileGate(identity: documentIdentity, canWrite: canWrite,
                initialCompany: scope.companyID,
                headingOverride: NovaCompanySection.files.title,
                onBack: { addingFile = false })
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
    /// `counts` is the risk module's per-state tally for this company. The
    /// worst state present wins, same priority the risk board itself sorts by.
    private func riskTag(_ counts: [String: Int]) -> (String, NovaStatus)? {
        if (counts["expired"] ?? 0) > 0 { return (NovaRiskGroup.expired.title, .danger) }
        if (counts["due_soon"] ?? 0) > 0 { return (NovaRiskGroup.dueSoon.title, .warning) }
        if (counts["never_assessed"] ?? 0) > 0 || (counts["period_unknown"] ?? 0) > 0 { return (NovaRiskGroup.untracked.title, .info) }
        if (counts["valid"] ?? 0) > 0 { return (NovaRiskGroup.current.title, .success) }
        return nil
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
    private func sectionView(_ section: NovaCompanySection, outlinesWhenExpanded: Bool = true) -> some View {
        NovaCompanyAccordion(title: section.title, symbol: section.symbol, state: progress[section],
            identifier: "company.section.\(section.rawValue)",
            outlinesWhenExpanded: outlinesWhenExpanded,
            expanded: Binding(get: { expandedSections.contains(section) }, set: { value in
                if value { expandedSections.insert(section) } else { expandedSections.remove(section) }
            })) {
                if section == .personnel {
                    HStack(spacing: 8) {
                        NovaButton(label: "Personeller", symbol: "person.2", variant: .muted) { sheet = .personnel }
                        NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.personel.ekle.565c83dd", table: .localizable, fallback: "Personel Ekle"), symbol: "plus", isEnabled: canWrite) { sheet = .addPersonnel }
                            .accessibilityIdentifier("company.personnel.add")
                    }
                } else if section == .risk {
                    if let riskSummary {
                        if riskSummary.total > 0 {
                            moduleFilledRow(summary: "\(riskSummary.total) kayıt", tag: riskTag(riskSummary.counts)) { processKind = "risk" }
                        } else {
                            moduleEmptyState(addLabel: section.title + " Ekle") { processAdding = true; processKind = "risk" }
                        }
                    } else {
                        NovaButton(label: RDLocalization.string("localizable.nova.workspace.section.risk.open", table: .localizable, fallback: "Değerlendirmeleri aç"),
                            symbol: "shield", variant: .surface) { processKind = "risk" }
                    }
                } else if section == .training {
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.workspace.section.training.hint", table: .localizable,
                        fallback: "Gerçekleşen eğitimleri personel seçerek kaydedin ve eğitim geçmişini görüntüleyin."))
                    NovaButton(label: RDLocalization.string("localizable.nova.workspace.section.training.open", table: .localizable, fallback: "Eğitimleri aç"),
                        symbol: "graduationcap", variant: .surface) { sheet = .training }
                }
                if let kind = moduleKind(section) {
                    if let row = processTracking?.summaries.first(where: { $0.id == kind }), row.available {
                        if row.total > 0 {
                            let summary = String(format: RDLocalization.string("localizable.nova.workspace.section.tracking.summary", table: .localizable,
                                fallback: "%1$d kayıt · %2$d tarihi geçmiş · %3$d yaklaşan"), row.total, row.overdue, row.upcoming)
                            moduleFilledRow(summary: summary, tag: moduleTag(overdue: row.overdue, upcoming: row.upcoming, total: row.total)) { processKind = kind }
                        } else {
                            moduleEmptyState(addLabel: section.title + " Ekle") { processAdding = true; processKind = kind }
                        }
                    } else {
                        NovaButton(label: kind == "appointment"
                            ? RDLocalization.string("localizable.nova.workspace.section.appointments.open", table: .localizable, fallback: "Atamaları aç")
                            : RDLocalization.string("localizable.nova.workspace.section.records.open", table: .localizable, fallback: "Kayıtları aç"),
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
                if let kinds = NovaDocumentSectionMap.kinds(for: section) {
                    NovaDocumentSectionStrip(counts: documents?.counts(forKinds: kinds) ?? [:],
                        isLoading: documents == nil && documentsLoading) { documentSection = section }
                }
                // The archive is a second, separate thing from the tracker: the
                // tracker says what is owed, the archive holds the files that
                // were actually filed under this heading.
                let categories = NovaFileSectionMap.categories(for: section, in: fileCategories)
                if !categories.isEmpty {
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
