import SwiftUI

/// The reports that were produced from photo analyses. The page lists what the
/// archive holds; it does not produce anything of its own.
struct NovaAnalysisReportsScreen: View {
    let load: (Int) async throws -> (rows: [NovaAnalysisReportEntry], hasMore: Bool)
    let download: (NovaAnalysisReportEntry) async throws -> URL
    let onBack: () -> Void
    /// Opens the analysis a report was produced from, when it still exists.
    var onOpenAnalysis: ((UUID) -> Void)?
    @Environment(\.colorScheme) private var scheme
    @State private var rows: [NovaAnalysisReportEntry]?
    @State private var error: String?
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var reload = UUID()
    @State private var hasMore = false
    @State private var loadingMore = false
    @State private var downloading: UUID?
    @State private var shareItem: ShareItem?
    @State private var downloadError: String?

    private enum Filter: String, CaseIterable, Identifiable {
        case all, document, spreadsheet
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü")
            case .document: return RDLocalization.string("localizable.nova.analysis.reports.filter.pdf", table: .localizable, fallback: "PDF")
            case .spreadsheet: return RDLocalization.string("localizable.nova.analysis.reports.filter.excel", table: .localizable, fallback: "Excel")
            }
        }
    }

    private var all: [NovaAnalysisReportEntry] { rows ?? [] }
    private var stats: NovaAnalysisReportStats { .init(all) }
    private var visible: [NovaAnalysisReportEntry] {
        all.filter { row in
            guard row.matches(query) else { return false }
            switch filter {
            case .all: return true
            case .document: return !row.isSpreadsheet
            case .spreadsheet: return row.isSpreadsheet
            }
        }
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    overview
                    NovaListHint(text: "Oluşturduğunuz PDF ve Excel raporlarını arayıp dosya türüne göre filtreleyin.")
                    NovaAnalysisSearchField(text: $query,
                        placeholder: RDLocalization.string("localizable.nova.analysis.reports.search", table: .localizable, fallback: "Rapor ara"),
                        identifier: "analysis.reports.search")
                    chips
                    NovaListSectionHeading(title: "Raporlar", count: "\(visible.count) rapor")
                    list.novaAsyncContent(isLoading: rows == nil)
                        .novaListEntrance(hasRecords: !(rows ?? []).isEmpty)
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) { await refresh() }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert(downloadError ?? "", isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })) {
            Button("Tamam") { downloadError = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            NovaBackButton { onBack() }
            NovaText(text: RDLocalization.string("localizable.nova.analysis.reports.title", table: .localizable, fallback: "Analiz Raporları"),
                style: .screenTitle)
            Spacer(minLength: 0)
            Button { reload = UUID() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NovaColorToken.text.color(in: scheme))
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
            }.buttonStyle(NovaRowPressStyle())
                .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.analysis.list.refresh", table: .localizable, fallback: "Listeyi yenile")))
                .accessibilityIdentifier("analysis.reports.refresh")
        }
    }

    private var overview: some View {
        NovaMetricStrip(items: [
            .init(id: "total", value: rows == nil ? "—" : "\(stats.total)", label: "Dosya", symbol: "doc.text", status: .neutral),
            .init(id: "pdf", value: rows == nil ? "—" : "\(stats.documents)", label: "PDF", symbol: "doc.text", status: .info),
            .init(id: "excel", value: rows == nil ? "—" : "\(stats.spreadsheets)", label: "Excel", symbol: "tablecells", status: .neutral),
            .init(id: "companies", value: rows == nil ? "—" : "\(stats.companies)", label: "Firma", symbol: "building.2", status: .neutral)
        ])
    }

    private var chips: some View {
        HStack(spacing: 7) {
            ForEach(Filter.allCases) { value in
                NovaAnalysisFilterChip(title: value.title, isOn: filter == value,
                    identifier: "analysis.reports.filter.\(value.rawValue)") { filter = value }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var list: some View {
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if rows == nil {
            NovaLoadingView(message: RDLocalization.string("localizable.nova.analysis.reports.loading", table: .localizable,
                fallback: "Raporlar yükleniyor…")).frame(minHeight: 280)
        } else if visible.isEmpty {
            NovaEmptyState(title: RDLocalization.string("localizable.nova.analysis.reports.empty", table: .localizable,
                fallback: "Henüz analizden rapor oluşturmadınız."),
                message: RDLocalization.string("localizable.nova.analysis.reports.empty.detail", table: .localizable,
                    fallback: "Bir analizin raporunu oluşturarak PDF ve Excel çıktılarını denetimlerde hızlıca bulabilir, firma bazında saklayabilirsiniz."))
        } else {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                card(row).novaRowEntrance(index)
            }
            if hasMore && query.isEmpty && filter == .all {
                Button {
                    Task { await loadMore() }
                } label: {
                    HStack(spacing: 6) {
                        if loadingMore { ProgressView() }
                        NovaText(text: RDLocalization.string("localizable.nova.analysis.list.more", table: .localizable,
                            fallback: "Daha fazla göster"), style: .meta,
                            color: NovaColorToken.accentInk.color(in: scheme))
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(NovaRowPressStyle())
                .disabled(loadingMore)
                .accessibilityIdentifier("analysis.reports.more")
            }
        }
    }

    private func card(_ row: NovaAnalysisReportEntry) -> some View {
        NovaCard(padding: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    if let analysis = row.analysisID { onOpenAnalysis?(analysis) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: row.isSpreadsheet ? "tablecells" : "doc.text")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            NovaText(text: row.title, style: .cardTitle).lineLimit(1)
                            HStack(spacing: 5) {
                                fact("calendar", row.createdOn)
                                if let size = row.fileSize { fact("arrow.down.circle", Self.size(size)) }
                            }
                            HStack(spacing: 5) {
                                if let name = row.companyName {
                                    NovaAnalysisTag(symbol: "building.2", text: name, status: .neutral)
                                } else {
                                    NovaAnalysisTag(symbol: "building.2",
                                        text: RDLocalization.string("localizable.nova.analysis.unassigned", table: .localizable, fallback: "Firmasız"),
                                        status: .info)
                                }
                                NovaAnalysisTag(symbol: "slider.horizontal.3", text: row.methodLabel, status: .neutral)
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if row.analysisID != nil {
                            Image(systemName: "chevron.right").font(.system(size: 12))
                                .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)).padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NovaRowPressStyle())
                .disabled(row.analysisID == nil)

                Button {
                    Task { await downloadReport(row) }
                } label: {
                    Group {
                        if downloading == row.id {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NovaRowPressStyle())
                .disabled(downloading != nil)
                .accessibilityLabel(Text(verbatim: "Raporu indir"))
                .accessibilityIdentifier("analysis.reports.download.\(row.id.uuidString.lowercased())")
            }
        }
        .accessibilityIdentifier("analysis.reports.row.\(row.id.uuidString.lowercased())")
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: text, style: .micro, color: NovaColorToken.textSecondary.color(in: scheme)).lineLimit(1)
        }
    }

    /// A byte count as the archive recorded it, rounded the way a file listing
    /// rounds it rather than to a precision the number does not carry.
    private static func size(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func refresh() async {
        error = nil
        do {
            let page = try await load(0)
            rows = page.rows
            hasMore = page.hasMore
        }
        catch is CancellationError { }
        catch {
            rows = []
            hasMore = false
            self.error = RDLocalization.string("localizable.nova.analysis.reports.failed", table: .localizable,
                fallback: "Raporlar alınamadı. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }

    private func loadMore() async {
        guard !loadingMore, hasMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await load(all.count)
            rows = all + page.rows
            hasMore = page.hasMore
        } catch is CancellationError { }
        catch {
            // Keep the already loaded archive visible. A later tap can retry.
            hasMore = true
        }
    }

    private func downloadReport(_ row: NovaAnalysisReportEntry) async {
        guard downloading == nil else { return }
        downloading = row.id
        defer { downloading = nil }
        do {
            shareItem = ShareItem(url: try await download(row))
        } catch is CancellationError { }
        catch {
            downloadError = RDLocalization.string("localizable.nova.analysis.reports.download.failed", table: .localizable,
                fallback: "Rapor indirilemedi. Lütfen tekrar deneyin.")
        }
    }
}
