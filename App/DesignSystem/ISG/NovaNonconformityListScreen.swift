import SwiftUI

/// Everything the nonconformity board needs, as closures. The design layer
/// never imports the SDK.
struct NovaNonconformityBoardClient {
    let load: () async throws -> [NovaNonconformityEntry]
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
    @State private var filter = NovaNonconformityFilter()
    @State private var error: String?
    @State private var reload = UUID()
    @FocusState private var searching: Bool

    private var visible: [NovaNonconformityEntry] {
        (entries ?? []).filter { $0.matches(filter, today: today) }
    }
    private var overdueCount: Int {
        (entries ?? []).filter { $0.isOverdue(today: today) }.count
    }

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    search
                    filters
                    summary
                    body_
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
        .background(NovaKeyboardDismissArea())
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
                }.buttonStyle(.plain).accessibilityIdentifier("nonconformity.new")
            }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14))
                .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)).accessibilityHidden(true)
            TextField(RDLocalization.string("localizable.nova.nonconformity.search", table: .localizable,
                fallback: "Başlık, firma veya işyeri ara"), text: $filter.query)
                .font(.custom("PlusJakartaSans-Medium", size: 14))
                .focused($searching).submitLabel(.done)
                .accessibilityIdentifier("nonconformity.search")
            if !filter.query.isEmpty {
                Button { filter.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 32, height: 32)
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                }.buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.nonconformity.search.clear", table: .localizable, fallback: "Aramayı temizle")))
            }
        }.padding(.horizontal, 14).frame(minHeight: 46)
            .background(NovaColorToken.surface.color(in: scheme), in: Capsule())
    }

    @ViewBuilder private var filters: some View {
        VStack(alignment: .leading, spacing: 7) {
            if companies.count > 1 {
                row(label: RDLocalization.string("localizable.nova.nonconformity.filter.company", table: .localizable, fallback: "Firma")) {
                    chip(RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"),
                         isOn: filter.companyID == nil, id: "company.all") { filter.companyID = nil }
                    ForEach(companies) { company in
                        chip(company.name, isOn: filter.companyID == company.id,
                             id: "company.\(company.id.uuidString.lowercased())") { filter.companyID = company.id }
                    }
                }
            }
            row(label: RDLocalization.string("localizable.nova.nonconformity.filter.state", table: .localizable, fallback: "Durum")) {
                chip(RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"),
                     isOn: filter.state == nil && !filter.overdueOnly, id: "state.all") {
                    filter.state = nil; filter.overdueOnly = false
                }
                ForEach([NovaNonconformityState.draft, .open, .assigned, .in_progress, .pending_verification, .closed], id: \.rawValue) { value in
                    chip(NovaNonconformityWords.state(value.rawValue), isOn: filter.state == value,
                         id: "state.\(value.rawValue)") { filter.state = value; filter.overdueOnly = false }
                }
                chip(String(format: RDLocalization.string("localizable.nova.nonconformity.filter.overdue", table: .localizable,
                    fallback: "Termini geçen · %d"), overdueCount), isOn: filter.overdueOnly, id: "state.overdue") {
                    filter.overdueOnly.toggle(); filter.state = nil
                }
            }
            row(label: RDLocalization.string("localizable.nova.analysis.file.kind", table: .localizable, fallback: "Kayıt türü")) {
                chip(RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"),
                     isOn: filter.kind == nil, id: "kind.all") { filter.kind = nil }
                ForEach(NovaNonconformityRecordKind.allCases) { value in
                    chip(NovaNonconformityWords.recordKind(value), isOn: filter.kind == value,
                         id: "kind.\(value.rawValue)") { filter.kind = value }
                }
            }
        }
    }

    private func row<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { content() }.padding(.vertical, 1)
            }
        }
    }

    private func chip(_ title: String, isOn: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaText(text: title, style: .meta,
                color: isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                .lineLimit(1)
                .padding(.horizontal, 12).frame(minHeight: 38)
                .background(isOn ? NovaColorToken.statusSuccessBg.color(in: scheme) : NovaColorToken.surface.color(in: scheme),
                    in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("nonconformity.filter.\(id)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
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
                            style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                            .frame(minHeight: 32)
                    }.buttonStyle(.plain).accessibilityIdentifier("nonconformity.filter.reset")
                }
                Button { reload = UUID() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 40, height: 40)
                }.buttonStyle(.plain)
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
            NovaCard(padding: 16) {
                NovaText(text: filter.isEmpty
                    ? RDLocalization.string("localizable.nova.nonconformity.empty", table: .localizable, fallback: "Henüz uygunsuzluk kaydı yok.")
                    : RDLocalization.string("localizable.nova.nonconformity.empty.filtered", table: .localizable,
                        fallback: "Bu filtrelerle eşleşen kayıt yok."), style: .metaQuiet)
            }
        } else {
            ForEach(visible) { entry in card(entry) }
        }
    }

    private func card(_ entry: NovaNonconformityEntry) -> some View {
        Button { client.open(entry) } label: {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 8) {
                        NovaText(text: entry.row.title, style: .cardTitle)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12))
                            .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                    }
                    HStack(spacing: 6) {
                        NovaStatusPill(label: NovaNonconformityWords.band(entry.row.severity),
                            status: NovaNonconformityWords.tone(entry.row.severity))
                        NovaStatusPill(label: NovaNonconformityWords.state(entry.row.state), status: .neutral, showsDot: false)
                        if entry.row.kind == .improvement {
                            NovaStatusPill(label: NovaNonconformityWords.recordKind(.improvement), status: .info, showsDot: false)
                        }
                    }
                    HStack(spacing: 6) {
                        NovaIcon(symbol: "building.2", size: 13)
                            .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                        NovaText(text: [entry.companyName, entry.workplaceName].compactMap { $0 }.joined(separator: " · "),
                            style: .metaQuiet)
                    }
                    HStack(spacing: 6) {
                        NovaText(text: String(format: RDLocalization.string("localizable.nova.nonconformity.opened.on", table: .localizable,
                            fallback: "Açılış %@"), entry.row.opened_on), style: .metaQuiet)
                        if let due = entry.row.due_on {
                            NovaText(text: "·", style: .metaQuiet)
                            NovaText(text: String(format: RDLocalization.string("localizable.nova.nonconformity.due.on", table: .localizable,
                                fallback: "Termin %@"), due), style: .metaQuiet,
                                color: entry.isOverdue(today: today) ? NovaColorToken.statusDangerInk.color(in: scheme) : nil)
                        }
                    }
                    if entry.isOverdue(today: today) {
                        NovaStatusPill(label: RDLocalization.string("localizable.nova.nonconformity.overdue", table: .localizable, fallback: "Termini geçti"), status: .danger)
                    }
                    if entry.row.camefromFinding {
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.from.analysis", table: .localizable,
                            fallback: "Fotoğraf analizinden geldi"), style: .metaQuiet)
                    } else if entry.row.camefromExpertItem {
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.from.expert", table: .localizable,
                            fallback: "Uzman görüşü maddesinden geldi"), style: .metaQuiet)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("nonconformity.row.\(entry.id.uuidString.lowercased())")
    }

    private func load() async {
        error = nil
        do { entries = try await client.load() }
        catch is CancellationError { }
        catch let failure as NovaNonconformityFailure {
            entries = []
            error = NovaNonconformityWords.failure(failure)
        } catch {
            entries = []
            self.error = RDLocalization.string("localizable.nova.nonconformity.error.list", table: .localizable,
                fallback: "Uygunsuzluklar yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
}
