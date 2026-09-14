import SwiftUI

/// The reports that were produced from photo analyses. The page lists what the
/// archive holds; it does not produce anything of its own.
struct NovaAnalysisReportsScreen: View {
    let load: () async throws -> [NovaAnalysisReportEntry]
    let onBack: () -> Void
    /// Opens the analysis a report was produced from, when it still exists.
    var onOpenAnalysis: ((UUID) -> Void)?
    @Environment(\.colorScheme) private var scheme
    @State private var rows: [NovaAnalysisReportEntry]?
    @State private var error: String?
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var reload = UUID()

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
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    overview
                    NovaAnalysisSearchField(text: $query,
                        placeholder: RDLocalization.string("localizable.nova.analysis.reports.search", table: .localizable, fallback: "Rapor ara"),
                        identifier: "analysis.reports.search")
                    chips
                    list
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) { await refresh() }
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
            }.buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.analysis.list.refresh", table: .localizable, fallback: "Listeyi yenile")))
                .accessibilityIdentifier("analysis.reports.refresh")
        }
    }

    private var overview: some View {
        NovaAnalysisOverviewCard(symbol: "doc.text",
            title: RDLocalization.string("localizable.nova.analysis.reports.overview.title", table: .localizable, fallback: "Denetime hazır çıktılar"),
            detail: RDLocalization.string("localizable.nova.analysis.reports.overview.detail", table: .localizable,
                fallback: "Fotoğraflı analizlerden ürettiğiniz PDF ve Excel raporları burada durur."),
            headline: "\(stats.total)",
            headlineCaption: RDLocalization.string("localizable.nova.analysis.reports.unit", table: .localizable, fallback: "dosya"),
            figures: [
                .init(symbol: "doc.text", value: "\(stats.documents)",
                      label: RDLocalization.string("localizable.nova.analysis.reports.filter.pdf", table: .localizable, fallback: "PDF")),
                .init(symbol: "tablecells", value: "\(stats.spreadsheets)",
                      label: RDLocalization.string("localizable.nova.analysis.reports.filter.excel", table: .localizable, fallback: "Excel")),
                .init(symbol: "building.2", value: "\(stats.companies)",
                      label: RDLocalization.string("localizable.nova.nonconformity.filter.company", table: .localizable, fallback: "Firma"))
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
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.reports.empty", table: .localizable,
                    fallback: "Henüz analizden rapor oluşturmadınız."), style: .metaQuiet)
            }
        } else {
            ForEach(visible) { row in card(row) }
        }
    }

    private func card(_ row: NovaAnalysisReportEntry) -> some View {
        Button {
            if let analysis = row.analysisID { onOpenAnalysis?(analysis) }
        } label: {
            NovaCard(padding: 10) {
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
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if row.analysisID != nil {
                        Image(systemName: "chevron.right").font(.system(size: 12))
                            .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)).padding(.top, 6)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
            // A report whose analysis is gone still lists; it simply does not
            // open one, and it is not greyed out as if the row were broken.
            .allowsHitTesting(row.analysisID != nil)
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
        do { rows = try await load() }
        catch is CancellationError { }
        catch {
            rows = []
            self.error = RDLocalization.string("localizable.nova.analysis.reports.failed", table: .localizable,
                fallback: "Raporlar alınamadı. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
}
