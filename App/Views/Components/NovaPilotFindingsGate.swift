import SwiftUI

/// Which menu entry opened this surface. Each one lands on exactly one page;
/// there is no hub in between.
enum NovaFindingsSurface: Equatable { case board, analyses, newAnalysis, addFinding }

/// The analysis and nonconformity surfaces. The analysis engine, the report
/// renderer and the nonconformity boundary are the ones already shipping; this
/// carries them and owns nothing of its own.
struct NovaPilotFindingsGate: View {
    let identity: NovaSessionIdentity
    /// The company workspace currently in scope, or nil when none is selected.
    let scope: NovaPersonnelScope?
    let canWrite: Bool
    /// Selecting a company here is the same selection the Firmalar tab uses;
    /// the workspace follows the record rather than keeping two scopes.
    let select: (UUID?) -> Void
    let currentScope: () -> NovaPersonnelScope?
    let surface: NovaFindingsSurface
    let onNavigate: (NovaDestination) -> Void
    let onCompanies: () -> Void
    let onHome: () -> Void
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    private enum Route: Equatable { case root, photo, manual, reports }
    /// The analysis detail is presented over the shell rather than pushed into
    /// it, because that page owns its own pinned bar and must not sit under
    /// the tab bar.
    private struct AnalysisTarget: Identifiable, Equatable { let id: UUID }
    @State private var route: Route = .root
    @State private var openAnalysis: AnalysisTarget?
    @State private var pending: UUID?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var images: [UIImage] = []
    @State private var draft = NovaAnalysisIntakeDraft()
    @State private var intakeOpen = false
    @State private var job: NovaPhotoBridgeJob?
    @State private var record: NovaNonconformityEntry?
    @State private var notice: String?
    @State private var boardRevision = UUID()

    private var service: NovaNonconformityService { .live(currentScope: currentScope) }
    private var analysisFilingService: NovaNonconformityService { .live(identity: identity) }
    private var files: NovaFileLibraryService { .live() }
    private var today: String { NovaAnalysisWorkspace.todayISO() }
    private var method: RiskMethod { app.profile?.preferredMethod?.domain ?? .fineKinney }
    private var organizationEntitlements: Bool {
        NovaExpertTransport.shared.capture()?.access.usesOrganizationEntitlements == true
    }

    var body: some View {
        Group {
            switch route {
            case .root: root
            case .photo: photo
            case .manual: manual
            case .reports: reports
            }
        }
        // The finished analysis is opened from the waiting screen's own
        // dismissal, so the two presentations never contend for the same slot.
        .novaFullScreenCover(item: $job, onDismiss: {
            guard let id = pending else { return }
            pending = nil
            openAnalysis = .init(id: id)
        }) { work in
            AnalyzingView(isPresented: Binding(get: { job != nil }, set: { if !$0 { job = nil } }),
                previewImage: work.preview, photoCount: work.photoCount,
                onError: { message in job = nil; notice = message },
                identityWork: work.work, onCompleteIdentity: { analysisID in
                    images = []
                    pending = analysisID
                    job = nil
                })
        }
        .novaFullScreenCover(item: $openAnalysis) { target in
            detail(target.id)
        }
        .novaPopupCover(item: $record) { entry in
            NovaPopup {
                if entry.row.camefromFinding {
                    NovaFiledFindingSheet(entry: entry, identity: identity, preferredMethod: method,
                        fallbackClient: recordClient(entry), canWrite: canWrite)
                } else {
                    NovaNonconformityRecordSheet(entry: entry, client: recordClient(entry), canWrite: canWrite)
                }
            }
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(RDLocalization.string("localizable.nova.bridge.alert.ok", table: .localizable, fallback: "Tamam")) { notice = nil }
        }
        .task { await loadCompanies() }
        .onChange(of: record) { value in if value == nil { boardRevision = UUID() } }
        .onAppear { if surface == .newAnalysis { route = .photo } }
    }

    @ViewBuilder private var root: some View {
        switch surface {
        case .board: board
        case .analyses: analyses
        case .newAnalysis: photo
        case .addFinding: addFinding
        }
    }

    private func loadCompanies() async {
        companies = (try? await NovaAnalysisWorkspace.companyOptions(identity: identity)) ?? []
    }

    // MARK: board

    private var board: some View {
        NovaNonconformityListScreen(
            client: .init(
                load: { try await NovaAnalysisWorkspace.board(identity: identity) },
                thumbnail: { await NovaAnalysisWorkspace.recordThumbnail($0) },
                // Opening a record must not rebuild the whole workspace first.
                // Doing that cleared `record` before the full-screen cover could
                // present, so the row looked as if it did not respond to taps.
                open: { entry in record = entry },
                create: { onNavigate(.newFinding) }),
            companies: companies, today: today, onBack: onHome)
            .id(boardRevision)
    }

    private func recordClient(_ entry: NovaNonconformityEntry) -> NovaNonconformityRecordClient {
        let recordScope = analysisFilingScope(entry.companyID)
        return .init(
            load: { try await analysisFilingService.detail(recordScope, id: entry.id) },
            transition: { state, reason, assignee in
                let current = try await analysisFilingService.detail(recordScope, id: entry.id)
                return try await analysisFilingService.transition(recordScope, id: entry.id, to: state,
                    expectedVersion: current.version, reason: reason, assignee: assignee)
            },
            addAction: { description, assignee, due in
                try await analysisFilingService.addAction(recordScope, id: entry.id, description: description,
                    assignee: assignee, dueOn: due)
            },
            verify: { accepted, note in
                try await analysisFilingService.verify(recordScope, id: entry.id, accepted: accepted, note: note)
            },
            saveDetail: { draft in
                try await analysisFilingService.setDetail(recordScope, id: entry.id, description: draft.description,
                    measure: draft.measure, legislation: draft.legislation, responsible: draft.responsible,
                    score: draft.score)
            },
            download: { bucket, path in try await files.download(identity, bucket: bucket, path: path) })
    }

    /// Selecting a company runs the workspace availability check again, so the
    /// scope arrives a moment later. Waiting for it is waiting for a real
    /// verification, not working around one.
    private func waitForScope(_ company: UUID) async throws -> NovaPersonnelScope {
        if let ready = currentScope(), ready.companyID == company { return ready }
        select(company)
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if let ready = currentScope(), ready.companyID == company { return ready }
        }
        throw NovaNonconformityFailure.denied
    }

    // MARK: add a nonconformity

    private var addFinding: some View {
        NovaPageSurface(onEdgeBack: { onNavigate(.findings) }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        NovaBackButton { onNavigate(.findings) }
                        NovaText(text: NovaDestination.newFinding.title, style: .screenTitle)
                        Spacer(minLength: 0)
                    }
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.add.finding.hint", table: .localizable,
                        fallback: "Daha önce yaptığınız bir analizin bulgularından seçebilir ya da kaydı kendiniz girebilirsiniz."))
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            NovaText(text: RDLocalization.string("localizable.nova.add.finding.from.analysis", table: .localizable,
                                fallback: "Analiz bulgularından seç"), style: .cardTitle)
                            NovaText(text: RDLocalization.string("localizable.nova.add.finding.from.analysis.detail", table: .localizable,
                                fallback: "Bir analizi açın, bulguları seçin ve firmaya uygunsuzluk olarak aktarın."), style: .metaQuiet)
                            NovaButton(label: NovaDestination.analyses.title, symbol: "photo.on.rectangle.angled") { onNavigate(.analyses) }
                                .accessibilityIdentifier("addfinding.analyses")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            NovaText(text: RDLocalization.string("localizable.nova.add.finding.manual", table: .localizable,
                                fallback: "Kendim gireceğim"), style: .cardTitle)
                            NovaText(text: RDLocalization.string("localizable.nova.add.finding.manual.detail", table: .localizable,
                                fallback: "Fotoğraf, firma, tehlike, skorlama, mevzuat ve sorumlu adım adım sorulur."), style: .metaQuiet)
                            NovaButton(label: RDLocalization.string("localizable.nova.add.finding.manual.action", table: .localizable, fallback: "Forma geç"),
                                symbol: "square.and.pencil", variant: .surface, isEnabled: canWriteSomewhere) { route = .manual }
                                .accessibilityIdentifier("addfinding.manual")
                            if !canWriteSomewhere {
                                NovaText(text: RDLocalization.string("localizable.nova.manual.no.company", table: .localizable,
                                    fallback: "Bu hesapta kayıt açılacak firma yok."), style: .metaQuiet)
                                NovaButton(label: NovaDestination.companies.title, symbol: "building.2", variant: .surface) { onCompanies() }
                                    .accessibilityIdentifier("addfinding.companies")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            NovaText(text: NovaDestination.newAnalysis.title, style: .cardTitle)
                            NovaText(text: RDLocalization.string("localizable.nova.add.finding.new.analysis", table: .localizable,
                                fallback: "Elinizde yeni bir fotoğraf varsa önce analiz edin."), style: .metaQuiet)
                            NovaButton(label: RDLocalization.string("localizable.nova.nonconformity.choose.photo.action", table: .localizable, fallback: "Fotoğraf seç"),
                                symbol: "camera", variant: .surface) { onNavigate(.newAnalysis) }
                                .accessibilityIdentifier("addfinding.photo")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
    }

    private var canWriteSomewhere: Bool { !companies.isEmpty }

    // MARK: photo

    private var photo: some View {
        NovaPhotoIntakeScreen(images: $images, onStart: {
            draft = NovaAnalysisIntakeDraft()
            draft.photoCount = images.count
            // The workspace already has a company selected: offer it as the
            // answer rather than making the expert pick it again.
            if let current = scope?.companyID, let match = companies.first(where: { $0.id == current }) {
                draft.choose(owner: .company(id: match.id, name: match.name, sector: match.sector),
                    catalog: Self.sectorOptions.map { .init(id: $0.id, labels: [$0.label]) })
            }
            intakeOpen = true
        }, onBack: { onNavigate(.findings) })
        .novaPopupCover(isPresented: $intakeOpen) {
            NovaPopup {
                NovaAnalysisIntakePopup(companies: companies, sectors: Self.sectorOptions, focuses: focusOptions,
                    draft: $draft, isStarting: job != nil, onStart: { intakeOpen = false; start() })
            }
        }
    }

    static var sectorOptions: [NovaAnalysisSectorOption] {
        AnalysisSectorID.allCases.map {
            .init(id: $0.rawValue, label: $0.label(), subtitle: $0.subtitle, symbol: $0.icon)
        }
    }

    private var focusOptions: [NovaAnalysisFocusOption] {
        AnalysisCanvas.all.map { canvas in
            .init(id: canvas.id, title: canvas.title, detail: canvas.body, symbol: canvas.icon,
                  isLocked: !organizationEntitlements && !app.currentTier.includes(canvas.minTier),
                  lockLabel: canvas.minTier.title)
        }
    }

    /// Hands the existing pipeline the work. The company, sector and focus are
    /// exactly what the expert answered; nothing is filled in behind them.
    private func start() {
        guard draft.isReady, !images.isEmpty else { return }
        let localization = app.localizationRequestForNewAnalysis
        if RDGlobalLocalizationBuildGate.isEnabled && localization == nil {
            notice = RDLocalization.string("localizable.nova.analysis.localization.required", table: .localizable,
                fallback: "Güvenlik terminolojisi profili tamamlanmadan analiz başlatılamaz.")
            return
        }
        let canvases = AnalysisCanvas.all.filter { draft.focusIDs.contains($0.id) && (organizationEntitlements || app.currentTier.includes($0.minTier)) }
        guard !canvases.isEmpty else {
            notice = RDLocalization.string("localizable.nova.analysis.focus.required", table: .localizable,
                fallback: "Planınızın kapsadığı en az bir odak seçin.")
            return
        }
        let sector = draft.sectorID.flatMap(AnalysisSectorID.init(rawValue:))
        let company = draft.owner.companyID
        select(company)
        let captured = images
        let owner = identity.userID
        job = NovaPhotoBridgeJob(work: { progress in
            if let backend = try NovaExpertAnalysisBackend.current() {
                return try await backend.run(company: company, images: captured, focuses: canvases.map(\.id), sector: sector?.rawValue, progress: progress)
            }
            return try await AnalysisService.shared.runPhotoAnalysis(userID: owner, images: captured, canvases: canvases,
                localization: localization, analysisSector: sector, companyID: company, onProgress: progress).analysis.id
        }, preview: captured.first, photoCount: captured.count)
    }

    // MARK: analyses and detail

    private var analyses: some View {
        NovaAnalysisListScreen(
            load: { offset in try await NovaAnalysisWorkspace.summaries(identity: identity, method: method, offset: offset) },
            thumbnail: { await NovaAnalysisWorkspace.thumbnail(analysisID: $0) },
            onOpen: { openAnalysis = .init(id: $0) }, onBack: { onNavigate(.findings) },
            onNewPhotoAnalysis: { onNavigate(.newAnalysis) },
            onReports: { route = .reports })
    }

    /// The archive of reports produced from photo analyses.
    private var reports: some View {
        NovaAnalysisReportsScreen(
            load: { try await NovaAnalysisWorkspace.reports(identity: identity) },
            onBack: { route = .root },
            onOpenAnalysis: { openAnalysis = .init(id: $0) })
    }

    private func detail(_ analysisID: UUID) -> some View {
        NovaAnalysisDetailScreen(analysisID: analysisID, client: detailClient(analysisID),
            onBack: { openAnalysis = nil; boardRevision = UUID() },
            canWrite: NovaExpertTransport.shared.capture()?.access.canOperate ?? canWrite)
            .modifier(NovaSuccessPresentation())
    }

    private func detailClient(_ analysisID: UUID) -> NovaAnalysisDetailClient {
        .init(
            load: { try await NovaAnalysisWorkspace.detail(analysisID: analysisID, identity: identity,
                method: method, methodLabel: method.label) },
            photos: { await NovaAnalysisWorkspace.photos(analysisID: analysisID) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            assign: { company in
                try await NovaAnalysisWorkspace.assign(analysisID: analysisID, companyID: company)
                select(company)
            },
            workplaces: { company in try await analysisFilingService.filingWorkplaces(analysisFilingScope(company)) },
            file: { request in await file(request, analysisID: analysisID) },
            edit: { try await NovaAnalysisWorkspace.edit($0) },
            remove: { try await NovaAnalysisWorkspace.remove(analysisID: analysisID, findingID: $0.id) },
            react: { item, section, reaction in
                try await NovaAnalysisWorkspace.react(analysisID: analysisID, itemID: item.id,
                    section: section, reaction: reaction)
            },
            report: { request in
                try await NovaAnalysisWorkspace.report(request, profile: app.profile, userID: identity.userID,
                    company: nil)
            })
    }

    /// The server serializes company/source and returns an existing record on repeat clicks.
    private func file(_ request: NovaAnalysisFileRequest, analysisID: UUID) async -> NovaFindingOutcome {
        do {
            if let backend = try NovaExpertAnalysisBackend.current() {
                let created = try await backend.file(request, analysis: analysisID)
                boardRevision = UUID()
                return created ? .opened : .alreadyOpen
            }
        } catch { return .failed(RDLocalization.string("localizable.nova.finding.file.company.failed", table: .localizable,
            fallback: "Kayıt oluşturulamadı. Firma erişiminizi kontrol edip tekrar deneyin.")) }
        guard let company = request.companyID ?? currentScope()?.companyID else {
            return .failed(NovaNonconformityWords.failure(.denied))
        }
        let current = analysisFilingScope(company)
        var intent = NovaNonconformityIntent(origin: request.section.isScored ? .finding : .expertItem,
            workplaceID: request.workplaceID, title: request.item.title)
        intent.severity = request.severity
        intent.recordKind = request.recordKind
        if request.section.isScored {
            intent.findingID = request.item.id
            intent.sourceMethod = request.sourceMethod
            if request.severity == nil { intent.riskBand = request.band }
        } else {
            intent.expertItemID = request.item.id
            intent.hazardDescription = request.item.body
        }
        do {
            let result = try await analysisFilingService.open(current, intent: intent)
            // An analysis finding has already been reviewed and deliberately
            // assigned to a company. It enters the actionable queue as Open;
            // Draft is reserved for unfinished manual entry.
            let filedRow = result.row.state == NovaNonconformityState.draft.rawValue
                ? try await analysisFilingService.transition(current, id: result.row.id, to: .open,
                    expectedVersion: result.row.version, reason: "")
                : result.row
            // Do not celebrate a write until the same read path used by the
            // board can see it. This catches a contract/read projection drift
            // instead of telling the user a record exists while hiding it.
            let visible = try await analysisFilingService.list(current)
            guard visible.contains(where: { $0.id == filedRow.id && $0.state == filedRow.state }) else {
                return .failed(RDLocalization.string("localizable.nova.bridge.outcome.verify.failed", table: .localizable,
                    fallback: "İşlem sonucu doğrulanamadı. Yeniden denemeden önce listeyi yenileyin."))
            }
            boardRevision = UUID()
            return result.alreadyOpen ? .alreadyOpen : .opened
        } catch let failure as NovaNonconformityFailure {
            return .failed(NovaNonconformityWords.failure(failure))
        } catch {
            return .failed(RDLocalization.string("localizable.nova.bridge.outcome.failed", table: .localizable,
                fallback: "Bu bulgu için kayıt açılamadı. Aynı işlemi tekrar deneyin."))
        }
    }

    private func analysisFilingScope(_ company: UUID) -> NovaPersonnelScope {
        .init(ownerID: identity.userID, sessionID: identity.sessionID, companyID: company,
              epoch: "analysis-filing:\(company.uuidString.lowercased())")
    }

    // MARK: manual

    private var manual: some View {
        NovaManualNonconformityScreen(companies: companies,
            workplaces: { company in try await service.workplaces(try await waitForScope(company)) },
            fileClient: fileClient,
            save: { draft in await saveManual(draft) },
            onBack: { route = .root })
    }

    private var fileClient: NovaFileLibraryClient {
        .init(
            catalogue: { try await files.catalogue(identity) },
            library: { request in try await files.library(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            file: { company, draft, data in try await files.file(identity, company: company, draft: draft, data: data) },
            rename: { entry, title, category, note in
                try await files.rename(identity, entry: entry, title: title, category: category, note: note) },
            archive: { entry in try await files.archive(identity, entry: entry) },
            cancel: { entry in try await files.cancel(identity, entry: entry) },
            recheck: { entry in try await files.recheck(identity, entry: entry) },
            contents: { entry in try await files.contents(identity, entry: entry) },
            download: { bucket, path in try await files.download(identity, bucket: bucket, path: path) })
    }

    /// Returns nil when the record was opened, and the reason otherwise.
    private func saveManual(_ value: NovaManualDraft) async -> String? {
        guard let company = value.companyID, let workplace = value.workplaceID else {
            return NovaNonconformityWords.failure(.validation)
        }
        guard let target = try? await waitForScope(company) else {
            return NovaNonconformityWords.failure(.denied)
        }
        var intent = NovaNonconformityIntent(origin: .detailed, workplaceID: workplace,
            title: value.title.trimmingCharacters(in: .whitespacesAndNewlines))
        intent.severity = value.severity
        intent.recordKind = value.recordKind
        intent.hazardDescription = value.hazardDescription
        intent.controlMeasure = value.controlMeasure
        intent.legislation = value.legislation
        intent.responsible = value.responsible
        intent.score = value.score
        intent.evidenceAssetIDs = value.evidenceAssetIDs
        do {
            let result = try await service.open(target, intent: intent)
            let visible = try await service.list(target)
            guard visible.contains(where: { $0.id == result.row.id }) else {
                return RDLocalization.string("localizable.nova.bridge.outcome.verify.failed", table: .localizable,
                    fallback: "İşlem sonucu doğrulanamadı. Yeniden denemeden önce listeyi yenileyin.")
            }
            if !result.alreadyOpen {
                NotificationCenter.default.post(name: Notification.Name("isgada.mutation.succeeded"), object: identity.userID,
                    userInfo: ["message": NovaSuccessMessage.findingCreated])
            }
            boardRevision = UUID()
            onNavigate(.findings)
            return nil
        } catch let failure as NovaNonconformityFailure {
            return NovaNonconformityWords.failure(failure)
        } catch {
            return RDLocalization.string("localizable.nova.nonconformity.error.save", table: .localizable,
                fallback: "Kayıt açılamadı. Bilgileri kontrol edip aynı işlemi tekrar deneyin.")
        }
    }
}
