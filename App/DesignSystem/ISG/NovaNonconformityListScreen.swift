import SwiftUI

/// Everything the nonconformity board needs, as closures. The design layer
/// never imports the SDK.
struct NovaNonconformityBoardClient {
    let load: () async throws -> [NovaNonconformityEntry]
    /// The picture behind a record, when it came from a photo analysis.
    let thumbnail: (NovaNonconformityEntry) async -> UIImage?
    let open: (NovaNonconformityEntry) -> Void
    let create: (() -> Void)?
}

/// The record list: every nonconformity and improvement the account can see,
/// across companies, with the filters an expert actually sorts by.
struct NovaNonconformityListScreen: View {
    let client: NovaNonconformityBoardClient
    let companies: [NovaAnalysisCompanyOption]
    /// Today as an ISO day string, so "overdue" is decided by the caller's
    /// clock and time zone rather than guessed inside the view.
    let today: String
    let onBack: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var entries: [NovaNonconformityEntry]?
    @State private var pictures: [UUID: UIImage] = [:]
    @State private var openFilter: String?
    @State private var filter = NovaNonconformityFilter()
    @State private var error: String?
    @State private var reload = UUID()

    private var visible: [NovaNonconformityEntry] {
        (entries ?? []).filter { $0.matches(filter, today: today) }
    }
    private var overdueCount: Int {
        (entries ?? []).filter { $0.isOverdue(today: today) }.count
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    header
                    search
                    filters
                    summary
                    body_
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }

        .task(id: reload) { await load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            NovaBackButton { onBack() }
            NovaText(text: RDLocalization.string("localizable.nova.navigation.uygunsuzluklar", table: .localizable, fallback: "Uygunsuzluklar"), style: .screenTitle)
            Spacer(minLength: 0)
            if let create = client.create {
                Button(action: create) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.new.short", table: .localizable, fallback: "Yeni"),
                            style: .buttonSm, color: NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    }
                    .foregroundStyle(NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(NovaColorToken.accent.color(in: scheme), in: Capsule())
                }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("nonconformity.new")
            }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14))
                .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)).accessibilityHidden(true)
            TextField(RDLocalization.string("localizable.nova.nonconformity.search", table: .localizable,
                fallback: "Başlık, firma veya işyeri ara"), text: $filter.query)
                .font(NovaFont.font(.body)).submitLabel(.done)
                .accessibilityIdentifier("nonconformity.search")
            if !filter.query.isEmpty {
                Button { filter.query = "" } label: {
                    Image(systemName: "xmark.circle").frame(width: 32, height: 32)
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                }.buttonStyle(NovaRowPressStyle())
                    .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.nonconformity.search.clear", table: .localizable, fallback: "Aramayı temizle")))
            }
        }.padding(.horizontal, 14).frame(minHeight: 44)
            .background(NovaColorToken.surface.color(in: scheme), in: Capsule())
    }

    // MARK: filters

    private var filters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                filterButton(RDLocalization.string("localizable.nova.nonconformity.filter.company", table: .localizable, fallback: "Firma"),
                    key: "company", value: companies.first { $0.id == filter.companyID }?.name)
                filterButton(RDLocalization.string("localizable.nova.nonconformity.filter.state", table: .localizable, fallback: "Durum"),
                    key: "state", value: filter.overdueOnly ? RDLocalization.string("localizable.nova.nonconformity.filter.overdue", table: .localizable, fallback: "Termini geçen") : filter.state.map { NovaNonconformityWords.state($0.rawValue) })
                filterButton(RDLocalization.string("localizable.nova.nonconformity.filter.kind", table: .localizable, fallback: "Kayıt türü"),
                    key: "kind", value: filter.kind.map(NovaNonconformityWords.recordKind))
            }
            if let openFilter {
                NovaFileChooserPanel(options: filterOptions(openFilter), selected: filterSelection(openFilter),
                    identifier: "nonconformity.filter.\(openFilter).options") { value in
                    switch openFilter {
                    case "company": filter.companyID = value.flatMap(UUID.init(uuidString:))
                    case "state":
                        filter.overdueOnly = value == "overdue"
                        filter.state = value.flatMap(NovaNonconformityState.init(rawValue:))
                    default: filter.kind = value.flatMap(NovaNonconformityRecordKind.init(rawValue:))
                    }
                    self.openFilter = nil
                }
            }
        }
    }
    private func filterButton(_ label: String, key: String, value: String?) -> some View {
        NovaFileChooserButton(label: label, value: value ?? RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"), isOpen: openFilter == key,
            identifier: "nonconformity.filter.\(key)") { openFilter = openFilter == key ? nil : key }
    }
    private func filterSelection(_ key: String) -> String? {
        switch key {
        case "company": return filter.companyID?.uuidString
        case "state": return filter.overdueOnly ? "overdue" : filter.state?.rawValue
        default: return filter.kind?.rawValue
        }
    }
    private func filterOptions(_ key: String) -> [NovaFileChooserOption] {
        let all = [NovaFileChooserOption(id: nil, title: RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"))]
        switch key {
        case "company": return all + companies.map { .init(id: $0.id.uuidString, title: $0.name) }
        case "state":
            return all + [.init(id: "overdue", title: RDLocalization.string("localizable.nova.nonconformity.filter.overdue", table: .localizable, fallback: "Termini geçen"), count: overdueCount)] +
                [NovaNonconformityState.draft, .open, .assigned, .in_progress, .pending_verification, .closed, .reopened, .cancelled].map { .init(id: $0.rawValue, title: NovaNonconformityWords.state($0.rawValue)) }
        default: return all + NovaNonconformityRecordKind.allCases.map { .init(id: $0.rawValue, title: NovaNonconformityWords.recordKind($0)) }
        }
    }

    @ViewBuilder private var summary: some View {
        if entries != nil {
            HStack(spacing: 8) {
                NovaText(text: String(format: RDLocalization.string("localizable.nova.nonconformity.count", table: .localizable,
                    fallback: "%1$d / %2$d kayıt"), visible.count, entries?.count ?? 0), style: .metaQuiet)
                Spacer(minLength: 0)
                if !filter.isEmpty {
                    Button { filter = NovaNonconformityFilter() } label: {
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.filter.reset", table: .localizable, fallback: "Filtreleri temizle"),
                            style: .meta, color: NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 32)
                    }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("nonconformity.filter.reset")
                }
                Button { reload = UUID() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 40, height: 40)
                }.buttonStyle(NovaRowPressStyle())
                    .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.nonconformity.refresh", table: .localizable, fallback: "Listeyi yenile")))
                    .accessibilityIdentifier("nonconformity.refresh")
            }
        }
    }

    @ViewBuilder private var body_: some View {
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if entries == nil {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.nonconformity.loading", table: .localizable, fallback: "Kayıtlar yükleniyor"), style: .metaQuiet)
            }
        } else if visible.isEmpty {
            NovaEmptyState(title: filter.isEmpty
                ? RDLocalization.string("localizable.nova.nonconformity.empty", table: .localizable,
                    fallback: "Henüz uygunsuzluk kaydı yok.")
                : RDLocalization.string("localizable.nova.nonconformity.empty.filtered", table: .localizable,
                    fallback: "Bu filtrelerle eşleşen kayıt yok."),
                message: filter.isEmpty
                    ? RDLocalization.string("localizable.nova.nonconformity.empty.detail", table: .localizable,
                        fallback: "Hızlıca uygunsuzluk ekleyebilir, düzeltme sürecini ve terminleri dijital ortamda takip edebilirsiniz.")
                    : RDLocalization.string("localizable.nova.nonconformity.empty.filtered.detail", table: .localizable,
                        fallback: "Arama veya filtreleri değiştirerek diğer uygunsuzluk kayıtlarını görüntüleyebilirsiniz."))
        } else {
            ForEach(visible) { entry in card(entry) }
        }
    }

    // MARK: card

    /// Compact by design: a picture, the title, and the rest as icons rather
    /// than sentences.
    private func card(_ entry: NovaNonconformityEntry) -> some View {
        Button { client.open(entry) } label: {
            NovaCard(padding: 10) {
                HStack(alignment: .top, spacing: 10) {
                    picture(entry)
                    VStack(alignment: .leading, spacing: 5) {
                        NovaText(text: entry.row.title, style: .cardTitle).lineLimit(2)
                        HStack(spacing: 5) {
                            NovaStatusPill(label: NovaNonconformityWords.band(entry.row.severity),
                                status: NovaNonconformityWords.tone(entry.row.severity))
                            NovaStatusPill(label: NovaNonconformityWords.state(entry.row.state), status: .neutral, showsDot: false)
                            if entry.row.kind == .improvement {
                                NovaIcon(symbol: "lightbulb", size: 13)
                                    .foregroundStyle(NovaColorToken.statusInfoInk.color(in: scheme))
                                    .accessibilityLabel(Text(verbatim: NovaNonconformityWords.recordKind(.improvement)))
                            }
                        }
                        HStack(spacing: 9) {
                            fact("building.2", entry.companyName)
                        }
                        HStack(spacing: 9) {
                            fact("calendar", entry.row.opened_on)
                            if let due = entry.row.due_on {
                                fact("clock", due, tone: entry.isOverdue(today: today)
                                    ? NovaColorToken.statusDangerInk.color(in: scheme) : nil)
                            }
                            fact(entry.row.sourceSymbol, entry.row.sourceTitle)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 12))
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)).padding(.top, 3)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier("nonconformity.row.\(entry.id.uuidString.lowercased())")
    }

    private func fact(_ symbol: String, _ text: String, tone: Color? = nil) -> some View {
        HStack(spacing: 4) {
            NovaIcon(symbol: symbol, size: 11)
                .foregroundStyle(tone ?? NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: text, style: .micro, color: tone ?? NovaColorToken.textSecondary.color(in: scheme))
                .lineLimit(1)
        }
    }

    @ViewBuilder private func picture(_ entry: NovaNonconformityEntry) -> some View {
        Group {
            if let image = pictures[entry.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                NovaColorToken.surfaceMuted.color(in: scheme)
                    .overlay(NovaIcon(symbol: entry.row.camefromFinding ? "photo" : entry.row.sourceSymbol, size: 16)
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)))
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .accessibilityHidden(true)
        .task(id: entry.id) {
            guard pictures[entry.id] == nil else { return }
            if let image = await client.thumbnail(entry) { pictures[entry.id] = image }
        }
    }

    private func load() async {
        error = nil
        do { entries = try await client.load() }
        catch is CancellationError { }
        catch let failure as NovaNonconformityFailure {
            entries = nil
            error = NovaNonconformityWords.failure(failure)
        } catch {
            entries = nil
            self.error = RDLocalization.string("localizable.nova.nonconformity.error.list", table: .localizable,
                fallback: "Uygunsuzluklar yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
}
