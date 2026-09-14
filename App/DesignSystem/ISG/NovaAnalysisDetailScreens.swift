import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// screen these closures.
struct NovaAnalysisDetailClient {
    let load: () async throws -> NovaAnalysisDetailData
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    /// Attaches the analysis to a company. The analysis row keeps living where
    /// it is; only its company reference changes.
    let assign: (UUID) async throws -> Void
    let workplaces: (UUID) async throws -> [NovaNonconformityWorkplace]
    let file: (NovaAnalysisFileRequest) async -> NovaFindingOutcome
    let edit: (NovaAnalysisFindingEdit) async throws -> Void
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
    @State private var loadError: String?
    @State private var section: NovaAnalysisSectionKind = .riskAnalysis
    @State private var expanded: Set<UUID> = []
    @State private var selected: Set<UUID> = []
    @State private var outcomes: [UUID: NovaFindingOutcome] = [:]
    @State private var editing: NovaAnalysisItem?
    @State private var filing = false
    @State private var reporting = false
    @State private var assigning = false
    @State private var notice: String?
    @State private var reload = UUID()

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
        .fullScreenCover(item: $editing) { item in
            NovaPopup {
                NovaFindingEditSheet(item: item, method: data?.method ?? .fineKinney) { edit in
                    guard let data else { return }
                    try await client.edit(.init(analysisID: data.analysisID, findingID: item.id,
                        title: edit.title, category: edit.category, body: edit.body, measure: edit.measure,
                        references: edit.references, score: edit.score))
                    editing = nil
                    reload = UUID()
                }
            }
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
        do { data = try await client.load() }
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
        HStack(spacing: 10) {
            NovaBackButton { onBack() }
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: data?.title ?? RDLocalization.string("localizable.nova.analysis.title", table: .localizable, fallback: "Analiz"), style: .screenTitle)
                if let data {
                    NovaText(text: [data.createdOn, data.methodLabel,
                        data.companyName ?? RDLocalization.string("localizable.nova.analysis.unassigned", table: .localizable, fallback: "Firmasız")]
                        .joined(separator: " · "), style: .metaQuiet)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func content(_ data: NovaAnalysisDetailData) -> some View {
        if data.isProjectionMissing {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.projection.missing", table: .localizable,
                    fallback: "Bu analizin bölümleri henüz hazır değil. Biraz sonra tekrar açın."), style: .metaQuiet)
            }
        }
        actions(data)
        sectionPicker(data)
        if let current = data.section(section) {
            if current.isTeaser {
                NovaCard(padding: 16) {
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.teaser", table: .localizable,
                        fallback: "Bu bölümün tamamı planınıza dahil değil; yalnız bir özeti gösteriliyor."), style: .metaQuiet)
                }
            }
            if current.items.isEmpty {
                NovaCard(padding: 16) {
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.section.empty", table: .localizable,
                        fallback: "Bu bölümde kayıt yok."), style: .metaQuiet)
                }
            } else {
                ForEach(current.items) { item in row(item, data: data) }
                fileFooter(data, section: current)
            }
        }
    }

    @ViewBuilder private func actions(_ data: NovaAnalysisDetailData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if data.companyID == nil {
                NovaCard(padding: 14, tint: NovaColorToken.statusInfoBg.color(in: scheme)) {
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

    private func sectionPicker(_ data: NovaAnalysisDetailData) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(data.sections) { entry in
                    Button {
                        section = entry.kind; selected = []
                    } label: {
                        NovaText(text: sectionTitle(entry.kind) + " · \(entry.items.count)", style: .meta,
                            color: section == entry.kind ? NovaColorToken.accentInk.color(in: scheme)
                                                         : NovaColorToken.textSecondary.color(in: scheme))
                            .padding(.horizontal, 12).frame(minHeight: 40)
                            .background(section == entry.kind ? NovaColorToken.statusSuccessBg.color(in: scheme) : .clear,
                                in: Capsule())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("analysis.detail.section.\(entry.kind.rawValue)")
                        .accessibilityAddTraits(section == entry.kind ? .isSelected : [])
                }
            }
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

    // MARK: item row

    private func row(_ item: NovaAnalysisItem, data: NovaAnalysisDetailData) -> some View {
        let isOpen = expanded.contains(item.id)
        return NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    if section.isFileable && data.companyID != nil && canWrite {
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                        } label: {
                            Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(item.id) ? NovaColorToken.accentInk.color(in: scheme)
                                                                            : NovaColorToken.borderStrong.color(in: scheme))
                                .frame(width: 30, height: 44)
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("analysis.detail.select.\(item.id.uuidString.lowercased())")
                            .accessibilityLabel(Text(verbatim: item.title))
                            .accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
                    }
                    Button {
                        if isOpen { expanded.remove(item.id) } else { expanded.insert(item.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            NovaText(text: "\(item.ordinal). \(item.title)", style: .cardTitle)
                            if let band = item.band { bandLine(item, band: band, method: data.methodLabel) }
                            else if let category = item.category { NovaText(text: category, style: .metaQuiet) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("analysis.detail.item.\(item.id.uuidString.lowercased())")
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 12))
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                }
                if isOpen { detail(item, data: data) }
                if let outcome = outcomes[item.id] { outcomeLine(outcome) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bandLine(_ item: NovaAnalysisItem, band: String, method: String) -> some View {
        HStack(spacing: 6) {
            NovaStatusPill(label: NovaNonconformityWords.band(band), status: NovaNonconformityWords.tone(band))
            if let score = item.score {
                NovaText(text: NovaNonconformityWords.score(score) + " · " + method, style: .metaQuiet)
            } else {
                NovaText(text: method, style: .metaQuiet)
            }
        }
    }

    @ViewBuilder private func detail(_ item: NovaAnalysisItem, data: NovaAnalysisDetailData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !item.body.isEmpty { NovaText(text: item.body) }
            if let measure = item.measure, !measure.isEmpty {
                labelled(RDLocalization.string("localizable.nova.analysis.field.measure", table: .localizable, fallback: "Önlem"), measure)
            }
            if let references = item.references, !references.isEmpty {
                labelled(RDLocalization.string("localizable.nova.analysis.field.references", table: .localizable, fallback: "Mevzuat"), references)
            }
            if section.isScored && canWrite {
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.edit", table: .localizable, fallback: "Bulguyu düzenle"),
                    symbol: "square.and.pencil", variant: .surface) { editing = item }
                    .accessibilityIdentifier("analysis.detail.edit.\(item.id.uuidString.lowercased())")
            }
            if section.isFileable && data.companyID == nil {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.file.needs.company", table: .localizable,
                    fallback: "Uygunsuzluk açmak için önce analizi bir firmaya atayın."), style: .metaQuiet)
            }
        }
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NovaText(text: title, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: value, style: .metaQuiet)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
                EmptyView()
            } else {
                NovaButton(label: String(format: RDLocalization.string("localizable.nova.analysis.file.selected", table: .localizable,
                    fallback: "Seçilenleri firmaya aktar (%d)"), selected.count),
                    symbol: "arrow.right.doc.on.clipboard", isEnabled: !selected.isEmpty) { filing = true }
                    .accessibilityIdentifier("analysis.detail.file")
            }
        }
    }
}
