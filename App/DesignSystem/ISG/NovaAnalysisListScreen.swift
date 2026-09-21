import SwiftUI

/// The card that opens a list page: what the page is, how many rows it has,
/// and a short row of counters. Every number is passed in already counted.
struct NovaAnalysisOverviewCard: View {
    let symbol: String
    let title: String
    let detail: String
    let headline: String
    let headlineCaption: String
    let figures: [NovaAnalysisOverviewFigure]
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                NovaIcon(symbol: symbol, size: 19)
                    .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    NovaText(text: title, style: .sheetTitle)
                    NovaText(text: detail, style: .metaQuiet,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                     count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                NovaListStat(title: headlineCaption, symbol: symbol, value: headline)
                ForEach(figures) { figure in
                    NovaListStat(title: figure.label, symbol: figure.symbol, value: figure.value)
                }
            }
        }
    }
}

struct NovaAnalysisOverviewFigure: Identifiable, Equatable {
    let symbol: String
    let value: String
    let label: String
    var id: String { label }
}

/// The search field the analysis pages share.
struct NovaAnalysisSearchField: View {
    @Binding var text: String
    let placeholder: String
    var identifier = "analysis.search"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            TextField(placeholder, text: $text)
                .font(NovaFont.font(.body))
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle").font(.system(size: 14))
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                }.buttonStyle(NovaRowPressStyle())
                    .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.analysis.search.clear", table: .localizable, fallback: "Aramayı temizle")))
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 44)
        .background(NovaColorToken.surface.color(in: scheme), in: Capsule())
        .overlay(Capsule().strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
    }
}

/// One filter chip in the row under the search field.
struct NovaAnalysisFilterChip: View {
    let title: String
    let isOn: Bool
    var identifier: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NovaColorToken.onInverse.color(in: scheme))
                }
                NovaText(text: title, style: .meta,
                    color: isOn ? NovaColorToken.onInverse.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
            }
            .padding(.horizontal, 13).frame(minHeight: 38)
            .background(isOn ? NovaColorToken.inverse.color(in: scheme) : NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
            .animation(NovaMotion.easeOut(0.14), value: isOn)
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier(identifier)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Every completed analysis on the account, with its picture and the labels it
/// ran under. An unassigned one is not hidden: it is the row that still needs
/// a decision.
struct NovaAnalysisListScreen: View {
    /// One page, from an offset; the screen owns paging so the caller only
    /// answers the one question it is asked.
    let load: (Int) async throws -> (rows: [NovaAnalysisSummary], hasMore: Bool)
    /// The first picture of one analysis. A missing picture is simply absent.
    let thumbnail: (UUID) async -> UIImage?
    let onOpen: (UUID) -> Void
    let onBack: () -> Void
    var onNewPhotoAnalysis: (() -> Void)?
    var onReports: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    @State private var rows: [NovaAnalysisSummary]?
    @State private var hasMore = false
    @State private var loadingMore = false
    @State private var images: [UUID: UIImage] = [:]
    @State private var error: String?
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var company: String?
    @State private var reload = UUID()

    private enum Filter: String, CaseIterable, Identifiable {
        case all, week, critical, unassigned
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü")
            case .week: return RDLocalization.string("localizable.nova.analysis.filter.week", table: .localizable, fallback: "Bu hafta")
            case .critical: return RDLocalization.string("localizable.nova.nonconformity.severity.critical", table: .localizable, fallback: "Kritik")
            case .unassigned: return RDLocalization.string("localizable.nova.analysis.list.filter.unassigned", table: .localizable, fallback: "Firmasız")
            }
        }
    }

    private var all: [NovaAnalysisSummary] { rows ?? [] }
    private var stats: NovaAnalysisListStats { .init(all) }
    private var companyNames: [String] { Array(Set(all.compactMap(\.companyName))).sorted() }

    private var visible: [NovaAnalysisSummary] {
        let boundary = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return all.filter { row in
            guard row.matches(query) else { return false }
            if let company, row.companyName != company { return false }
            switch filter {
            case .all: return true
            case .week: return (row.createdAt ?? .distantPast) >= boundary
            case .critical: return row.highestBand == "critical"
            case .unassigned: return row.isUnassigned
            }
        }
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    overview
                    search
                    chips
                    list.novaAsyncContent(isLoading: rows == nil)
                        .novaListEntrance(hasRecords: !(rows ?? []).isEmpty)
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) { await refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            NovaBackButton { onBack() }
            NovaText(text: RDLocalization.string("localizable.nova.analysis.list.title", table: .localizable, fallback: "Analizlerim"), style: .screenTitle)
            Spacer(minLength: 0)
            if let onReports {
                Button(action: onReports) {
                    Image(systemName: "doc.text").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NovaColorToken.text.color(in: scheme))
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                }.buttonStyle(NovaRowPressStyle())
                    .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.analysis.reports.title", table: .localizable, fallback: "Analiz Raporları")))
                    .accessibilityIdentifier("analysis.list.reports")
            }
            if let onNewPhotoAnalysis {
                Button(action: onNewPhotoAnalysis) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera").font(.system(size: 13, weight: .bold))
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.new.short", table: .localizable, fallback: "Yeni"),
                            style: .buttonSm, color: NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    }
                    .foregroundStyle(NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(NovaColorToken.accent.color(in: scheme), in: Capsule())
                }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("analysis.list.new")
            }
        }
    }

    /// The counters are taken from the rows this page actually read, so the
    /// caption says how many that was rather than implying an account total.
    private var overview: some View {
        HStack(spacing: 8) {
            metric("Analiz", value: stats.total, symbol: "viewfinder")
            metric("Bu hafta", value: stats.thisWeek, symbol: "calendar")
            metric("Kritik", value: stats.critical, symbol: "exclamationmark.triangle")
            metric("Bulgu", value: stats.findings, symbol: "list.bullet")
        }
    }

    private func metric(_ label: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaIcon(symbol: symbol, size: 17)
            NovaSizedText(text: rows == nil ? "—" : String(value), size: 21, weight: "ExtraBold")
            NovaSizedText(text: label, size: 10, weight: "Medium")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .novaControlBackground(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }

    private var search: some View {
        VStack(spacing: 8) {
            NovaAnalysisSearchField(text: $query,
                placeholder: RDLocalization.string("localizable.nova.analysis.search.placeholder", table: .localizable, fallback: "Analiz ara"),
                identifier: "analysis.list.search")
            companyMenu
        }
    }

    private var companyMenu: some View {
        NovaFilterField(label: RDLocalization.string("localizable.nova.nonconformity.filter.company", table: .localizable,
            fallback: "Firma"), options: [.init(id: nil, title: RDLocalization.string("localizable.nova.document.company.all", table: .localizable,
                fallback: "Tüm firmalar"))] + companyNames.map { .init(id: $0, title: $0) },
            selected: company, identifier: "analysis.list.company") { company = $0 }
    }

    private var chips: some View {
        NovaFilterField(label: "Durum", options: Filter.allCases.map { .init(id: $0.rawValue, title: $0.title) },
            selected: filter.rawValue, identifier: "analysis.list.filter") { value in
            if let value, let selection = Filter(rawValue: value) { filter = selection }
        }
    }

    @ViewBuilder private var list: some View {
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if rows == nil {
            NovaLoadingView(message: RDLocalization.string("localizable.nova.analysis.list.loading", table: .localizable,
                fallback: "Analizler yükleniyor…"))
                .frame(minHeight: 280)
        } else if visible.isEmpty {
            NovaEmptyState(title: RDLocalization.string("localizable.nova.analysis.list.empty", table: .localizable,
                fallback: "Henüz analiz kaydı yok"),
                message: RDLocalization.string("localizable.nova.analysis.list.empty.detail", table: .localizable,
                    fallback: "Fotoğraf veya metin analizi oluşturarak riskleri, uzman görüşlerini ve önerileri dijital ortamda saklayabilirsiniz."))
        } else {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                card(row).novaRowEntrance(index)
            }
            // Only offered on an unfiltered, unsearched view of the account's
            // own order: filtering client-side over one page would silently
            // hide rows a further page might actually answer.
            if hasMore && query.isEmpty && company == nil && filter == .all {
                Button {
                    Task { await loadMore() }
                } label: {
                    HStack(spacing: 6) {
                        if loadingMore { ProgressView() }
                        NovaText(text: RDLocalization.string("localizable.nova.analysis.list.more", table: .localizable,
                            fallback: "Daha fazla göster"), style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(NovaRowPressStyle()).disabled(loadingMore)
                    .accessibilityIdentifier("analysis.list.more")
            }
        }
    }

    private func card(_ row: NovaAnalysisSummary) -> some View {
        Button { onOpen(row.id) } label: {
            NovaCard(padding: 10) {
                HStack(alignment: .top, spacing: 10) {
                    picture(row)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .top, spacing: 6) {
                            NovaText(text: row.title, style: .cardTitle).lineLimit(1)
                            Spacer(minLength: 0)
                            if let band = row.highestBand {
                                NovaStatusPill(label: NovaNonconformityWords.band(band),
                                    status: NovaNonconformityWords.tone(band), showsDot: false)
                            }
                        }
                        HStack(spacing: 5) {
                            fact("calendar", row.createdOn)
                            if let count = row.findingCount { fact("exclamationmark.triangle", "\(count)") }
                            if row.photoCount > 0 { fact("photo", "\(row.photoCount)") }
                        }
                        HStack(spacing: 5) {
                            if row.isUnassigned {
                                NovaAnalysisTag(symbol: "building.2",
                                    text: RDLocalization.string("localizable.nova.analysis.unassigned", table: .localizable, fallback: "Firmasız"),
                                    status: .info)
                            } else if let name = row.companyName {
                                NovaAnalysisTag(symbol: "building.2", text: name, status: .neutral)
                            }
                            if let sector = row.sectorLabel {
                                NovaAnalysisTag(symbol: "square.grid.2x2", text: sector, status: .neutral)
                            }
                            if row.isReviewed {
                                NovaAnalysisTag(symbol: "checkmark.circle",
                                    text: RDLocalization.string("localizable.history.status.reviewed", table: .localizable, fallback: "İncelendi"),
                                    status: .warning)
                            }
                            Spacer(minLength: 0)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 12))
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)).padding(.top, 6)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier("analysis.list.row.\(row.id.uuidString.lowercased())")
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: text, style: .micro, color: NovaColorToken.textSecondary.color(in: scheme)).lineLimit(1)
        }
    }

    @ViewBuilder private func picture(_ row: NovaAnalysisSummary) -> some View {
        Group {
            if let image = images[row.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                NovaColorToken.surfaceMuted.color(in: scheme)
                    .overlay(NovaIcon(symbol: "photo", size: 16)
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)))
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .bottomLeading) {
            Image(systemName: "camera").font(.system(size: 8, weight: .bold))
                .foregroundStyle(NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                .frame(width: 17, height: 17)
                .padding(3)
        }
        .accessibilityHidden(true)
        .task(id: row.id) {
            guard images[row.id] == nil else { return }
            if let image = await thumbnail(row.id) { images[row.id] = image }
        }
    }

    private func refresh() async {
        error = nil
        do {
            let page = try await load(0)
            rows = page.rows; hasMore = page.hasMore
        }
        catch is CancellationError { }
        catch {
            rows = []; hasMore = false
            self.error = RDLocalization.string("localizable.nova.analysis.list.failed", table: .localizable,
                fallback: "Analizler alınamadı. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
    private func loadMore() async {
        guard !loadingMore, hasMore else { return }
        loadingMore = true; defer { loadingMore = false }
        do {
            let page = try await load(all.count)
            rows = all + page.rows; hasMore = page.hasMore
        }
        catch is CancellationError { }
        catch {
            self.error = RDLocalization.string("localizable.nova.analysis.list.failed", table: .localizable,
                fallback: "Analizler alınamadı. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
}
