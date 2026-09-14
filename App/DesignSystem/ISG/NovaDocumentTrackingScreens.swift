import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// tracker these closures.
struct NovaDocumentTrackingClient {
    /// The whole account in one answer: the tally, the per-company summary and
    /// one page of rows.
    let portfolio: (NovaDocumentQuery) async throws -> NovaDocumentPortfolio
    /// The companies a new obligation can be opened on.
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    let kinds: (UUID) async throws -> [NovaDocumentKind]
    let workplaces: (UUID) async throws -> [NovaDocumentWorkplace]
    let add: (UUID, NovaDocumentDraft) async throws -> NovaDocumentObligation
    let update: (NovaDocumentObligation, NovaDocumentDraft) async throws -> NovaDocumentObligation
    let archive: (NovaDocumentObligation) async throws -> Void
    let recordCopy: (NovaDocumentObligation, NovaDocumentCopyDraft) async throws -> NovaDocumentObligation
    let removeCopy: (NovaDocumentObligation, NovaDocumentCopy) async throws -> NovaDocumentObligation
}

/// A day, typed as a calendar rather than as free text, and carried as the same
/// ISO string the server stores.
struct NovaDayField: View {
    let label: String
    @Binding var value: String
    var identifier: String
    var isClearable = false
    @Environment(\.colorScheme) private var scheme

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    static func text(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ text: String) -> Date? { formatter.date(from: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                Spacer(minLength: 0)
                if isClearable && !value.isEmpty {
                    Button { value = "" } label: {
                        NovaText(text: RDLocalization.string("localizable.nova.document.date.clear", table: .localizable, fallback: "Temizle"),
                            style: .micro, color: NovaColorToken.accentInk.color(in: scheme))
                    }.buttonStyle(.plain).accessibilityIdentifier("\(identifier).clear")
                }
            }
            // An optional day that has not been set shows as unset. A picker
            // defaulted to today would read as a date the expert chose.
            if isClearable && value.isEmpty {
                Button { value = Self.text(Date()) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
                        NovaText(text: RDLocalization.string("localizable.nova.document.date.unset", table: .localizable, fallback: "Belirtilmedi"),
                            style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    .padding(.horizontal, 11).frame(minHeight: 36)
                    .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                }.buttonStyle(.plain).accessibilityIdentifier("\(identifier).set")
            } else {
                DatePicker("", selection: Binding(
                    get: { Self.date(value) ?? Date() },
                    set: { value = Self.text($0) }), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact)
                    .accessibilityIdentifier(identifier)
                    .accessibilityLabel(Text(verbatim: label))
            }
        }
    }
}

/// Every document the expert tracks, across every company: what is missing,
/// what ran out and what is about to. The list is a tally of tracked documents;
/// it is never a verdict about a company or about any person.
struct NovaDocumentTrackingScreen: View {
    let client: NovaDocumentTrackingClient
    let onBack: () -> Void
    var canWrite = true
    /// Opens straight onto one company's own documents, from the company page.
    var initialCompany: UUID?
    /// Opens onto one heading of the company page, such as periodic checks.
    var initialKinds: [String]?
    var headingOverride: String?
    @Environment(\.colorScheme) private var scheme
    @State private var board: NovaDocumentPortfolio?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var error: String?
    @State private var query = ""
    @State private var status: NovaDocumentStatus?
    @State private var company: UUID?
    @State private var shown = NovaDocumentQuery().limit
    @State private var inspecting: NovaDocumentObligation?
    @State private var adding = false
    @State private var loading = false
    @State private var reload = UUID()
    @State private var started = false

    private var selectedCompany: NovaDocumentCompanySummary? {
        board?.companies.first { $0.id == company }
    }
    private var request: NovaDocumentQuery {
        .init(query: query, status: status, company: company, kinds: initialKinds, limit: shown, offset: 0)
    }

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    overview
                    if let selectedCompany { companyCard(selectedCompany) }
                    hint
                    search
                    chips
                    list
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) { await refresh() }
        // Filters re-read the page rather than trimming what is already here,
        // so the row count on screen is always the server's own answer.
        .onChange(of: status) { _ in shown = NovaDocumentQuery().limit; reload = UUID() }
        .onChange(of: company) { _ in shown = NovaDocumentQuery().limit; reload = UUID() }
        .fullScreenCover(item: $inspecting) { row in
            NovaPopup {
                NovaDocumentObligationSheet(obligation: row, client: client, canWrite: canWrite,
                    onChanged: { reload = UUID() }, onClosed: { inspecting = nil })
            }
        }
        .fullScreenCover(isPresented: $adding) {
            NovaPopup {
                NovaDocumentAddSheet(companies: companies, preselected: company ?? initialCompany,
                    allowedKinds: initialKinds, client: client) {
                        adding = false
                        reload = UUID()
                    }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            NovaBackButton { onBack() }
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: headingOverride ?? NovaDestination.documentChecklist.title, style: .screenTitle)
                if let board {
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.document.subtitle", table: .localizable,
                        fallback: "%1$d firma · %2$d kayıt"), board.companies.count, board.tracked), style: .metaQuiet)
                }
            }
            Spacer(minLength: 0)
            if canWrite {
                Button { adding = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.new.short", table: .localizable, fallback: "Yeni"),
                            style: .buttonSm, color: NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    }
                    .foregroundStyle(NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(NovaColorToken.accent.color(in: scheme), in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("document.tracking.new")
            }
        }
    }

    /// The account's own standing, counted by the server over everything it
    /// tracks — not over the page that happens to be on screen.
    private var overview: some View {
        let value = board ?? .init()
        return NovaAnalysisOverviewCard(symbol: "doc.text",
            title: RDLocalization.string("localizable.nova.document.overview.title", table: .localizable, fallback: "Evrak takibi"),
            detail: RDLocalization.string("localizable.nova.document.overview.detail.portfolio", table: .localizable,
                fallback: "Tüm firmalarınızda eksik, süresi dolmuş ve yaklaşan evrakları tek yerden görün."),
            headline: "\(value.needsAttention)",
            headlineCaption: RDLocalization.string("localizable.nova.document.overview.attention", table: .localizable, fallback: "ilgi bekliyor"),
            figures: [
                .init(symbol: "questionmark.circle", value: "\(value.count(.missing))",
                      label: NovaDocumentWords.status(.missing)),
                .init(symbol: "exclamationmark.circle", value: "\(value.count(.expired))",
                      label: NovaDocumentWords.status(.expired)),
                .init(symbol: "clock", value: "\(value.count(.dueSoon))",
                      label: NovaDocumentWords.status(.dueSoon))
            ])
    }

    /// When one company is picked, its own standing sits under the headline so
    /// the expert sees that company's detail without leaving the page.
    private func companyCard(_ entry: NovaDocumentCompanySummary) -> some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    NovaIcon(symbol: "building.2", size: 15)
                        .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    NovaText(text: entry.name, style: .cardTitle)
                    Spacer(minLength: 0)
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.document.company.total", table: .localizable,
                        fallback: "%d kayıt"), entry.total), style: .micro,
                        color: NovaColorToken.textTertiary.color(in: scheme))
                }
                HStack(spacing: 6) {
                    ForEach(NovaDocumentStatus.allCases) { state in
                        let palette = NovaDocumentWords.tone(state).tokens
                        VStack(spacing: 2) {
                            NovaText(text: "\(entry.count(state))", style: .cardTitle,
                                color: palette.ink.color(in: scheme))
                            NovaText(text: NovaDocumentWords.status(state), style: .micro,
                                color: NovaColorToken.textTertiary.color(in: scheme)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(palette.background.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Two things the screen has to say out loud rather than let a reader assume.
    private var hint: some View {
        NovaHelpHint(text: RDLocalization.string("localizable.nova.document.hint", table: .localizable,
            fallback: "Bu liste takip ettiğiniz evrakların sayımıdır; firmanın veya bir kişinin uygunluğuna dair karar değildir. Sağlık evrakı bu listede tutulmaz ve dosyanın kendisi burada saklanmaz."))
    }

    private var search: some View {
        HStack(spacing: 8) {
            NovaAnalysisSearchField(text: $query,
                placeholder: RDLocalization.string("localizable.nova.document.search", table: .localizable, fallback: "Evrak ara"),
                identifier: "document.tracking.search")
                .onSubmit { shown = NovaDocumentQuery().limit; reload = UUID() }
            companyMenu
        }
    }

    private var companyMenu: some View {
        Menu {
            Button(RDLocalization.string("localizable.nova.document.company.all", table: .localizable, fallback: "Tüm firmalar")) { company = nil }
            ForEach(board?.companies ?? []) { entry in
                Button("\(entry.name) · \(entry.total)") { company = entry.id }
            }
        } label: {
            Image(systemName: company == nil ? "building.2" : "building.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(company == nil ? NovaColorToken.text.color(in: scheme) : NovaColorToken.accentInk.color(in: scheme))
                .frame(width: 44, height: 44)
                .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
        }
        .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.nonconformity.filter.company", table: .localizable, fallback: "Firma")))
        .accessibilityIdentifier("document.tracking.company")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                NovaAnalysisFilterChip(title: RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"),
                    isOn: status == nil, identifier: "document.tracking.filter.all") { status = nil }
                ForEach(NovaDocumentStatus.allCases) { value in
                    NovaAnalysisFilterChip(title: "\(NovaDocumentWords.status(value)) \(board?.count(value) ?? 0)",
                        isOn: status == value,
                        identifier: "document.tracking.filter.\(value.rawValue)") { status = value }
                }
            }
        }
    }

    @ViewBuilder private var list: some View {
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if board == nil {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.document.loading", table: .localizable,
                    fallback: "Evrak takibi yükleniyor…"), style: .metaQuiet)
            }
        } else if board?.rows.isEmpty ?? true {
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: (board?.tracked ?? 0) == 0
                        ? RDLocalization.string("localizable.nova.document.empty", table: .localizable,
                            fallback: "Bu firmada takibe alınmış evrak yok. Takip etmek istediğiniz evrakı ekleyin.")
                        : RDLocalization.string("localizable.nova.document.empty.filtered", table: .localizable,
                            fallback: "Bu filtreye uyan kayıt yok."), style: .metaQuiet)
                    if canWrite && (board?.tracked ?? 0) == 0 {
                        NovaButton(label: RDLocalization.string("localizable.nova.document.add.title", table: .localizable, fallback: "Takibe evrak ekle"),
                            symbol: "plus") { adding = true }
                            .accessibilityIdentifier("document.tracking.empty.add")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let board {
            ForEach(board.rows) { row in card(row) }
            footer(board)
        }
    }

    /// The page shows ten at a time and says how many are still behind it.
    @ViewBuilder private func footer(_ board: NovaDocumentPortfolio) -> some View {
        HStack(spacing: 8) {
            NovaText(text: String(format: RDLocalization.string("localizable.nova.document.page", table: .localizable,
                fallback: "%1$d / %2$d kayıt"), board.rows.count, board.total), style: .micro,
                color: NovaColorToken.textTertiary.color(in: scheme))
            Spacer(minLength: 0)
            if board.hasMore {
                Button {
                    shown += NovaDocumentQuery().limit
                    reload = UUID()
                } label: {
                    HStack(spacing: 5) {
                        if loading { NovaText(text: "…", style: .meta, color: NovaColorToken.accentInk.color(in: scheme)) }
                        else { Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)) }
                        NovaText(text: RDLocalization.string("localizable.nova.document.more", table: .localizable, fallback: "Daha fazla göster"),
                            style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                    }.foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 40)
                }.buttonStyle(.plain).disabled(loading)
                    .accessibilityIdentifier("document.tracking.more")
            }
        }
    }

    private func card(_ row: NovaDocumentObligation) -> some View {
        Button { inspecting = row } label: {
            NovaCard(padding: 11) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 9) {
                        NovaIcon(symbol: NovaDocumentWords.kindSymbol(row.kindCode), size: 16)
                            .foregroundStyle(NovaDocumentWords.tone(row.status).tokens.ink.color(in: scheme))
                            .frame(width: 38, height: 38)
                            .background(NovaDocumentWords.tone(row.status).tokens.background.color(in: scheme),
                                        in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: row.title, style: .cardTitle).lineLimit(2)
                            // The kind is only worth a second line when the
                            // expert renamed the entry away from it.
                            if NovaDocumentWords.kind(row.kindCode) != row.title {
                                NovaText(text: NovaDocumentWords.kind(row.kindCode), style: .micro,
                                    color: NovaColorToken.textTertiary.color(in: scheme))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        NovaStatusPill(label: NovaDocumentWords.status(row.status),
                            status: NovaDocumentWords.tone(row.status), showsDot: false)
                    }
                    HStack(spacing: 5) {
                        if let name = row.companyName, company == nil {
                            NovaAnalysisTag(symbol: "building.2", text: name, status: .neutral)
                        }
                        NovaAnalysisTag(symbol: row.basis == .legal ? "book" : "person",
                            text: NovaDocumentWords.basis(row.basis), status: .neutral)
                        if let until = row.latestValidUntil {
                            NovaAnalysisTag(symbol: "calendar", text: until,
                                status: NovaDocumentWords.tone(row.status))
                        }
                        Spacer(minLength: 0)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("document.tracking.row.\(row.id.uuidString.lowercased())")
    }

    private func refresh() async {
        error = nil
        loading = true
        defer { loading = false }
        if !started {
            started = true
            company = initialCompany
            companies = (try? await client.companies()) ?? []
        }
        do { board = try await client.portfolio(request) }
        catch is CancellationError { }
        catch let failure as NovaDocumentFailure {
            board = .init()
            error = NovaDocumentWords.failure(failure)
        }
        catch {
            board = .init()
            self.error = RDLocalization.string("localizable.nova.document.failed", table: .localizable,
                fallback: "Evrak takibi alınamadı. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
}

/// One company-page heading's document standing: four counters and the way in.
/// The counts are the tracker's own, so the heading and the tracker can never
/// disagree about what is on file.
struct NovaDocumentSectionStrip: View {
    let counts: [NovaDocumentStatus: Int]
    var isLoading = false
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var total: Int { NovaDocumentStatus.allCases.reduce(0) { $0 + (counts[$1] ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                NovaText(text: RDLocalization.string("localizable.nova.document.loading", table: .localizable,
                    fallback: "Evrak takibi yükleniyor…"), style: .metaQuiet)
            } else if total == 0 {
                NovaText(text: RDLocalization.string("localizable.nova.document.section.empty", table: .localizable,
                    fallback: "Bu başlık için takibe alınmış evrak yok."), style: .metaQuiet)
            } else {
                HStack(spacing: 6) {
                    ForEach(NovaDocumentStatus.allCases) { state in
                        let palette = NovaDocumentWords.tone(state).tokens
                        VStack(spacing: 2) {
                            NovaText(text: "\(counts[state] ?? 0)", style: .cardTitle,
                                color: palette.ink.color(in: scheme))
                            NovaText(text: NovaDocumentWords.status(state), style: .micro,
                                color: NovaColorToken.textTertiary.color(in: scheme)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(palette.background.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            NovaButton(label: RDLocalization.string("localizable.nova.document.section.open", table: .localizable, fallback: "Evrak takibini aç"),
                symbol: "doc.text", variant: .surface, action: onOpen)
                .accessibilityIdentifier("company.section.documents.open")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
