import SwiftUI

/// Every completed analysis on the account, with its picture and the labels it
/// ran under. An unassigned one is not hidden: it is the row that still needs
/// a decision.
struct NovaAnalysisListScreen: View {
    let load: () async throws -> [NovaAnalysisSummary]
    /// The first picture of one analysis. A missing picture is simply absent.
    let thumbnail: (UUID) async -> UIImage?
    let onOpen: (UUID) -> Void
    let onBack: () -> Void
    var onNewPhotoAnalysis: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    @State private var rows: [NovaAnalysisSummary]?
    @State private var images: [UUID: UIImage] = [:]
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
                VStack(alignment: .leading, spacing: 12) {
                    header
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.analysis.list.hint", table: .localizable,
                        fallback: "Firmasız analizler hesabınızda durur; istediğiniz zaman bir firmaya atayabilirsiniz."))
                    filters
                    body_
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) { await refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            NovaBackButton { onBack() }
            NovaText(text: RDLocalization.string("localizable.nova.analysis.list.title", table: .localizable, fallback: "Analizlerim"), style: .screenTitle)
            Spacer(minLength: 0)
            if let onNewPhotoAnalysis {
                Button(action: onNewPhotoAnalysis) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera").font(.system(size: 13, weight: .bold))
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.new.short", table: .localizable, fallback: "Yeni"),
                            style: .buttonSm, color: NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    }
                    .foregroundStyle(NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(NovaColorToken.accent.color(in: scheme), in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("analysis.list.new")
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            chip(false, RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"))
            chip(true, RDLocalization.string("localizable.nova.analysis.list.filter.unassigned", table: .localizable, fallback: "Firmasız"))
            Spacer(minLength: 0)
            Button { reload = UUID() } label: {
                Image(systemName: "arrow.clockwise").frame(width: 40, height: 40)
            }.buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.analysis.list.refresh", table: .localizable, fallback: "Listeyi yenile")))
                .accessibilityIdentifier("analysis.list.refresh")
        }
    }

    private func chip(_ value: Bool, _ title: String) -> some View {
        Button { onlyUnassigned = value } label: {
            NovaText(text: title, style: .meta,
                color: onlyUnassigned == value ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                .padding(.horizontal, 12).frame(minHeight: 38)
                .background(onlyUnassigned == value ? NovaColorToken.statusSuccessBg.color(in: scheme) : NovaColorToken.surface.color(in: scheme), in: Capsule())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("analysis.list.filter.\(value ? "unassigned" : "all")")
            .accessibilityAddTraits(onlyUnassigned == value ? .isSelected : [])
    }

    @ViewBuilder private var body_: some View {
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
    }

    private func card(_ row: NovaAnalysisSummary) -> some View {
        Button { onOpen(row.id) } label: {
            NovaCard(padding: 12) {
                HStack(alignment: .top, spacing: 11) {
                    picture(row)
                    VStack(alignment: .leading, spacing: 6) {
                        NovaText(text: row.title, style: .cardTitle).lineLimit(2)
                        HStack(spacing: 6) {
                            if row.isUnassigned {
                                NovaStatusPill(label: RDLocalization.string("localizable.nova.analysis.unassigned", table: .localizable, fallback: "Firmasız"), status: .info)
                            } else if let name = row.companyName {
                                NovaStatusPill(label: name, status: .neutral, showsDot: false)
                            }
                            if let band = row.highestBand {
                                NovaStatusPill(label: NovaNonconformityWords.band(band), status: NovaNonconformityWords.tone(band))
                            }
                        }
                        HStack(spacing: 5) {
                            if let count = row.findingCount {
                                label("exclamationmark.triangle", String(format: RDLocalization.string("localizable.nova.analysis.list.findings", table: .localizable,
                                    fallback: "%d bulgu"), count))
                            }
                            if row.photoCount > 0 {
                                label("photo", String(format: RDLocalization.string("localizable.nova.analysis.tag.photos", table: .localizable,
                                    fallback: "%d fotoğraf"), row.photoCount))
                            }
                        }
                        if let sector = row.sectorLabel {
                            label("building.2", sector)
                        }
                        NovaText(text: row.createdOn, style: .metaQuiet)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 12))
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)).padding(.top, 4)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("analysis.list.row.\(row.id.uuidString.lowercased())")
    }

    private func label(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            NovaIcon(symbol: symbol, size: 11).foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: text, style: .micro, color: NovaColorToken.textSecondary.color(in: scheme))
        }
    }

    @ViewBuilder private func picture(_ row: NovaAnalysisSummary) -> some View {
        Group {
            if let image = images[row.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                NovaColorToken.surfaceMuted.color(in: scheme)
                    .overlay(NovaIcon(symbol: "photo", size: 18)
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)))
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .accessibilityHidden(true)
        .task(id: row.id) {
            guard images[row.id] == nil else { return }
            if let image = await thumbnail(row.id) { images[row.id] = image }
        }
    }

    private func refresh() async {
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
