import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// screen these closures.
struct NovaAnalysisDetailClient {
    let load: () async throws -> NovaAnalysisDetailData
    /// The pictures the analysis ran on. Missing ones are simply absent.
    let photos: () async -> [UIImage]
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    /// Attaches the analysis to a company. The analysis row keeps living where
    /// it is; only its company reference changes.
    let assign: (UUID) async throws -> Void
    let workplaces: (UUID) async throws -> [NovaNonconformityWorkplace]
    let file: (NovaAnalysisFileRequest) async -> NovaFindingOutcome
    let edit: (NovaAnalysisFindingEdit) async throws -> Void
    let remove: (NovaAnalysisItem) async throws -> Void
    let react: (NovaAnalysisItem, NovaAnalysisSectionKind, NovaAnalysisReaction) async throws -> Void
    /// Returns the file name the report was archived under.
    let report: (NovaAnalysisReportRequest) async throws -> String
}

struct NovaAnalysisDetailScreen: View {
    let analysisID: UUID
    let client: NovaAnalysisDetailClient
    let onBack: () -> Void
    var canWrite = true
    var canEdit = true
    var canReact = true
    var canFile = true
    var canFileTraining = true
    var canReport = true
    var reportResultIsArchiveName = true
    @Environment(\.colorScheme) private var scheme
    @State private var data: NovaAnalysisDetailData?
    @State private var pictures: [UIImage] = []
    @State private var loadError: String?
    @State private var section: NovaAnalysisSectionKind = .riskAnalysis
    @State private var method: NovaRiskMethod = .fineKinney
    @State private var methodChosen = false
    @State private var outcomes: [UUID: NovaFindingOutcome] = [:]
    @State private var reactions: [UUID: NovaAnalysisReaction] = [:]
    @State private var inspecting: NovaAnalysisItem?
    @State private var editing: NovaAnalysisItem?
    @State private var deleting: NovaAnalysisItem?
    @State private var preview: NovaPreviewImage?
    @State private var reporting = false
    @State private var assigning = false
    @State private var notice: String?
    @State private var reload = UUID()

    private var current: NovaAnalysisSection? { data?.section(section) }
    private var items: [NovaAnalysisItem] { current?.items ?? [] }
    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            VStack(spacing: 0) {
                header
                if data == nil && loadError == nil {
                    loadingSkeleton
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let loadError {
                            NovaCard(padding: 16) {
                                VStack(spacing: 12) {
                                    NovaText(text: loadError, style: .body)
                                    Button { reload = UUID() } label: {
                                        NovaText(text: RDLocalization.string("localizable.nova.analysis.retry", table: .localizable,
                                            fallback: "Tekrar dene"), style: .buttonSm)
                                    }.accessibilityIdentifier("nova.analysis.retry")
                                }
                            }
                        } else if let data {
                            summaryCard(data)
                            resultOverview(data)
                            tabs(data)
                        } else {
                            NovaCard(padding: 16) {
                                NovaText(text: RDLocalization.string("localizable.nova.analysis.loading", table: .localizable,
                                    fallback: "Analiz yükleniyor…"), style: .metaQuiet)
                            }
                        }
                    }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
                }
                }
            }
                .novaAsyncContent(isLoading: data == nil && loadError == nil)
        }
        // Analysis result is a focused child task. Suppress the standalone
        // brand chrome so the first viewport starts with its own compact
        // back/title header.
        .environment(\.novaHasHeader, true)
        .statusBarHidden(false)
        .safeAreaInset(edge: .bottom, spacing: 0) { if data != nil { actionBar } }
        .task(id: reload) { await load() }
        .novaFullScreenCover(item: $inspecting) { item in
            NovaAnalysisItemDetailScreen(item: item, section: section, method: method,
                photo: photo(for: item), analysisTitle: data?.title ?? "",
                companyName: data?.companyName, createdOn: data?.createdOn ?? "",
                reaction: reactions[item.id] ?? item.reaction, canWrite: canWrite,
                canEdit: canEdit, canReact: canReact,
                canFile: canFile && (section != .trainingRecommendations || canFileTraining),
                filingScreen: data.map { filingScreen(item: item, data: $0) },
                react: { value in
                    try await client.react(item, section, value)
                    reactions[item.id] = value
                },
                onBack: { inspecting = nil },
                onEdit: { inspecting = nil; editing = item },
                onDelete: { inspecting = nil; deleting = item })
        }
        .novaPopupCover(item: $editing) { item in
            NovaPopup {
                NovaAnalysisEditSheet(item: item, method: method) { values in
                    guard let data else { return }
                    try await client.edit(.init(analysisID: data.analysisID, findingID: item.id,
                        title: values.title, category: values.category, body: values.body, measure: values.measure,
                        references: values.references, score: values.score))
                    editing = nil
                    reload = UUID()
                }
            }
        }
        .novaPopupCover(item: $deleting) { item in
            NovaPopup {
                NovaAnalysisDeleteSheet(item: item) {
                    try await client.remove(item)
                    deleting = nil
                    reload = UUID()
                }
            }
        }
        .novaPopupCover(item: $preview) { item in
            NovaPopup { NovaImageViewer(image: item.image) }
        }
        .novaPopupCover(isPresented: $reporting) {
            NovaPopup {
                if let data {
                    NovaAnalysisReportSheet(data: data, method: method) { request in
                        let name = try await client.report(request)
                        reporting = false
                        notice = reportResultIsArchiveName
                            ? String(format: RDLocalization.string("localizable.nova.analysis.report.saved", table: .localizable,
                                fallback: "Rapor arşive kaydedildi: %@"), name)
                            : name
                    }
                }
            }
        }
        .novaPopupCover(isPresented: $assigning) {
            NovaPopup {
                NovaAnalysisCompanySheet(load: client.companies) { company in
                    try await client.assign(company)
                    assigning = false
                    reload = UUID()
                }
            }
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(RDLocalization.string("localizable.nova.bridge.alert.ok", table: .localizable, fallback: "Tamam")) { notice = nil }
        }
    }

    private func load() async {
        loadError = nil
        data = nil
        do {
            let value = try await client.load()
            data = value
            // The expert's own method opens the screen; after that the toggle
            // owns the choice and a reload must not undo it.
            if !methodChosen { method = value.method }
            pictures = await client.photos()
        }
        catch is CancellationError { }
        catch {
            loadError = RDLocalization.string("localizable.nova.analysis.load.failed", table: .localizable,
                fallback: "Analiz yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }

    private func filingScreen(item: NovaAnalysisItem, data: NovaAnalysisDetailData) -> AnyView {
        AnyView(NovaAnalysisFilingScreen(data: data, item: item, section: section, method: method,
            loadCompanies: client.companies, loadWorkplaces: client.workplaces,
            file: client.file, record: { id, outcome in outcomes[id] = outcome }))
    }

    private var displayItems: [NovaAnalysisItem] {
        guard section == .riskAnalysis else { return items }
        return items.sorted {
            let left = $0.value(method) ?? -1
            let right = $1.value(method) ?? -1
            return left == right ? $0.ordinal < $1.ordinal : left > right
        }
    }

    /// The picture an item was read from, when the analysis recorded one. The
    /// indices are one-based, so an index that falls outside what was actually
    /// downloaded resolves to nothing rather than to the wrong photo.
    private func photo(for item: NovaAnalysisItem) -> UIImage? {
        guard let index = item.photoIndices.first, index >= 1, index <= pictures.count else {
            return nil
        }
        return pictures[index - 1]
    }

    // MARK: header and summary

    private var header: some View {
        HStack(spacing: 10) {
            NovaBackButton { onBack() }
            NovaText(text: RDLocalization.string("localizable.nova.analysis.result.title", table: .localizable, fallback: "Analiz Sonucu"), style: .screenTitle)
            Spacer(minLength: 0)
        }.padding(.horizontal, 16).padding(.bottom, 6)
    }

    private var loadingSkeleton: some View {
        ScrollView {
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 16).fill(NovaColorToken.surfaceMuted.color(in: scheme)).frame(height: 82)
                RoundedRectangle(cornerRadius: 16).fill(NovaColorToken.surfaceMuted.color(in: scheme)).frame(height: 112)
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16).fill(NovaColorToken.surfaceMuted.color(in: scheme)).frame(height: 104)
                }
            }
            .padding(.horizontal, 16).padding(.top, 4)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
        }
    }

    /// One compact card for what this analysis is: picture, name, company,
    /// date and sector. Tapping the picture opens it full size.
    private func summaryCard(_ data: NovaAnalysisDetailData) -> some View {
        NovaCard(padding: 11) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 6) {
                        NovaText(text: NovaAnalysisPresentation.title(data.title), style: .cardTitle).lineLimit(2)
                        HStack(spacing: 10) {
                            if let name = data.companyName {
                                summaryFact(symbol: "building.2", text: name)
                            } else {
                                summaryFact(symbol: "building.2",
                                    text: RDLocalization.string("localizable.nova.analysis.unassigned", table: .localizable, fallback: "Firmasız"))
                                if canWrite { assignTag }
                            }
                            if let sector = data.sectorLabel {
                                summaryFact(symbol: "square.grid.2x2", text: sector)
                            }
                        }
                        HStack(spacing: 10) {
                            summaryFact(symbol: "calendar", text: NovaAnalysisPresentation.dateOnly(data.createdOn))
                            if data.photoCount > 0 {
                                summaryFact(symbol: "photo",
                                    text: String(format: RDLocalization.string("localizable.nova.analysis.tag.photos", table: .localizable,
                                        fallback: "%d fotoğraf"), data.photoCount))
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if data.isProjectionMissing {
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.projection.missing", table: .localizable,
                        fallback: "Bu eski analiz kayıtlı bulgularından gösteriliyor; bazı ek öneri bölümleri bulunmayabilir."), style: .metaQuiet)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The first viewport answers the questions that matter before the user
    /// starts reading individual rows: volume, severity and first priority.
    private func resultOverview(_ data: NovaAnalysisDetailData) -> some View {
        let risk = data.section(.riskAnalysis)
        let entries = risk?.items ?? []
        let distribution = risk?.distribution(method) ?? []
        let critical = distribution.first(where: { $0.band == "critical" })?.count ?? 0
        let high = distribution.first(where: { $0.band == "high" })?.count ?? 0
        let highest = risk?.highest(method)
        let highestBand = highest?.band(method)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                overviewMetric(value: "\(entries.count)",
                    label: RDLocalization.string("localizable.nova.analysis.detail.metric.finding", table: .localizable, fallback: "Bulgu"),
                    status: .neutral)
                overviewDivider
                overviewMetric(value: "\(critical)",
                    label: RDLocalization.string("localizable.nova.nonconformity.severity.critical", table: .localizable, fallback: "Kritik"),
                    status: .danger)
                overviewDivider
                overviewMetric(value: "\(high)",
                    label: RDLocalization.string("localizable.nova.nonconformity.severity.high", table: .localizable, fallback: "Yüksek"),
                    status: .warning)
                overviewDivider
                overviewMetric(value: highest.flatMap { $0.value(method) }.map(NovaNonconformityWords.score) ?? "—",
                    label: NovaNonconformityWords.method(method), status: NovaNonconformityWords.tone(highestBand))
            }
            .frame(minHeight: 54)

            if let highest, let highestBand, ["critical", "high"].contains(highestBand) {
                Button { inspecting = highest } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(NovaNonconformityWords.tone(highestBand).tokens.ink.color(in: scheme))
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: RDLocalization.string("localizable.nova.analysis.detail.priority", table: .localizable,
                                fallback: "Öncelikli bulgu"), style: .micro,
                                color: NovaNonconformityWords.tone(highestBand).tokens.ink.color(in: scheme))
                            NovaText(text: highest.title, style: .metaQuiet).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                    }
                    .padding(11)
                    .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(NovaColorToken.hairline.color(in: scheme), lineWidth: 1))
                }
                .buttonStyle(NovaRowPressStyle())
                .accessibilityIdentifier("analysis.detail.priority")
            }
        }
        .padding(12)
        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
    }

    private func overviewMetric(value: String, label: String, status: NovaStatus) -> some View {
        VStack(spacing: 2) {
            NovaSizedText(text: value, size: 17, weight: "ExtraBold", color: status.tokens.ink.color(in: scheme))
            NovaText(text: label, style: .micro, color: NovaColorToken.textSecondary.color(in: scheme)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var overviewDivider: some View {
        Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(width: 1, height: 28)
    }

    /// An unassigned analysis says so where the company would be, and offers
    /// the one step that changes it.
    private var assignTag: some View {
        Button { assigning = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle").font(.system(size: 10, weight: .regular))
                NovaText(text: RDLocalization.string("localizable.nova.analysis.assign", table: .localizable, fallback: "Firmaya ata"),
                    style: .metaQuiet, color: NovaColorToken.accentInk.color(in: scheme))
            }
            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
        }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("analysis.detail.assign")
    }

    private func summaryFact(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .regular))
                .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: text, style: .metaQuiet,
                color: NovaColorToken.textSecondary.color(in: scheme)).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// The analysed picture; tapping it opens the full size in a popup rather
    /// than pushing another page.
    @ViewBuilder private var thumbnail: some View {
        if let first = pictures.first {
            Button { preview = .init(image: first) } label: {
                Image(uiImage: first).resizable().scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                    .overlay(alignment: .bottomTrailing) {
                        if pictures.count > 1 {
                            NovaText(text: "\(pictures.count)", style: .micro, color: NovaColorToken.onInverse.color(in: scheme))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(NovaColorToken.inverse.color(in: scheme).opacity(0.8), in: Capsule())
                                .padding(3)
                        }
                    }
            }.buttonStyle(NovaRowPressStyle())
                .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.analysis.photo.open", table: .localizable, fallback: "Analiz fotoğrafını büyüt")))
                .accessibilityIdentifier("analysis.detail.photo")
        } else {
            NovaColorToken.surfaceMuted.color(in: scheme)
                .frame(width: 54, height: 54)
                .overlay(NovaIcon(symbol: "photo", size: 18).foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
        }
    }

    // MARK: sections

    private func tabs(_ data: NovaAnalysisDetailData) -> some View {
        let visibleSections = data.sections.filter { $0.kind != .approvedNotebook }
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(visibleSections) { entry in compactTab(entry) }
                }
            }
            sectionBody(data)
        }
    }

    private func compactTab(_ entry: NovaAnalysisSection) -> some View {
        let isOn = section == entry.kind
        let tone = NovaAnalysisSectionTone.of(entry.kind)
        return Button {
            section = entry.kind
        } label: {
            HStack(spacing: 6) {
                NovaIcon(symbol: tone.symbol, size: 12)
                NovaText(text: NovaAnalysisWords.sectionTitle(entry.kind), style: .meta,
                    color: isOn ? NovaColorToken.onInverse.color(in: scheme) : NovaColorToken.text.color(in: scheme))
                NovaText(text: "\(entry.items.count)", style: .micro,
                    color: isOn ? NovaColorToken.onInverse.color(in: scheme) : tone.status.tokens.ink.color(in: scheme))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(isOn ? NovaColorToken.onInverse.color(in: scheme).opacity(0.16)
                                     : tone.status.tokens.background.color(in: scheme), in: Capsule())
            }
            .foregroundStyle(isOn ? NovaColorToken.onInverse.color(in: scheme) : NovaColorToken.text.color(in: scheme))
            .padding(.horizontal, 11).frame(minHeight: 38)
            .background(isOn ? NovaColorToken.inverse.color(in: scheme) : NovaColorToken.surface.color(in: scheme), in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? NovaColorToken.inverse.color(in: scheme)
                                                  : NovaColorToken.border.color(in: scheme), lineWidth: 1))
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityIdentifier("analysis.detail.section.\(entry.kind.rawValue)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder private func sectionBody(_ data: NovaAnalysisDetailData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                NovaCard(padding: 14) {
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.section.empty", table: .localizable,
                        fallback: "Bu bölümde kayıt yok."), style: .metaQuiet)
                }
            } else {
                switch section {
                case .riskAnalysis: riskBody
                case .expertRecommendations, .trainingRecommendations: adviceBody
                case .approvedNotebook: NovaNotebookPanel(items: items) { inspecting = $0 }
                }
            }
        }
    }

    @ViewBuilder private var riskBody: some View {
        HStack(spacing: 8) {
            NovaText(text: "Skorlama", style: .metaQuiet)
            Spacer(minLength: 0)
            NovaAnalysisMethodToggle(method: Binding(get: { method }, set: { method = $0; methodChosen = true }))
                .frame(maxWidth: 230)
        }
        ForEach(displayItems) { item in
            VStack(alignment: .leading, spacing: 5) {
                NovaAnalysisFindingCard(item: withReaction(item), method: method,
                    isSelected: false, isSelectable: false,
                    canEdit: canWrite && canEdit, canReact: canWrite && canReact,
                    onSelect: { }, onOpen: { inspecting = item },
                    onEdit: { editing = item }, onDelete: { deleting = item },
                    onReact: { react(item, $0) })
                if let outcome = outcomes[item.id] { outcomeLine(outcome) }
            }
        }
    }

    @ViewBuilder private var adviceBody: some View {
        ForEach(displayItems) { item in
            VStack(alignment: .leading, spacing: 5) {
                NovaAnalysisAdviceCard(item: withReaction(item), kind: section,
                    isSelected: false, isSelectable: false,
                    canReact: canWrite && canReact,
                    onSelect: { }, onOpen: { inspecting = item },
                    onReact: { react(item, $0) })
                if let outcome = outcomes[item.id] { outcomeLine(outcome) }
            }
        }
    }

    private func withReaction(_ item: NovaAnalysisItem) -> NovaAnalysisItem {
        guard let value = reactions[item.id] else { return item }
        var copy = item
        copy.reaction = value
        return copy
    }

    private func react(_ item: NovaAnalysisItem, _ value: NovaAnalysisReaction) {
        let previous = reactions[item.id] ?? item.reaction
        reactions[item.id] = value
        Task {
            do { try await client.react(item, section, value) }
            catch {
                // The answer did not reach the server, so the card must not
                // keep showing it as if it had.
                reactions[item.id] = previous
                notice = RDLocalization.string("localizable.nova.analysis.item.reaction.failed", table: .localizable,
                    fallback: "Geri bildirim kaydedilemedi. Tekrar deneyin.")
            }
        }
    }

    @ViewBuilder private func outcomeLine(_ outcome: NovaFindingOutcome) -> some View {
        switch outcome {
        case .untouched: EmptyView()
        case .opened:
            NovaAnalysisTag(symbol: "checkmark.circle",
                text: RDLocalization.string("localizable.nova.bridge.outcome.opened", table: .localizable, fallback: "Uygunsuzluk açıldı"),
                status: .success)
        case .alreadyOpen:
            NovaAnalysisTag(symbol: "clock.arrow.circlepath",
                text: RDLocalization.string("localizable.nova.bridge.outcome.existing", table: .localizable, fallback: "Bu bulgunun uygunsuzluğu zaten vardı"),
                status: .neutral)
        case .failed(let reason):
            NovaAnalysisTag(symbol: "exclamationmark.circle", text: reason, status: .danger)
        }
    }

    // MARK: the bar that stays

    /// A report always represents the complete analysis. The options sheet is
    /// the only decision the user needs; making every row selectable added a
    /// step without changing the generated report request.
    private var actionBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    VStack(spacing: 1) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                        NovaText(text: RDLocalization.string("localizable.nova.analysis.back", table: .localizable, fallback: "Geri Dön"),
                            style: .badge, color: NovaColorToken.text.color(in: scheme))
                    }
                    .foregroundStyle(NovaColorToken.text.color(in: scheme))
                    .frame(width: 74, height: 54)
                    .novaControlBackground(cornerRadius: 18)
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("analysis.detail.back")
                if canReport {
                    primary(RDLocalization.string("localizable.nova.analysis.report", table: .localizable, fallback: "Rapor oluştur"),
                            symbol: "doc.text", id: "report") {
                        reporting = true
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 5).padding(.bottom, 0)
        .background(NovaColorToken.canvas.color(in: scheme).opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(height: 1)
        }
    }

    private func primary(_ label: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                HStack {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "paperplane").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NovaColorToken.onInverse.color(in: scheme))
                    .frame(width: 38, height: 38)
                }
                NovaText(text: label, style: .buttonSm, color: NovaColorToken.onInverse.color(in: scheme))
                    .multilineTextAlignment(.center).padding(.horizontal, 42)
            }
            .foregroundStyle(NovaColorToken.onInverse.color(in: scheme))
            .padding(.leading, 16).padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(NovaColorToken.inverse.color(in: scheme), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("analysis.detail.\(id)")
    }

}

/// A finding is a destination, not a modal. The image, title and actions live
/// on separate surfaces so long text remains readable and the primary next
/// step is never buried among edit controls.
private struct NovaAnalysisItemDetailScreen: View {
    let item: NovaAnalysisItem
    let section: NovaAnalysisSectionKind
    let method: NovaRiskMethod
    var photo: UIImage?
    var analysisTitle = ""
    var companyName: String?
    var createdOn = ""
    let reaction: NovaAnalysisReaction
    var canWrite = true
    var canEdit = true
    var canReact = true
    var canFile = true
    var filingScreen: AnyView?
    let react: (NovaAnalysisReaction) async throws -> Void
    let onBack: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var chosen: NovaAnalysisReaction = .none
    @State private var scoreExpanded = false
    @State private var feedbackBusy = false
    @State private var feedbackError: String?
    @State private var filing = false

    private var score: NovaAnalysisScore? { item.score(method) }
    private var metaText: String {
        [companyName,
         analysisTitle.isEmpty ? nil : NovaAnalysisPresentation.title(analysisTitle),
         createdOn.isEmpty ? nil : NovaAnalysisPresentation.dateOnly(createdOn)]
            .compactMap { $0 }
            .reduce(into: [String]()) { values, value in
                if !values.contains(value) { values.append(value) }
            }
            .joined(separator: " · ")
    }

    private var detailBlocks: [NovaFindingDetailBlock.Model] {
        var values = [NovaFindingDetailBlock.Model]()
        values.appendIfPresent(title: RDLocalization.string("localizable.nova.analysis.detail.observed", table: .localizable,
            fallback: "Ne gözlendi?"), symbol: "eye", text: item.body)
        if item.measures.isEmpty {
            values.appendIfPresent(title: RDLocalization.string("localizable.nova.analysis.field.measure.corrective", table: .localizable,
                fallback: "Düzeltici önlem"), symbol: "checkmark.seal", text: item.measure)
        } else {
            for measure in item.measures {
                values.appendIfPresent(
                    title: measure.isPreventive
                        ? RDLocalization.string("localizable.nova.analysis.detail.measure.preventive", table: .localizable,
                            fallback: "Önleyici faaliyet")
                        : RDLocalization.string("localizable.nova.analysis.field.measure.corrective", table: .localizable,
                            fallback: "Düzeltici önlem"),
                    symbol: measure.isPreventive ? "shield" : "checkmark.seal",
                    text: measure.text
                )
            }
        }
        values.appendIfPresent(title: RDLocalization.string("localizable.nova.analysis.field.root.cause", table: .localizable,
            fallback: "Kök neden"), symbol: "magnifyingglass", text: item.rootCause)
        values.appendIfPresent(title: RDLocalization.string("localizable.nova.analysis.detail.references", table: .localizable,
            fallback: "Mevzuat ve ek bilgiler"), symbol: "book", text: item.references)
        if let duration = item.durationValue {
            values.appendIfPresent(
                title: item.durationLabel ?? RDLocalization.string("localizable.nova.analysis.detail.duration", table: .localizable,
                    fallback: "Önerilen süre"),
                symbol: "clock",
                text: [duration, item.durationNote].compactMap { $0 }.joined(separator: "\n")
            )
        }
        return values
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        NovaFindingPhoto(photo: photo)
                        titleBlock
                        ForEach(detailBlocks) { block in
                            NovaFindingDetailBlock(model: block)
                        }
                        if let score, let value = score.value {
                            NovaFindingScoreDisclosure(
                                score: score,
                                value: value,
                                method: method,
                                isExpanded: $scoreExpanded
                            )
                        }
                        if canWrite && canReact {
                            feedbackBlock
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
        }
        .environment(\.novaHasHeader, true)
        .statusBarHidden(false)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomAction }
        .onAppear { chosen = reaction }
        .novaFullScreenCover(isPresented: $filing) {
            if let filingScreen { filingScreen }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            NovaBackButton(action: onBack)
                .accessibilityIdentifier("analysis.finding.detail.back")
            NovaText(text: RDLocalization.string("localizable.nova.analysis.finding.detail.title", table: .localizable,
                fallback: "Bulgu Detayı"), style: .screenTitle)
            Spacer(minLength: 0)
            if canWrite && canEdit && section.isScored {
                Menu {
                    Button(action: onEdit) {
                        Label(RDLocalization.string("localizable.nova.analysis.finding.edit", table: .localizable, fallback: "Düzenle"),
                            systemImage: "square.and.pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label(RDLocalization.string("localizable.nova.analysis.finding.delete", table: .localizable, fallback: "Sil"),
                            systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NovaColorToken.text.color(in: scheme))
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                }
                .accessibilityLabel(Text(RDLocalization.string("localizable.nova.analysis.finding.actions", table: .localizable,
                    fallback: "Bulgu işlemleri")))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                NovaStatusPill(
                    label: section.isScored ? NovaNonconformityWords.band(item.band(method))
                        : RDLocalization.string("localizable.nova.analysis.section.expert", table: .localizable, fallback: "Uzman Görüşü"),
                    status: section.isScored ? NovaNonconformityWords.tone(item.band(method)) : .warning,
                    showsDot: true
                )
                NovaText(text: String(format: RDLocalization.string("localizable.nova.analysis.finding.number", table: .localizable,
                    fallback: "Bulgu #%d"), item.ordinal), style: .micro,
                    color: NovaColorToken.textSecondary.color(in: scheme))
            }
            NovaText(text: item.title, style: .sheetTitle)
                .fixedSize(horizontal: false, vertical: true)
            if !metaText.isEmpty {
                NovaText(text: metaText, style: .metaQuiet).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    @ViewBuilder private var bottomAction: some View {
        if canWrite && canFile && section.isFileable, filingScreen != nil {
            NovaButton(label: RDLocalization.string("localizable.nova.analysis.finding.file", table: .localizable,
                fallback: "Uygunsuzluk oluştur"), symbol: "plus.circle") { filing = true }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(NovaColorToken.canvas.color(in: scheme).opacity(0.98))
                .overlay(alignment: .top) {
                    Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(height: 1)
                }
                .accessibilityIdentifier("analysis.finding.file")
        }
    }

    private var feedbackBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider().padding(.top, 16)
            NovaText(text: RDLocalization.string("localizable.nova.analysis.finding.feedback.question", table: .localizable,
                fallback: "Bu bulgu faydalı mıydı?"), style: .label)
            HStack(spacing: 8) {
                reactionButton(.like, symbol: "hand.thumbsup",
                    label: RDLocalization.string("localizable.nova.analysis.item.like", table: .localizable, fallback: "Faydalı"))
                reactionButton(.dislike, symbol: "hand.thumbsdown",
                    label: RDLocalization.string("localizable.nova.analysis.finding.feedback.dislike", table: .localizable,
                        fallback: "Faydalı değil"))
            }
            if let feedbackError {
                NovaText(text: feedbackError, style: .metaQuiet,
                    color: NovaColorToken.statusDangerInk.color(in: scheme))
            }
        }
    }

    private func reactionButton(_ value: NovaAnalysisReaction, symbol: String, label: String) -> some View {
        let selected = chosen == value
        return Button {
            let next: NovaAnalysisReaction = selected ? .none : value
            Task {
                feedbackBusy = true
                feedbackError = nil
                do {
                    try await react(next)
                    chosen = next
                } catch {
                    feedbackError = "Geri bildirim kaydedilemedi. Tekrar deneyin."
                }
                feedbackBusy = false
            }
        } label: {
            Label(label, systemImage: selected ? "\(symbol).fill" : symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? NovaColorToken.accentInk.color(in: scheme)
                                          : NovaColorToken.text.color(in: scheme))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(selected ? NovaColorToken.statusSuccessBg.color(in: scheme)
                                     : NovaColorToken.surface.color(in: scheme),
                    in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? NovaColorToken.accentInk.color(in: scheme)
                                           : NovaColorToken.border.color(in: scheme), lineWidth: 1))
        }
        .buttonStyle(NovaRowPressStyle())
        .disabled(feedbackBusy)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Filing is a child task of the finding detail, so the finding stays in the
/// navigation stack and returns exactly as it was after cancel or success.
/// Company selection and record options live on one full-screen surface;
/// neither step is presented as a popup over the analysis result.
private struct NovaAnalysisFilingScreen: View {
    let data: NovaAnalysisDetailData
    let item: NovaAnalysisItem
    let section: NovaAnalysisSectionKind
    let method: NovaRiskMethod
    let loadCompanies: () async throws -> [NovaAnalysisCompanyOption]
    let loadWorkplaces: (UUID) async throws -> [NovaNonconformityWorkplace]
    let file: (NovaAnalysisFileRequest) async -> NovaFindingOutcome
    let record: (UUID, NovaFindingOutcome) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NovaCompanyCreateFlow(
            title: RDLocalization.string("localizable.nova.analysis.finding.file", table: .localizable,
                fallback: "Uygunsuzluk oluştur"),
            companies: loadCompanies,
            catalogue: { company in
                guard let company else { return [NovaNonconformityWorkplace]() }
                return try await loadWorkplaces(company)
            },
            onSelect: { _ in },
            fixedCompany: data.companyID,
            fullScreenTask: true,
            showsSelectedTaskHeader: true,
            onClose: { dismiss() }
        ) { workplaces, company in
            NovaAnalysisFileSheet(items: [item], section: section, method: method,
                showsHeading: false, targetCompany: company, loadWorkplaces: { workplaces }, file: file,
                onFinished: { dismiss() }, record: record)
        }
        .environment(\.novaHasHeader, true)
        .statusBarHidden(false)
    }
}

private extension Array where Element == NovaFindingDetailBlock.Model {
    mutating func appendIfPresent(title: String, symbol: String, text: String?) {
        guard let text else { return }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        append(.init(title: title, symbol: symbol, text: normalized))
    }
}

private struct NovaFindingPhoto: View {
    let photo: UIImage?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .accessibilityLabel(Text(RDLocalization.string("localizable.nova.analysis.finding.source.photo", table: .localizable,
                        fallback: "Bulguyla ilişkili kaynak fotoğraf")))
            } else {
                VStack(spacing: 7) {
                    NovaIcon(symbol: "photo", size: 24)
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.finding.source.photo.failed", table: .localizable,
                        fallback: "Kaynak görsel yüklenemedi"), style: .metaQuiet)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NovaColorToken.surfaceMuted.color(in: scheme))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: photo == nil ? 120 : 190)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct NovaFindingDetailBlock: View {
    struct Model: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let text: String
    }
    let model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 16)
            Label(model.title, systemImage: model.symbol)
                .font(.system(size: 13, weight: .bold))
            NovaText(text: model.text, style: .body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NovaFindingScoreDisclosure: View {
    let score: NovaAnalysisScore
    let value: Double
    let method: NovaRiskMethod
    @Binding var isExpanded: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.top, 16)
            Button { withAnimation(NovaMotion.easeOut(0.16)) { isExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(
                            text: "\(NovaNonconformityWords.score(value)) · \(NovaNonconformityWords.band(score.band))",
                            style: .cardTitle,
                            color: NovaNonconformityWords.tone(score.band).tokens.ink.color(in: scheme)
                        )
                        NovaText(text: NovaNonconformityWords.method(method), style: .micro,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    Spacer(minLength: 0)
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.finding.score.explain", table: .localizable,
                        fallback: "Skor nasıl oluştu?"), style: .meta,
                        color: NovaColorToken.accentInk.color(in: scheme))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(11)
                .background(NovaNonconformityWords.tone(score.band).tokens.background.color(in: scheme),
                    in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(NovaRowPressStyle())
            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(score.factors) { factor in
                            NovaAnalysisTag(symbol: "number",
                                text: "\(factor.label) \(NovaNonconformityWords.score(factor.value))")
                        }
                        if !score.factors.isEmpty {
                            NovaText(text: "= \(NovaNonconformityWords.score(value))", style: .meta)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
