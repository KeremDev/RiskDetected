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
    @Environment(\.colorScheme) private var scheme
    @State private var data: NovaAnalysisDetailData?
    @State private var pictures: [UIImage] = []
    @State private var loadError: String?
    @State private var section: NovaAnalysisSectionKind = .riskAnalysis
    @State private var method: NovaRiskMethod = .fineKinney
    @State private var methodChosen = false
    @State private var selected: Set<UUID> = []
    @State private var outcomes: [UUID: NovaFindingOutcome] = [:]
    @State private var reactions: [UUID: NovaAnalysisReaction] = [:]
    @State private var inspecting: NovaAnalysisItem?
    @State private var editing: NovaAnalysisItem?
    @State private var deleting: NovaAnalysisItem?
    @State private var preview: NovaPreviewImage?
    @State private var filing = false
    @State private var reporting = false
    @State private var assigning = false
    @State private var notice: String?
    @State private var reload = UUID()

    private var current: NovaAnalysisSection? { data?.section(section) }
    private var items: [NovaAnalysisItem] { current?.items ?? [] }
    private var selectable: Bool { section.isFileable && canWrite && data?.companyID != nil }

    var body: some View {
        NovaPageSurface {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let loadError {
                            NovaCard(padding: 16) { NovaText(text: loadError, style: .metaQuiet) }
                        } else if let data {
                            summaryCard(data)
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
        .safeAreaInset(edge: .bottom) { actionBar }
        .task(id: reload) { await load() }
        .fullScreenCover(item: $inspecting) { item in
            NovaPopup {
                NovaAnalysisItemSheet(item: item, section: section, method: method,
                    photo: photo(for: item), analysisTitle: data?.title ?? "",
                    companyName: data?.companyName, createdOn: data?.createdOn ?? "",
                    reaction: reactions[item.id] ?? item.reaction, canWrite: canWrite,
                    react: { value in
                        try await client.react(item, section, value)
                        reactions[item.id] = value
                    },
                    onEdit: { inspecting = nil; editing = item },
                    onDelete: { inspecting = nil; deleting = item })
            }
        }
        .fullScreenCover(item: $editing) { item in
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
        .fullScreenCover(item: $deleting) { item in
            NovaPopup {
                NovaAnalysisDeleteSheet(item: item) {
                    try await client.remove(item)
                    deleting = nil
                    reload = UUID()
                }
            }
        }
        .fullScreenCover(item: $preview) { item in
            NovaPopup { NovaImageViewer(image: item.image) }
        }
        .fullScreenCover(isPresented: $filing) {
            NovaPopup {
                if let data, let company = data.companyID {
                    NovaAnalysisFileSheet(items: selectedItems(), section: section, method: method,
                        loadWorkplaces: { try await client.workplaces(company) },
                        file: client.file, onFinished: { selected = []; filing = false },
                        record: { id, outcome in outcomes[id] = outcome })
                }
            }
        }
        .fullScreenCover(isPresented: $reporting) {
            NovaPopup {
                if let data {
                    NovaAnalysisReportSheet(data: data, method: method, selectedCount: selected.count) { request in
                        let name = try await client.report(request)
                        reporting = false
                        notice = String(format: RDLocalization.string("localizable.nova.analysis.report.saved", table: .localizable,
                            fallback: "Rapor arşive kaydedildi: %@"), name)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $assigning) {
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

    private func selectedItems() -> [NovaAnalysisItem] {
        items.filter { selected.contains($0.id) }
    }

    /// The picture an item was read from, when the analysis recorded one. The
    /// indices are one-based, so an index that falls outside what was actually
    /// downloaded resolves to nothing rather than to the wrong photo.
    private func photo(for item: NovaAnalysisItem) -> UIImage? {
        guard let index = item.photoIndices.first, index >= 1, index <= pictures.count else {
            return pictures.first
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

    /// One compact card for what this analysis is: picture, name, company,
    /// date and sector. Tapping the picture opens it full size.
    private func summaryCard(_ data: NovaAnalysisDetailData) -> some View {
        NovaCard(padding: 11) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 5) {
                        NovaText(text: data.title, style: .cardTitle).lineLimit(2)
                        HStack(spacing: 5) {
                            if let name = data.companyName {
                                NovaAnalysisTag(symbol: "building.2", text: name, status: .neutral)
                            } else {
                                NovaAnalysisTag(symbol: "building.2",
                                    text: RDLocalization.string("localizable.nova.analysis.unassigned", table: .localizable, fallback: "Firmasız"),
                                    status: .info)
                            }
                            if let sector = data.sectorLabel {
                                NovaAnalysisTag(symbol: "square.grid.2x2", text: sector, status: .neutral)
                            }
                        }
                        HStack(spacing: 5) {
                            NovaAnalysisTag(symbol: "calendar", text: data.createdOn, status: .neutral)
                            if data.photoCount > 0 {
                                NovaAnalysisTag(symbol: "photo",
                                    text: String(format: RDLocalization.string("localizable.nova.analysis.tag.photos", table: .localizable,
                                        fallback: "%d fotoğraf"), data.photoCount), status: .neutral)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if data.companyID == nil && canWrite { assignRow }
                if data.isProjectionMissing {
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.projection.missing", table: .localizable,
                        fallback: "Bu analizin bölümleri henüz hazır değil. Biraz sonra tekrar açın."), style: .metaQuiet)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// An unassigned analysis says so where the company would be, and offers
    /// the one step that changes it.
    private var assignRow: some View {
        Button { assigning = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "building.2.crop.circle").font(.system(size: 13, weight: .semibold))
                NovaText(text: RDLocalization.string("localizable.nova.analysis.assign", table: .localizable, fallback: "Firmaya ata"),
                    style: .meta, color: NovaColorToken.statusInfoInk.color(in: scheme))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(NovaColorToken.statusInfoInk.color(in: scheme))
            .padding(.horizontal, 11).frame(minHeight: 42)
            .background(NovaColorToken.statusInfoBg.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityIdentifier("analysis.detail.assign")
    }

    /// The analysed picture; tapping it opens the full size in a popup rather
    /// than pushing another page.
    @ViewBuilder private var thumbnail: some View {
        if let first = pictures.first {
            Button { preview = .init(image: first) } label: {
                Image(uiImage: first).resizable().scaledToFill()
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                    .overlay(alignment: .bottomTrailing) {
                        if pictures.count > 1 {
                            NovaText(text: "\(pictures.count)", style: .micro, color: NovaColorToken.onInverse.color(in: scheme))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(NovaColorToken.inverse.color(in: scheme).opacity(0.8), in: Capsule())
                                .padding(3)
                        }
                    }
            }.buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.analysis.photo.open", table: .localizable, fallback: "Analiz fotoğrafını büyüt")))
                .accessibilityIdentifier("analysis.detail.photo")
        } else {
            NovaColorToken.surfaceMuted.color(in: scheme)
                .frame(width: 62, height: 62)
                .overlay(NovaIcon(symbol: "photo", size: 18).foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
        }
    }

    // MARK: sections

    private func tabs(_ data: NovaAnalysisDetailData) -> some View {
        NovaFolderTabs(tabs: data.sections.map { entry in
            .init(id: entry.kind.rawValue, title: NovaAnalysisWords.sectionTitle(entry.kind),
                  symbol: NovaAnalysisSectionTone.of(entry.kind).symbol,
                  caption: NovaAnalysisWords.unit(entry.kind, entry.items.count))
        }, selection: Binding(get: { section.rawValue },
                              set: { value in
                                  guard let next = NovaAnalysisSectionKind(rawValue: value) else { return }
                                  section = next; selected = []
                              }),
        identifierPrefix: "analysis.detail.section") {
            sectionBody(data)
        }
    }

    @ViewBuilder private func sectionBody(_ data: NovaAnalysisDetailData) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            NovaAnalysisSectionHeader(kind: section, count: items.count, isTeaser: current?.isTeaser ?? false)
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
            if section.isFileable && canWrite && !items.isEmpty { fileHint }
        }
    }

    @ViewBuilder private var riskBody: some View {
        if let entry = current {
            NovaAnalysisStatsCard(section: entry, method: method)
        }
        NovaAnalysisMethodToggle(method: Binding(get: { method }, set: { method = $0; methodChosen = true }))
        selectionRow
        ForEach(items) { item in
            VStack(alignment: .leading, spacing: 5) {
                NovaAnalysisFindingCard(item: withReaction(item), method: method,
                    isSelected: selected.contains(item.id), isSelectable: selectable, canEdit: canWrite,
                    onSelect: { toggle(item) }, onOpen: { inspecting = item },
                    onEdit: { editing = item }, onDelete: { deleting = item },
                    onReact: { react(item, $0) })
                if let outcome = outcomes[item.id] { outcomeLine(outcome) }
            }
        }
    }

    @ViewBuilder private var adviceBody: some View {
        selectionRow
        ForEach(items) { item in
            VStack(alignment: .leading, spacing: 5) {
                NovaAnalysisAdviceCard(item: withReaction(item), kind: section,
                    isSelected: selected.contains(item.id), isSelectable: selectable,
                    onSelect: { toggle(item) }, onOpen: { inspecting = item },
                    onReact: { react(item, $0) })
                if let outcome = outcomes[item.id] { outcomeLine(outcome) }
            }
        }
    }

    /// How many rows are picked, and one control that takes or releases all of
    /// them. Shown only where filing is actually possible.
    @ViewBuilder private var selectionRow: some View {
        if selectable {
            HStack(spacing: 8) {
                NovaText(text: String(format: RDLocalization.string("localizable.nova.analysis.selection.count", table: .localizable,
                    fallback: "%1$d/%2$d seçili"), selected.count, items.count), style: .meta,
                    color: NovaColorToken.textSecondary.color(in: scheme))
                Spacer(minLength: 0)
                Button {
                    if selected.count == items.count { selected = [] }
                    else { selected = Set(items.map(\.id)) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: selected.count == items.count ? "xmark.circle" : "checkmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                        NovaText(text: selected.count == items.count
                            ? RDLocalization.string("localizable.nova.analysis.selection.none", table: .localizable, fallback: "Tümünü bırak")
                            : RDLocalization.string("localizable.nova.analysis.selection.all", table: .localizable, fallback: "Tümünü seç"),
                            style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                    }.foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 36)
                }.buttonStyle(.plain).accessibilityIdentifier("analysis.detail.select.all")
            }
        }
    }

    @ViewBuilder private var fileHint: some View {
        if data?.companyID == nil && canWrite && section.isFileable {
            NovaCard(padding: 13) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.file.needs.company", table: .localizable,
                    fallback: "Uygunsuzluk açmak için önce analizi bir firmaya atayın."), style: .metaQuiet)
            }
        }
    }

    private func withReaction(_ item: NovaAnalysisItem) -> NovaAnalysisItem {
        guard let value = reactions[item.id] else { return item }
        var copy = item
        copy.reaction = value
        return copy
    }

    private func toggle(_ item: NovaAnalysisItem) {
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
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

    /// The two things the expert always needs are pinned: the way back, and
    /// the report. When rows are picked, filing them takes the wide slot
    /// because that is the step the selection was made for.
    private var actionBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button { onBack() } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                        NovaText(text: RDLocalization.string("localizable.nova.analysis.back", table: .localizable, fallback: "Geri Dön"),
                            style: .badge, color: NovaColorToken.text.color(in: scheme))
                    }
                    .foregroundStyle(NovaColorToken.text.color(in: scheme))
                    .frame(width: 74, height: 54)
                    .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityIdentifier("analysis.detail.back")
                if selectable && !selected.isEmpty {
                    primary(RDLocalization.string("localizable.nova.analysis.file.run.short", table: .localizable, fallback: "Firmaya Aktar"),
                            symbol: "arrow.right.doc.on.clipboard", id: "file") { filing = true }
                } else {
                    primary(RDLocalization.string("localizable.nova.analysis.report", table: .localizable, fallback: "Rapor oluştur"),
                            symbol: "slider.horizontal.3", id: "report") { reporting = true }
                }
            }
            if selectable && !items.isEmpty {
                NovaText(text: String(format: RDLocalization.string("localizable.nova.analysis.selection.count", table: .localizable,
                    fallback: "%1$d/%2$d seçili"), selected.count, items.count), style: .micro,
                    color: NovaColorToken.textTertiary.color(in: scheme))
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
        .background(NovaColorToken.canvas.color(in: scheme).opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(height: 1)
        }
    }

    private func primary(_ label: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                NovaText(text: label, style: .button, color: NovaColorToken.onInverse.color(in: scheme))
                Spacer(minLength: 0)
                Image(systemName: "paperplane.fill").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NovaColorToken.inverse.color(in: scheme))
                    .frame(width: 38, height: 38)
                    .background(NovaColorToken.onInverse.color(in: scheme), in: Circle())
            }
            .foregroundStyle(NovaColorToken.onInverse.color(in: scheme))
            .padding(.leading, 16).padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(NovaColorToken.inverse.color(in: scheme), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("analysis.detail.\(id)")
    }
}
