import SwiftUI

/// The Uygunsuzluklar tab, end to end: the record board across companies, one
/// record's own page, a photo analysis that may or may not belong to a company,
/// its detail page, and the hand-entered form. The analysis engine, the report
/// renderer and the nonconformity boundary are the ones already shipping.
struct NovaPilotFindingsGate: View {
    let identity: NovaSessionIdentity
    /// The company workspace currently in scope, or nil when none is selected.
    let scope: NovaPersonnelScope?
    let canWrite: Bool
    /// Selecting a company here is the same selection the Firmalar tab uses;
    /// the workspace follows the record rather than keeping two scopes.
    let select: (UUID?) -> Void
    let currentScope: () -> NovaPersonnelScope?
    var startMode: NovaFindingsStart = .board
    let onCompanies: () -> Void
    let onHome: () -> Void
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    private enum Route: Equatable {
        case board, chooser, photo, manual, analyses
        case record(NovaNonconformityEntry)
        case detail(UUID)
    }
    @State private var route: Route = .board
    @State private var started = false
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var images: [UIImage] = []
    @State private var draft = NovaAnalysisIntakeDraft()
    @State private var intakeOpen = false
    @State private var job: NovaPhotoBridgeJob?
    @State private var manualWorkplaces: [NovaNonconformityWorkplace] = []
    @State private var notice: String?
    @State private var boardRevision = UUID()

    private var service: NovaNonconformityService { .live(currentScope: currentScope) }
    private var today: String { NovaAnalysisWorkspace.todayISO() }

    var body: some View {
        Group {
            switch route {
            case .board: board
            case .chooser: chooser
            case .photo: photo
            case .manual: manual
            case .analyses: analyses
            case .record(let entry): record(entry)
            case .detail(let id): detail(id)
            }
        }
        .fullScreenCover(item: $job) { work in
            AnalyzingView(isPresented: Binding(get: { job != nil }, set: { if !$0 { job = nil } }),
                asyncWork: work.work, previewImage: work.preview, photoCount: work.photoCount,
                onComplete: { bundle in
                    job = nil
                    guard let bundle else { return }
                    images = []
                    route = .detail(bundle.analysis.id)
                },
                onError: { message in job = nil; notice = message })
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(RDLocalization.string("localizable.nova.bridge.alert.ok", table: .localizable, fallback: "Tamam")) { notice = nil }
        }
        .task { await loadCompanies() }
        .onAppear {
            guard !started else { return }
            started = true
            switch startMode {
            case .board: break
            case .chooser: route = .chooser
            case .photo: route = .photo
            }
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
                open: { entry in select(entry.companyID); route = .record(entry) },
                create: canWriteSomewhere ? { route = .chooser } : nil),
            companies: companies, today: today, onBack: onHome)
            .id(boardRevision)
    }

    /// The board lists every company, so the create control is offered as long
    /// as the account can write anywhere; the server checks the company itself.
    private var canWriteSomewhere: Bool { canWrite || !companies.isEmpty }

    private func record(_ entry: NovaNonconformityEntry) -> some View {
        NovaNonconformityRecordScreen(entry: entry, client: recordClient(entry),
            onBack: { route = .board; boardRevision = UUID() }, canWrite: canWrite)
    }

    private func recordClient(_ entry: NovaNonconformityEntry) -> NovaNonconformityRecordClient {
        func scoped() async throws -> NovaPersonnelScope {
            try await waitForScope(entry.companyID)
        }
        return .init(
            load: { try await service.detail(scoped(), id: entry.id) },
            transition: { state, reason, assignee in
                let current = try await service.detail(scoped(), id: entry.id)
                return try await service.transition(try await scoped(), id: entry.id, to: state,
                    expectedVersion: current.version, reason: reason, assignee: assignee)
            },
            addAction: { description, assignee, due in
                try await service.addAction(try await scoped(), id: entry.id, description: description,
                    assignee: assignee, dueOn: due)
            },
            verify: { accepted, note in
                try await service.verify(try await scoped(), id: entry.id, accepted: accepted, note: note)
            },
            saveDetail: { draft in
                try await service.setDetail(try await scoped(), id: entry.id, description: draft.description,
                    measure: draft.measure, legislation: draft.legislation, responsible: draft.responsible,
                    score: draft.score)
            })
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

    // MARK: chooser

    private var chooser: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        NovaBackButton { route = .board }
                        NovaText(text: RDLocalization.string("localizable.nova.navigation.yeni.uygunsuzluk.0f9172a3", table: .localizable, fallback: "Yeni Uygunsuzluk"), style: .screenTitle)
                        Spacer(minLength: 0)
                    }
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.choose.prompt", table: .localizable,
                        fallback: "Nasıl başlamak istersiniz?"), style: .metaQuiet)
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            NovaText(text: RDLocalization.string("localizable.nova.nonconformity.choose.photo.title", table: .localizable,
                                fallback: "Fotoğraftan analiz"), style: .cardTitle)
                            NovaText(text: RDLocalization.string("localizable.nova.nonconformity.choose.photo.detail", table: .localizable,
                                fallback: "Mevcut analiz motoru çalışır; seçtiğiniz bulgulardan uygunsuzluk açılır."), style: .metaQuiet)
                            NovaButton(label: RDLocalization.string("localizable.nova.nonconformity.choose.photo.action", table: .localizable, fallback: "Fotoğraf seç"),
                                symbol: "camera") { route = .photo }
                                .accessibilityIdentifier("nonconformity.choose.photo")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            NovaText(text: RDLocalization.string("localizable.nova.nonconformity.choose.manual.title", table: .localizable,
                                fallback: "Elle gir"), style: .cardTitle)
                            NovaText(text: RDLocalization.string("localizable.nova.manual.choose.detail", table: .localizable,
                                fallback: "Yapay zekâ kullanılmaz. Tehlike, önlem, skorlama, mevzuat ve sorumlu adım adım sorulur."), style: .metaQuiet)
                            NovaButton(label: RDLocalization.string("localizable.nova.nonconformity.choose.manual.action", table: .localizable, fallback: "Forma geç"),
                                symbol: "square.and.pencil", variant: .surface, isEnabled: scope != nil && canWrite) { Task { await openManual() } }
                                .accessibilityIdentifier("nonconformity.choose.manual")
                            if scope == nil {
                                NovaText(text: RDLocalization.string("localizable.nova.manual.needs.company", table: .localizable,
                                    fallback: "Elle kayıt için önce bir firma seçmelisiniz."), style: .metaQuiet)
                                NovaButton(label: NovaDestination.companies.title, symbol: "building.2", variant: .surface) { onCompanies() }
                                    .accessibilityIdentifier("nonconformity.pick.company")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    NovaButton(label: RDLocalization.string("localizable.nova.analysis.list.title", table: .localizable, fallback: "Analizlerim"),
                        symbol: "list.bullet", variant: .surface) { route = .analyses }
                        .accessibilityIdentifier("nonconformity.analyses")
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
    }

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
        }, onBack: { route = .board })
        .fullScreenCover(isPresented: $intakeOpen) {
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
                  isLocked: !app.currentTier.includes(canvas.minTier),
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
        let canvases = AnalysisCanvas.all.filter { draft.focusIDs.contains($0.id) && app.currentTier.includes($0.minTier) }
        guard !canvases.isEmpty else {
            notice = RDLocalization.string("localizable.nova.analysis.focus.required", table: .localizable,
                fallback: "Planınızın kapsadığı en az bir odak seçin.")
            return
        }
        let sector = draft.sectorID.flatMap(AnalysisSectorID.init(rawValue:))
        let company = draft.owner.companyID
        // The workspace scope follows the answer, so the records this analysis
        // produces land on the company the expert just named.
        select(company)
        let captured = images
        let owner = identity.userID
        job = NovaPhotoBridgeJob(work: { progress in
            try await AnalysisService.shared.runPhotoAnalysis(userID: owner, images: captured, canvases: canvases,
                localization: localization, analysisSector: sector, companyID: company, onProgress: progress)
        }, preview: captured.first, photoCount: captured.count)
    }

    // MARK: analyses and detail

    private var analyses: some View {
        NovaAnalysisListScreen(load: {
                try await NovaAnalysisWorkspace.summaries(identity: identity,
                    method: app.profile?.preferredMethod?.domain ?? .fineKinney)
            },
            thumbnail: { await NovaAnalysisWorkspace.thumbnail(analysisID: $0) },
            onOpen: { route = .detail($0) }, onBack: { route = .board },
            onNewPhotoAnalysis: { images = []; route = .photo })
    }

    private func detail(_ analysisID: UUID) -> some View {
        NovaAnalysisDetailScreen(analysisID: analysisID, client: detailClient(analysisID),
            onBack: { route = .board; boardRevision = UUID() }, canWrite: true)
    }

    private func detailClient(_ analysisID: UUID) -> NovaAnalysisDetailClient {
        let method = app.profile?.preferredMethod?.domain ?? .fineKinney
        return .init(
            load: { try await NovaAnalysisWorkspace.detail(analysisID: analysisID, identity: identity,
                method: method, methodLabel: method.label) },
            photos: { await NovaAnalysisWorkspace.photos(analysisID: analysisID) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            assign: { company in
                try await NovaAnalysisWorkspace.assign(analysisID: analysisID, companyID: company)
                select(company)
            },
            workplaces: { company in
                try await service.workplaces(try await waitForScope(company))
            },
            file: { request in await file(request) },
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

    /// The item identifier is the mutation key, so filing the same item twice
    /// replays instead of opening a second record.
    private func file(_ request: NovaAnalysisFileRequest) async -> NovaFindingOutcome {
        guard let current = currentScope() else {
            return .failed(NovaNonconformityWords.failure(.denied))
        }
        var intent = NovaNonconformityIntent(origin: request.section.isScored ? .finding : .expertItem,
            workplaceID: request.workplaceID, title: request.item.title)
        intent.severity = request.severity
        intent.recordKind = request.recordKind
        if request.section.isScored {
            intent.findingID = request.item.id
            if request.severity == nil { intent.riskBand = request.item.band }
        } else {
            intent.expertItemID = request.item.id
            intent.hazardDescription = request.item.body
        }
        do {
            let result = try await service.open(current, intent: intent, mutationID: request.item.id)
            boardRevision = UUID()
            return result.alreadyOpen ? .alreadyOpen : .opened
        } catch let failure as NovaNonconformityFailure {
            return .failed(NovaNonconformityWords.failure(failure))
        } catch {
            return .failed(RDLocalization.string("localizable.nova.bridge.outcome.failed", table: .localizable,
                fallback: "Bu bulgu için kayıt açılamadı. Aynı işlemi tekrar deneyin."))
        }
    }

    // MARK: manual

    private func openManual() async {
        guard let scope else { return }
        do {
            manualWorkplaces = try await service.workplaces(scope)
            route = .manual
        } catch {
            notice = RDLocalization.string("localizable.nova.nonconformity.error.workplaces", table: .localizable,
                fallback: "İşyeri listesi alınamadı. Tekrar deneyin.")
        }
    }

    private var manual: some View {
        NovaManualNonconformityScreen(workplaces: manualWorkplaces, save: { draft in await saveManual(draft) },
            onBack: { route = .board })
    }

    /// Returns nil when the record was opened, and the reason otherwise.
    private func saveManual(_ value: NovaManualDraft) async -> String? {
        guard let scope, let workplace = value.workplaceID else { return NovaNonconformityWords.failure(.denied) }
        var intent = NovaNonconformityIntent(origin: .detailed, workplaceID: workplace,
            title: value.title.trimmingCharacters(in: .whitespacesAndNewlines))
        intent.severity = value.severity
        intent.recordKind = value.recordKind
        intent.hazardDescription = value.hazardDescription
        intent.controlMeasure = value.controlMeasure
        intent.legislation = value.legislation
        intent.responsible = value.responsible
        intent.score = value.score
        do {
            _ = try await service.open(scope, intent: intent)
            boardRevision = UUID()
            route = .board
            return nil
        } catch let failure as NovaNonconformityFailure {
            return NovaNonconformityWords.failure(failure)
        } catch {
            return RDLocalization.string("localizable.nova.nonconformity.error.save", table: .localizable,
                fallback: "Kayıt açılamadı. Bilgileri kontrol edip aynı işlemi tekrar deneyin.")
        }
    }
}

/// Where the Uygunsuzluklar surface opens. The home card goes straight to the
/// picture; the drawer entry asks how to start.
enum NovaFindingsStart: Equatable { case board, chooser, photo }
