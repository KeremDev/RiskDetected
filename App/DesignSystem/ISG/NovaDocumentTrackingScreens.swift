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

/// One counter, in the same shape the home page uses for its summary: a toned
/// icon beside the number, the name under it and a short factual footer.
struct NovaDocumentStatCard: View {
    let status: NovaDocumentStatus
    let value: Int
    var isSelected = false
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// What the count means, stated as a fact rather than as an instruction.
    private var footer: String {
        switch status {
        case .missing: return RDLocalization.string("localizable.nova.document.stat.missing", table: .localizable, fallback: "kopya yok")
        case .dueSoon: return RDLocalization.string("localizable.nova.document.stat.due.soon", table: .localizable, fallback: "bitişe yakın")
        case .expired: return RDLocalization.string("localizable.nova.document.stat.expired", table: .localizable, fallback: "bitiş geçti")
        case .valid: return RDLocalization.string("localizable.nova.document.stat.valid", table: .localizable, fallback: "dosyada")
        }
    }

    var body: some View {
        let tone = NovaDocumentWords.tone(status).tokens.ink
        return Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: NovaDocumentWords.symbol(status)).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tone.color(in: scheme))
                    NovaSizedText(text: "\(value)", size: 19, weight: "ExtraBold")
                }
                NovaSizedText(text: NovaDocumentWords.status(status), size: 10, weight: "Medium",
                    color: NovaColorToken.textMuted.color(in: scheme))
                    .lineLimit(2).frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
                NovaSizedText(text: footer, size: 9.5, weight: "Bold",
                    color: value > 0 ? tone.color(in: scheme) : NovaColorToken.textMuted.color(in: scheme))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10).padding(.vertical, 11)
            .frame(width: typeSize.isAccessibilitySize ? 160 : 86,
                   height: typeSize.isAccessibilitySize ? nil : 86, alignment: .topLeading)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isSelected ? tone.color(in: scheme) : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("document.stat.\(status.rawValue)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The tracker. A company is chosen first, because an obligation belongs to
/// one; its own standing and its own documents open underneath. The list is a
/// tally of tracked documents; it is never a verdict about a company or about
/// any person.
struct NovaDocumentTrackingScreen: View {
    let client: NovaDocumentTrackingClient
    let onBack: () -> Void
    var canWrite = true
    /// Opened from a company page: that company is already the answer.
    var initialCompany: UUID?
    /// Opens onto one heading of the company page, such as periodic checks.
    var initialKinds: [String]?
    var headingOverride: String?
    @Environment(\.colorScheme) private var scheme
    @State private var board: NovaDocumentPortfolio?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var error: String?
    @State private var companyQuery = ""
    @State private var query = ""
    @State private var status: NovaDocumentStatus?
    @State private var company: UUID?
    @State private var shown = NovaDocumentQuery().limit
    @State private var inspecting: NovaDocumentObligation?
    @State private var adding = false
    @State private var loading = false
    @State private var reload = UUID()
    @State private var started = false
    @FocusState private var searchingCompany: Bool

    /// The company page hands one in; there it is never changed on this screen.
    private var isCompanyLocked: Bool { initialCompany != nil }
    private var selectedCompany: NovaDocumentCompanySummary? {
        board?.companies.first { $0.id == company }
    }
    private var selectedName: String? {
        selectedCompany?.name ?? companies.first { $0.id == company }?.name
    }
    /// The counters follow what the page is actually showing: one heading when
    /// the company page named one, otherwise the chosen company, otherwise the
    /// whole account. The server's headline covers the account, so narrowing is
    /// read from the per-company and per-kind tallies it sends alongside it.
    private var visibleCounts: [NovaDocumentStatus: Int] {
        guard let board else { return [:] }
        if let initialKinds { return board.counts(forKinds: initialKinds) }
        if let selectedCompany { return selectedCompany.counts }
        return board.counts
    }
    private func count(_ state: NovaDocumentStatus) -> Int { visibleCounts[state] ?? 0 }
    private var trackedHere: Int { NovaDocumentStatus.allCases.reduce(0) { $0 + count($1) } }

    private var request: NovaDocumentQuery {
        .init(query: query, status: status, company: company, kinds: initialKinds, limit: shown, offset: 0)
    }
    /// What the picker is offering right now. An empty box lists everything, so
    /// the expert can pick without typing.
    private var offered: [NovaAnalysisCompanyOption] {
        let needle = companyQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return companies }
        return companies.filter { $0.name.lowercased().contains(needle) || $0.detail.lowercased().contains(needle) }
    }

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    if company == nil { picker } else { tracker }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) { await refresh() }
        // Filters re-read the page rather than trimming what is already here,
        // so the row count on screen is always the server's own answer.
        .onChange(of: status) { _ in shown = NovaDocumentQuery().limit; reload = UUID() }
        .onChange(of: company) { _ in
            shown = NovaDocumentQuery().limit
            status = nil
            query = ""
            reload = UUID()
        }
        .fullScreenCover(item: $inspecting) { row in
            NovaPopup {
                NovaDocumentObligationSheet(obligation: row, client: client, canWrite: canWrite,
                    onChanged: { reload = UUID() }, onClosed: { inspecting = nil })
            }
        }
        .fullScreenCover(isPresented: $adding) {
            NovaPopup {
                NovaDocumentAddSheet(companies: companies, preselected: company,
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
                if let selectedName { NovaText(text: selectedName, style: .metaQuiet) }
            }
            Spacer(minLength: 0)
            // Adding needs a company, so the control appears once there is one.
            if canWrite && company != nil {
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

    // MARK: choosing a company

    @ViewBuilder private var picker: some View {
        companyField
        NovaHelpHint(text: RDLocalization.string("localizable.nova.document.pick.company", table: .localizable,
            fallback: "İlk önce firma seçimi yapın. Seçtiğiniz firmanın evrak kontrolü hemen aşağıda açılır."))
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if companies.isEmpty {
            NovaCard(padding: 16) {
                NovaText(text: loading
                    ? RDLocalization.string("localizable.nova.document.loading", table: .localizable, fallback: "Evrak takibi yükleniyor…")
                    : RDLocalization.string("localizable.nova.document.company.empty", table: .localizable,
                        fallback: "Evrak takibi için önce bir firma ekleyin."), style: .metaQuiet)
            }
        } else if offered.isEmpty {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.document.company.nomatch", table: .localizable,
                    fallback: "Bu aramaya uyan firma yok."), style: .metaQuiet)
            }
        } else {
            ForEach(offered) { option in companyRow(option) }
        }
    }

    private var companyField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            TextField(RDLocalization.string("localizable.nova.document.company.search", table: .localizable, fallback: "Firma ara veya listeden seçin"),
                text: $companyQuery)
                .font(.custom("PlusJakartaSans-Medium", size: 13.5))
                .textInputAutocapitalization(.never)
                .focused($searchingCompany)
                .accessibilityIdentifier("document.company.search")
            if !companyQuery.isEmpty {
                Button { companyQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                }.buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.analysis.search.clear", table: .localizable, fallback: "Aramayı temizle")))
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 46)
        .background(NovaColorToken.surface.color(in: scheme), in: Capsule())
        .overlay(Capsule().strokeBorder(searchingCompany ? NovaColorToken.accentInk.color(in: scheme)
                                                         : NovaColorToken.border.color(in: scheme),
                                        lineWidth: searchingCompany ? 1.4 : 1))
    }

    /// Each company carries what it is actually holding, so the choice is made
    /// with the counts in view rather than blind.
    private func companyRow(_ option: NovaAnalysisCompanyOption) -> some View {
        let summary = board?.companies.first { $0.id == option.id }
        return Button { company = option.id; searchingCompany = false } label: {
            NovaCard(padding: 11) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 9) {
                        NovaIcon(symbol: "building.2", size: 15)
                            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                            .frame(width: 36, height: 36)
                            .background(NovaColorToken.statusSuccessBg.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: option.name, style: .cardTitle).lineLimit(1)
                            if !option.detail.isEmpty { NovaText(text: option.detail, style: .micro,
                                color: NovaColorToken.textTertiary.color(in: scheme)).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                    }
                    if let summary, summary.total > 0 {
                        HStack(spacing: 5) {
                            ForEach(NovaDocumentStatus.allCases) { state in
                                if summary.count(state) > 0 {
                                    NovaAnalysisTag(symbol: NovaDocumentWords.symbol(state),
                                        text: "\(NovaDocumentWords.status(state)) \(summary.count(state))",
                                        status: NovaDocumentWords.tone(state))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    } else if summary == nil && board != nil {
                        NovaAnalysisTag(symbol: "questionmark.circle",
                            text: RDLocalization.string("localizable.nova.document.company.untracked", table: .localizable, fallback: "Takip başlamadı"),
                            status: .neutral)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("document.company.\(option.id.uuidString.lowercased())")
    }

    // MARK: the chosen company's documents

    @ViewBuilder private var tracker: some View {
        if !isCompanyLocked { chosenCompany }
        stats
        hint
        search
        chips
        list
    }

    private var chosenCompany: some View {
        HStack(spacing: 9) {
            NovaIcon(symbol: "building.2", size: 14)
                .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
            NovaText(text: selectedName ?? "", style: .cardTitle).lineLimit(1)
            Spacer(minLength: 0)
            Button { company = nil; companyQuery = "" } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .bold))
                    NovaText(text: RDLocalization.string("localizable.nova.document.company.change", table: .localizable, fallback: "Firma değiştir"),
                        style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                }.foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 36)
            }.buttonStyle(.plain).accessibilityIdentifier("document.company.change")
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
    }

    /// Four counters for the chosen company, in the home page's own card shape.
    /// Tapping one is the same filter the chips below carry.
    private var stats: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(NovaDocumentStatus.allCases) { state in
                    NovaDocumentStatCard(status: state, value: count(state),
                        isSelected: status == state) { status = status == state ? nil : state }
                }
            }.padding(.vertical, 2)
        }
    }

    /// Two things the screen has to say out loud rather than let a reader assume.
    private var hint: some View {
        NovaHelpHint(text: RDLocalization.string("localizable.nova.document.hint", table: .localizable,
            fallback: "Bu liste takip ettiğiniz evrakların sayımıdır; firmanın veya bir kişinin uygunluğuna dair karar değildir. Sağlık evrakı bu listede tutulmaz ve dosyanın kendisi burada saklanmaz."))
    }

    private var search: some View {
        NovaAnalysisSearchField(text: $query,
            placeholder: RDLocalization.string("localizable.nova.document.search", table: .localizable, fallback: "Evrak ara"),
            identifier: "document.tracking.search")
            .onSubmit { shown = NovaDocumentQuery().limit; reload = UUID() }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                NovaAnalysisFilterChip(title: RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"),
                    isOn: status == nil, identifier: "document.tracking.filter.all") { status = nil }
                ForEach(NovaDocumentStatus.allCases) { value in
                    NovaAnalysisFilterChip(title: "\(NovaDocumentWords.status(value)) \(count(value))",
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
                    NovaText(text: trackedHere == 0
                        ? RDLocalization.string("localizable.nova.document.empty", table: .localizable,
                            fallback: "Bu firmada takibe alınmış evrak yok. Takip etmek istediğiniz evrakı ekleyin.")
                        : RDLocalization.string("localizable.nova.document.empty.filtered", table: .localizable,
                            fallback: "Bu filtreye uyan kayıt yok."), style: .metaQuiet)
                    if canWrite && trackedHere == 0 {
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
                        NovaAnalysisTag(symbol: row.basis == .legal ? "book" : "person",
                            text: NovaDocumentWords.basis(row.basis), status: .neutral)
                        if let name = row.workplaceName {
                            NovaAnalysisTag(symbol: "building.2", text: name, status: .neutral)
                        }
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
