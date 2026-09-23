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
    @State private var sort: Sort = .newest
    @State private var company: String?
    @State private var reload = UUID()

    private enum Filter: String, CaseIterable, Identifiable {
        case all, critical, unassigned, unreviewed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü")
            case .critical: return RDLocalization.string("localizable.nova.nonconformity.severity.critical", table: .localizable, fallback: "Kritik")
            case .unassigned: return RDLocalization.string("localizable.nova.analysis.list.filter.unassigned", table: .localizable, fallback: "Firmasız")
            case .unreviewed: return RDLocalization.string("localizable.nova.analysis.list.filter.unreviewed", table: .localizable, fallback: "İncelenmemiş")
            }
        }
    }

    private enum Sort: String, CaseIterable, Identifiable {
        case newest, highestRisk, mostFindings, unreviewed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .newest: return RDLocalization.string("localizable.nova.analysis.list.sort.newest", table: .localizable, fallback: "En yeni")
            case .highestRisk: return RDLocalization.string("localizable.nova.analysis.list.sort.highest", table: .localizable, fallback: "En yüksek risk")
            case .mostFindings: return RDLocalization.string("localizable.nova.analysis.list.sort.findings", table: .localizable, fallback: "En çok bulgu")
            case .unreviewed: return RDLocalization.string("localizable.nova.analysis.list.sort.unreviewed", table: .localizable, fallback: "İncelenmemiş önce")
            }
        }
    }

    private var all: [NovaAnalysisSummary] { rows ?? [] }
    private var stats: NovaAnalysisListStats { .init(all) }
    private var companyNames: [String] { Array(Set(all.compactMap(\.companyName))).sorted() }
    private var activeFilterCount: Int { (filter == .all ? 0 : 1) + (company == nil ? 0 : 1) }

    private var visible: [NovaAnalysisSummary] {
        let filtered = all.filter { row in
            guard row.matches(query) else { return false }
            if let company, row.companyName != company { return false }
            switch filter {
            case .all: return true
            case .critical: return row.highestBand == "critical"
            case .unassigned: return row.isUnassigned
            case .unreviewed: return !row.isReviewed
            }
        }
        return filtered.sorted { left, right in
            switch sort {
            case .newest:
                return (left.createdAt ?? .distantPast) > (right.createdAt ?? .distantPast)
            case .highestRisk:
                let leftRank = riskRank(left.highestBand)
                let rightRank = riskRank(right.highestBand)
                return leftRank == rightRank
                    ? (left.createdAt ?? .distantPast) > (right.createdAt ?? .distantPast)
                    : leftRank > rightRank
            case .mostFindings:
                let leftCount = left.findingCount ?? 0
                let rightCount = right.findingCount ?? 0
                return leftCount == rightCount
                    ? (left.createdAt ?? .distantPast) > (right.createdAt ?? .distantPast)
                    : leftCount > rightCount
            case .unreviewed:
                return left.isReviewed == right.isReviewed
                    ? (left.createdAt ?? .distantPast) > (right.createdAt ?? .distantPast)
                    : !left.isReviewed
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
                    filterControls
                    activeFilters
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
            NovaText(text: RDLocalization.string("localizable.nova.analysis.list.title", table: .localizable, fallback: "Analizler"), style: .screenTitle)
            Spacer(minLength: 0)
            if let onReports {
                Menu {
                    Button(action: onReports) {
                        Label(RDLocalization.string("localizable.nova.analysis.reports.title", table: .localizable,
                            fallback: "Analiz Raporları"), systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NovaColorToken.text.color(in: scheme))
                        .frame(width: 44, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                }
                    .accessibilityIdentifier("analysis.list.reports")
            }
            if let onNewPhotoAnalysis {
                Button(action: onNewPhotoAnalysis) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
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
        HStack(spacing: 0) {
            summaryMetric(rows == nil ? "—" : String(stats.total), "analiz")
            divider
            summaryMetric(rows == nil ? "—" : String(stats.critical), "kritik", status: .danger)
            divider
            summaryMetric(rows == nil ? "—" : String(stats.findings), "bulgu")
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 48)
        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(width: 1, height: 22)
    }

    private func summaryMetric(_ value: String, _ label: String, status: NovaStatus = .neutral) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            NovaSizedText(text: value, size: 16, weight: "ExtraBold",
                color: status.tokens.ink.color(in: scheme))
            NovaText(text: label, style: .metaQuiet)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var search: some View {
        NovaAnalysisSearchField(text: $query,
            placeholder: RDLocalization.string("localizable.nova.analysis.search.placeholder", table: .localizable, fallback: "Analiz, firma veya sektör ara"),
            identifier: "analysis.list.search")
    }

    private var filterControls: some View {
        HStack(spacing: 8) {
            Menu {
                Section(RDLocalization.string("localizable.nova.analysis.list.filter.state", table: .localizable, fallback: "Durum")) {
                    ForEach(Filter.allCases) { option in
                        Button { filter = option } label: {
                            if filter == option { Label(option.title, systemImage: "checkmark") }
                            else { Text(option.title) }
                        }
                    }
                }
                if !companyNames.isEmpty {
                    Section(RDLocalization.string("localizable.nova.analysis.list.filter.company", table: .localizable, fallback: "Firma")) {
                        Button { company = nil } label: {
                            if company == nil {
                                Label(RDLocalization.string("localizable.nova.analysis.list.filter.companies", table: .localizable,
                                    fallback: "Tüm firmalar"), systemImage: "checkmark")
                            } else {
                                Text(RDLocalization.string("localizable.nova.analysis.list.filter.companies", table: .localizable,
                                    fallback: "Tüm firmalar"))
                            }
                        }
                        ForEach(companyNames, id: \.self) { name in
                            Button { company = name } label: {
                                if company == name { Label(name, systemImage: "checkmark") }
                                else { Text(name) }
                            }
                        }
                    }
                }
            } label: {
                compactControl(symbol: "line.3.horizontal.decrease",
                    title: activeFilterCount == 0 ? "Filtre" : "Filtre · \(activeFilterCount)", emphasized: activeFilterCount > 0)
            }
            .accessibilityIdentifier("analysis.list.filter")

            Menu {
                ForEach(Sort.allCases) { option in
                    Button { sort = option } label: {
                        if sort == option { Label(option.title, systemImage: "checkmark") }
                        else { Text(option.title) }
                    }
                }
            } label: {
                compactControl(symbol: "arrow.up.arrow.down", title: sort.title, emphasized: false)
            }
            .accessibilityIdentifier("analysis.list.sort")
            Spacer(minLength: 0)
        }
    }

    private func compactControl(symbol: String, title: String, emphasized: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            NovaText(text: title, style: .meta,
                color: emphasized ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.text.color(in: scheme))
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(emphasized ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.text.color(in: scheme))
        .padding(.horizontal, 12).frame(minHeight: 38)
        .background(emphasized ? NovaColorToken.statusSuccessBg.color(in: scheme) : NovaColorToken.surface.color(in: scheme),
            in: Capsule())
        .overlay(Capsule().strokeBorder(emphasized ? NovaColorToken.accentInk.color(in: scheme)
                                                    : NovaColorToken.border.color(in: scheme), lineWidth: 1))
    }

    @ViewBuilder private var activeFilters: some View {
        if filter != .all || company != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    if filter != .all {
                        removableFilter(filter.title) { filter = .all }
                    }
                    if let company {
                        removableFilter(company) { self.company = nil }
                    }
                }
            }
        }
    }

    private func removableFilter(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                NovaText(text: title, style: .micro, color: NovaColorToken.accentInk.color(in: scheme))
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
            .padding(.horizontal, 10).frame(minHeight: 30)
            .background(NovaColorToken.statusSuccessBg.color(in: scheme), in: Capsule())
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityLabel(Text(String(format: RDLocalization.string("localizable.nova.analysis.list.filter.remove", table: .localizable,
            fallback: "%@ filtresini kaldır"), title)))
    }

    @ViewBuilder private var list: some View {
        if let error {
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    NovaText(text: error, style: .metaQuiet)
                    Button { reload = UUID() } label: {
                        Label(RDLocalization.string("analysis.nova.analysis.list.screen.tekrar.dene.e6915e8e", table: .analysis, fallback: "Tekrar dene"), systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(NovaRowPressStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if rows == nil {
            ForEach(0..<4, id: \.self) { index in
                placeholderCard
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
                    .novaRowEntrance(index)
            }
        } else if visible.isEmpty {
            NovaEmptyState(title: RDLocalization.string("localizable.nova.analysis.list.empty", table: .localizable,
                fallback: "Görüntülenecek analiz yok."),
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
            HStack(alignment: .center, spacing: 11) {
                picture(row)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        NovaText(text: NovaAnalysisPresentation.title(row.title), style: .cardTitle).lineLimit(1)
                        Spacer(minLength: 0)
                        if let band = row.highestBand {
                            severity(band)
                        }
                    }
                    HStack(spacing: 6) {
                        fact("calendar", NovaAnalysisPresentation.dateOnly(row.createdOn))
                        if let count = row.findingCount { fact("exclamationmark.triangle", "\(count) bulgu") }
                        if row.photoCount > 0 { fact("photo", "\(row.photoCount)") }
                    }
                    HStack(spacing: 6) {
                        fact("building.2", row.companyName ?? RDLocalization.string(
                            "localizable.nova.analysis.unassigned", table: .localizable, fallback: "Firmasız"))
                        if let sector = row.sectorLabel { fact("square.grid.2x2", sector) }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                    .frame(width: 20, height: 44)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier("analysis.list.row.\(row.id.uuidString.lowercased())")
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .regular))
                .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: text, style: .metaQuiet,
                color: NovaColorToken.textSecondary.color(in: scheme)).lineLimit(1)
        }
    }

    private func severity(_ band: String) -> some View {
        let tone = NovaNonconformityWords.tone(band)
        return HStack(spacing: 5) {
            Circle().fill(tone.tokens.ink.color(in: scheme)).frame(width: 6, height: 6)
            NovaText(text: NovaNonconformityWords.band(band), style: .metaQuiet,
                color: NovaColorToken.textSecondary.color(in: scheme))
        }
        .accessibilityElement(children: .combine)
    }

    private var placeholderCard: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 12).fill(NovaColorToken.surfaceMuted.color(in: scheme))
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(NovaColorToken.surfaceMuted.color(in: scheme)).frame(height: 13)
                RoundedRectangle(cornerRadius: 4).fill(NovaColorToken.surfaceMuted.color(in: scheme)).frame(width: 180, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(NovaColorToken.surfaceMuted.color(in: scheme)).frame(width: 130, height: 10)
            }
        }
        .padding(11)
        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
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
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 13))
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

    private func riskRank(_ band: String?) -> Int {
        switch band {
        case "critical": return 4
        case "high": return 3
        case "medium": return 2
        case "low": return 1
        default: return 0
        }
    }
}
