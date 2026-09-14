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
    @State private var selected: Set<UUID> = []
    @State private var outcomes: [UUID: NovaFindingOutcome] = [:]
    @State private var reactions: [UUID: NovaAnalysisReaction] = [:]
    @State private var inspecting: NovaAnalysisItem?
    @State private var preview: NovaPreviewImage?
    @State private var filing = false
    @State private var reporting = false
    @State private var assigning = false
    @State private var notice: String?
    @State private var reload = UUID()

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if let loadError {
                        NovaCard(padding: 16) { NovaText(text: loadError, style: .metaQuiet) }
                    } else if let data {
                        content(data)
                    } else {
                        NovaCard(padding: 16) {
                            NovaText(text: RDLocalization.string("localizable.nova.analysis.loading", table: .localizable,
                                fallback: "Analiz yükleniyor…"), style: .metaQuiet)
                        }
                    }
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) { await load() }
        .fullScreenCover(item: $inspecting) { item in
            NovaPopup {
                NovaAnalysisItemSheet(item: item, section: section, method: data?.method ?? .fineKinney,
                    reaction: reactions[item.id] ?? .none, canWrite: canWrite,
                    react: { value in
                        try await client.react(item, section, value)
                        reactions[item.id] = value
                    },
                    save: { edit in
                        guard let data else { return }
                        try await client.edit(.init(analysisID: data.analysisID, findingID: item.id,
                            title: edit.title, category: edit.category, body: edit.body, measure: edit.measure,
                            references: edit.references, score: edit.score))
                        inspecting = nil
                        reload = UUID()
                    },
                    remove: {
                        try await client.remove(item)
                        inspecting = nil
                        reload = UUID()
                    })
            }
        }
        .fullScreenCover(item: $preview) { item in
            NovaPopup { NovaImageViewer(image: item.image) }
        }
        .fullScreenCover(isPresented: $filing) {
            NovaPopup {
                if let data, let company = data.companyID {
                    NovaAnalysisFileSheet(items: selectedItems(data), section: section,
                        loadWorkplaces: { try await client.workplaces(company) },
                        file: client.file, onFinished: { selected = []; filing = false },
                        record: { id, outcome in outcomes[id] = outcome })
                }
            }
        }
        .fullScreenCover(isPresented: $reporting) {
            NovaPopup {
                if let data {
                    NovaAnalysisReportSheet(data: data) { request in
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
            data = try await client.load()
            pictures = await client.photos()
        }
        catch is CancellationError { }
        catch {
            loadError = RDLocalization.string("localizable.nova.analysis.load.failed", table: .localizable,
                fallback: "Analiz yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }

    private func selectedItems(_ data: NovaAnalysisDetailData) -> [NovaAnalysisItem] {
        (data.section(section)?.items ?? []).filter { selected.contains($0.id) }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            NovaBackButton { onBack() }
            VStack(alignment: .leading, spacing: 3) {
                NovaText(text: data?.title ?? RDLocalization.string("localizable.nova.analysis.title", table: .localizable, fallback: "Analiz"), style: .screenTitle)
                if let data {
                    NovaText(text: [data.createdOn, data.methodLabel,
                        data.companyName ?? RDLocalization.string("localizable.nova.analysis.unassigned", table: .localizable, fallback: "Firmasız")]
                        .joined(separator: " · "), style: .metaQuiet)
                }
            }
            Spacer(minLength: 0)
            thumbnail
        }
    }

    /// The analysed picture sits next to the title; tapping it opens the full
    /// size in a popup rather than pushing another page.
    @ViewBuilder private var thumbnail: some View {
        if let first = pictures.first {
            Button { preview = .init(image: first) } label: {
                Image(uiImage: first).resizable().scaledToFill()
                    .frame(width: 54, height: 54)
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
        }
    }

    @ViewBuilder private func content(_ data: NovaAnalysisDetailData) -> some View {
        if data.isProjectionMissing {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.projection.missing", table: .localizable,
                    fallback: "Bu analizin bölümleri henüz hazır değil. Biraz sonra tekrar açın."), style: .metaQuiet)
            }
        }
        tags(data)
        actions(data)
        sectionFrame(data)
        if let current = data.section(section) {
            if current.isTeaser {
                NovaCard(padding: 14) {
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.teaser", table: .localizable,
                        fallback: "Bu bölümün tamamı planınıza dahil değil; yalnız bir özeti gösteriliyor."), style: .metaQuiet)
                }
            }
            if current.items.isEmpty {
                NovaCard(padding: 14) {
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.section.empty", table: .localizable,
                        fallback: "Bu bölümde kayıt yok."), style: .metaQuiet)
                }
            } else {
                ForEach(current.items) { item in row(item, data: data) }
                fileFooter(data, section: current)
            }
        }
    }

    /// What the analysis actually ran with, so the reader never has to guess.
    @ViewBuilder private func tags(_ data: NovaAnalysisDetailData) -> some View {
        let labels = [data.sectorLabel].compactMap { $0 } + data.focusLabels
        if !labels.isEmpty || data.photoCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if data.photoCount > 0 {
                        tag("photo", String(format: RDLocalization.string("localizable.nova.analysis.tag.photos", table: .localizable,
                            fallback: "%d fotoğraf"), data.photoCount))
                    }
                    if let sector = data.sectorLabel { tag("building.2", sector) }
                    ForEach(data.focusLabels, id: \.self) { focus in tag("sparkle", focus) }
                }.padding(.vertical, 1)
            }
        }
    }

    private func tag(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            NovaIcon(symbol: symbol, size: 12).foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: text, style: .micro, color: NovaColorToken.textSecondary.color(in: scheme))
        }.padding(.horizontal, 10).frame(minHeight: 30)
            .background(NovaColorToken.surface.color(in: scheme), in: Capsule())
    }

    @ViewBuilder private func actions(_ data: NovaAnalysisDetailData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if data.companyID == nil {
                NovaCard(padding: 13, tint: NovaColorToken.statusInfoBg.color(in: scheme)) {
                    VStack(alignment: .leading, spacing: 8) {
                        NovaText(text: RDLocalization.string("localizable.nova.analysis.unassigned.detail", table: .localizable,
                            fallback: "Bu analiz bir firmaya bağlı değil. Hesabınızda duruyor; istediğiniz zaman atayabilirsiniz."),
                            style: .metaQuiet, color: NovaColorToken.statusInfoInk.color(in: scheme))
                        NovaButton(label: RDLocalization.string("localizable.nova.analysis.assign", table: .localizable, fallback: "Firmaya ata"),
                            symbol: "building.2", variant: .surface, isEnabled: canWrite) { assigning = true }
                            .accessibilityIdentifier("analysis.detail.assign")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            NovaButton(label: RDLocalization.string("localizable.nova.analysis.report", table: .localizable, fallback: "Rapor oluştur"),
                symbol: "doc.text", variant: .surface) { reporting = true }
                .accessibilityIdentifier("analysis.detail.report")
        }
    }

    // MARK: section menu

    /// The four sections as an icon menu, and the chosen one's heading, inside
    /// one frame so the menu and the title read as a single control.
    private func sectionFrame(_ data: NovaAnalysisDetailData) -> some View {
        NovaCard(padding: 12, border: NovaColorToken.accentInk.color(in: scheme)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(data.sections) { entry in sectionIcon(entry) }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: sectionTitle(section), style: .sectionTitle)
                    NovaText(text: sectionCaption(data.section(section)), style: .metaQuiet)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionIcon(_ entry: NovaAnalysisSection) -> some View {
        let isOn = entry.kind == section
        return Button {
            section = entry.kind
            selected = []
        } label: {
            VStack(spacing: 4) {
                NovaIcon(symbol: sectionSymbol(entry.kind), size: 19)
                    .foregroundStyle(isOn ? NovaColorToken.onAccent.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                NovaText(text: "\(entry.items.count)", style: .micro,
                    color: isOn ? NovaColorToken.onAccent.color(in: scheme) : NovaColorToken.textTertiary.color(in: scheme))
            }.frame(width: 58, height: 54)
                .background(isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.surfaceMuted.color(in: scheme),
                    in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: sectionTitle(entry.kind)))
            .accessibilityValue(Text(verbatim: "\(entry.items.count)"))
            .accessibilityIdentifier("analysis.detail.section.\(entry.kind.rawValue)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func sectionCaption(_ entry: NovaAnalysisSection?) -> String {
        let count = entry?.items.count ?? 0
        switch section {
        case .riskAnalysis:
            return String(format: RDLocalization.string("localizable.nova.analysis.caption.risk", table: .localizable,
                fallback: "%d skorlu bulgu · uygunsuzluğa dönüştürülebilir"), count)
        case .expertRecommendations:
            return String(format: RDLocalization.string("localizable.nova.analysis.caption.expert", table: .localizable,
                fallback: "%d skorsuz öneri · önem derecesini siz seçersiniz"), count)
        case .trainingRecommendations:
            return String(format: RDLocalization.string("localizable.nova.analysis.caption.training", table: .localizable,
                fallback: "%d eğitim önerisi · skorsuz"), count)
        case .approvedNotebook:
            return String(format: RDLocalization.string("localizable.nova.analysis.caption.notebook", table: .localizable,
                fallback: "%d defter kaydı · firmaya aktarılmaz"), count)
        }
    }

    private func sectionTitle(_ kind: NovaAnalysisSectionKind) -> String {
        switch kind {
        case .riskAnalysis: return RDLocalization.string("localizable.nova.analysis.section.risk", table: .localizable, fallback: "Risk Analizi")
        case .expertRecommendations: return RDLocalization.string("localizable.nova.analysis.section.expert", table: .localizable, fallback: "Uzman Görüşü")
        case .trainingRecommendations: return RDLocalization.string("localizable.nova.analysis.section.training", table: .localizable, fallback: "Eğitim Önerileri")
        case .approvedNotebook: return RDLocalization.string("localizable.nova.analysis.section.notebook", table: .localizable, fallback: "Onaylı Defter")
        }
    }
    private func sectionSymbol(_ kind: NovaAnalysisSectionKind) -> String {
        switch kind {
        case .riskAnalysis: return "exclamationmark.triangle"
        case .expertRecommendations: return "person.crop.rectangle"
        // Not the shared asset alias: that one draws an award badge, which is
        // not what a training recommendation means.
        case .trainingRecommendations: return "graduationcap.fill"
        case .approvedNotebook: return "doc.text"
        }
    }

    // MARK: item row

    private func row(_ item: NovaAnalysisItem, data: NovaAnalysisDetailData) -> some View {
        NovaCard(padding: 13) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 9) {
                    if section.isFileable && data.companyID != nil && canWrite {
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                        } label: {
                            Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(item.id) ? NovaColorToken.accentInk.color(in: scheme)
                                                                            : NovaColorToken.borderStrong.color(in: scheme))
                                .frame(width: 28, height: 40)
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("analysis.detail.select.\(item.id.uuidString.lowercased())")
                            .accessibilityLabel(Text(verbatim: item.title))
                            .accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        NovaText(text: "\(item.ordinal). \(item.title)", style: .cardTitle)
                        if let band = item.band {
                            HStack(spacing: 6) {
                                NovaStatusPill(label: NovaNonconformityWords.band(band), status: NovaNonconformityWords.tone(band))
                                if let score = item.score {
                                    NovaText(text: NovaNonconformityWords.score(score) + " · " + data.methodLabel, style: .metaQuiet)
                                }
                            }
                        } else if let category = item.category {
                            NovaText(text: category, style: .metaQuiet)
                        }
                        // A glimpse of the body, never the whole of it: the full
                        // text belongs in the popup where it can be acted on.
                        if !item.body.isEmpty {
                            NovaText(text: item.body, style: .metaQuiet).lineLimit(2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 10) {
                    Button { inspecting = item } label: {
                        HStack(spacing: 5) {
                            NovaText(text: RDLocalization.string("localizable.nova.analysis.item.more", table: .localizable, fallback: "Devamını incele"),
                                style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        }.foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 36)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("analysis.detail.more.\(item.id.uuidString.lowercased())")
                    if let reaction = reactions[item.id], reaction != .none {
                        NovaIcon(symbol: reaction == .like ? "hand.thumbsup.fill" : "hand.thumbsdown.fill", size: 13)
                            .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                    }
                    Spacer(minLength: 0)
                }
                if let outcome = outcomes[item.id] { outcomeLine(outcome) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func outcomeLine(_ outcome: NovaFindingOutcome) -> some View {
        switch outcome {
        case .untouched: EmptyView()
        case .opened:
            NovaText(text: RDLocalization.string("localizable.nova.bridge.outcome.opened", table: .localizable, fallback: "Uygunsuzluk açıldı"), style: .metaQuiet)
        case .alreadyOpen:
            NovaText(text: RDLocalization.string("localizable.nova.bridge.outcome.existing", table: .localizable, fallback: "Bu bulgunun uygunsuzluğu zaten vardı"), style: .metaQuiet)
        case .failed(let reason):
            NovaText(text: reason, style: .metaQuiet)
        }
    }

    @ViewBuilder private func fileFooter(_ data: NovaAnalysisDetailData, section current: NovaAnalysisSection) -> some View {
        if current.kind.isFileable && canWrite {
            if data.companyID == nil {
                NovaCard(padding: 13) {
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.file.needs.company", table: .localizable,
                        fallback: "Uygunsuzluk açmak için önce analizi bir firmaya atayın."), style: .metaQuiet)
                }
            } else {
                NovaButton(label: String(format: RDLocalization.string("localizable.nova.analysis.file.selected", table: .localizable,
                    fallback: "Seçilenleri firmaya aktar (%d)"), selected.count),
                    symbol: "arrow.right.doc.on.clipboard", isEnabled: !selected.isEmpty) { filing = true }
                    .accessibilityIdentifier("analysis.detail.file")
            }
        }
    }
}
