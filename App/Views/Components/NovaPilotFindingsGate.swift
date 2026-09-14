import SwiftUI
import PhotosUI

/// The Uygunsuzluklar tab, end to end: a photo analysis that may or may not
/// belong to a company, its detail screen, the records it produces, and the
/// hand-entered form. The analysis engine, the report renderer and the
/// nonconformity boundary are the ones the product already ships.
struct NovaPilotFindingsGate: View {
    let identity: NovaSessionIdentity
    /// The company workspace currently in scope, or nil when none is selected.
    let scope: NovaPersonnelScope?
    let canWrite: Bool
    /// Selecting a company here is the same selection the Firmalar tab uses;
    /// the workspace follows the analysis rather than keeping two scopes.
    let select: (UUID?) -> Void
    let currentScope: () -> NovaPersonnelScope?
    let companyName: String?
    var startOnNew = false
    let onCompanies: () -> Void
    let onHome: () -> Void
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    private enum Route: Equatable {
        case hub, chooser, intake, manual, analyses
        case detail(UUID)
    }
    @State private var route: Route = .hub
    @State private var started = false
    @State private var rows: [NovaNonconformityRow] = []
    @State private var filter: NovaNonconformityState?
    @State private var kindFilter: NovaNonconformityRecordKind?
    @State private var listError: String?
    @State private var listLoading = false
    @State private var listRevision = UUID()
    @State private var picking = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var draft = NovaAnalysisIntakeDraft()
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var job: NovaPhotoBridgeJob?
    @State private var manualWorkplaces: [NovaNonconformityWorkplace] = []
    @State private var notice: String?

    private var service: NovaNonconformityService { .live(currentScope: currentScope) }

    var body: some View {
        Group {
            switch route {
            case .hub: hub
            case .chooser: chooser
            case .intake: intake
            case .manual: manual
            case .analyses: analyses
            case .detail(let id): detail(id)
            }
        }
        .photosPicker(isPresented: $picking, selection: $photos, maxSelectionCount: 3, matching: .images)
        .onChange(of: photos) { _ in Task { await loadPhotos() } }
        .fullScreenCover(item: $job) { work in
            AnalyzingView(isPresented: Binding(get: { job != nil }, set: { if !$0 { job = nil } }),
                asyncWork: work.work, previewImage: work.preview, photoCount: work.photoCount,
                onComplete: { bundle in
                    job = nil
                    guard let bundle else { return }
                    route = .detail(bundle.analysis.id)
                },
                onError: { message in job = nil; notice = message })
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(RDLocalization.string("localizable.nova.bridge.alert.ok", table: .localizable, fallback: "Tamam")) { notice = nil }
        }
        .task(id: ListKey(state: filter?.rawValue, revision: listRevision, company: scope?.companyID)) { await loadList() }
        .onAppear { if startOnNew && !started { started = true; route = .chooser } }
    }

    private struct ListKey: Equatable { let state: String?; let revision: UUID; let company: UUID? }

    // MARK: hub

    private var visibleRows: [NovaNonconformityRow] {
        guard let kindFilter else { return rows }
        return rows.filter { $0.kind == kindFilter }
    }

    private var hub: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        NovaBackButton { onHome() }
                        NovaText(text: RDLocalization.string("localizable.nova.navigation.uygunsuzluklar", table: .localizable, fallback: "Uygunsuzluklar"), style: .screenTitle)
                        Spacer(minLength: 0)
                    }
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.findings.hint", table: .localizable,
                        fallback: "Fotoğraftan analiz firmasız da yapılabilir; kayıt açmak için bir firma gerekir."))
                    NovaButton(label: RDLocalization.string("localizable.nova.nonconformity.new", table: .localizable, fallback: "Yeni Uygunsuzluk"),
                        symbol: "plus", isEnabled: canWrite || scope == nil) { route = .chooser }
                        .accessibilityIdentifier("nonconformity.new")
                    NovaButton(label: RDLocalization.string("localizable.nova.analysis.list.title", table: .localizable, fallback: "Analizlerim"),
                        symbol: "list.bullet", variant: .surface) { route = .analyses }
                        .accessibilityIdentifier("nonconformity.analyses")
                    if scope == nil {
                        NovaCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                NovaText(text: RDLocalization.string("localizable.nova.pilot.nonconformity.needs.company", table: .localizable,
                                    fallback: "Uygunsuzluk kaydı bir firmaya bağlıdır. Önce Firmalar'dan bir firma seçin."), style: .metaQuiet)
                                NovaButton(label: NovaDestination.companies.title, symbol: "building.2", variant: .surface) { onCompanies() }
                                    .accessibilityIdentifier("nonconformity.pick.company")
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        listFilters
                        listBody
                    }
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
    }

    private var listFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    stateChip(nil, RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"))
                    stateChip(.draft, RDLocalization.string("localizable.nova.nonconformity.filter.draft", table: .localizable, fallback: "Taslak"))
                    stateChip(.open, RDLocalization.string("localizable.nova.nonconformity.filter.open", table: .localizable, fallback: "Açık"))
                    stateChip(.closed, RDLocalization.string("localizable.nova.nonconformity.filter.closed", table: .localizable, fallback: "Kapalı"))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    kindChip(nil, RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"))
                    kindChip(.nonconformity, NovaNonconformityWords.recordKind(.nonconformity))
                    kindChip(.improvement, NovaNonconformityWords.recordKind(.improvement))
                }
            }
        }
    }

    private func stateChip(_ value: NovaNonconformityState?, _ title: String) -> some View {
        chip(title: title, isSelected: filter == value, identifier: "nonconformity.filter.\(value?.rawValue ?? "all")") { filter = value }
    }
    private func kindChip(_ value: NovaNonconformityRecordKind?, _ title: String) -> some View {
        chip(title: title, isSelected: kindFilter == value, identifier: "nonconformity.kind.\(value?.rawValue ?? "all")") { kindFilter = value }
    }
    private func chip(title: String, isSelected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaText(text: title, style: .meta,
                color: isSelected ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(isSelected ? NovaColorToken.statusSuccessBg.color(in: scheme) : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var listBody: some View {
        if let listError {
            NovaCard(padding: 16) { NovaText(text: listError, style: .metaQuiet) }
        } else if listLoading && rows.isEmpty {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.nonconformity.loading", table: .localizable, fallback: "Kayıtlar yükleniyor"), style: .metaQuiet)
            }
        } else if visibleRows.isEmpty {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.nonconformity.empty", table: .localizable, fallback: "Henüz uygunsuzluk kaydı yok."), style: .metaQuiet)
            }
        } else {
            ForEach(visibleRows) { row in card(row) }
        }
    }

    private func card(_ row: NovaNonconformityRow) -> some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                NovaText(text: row.title, style: .cardTitle)
                HStack(spacing: 8) {
                    NovaStatusPill(label: NovaNonconformityWords.band(row.severity), status: NovaNonconformityWords.tone(row.severity))
                    if row.kind == .improvement {
                        NovaStatusPill(label: NovaNonconformityWords.recordKind(.improvement), status: .info, showsDot: false)
                    }
                    NovaText(text: NovaNonconformityWords.state(row.state), style: .metaQuiet)
                }
                if let band = row.risk_band {
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.nonconformity.scored", table: .localizable,
                        fallback: "Skorlandı · %@"), NovaNonconformityWords.band(band)), style: .metaQuiet)
                }
                if row.camefromFinding {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.from.analysis", table: .localizable,
                        fallback: "Fotoğraf analizinden geldi"), style: .metaQuiet)
                } else if row.camefromExpertItem {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.from.expert", table: .localizable,
                        fallback: "Uzman görüşü maddesinden geldi"), style: .metaQuiet)
                }
                NovaText(text: row.opened_on, style: .metaQuiet)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("nonconformity.row.\(row.id.uuidString.lowercased())")
    }

    private func loadList() async {
        guard let scope else { rows = []; return }
        listLoading = true; listError = nil
        do {
            let loaded = try await service.list(scope, state: filter)
            try Task.checkCancellation()
            rows = loaded
        } catch is CancellationError {
        } catch let failure as NovaNonconformityFailure {
            listError = NovaNonconformityWords.failure(failure)
        } catch {
            listError = RDLocalization.string("localizable.nova.nonconformity.error.list", table: .localizable,
                fallback: "Uygunsuzluklar yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.")
        }
        listLoading = false
    }

    // MARK: chooser

    private var chooser: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        NovaBackButton { route = .hub }
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
                                symbol: "camera") { photos = []; images = []; picking = true }
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
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
    }

    // MARK: intake

    private var intake: some View {
        NovaAnalysisIntakeScreen(companies: companies, sectors: Self.sectorOptions,
            focuses: focusOptions, draft: $draft, isStarting: job != nil,
            onCancel: { route = .chooser }, onStart: { start() })
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

    private func loadPhotos() async {
        picking = false
        let items = photos
        guard !items.isEmpty else { return }
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        photos = []
        guard !loaded.isEmpty else {
            notice = RDLocalization.string("localizable.nova.bridge.photo.unreadable", table: .localizable,
                fallback: "Seçilen fotoğraflar okunamadı. Tekrar deneyin.")
            return
        }
        images = loaded
        draft = NovaAnalysisIntakeDraft()
        draft.photoCount = loaded.count
        companies = (try? await NovaAnalysisWorkspace.companyOptions(identity: identity)) ?? []
        // The workspace already has a company selected: offer it as the answer
        // rather than making the expert pick it again.
        if let current = scope?.companyID, let match = companies.first(where: { $0.id == current }) {
            draft.choose(owner: .company(id: match.id, name: match.name, sector: match.sector),
                catalog: Self.sectorOptions.map { .init(id: $0.id, labels: [$0.label]) })
        }
        route = .intake
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
        NovaAnalysisListScreen(load: { try await NovaAnalysisWorkspace.summaries(identity: identity) },
            onOpen: { route = .detail($0) }, onBack: { route = .hub },
            onNewPhotoAnalysis: { photos = []; images = []; picking = true })
    }

    private func detail(_ analysisID: UUID) -> some View {
        NovaAnalysisDetailScreen(analysisID: analysisID, client: detailClient(analysisID),
            onBack: { route = .hub; listRevision = UUID() }, canWrite: true)
    }

    private func detailClient(_ analysisID: UUID) -> NovaAnalysisDetailClient {
        let method = app.profile?.preferredMethod?.domain ?? .fineKinney
        return .init(
            load: { try await NovaAnalysisWorkspace.detail(analysisID: analysisID, identity: identity,
                method: method, methodLabel: method.label) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            assign: { company in
                try await NovaAnalysisWorkspace.assign(analysisID: analysisID, companyID: company)
                select(company)
            },
            workplaces: { company in
                guard let current = currentScope(), current.companyID == company else {
                    throw NovaNonconformityFailure.denied
                }
                return try await service.workplaces(current)
            },
            file: { request in await file(request) },
            edit: { try await NovaAnalysisWorkspace.edit($0) },
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
            listRevision = UUID()
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
            onBack: { route = .hub })
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
            listRevision = UUID()
            route = .hub
            return nil
        } catch let failure as NovaNonconformityFailure {
            return NovaNonconformityWords.failure(failure)
        } catch {
            return RDLocalization.string("localizable.nova.nonconformity.error.save", table: .localizable,
                fallback: "Kayıt açılamadı. Bilgileri kontrol edip aynı işlemi tekrar deneyin.")
        }
    }
}
