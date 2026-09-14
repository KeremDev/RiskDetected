import SwiftUI

/// Every completed analysis on the account, whether or not it belongs to a
/// company. An unassigned one is not hidden: it is the row that still needs a
/// decision.
struct NovaAnalysisListScreen: View {
    let load: () async throws -> [NovaAnalysisSummary]
    let onOpen: (UUID) -> Void
    let onBack: () -> Void
    var onNewPhotoAnalysis: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    @State private var rows: [NovaAnalysisSummary]?
    @State private var error: String?
    @State private var onlyUnassigned = false
    @State private var reload = UUID()

    private var visible: [NovaAnalysisSummary] {
        let all = rows ?? []
        return onlyUnassigned ? all.filter(\.isUnassigned) : all
    }

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        NovaBackButton { onBack() }
                        NovaText(text: RDLocalization.string("localizable.nova.analysis.list.title", table: .localizable, fallback: "Analizlerim"), style: .screenTitle)
                        Spacer(minLength: 0)
                    }
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.analysis.list.hint", table: .localizable,
                        fallback: "Firmasız analizler hesabınızda durur; istediğiniz zaman bir firmaya atayabilirsiniz."))
                    if let onNewPhotoAnalysis {
                        NovaButton(label: RDLocalization.string("localizable.nova.analysis.list.new", table: .localizable, fallback: "Yeni fotoğraf analizi"),
                            symbol: "camera") { onNewPhotoAnalysis() }
                            .accessibilityIdentifier("analysis.list.new")
                    }
                    filters
                    if let error {
                        NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
                    } else if rows == nil {
                        NovaCard(padding: 16) {
                            NovaText(text: RDLocalization.string("localizable.nova.analysis.list.loading", table: .localizable,
                                fallback: "Analizler yükleniyor…"), style: .metaQuiet)
                        }
                    } else if visible.isEmpty {
                        NovaCard(padding: 16) {
                            NovaText(text: RDLocalization.string("localizable.nova.analysis.list.empty", table: .localizable,
                                fallback: "Görüntülenecek analiz yok."), style: .metaQuiet)
                        }
                    } else {
                        ForEach(visible) { row in card(row) }
                    }
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) {
            error = nil
            do { rows = try await load() }
            catch is CancellationError { }
            catch {
                rows = []
                self.error = RDLocalization.string("localizable.nova.analysis.list.failed", table: .localizable,
                    fallback: "Analizler alınamadı. Bağlantınızı kontrol edip tekrar deneyin.")
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            chip(false, RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"))
            chip(true, RDLocalization.string("localizable.nova.analysis.list.filter.unassigned", table: .localizable, fallback: "Firmasız"))
            Spacer(minLength: 0)
            Button { reload = UUID() } label: {
                Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.analysis.list.refresh", table: .localizable, fallback: "Listeyi yenile")))
                .accessibilityIdentifier("analysis.list.refresh")
        }
    }

    private func chip(_ value: Bool, _ title: String) -> some View {
        Button { onlyUnassigned = value } label: {
            NovaText(text: title, style: .meta,
                color: onlyUnassigned == value ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(onlyUnassigned == value ? NovaColorToken.statusSuccessBg.color(in: scheme) : .clear, in: Capsule())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("analysis.list.filter.\(value ? "unassigned" : "all")")
            .accessibilityAddTraits(onlyUnassigned == value ? .isSelected : [])
    }

    private func card(_ row: NovaAnalysisSummary) -> some View {
        Button { onOpen(row.id) } label: {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    NovaText(text: row.title, style: .cardTitle)
                    HStack(spacing: 8) {
                        if row.isUnassigned {
                            NovaStatusPill(label: RDLocalization.string("localizable.nova.analysis.unassigned", table: .localizable, fallback: "Firmasız"), status: .info)
                        } else if let name = row.companyName {
                            NovaStatusPill(label: name, status: .neutral, showsDot: false)
                        }
                        if let count = row.findingCount {
                            NovaText(text: String(format: RDLocalization.string("localizable.nova.analysis.list.findings", table: .localizable,
                                fallback: "%d bulgu"), count), style: .metaQuiet)
                        }
                    }
                    NovaText(text: row.createdOn, style: .metaQuiet)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("analysis.list.row.\(row.id.uuidString.lowercased())")
    }
}
