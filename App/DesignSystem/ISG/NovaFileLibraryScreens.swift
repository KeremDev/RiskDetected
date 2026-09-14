import SwiftUI
import UniformTypeIdentifiers

/// The design system never imports the SDK; the composition root hands the
/// archive these closures.
struct NovaFileLibraryClient {
    /// What the server will accept and what the categories mean.
    let catalogue: () async throws -> (categories: [NovaFileCategory],
                                       accepts: [NovaFileAcceptance],
                                       assurance: NovaFileAssurance)
    /// The whole account in one answer: the tally, the per-company summary, the
    /// per-category tally and one page of rows.
    let library: (NovaFileQuery) async throws -> NovaFileLibrary
    /// The companies a file can be filed under.
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    /// Opens the upload, puts the bytes and asks the worker to inspect them.
    let file: (UUID, NovaFileDraft, Data) async throws -> NovaFileEntry
    let rename: (NovaFileEntry, String, String, String) async throws -> NovaFileEntry
    let archive: (NovaFileEntry) async throws -> Void
    let cancel: (NovaFileEntry) async throws -> Void
    let recheck: (NovaFileEntry) async throws -> NovaFileEntry
    let contents: (NovaFileEntry) async throws -> Data
}

/// One counter, in the same shape the home page uses for its summary: a toned
/// icon beside the number, the name under it and a short factual footer.
struct NovaFileStatCard: View {
    let group: NovaFileGroup
    let value: Int
    var isSelected = false
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var tone: NovaColorToken {
        switch group {
        case .filed: return .statusSuccessInk
        case .working: return .statusInfoInk
        case .rejected: return .statusDangerInk
        case .unchecked: return .statusWarningInk
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: group.symbol).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tone.color(in: scheme))
                    NovaSizedText(text: "\(value)", size: 19, weight: "ExtraBold")
                }
                NovaSizedText(text: group.title, size: 10, weight: "Medium",
                    color: NovaColorToken.textMuted.color(in: scheme))
                    // "Denetlenemedi" is one word wider than the card, so it is
                    // scaled down rather than broken across two lines.
                    .lineLimit(2).minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
                NovaSizedText(text: group.footer, size: 9.5, weight: "Bold",
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
            .accessibilityIdentifier("file.stat.\(group.rawValue)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Diğer Dosyalar. A company is chosen first, because a filed document belongs
/// to one; its archive opens underneath. What the page shows about a file is
/// always what really happened to it: an upload that has not been cleared is
/// shown as an upload, never as a document on file.
struct NovaFileLibraryScreen: View {
    let client: NovaFileLibraryClient
    let onBack: () -> Void
    var canWrite = true
    /// Opened from a company page: that company is already the answer.
    var initialCompany: UUID?
    /// Opens onto one heading of the company page, such as periodic checks.
    var initialCategories: [String]?
    var headingOverride: String?
    @Environment(\.colorScheme) private var scheme
    @State private var board: NovaFileLibrary?
    @State private var catalogue: [NovaFileCategory] = []
    @State private var accepts: [NovaFileAcceptance] = []
    @State private var assurance = NovaFileAssurance()
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var error: String?
    @State private var companyQuery = ""
    @State private var query = ""
    @State private var group: NovaFileGroup?
    @State private var category: String?
    @State private var company: UUID?
    @State private var shown = NovaFileQuery().limit
    @State private var inspecting: NovaFileEntry?
    @State private var adding = false
    @State private var loading = false
    @State private var reload = UUID()
    @State private var started = false
    @FocusState private var searchingCompany: Bool

    private var isCompanyLocked: Bool { initialCompany != nil }
    private var selectedCompany: NovaFileCompanySummary? { board?.companies.first { $0.id == company } }
    private var selectedName: String? {
        selectedCompany?.name ?? companies.first { $0.id == company }?.name
    }
    /// The counters follow what the page is actually showing: one heading when
    /// the company page named one, otherwise the chosen company, otherwise the
    /// whole account. The server's headline covers the account, so narrowing is
    /// read from the per-company and per-category tallies it sends alongside it.
    private var visibleCounts: [NovaFileState: Int] {
        guard let board else { return [:] }
        if let initialCategories { return board.counts(forCategories: initialCategories) }
        if let selectedCompany { return selectedCompany.counts }
        return board.counts
    }
    private func count(_ group: NovaFileGroup) -> Int {
        group.states.reduce(0) { $0 + (visibleCounts[$1] ?? 0) }
    }
    private var filedHere: Int { NovaFileState.allCases.reduce(0) { $0 + (visibleCounts[$1] ?? 0) } }

    /// The categories the page may file under. A heading limits them to its own.
    private var offeredCategories: [NovaFileCategory] {
        guard let initialCategories else { return catalogue }
        return catalogue.filter { initialCategories.contains($0.code) }
    }
    private var request: NovaFileQuery {
        .init(query: query, state: group?.rawValue, company: company,
              category: category ?? (initialCategories?.count == 1 ? initialCategories?.first : nil),
              limit: shown, offset: 0)
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
                    if company == nil { picker } else { archive }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) { await refresh() }
        .onChange(of: group) { _ in shown = NovaFileQuery().limit; reload = UUID() }
        .onChange(of: category) { _ in shown = NovaFileQuery().limit; reload = UUID() }
        .onChange(of: company) { _ in
            shown = NovaFileQuery().limit
            group = nil
            category = nil
            query = ""
            reload = UUID()
        }
        .fullScreenCover(item: $inspecting) { row in
            NovaPopup {
                NovaFileEntrySheet(entry: row, catalogue: catalogue, assurance: assurance,
                    client: client, canWrite: canWrite,
                    onChanged: { reload = UUID() }, onClosed: { inspecting = nil })
            }
        }
        .fullScreenCover(isPresented: $adding) {
            NovaPopup {
                NovaFileAddSheet(companies: companies, preselected: company,
                    categories: offeredCategories, accepts: accepts, assurance: assurance,
                    client: client) {
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
                NovaText(text: headingOverride ?? NovaDestination.documents.title, style: .screenTitle)
                if let selectedName { NovaText(text: selectedName, style: .metaQuiet) }
            }
            Spacer(minLength: 0)
            // Filing needs a company, so the control appears once there is one.
            if canWrite && company != nil {
                Button { adding = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        NovaText(text: RDLocalization.string("localizable.nova.file.add.short", table: .localizable, fallback: "Dosya"),
                            style: .buttonSm, color: NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    }
                    .foregroundStyle(NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(NovaColorToken.accent.color(in: scheme), in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("file.library.new")
            }
        }
    }

    // MARK: choosing a company

    @ViewBuilder private var picker: some View {
        companyField
        NovaHelpHint(text: RDLocalization.string("localizable.nova.file.pick.company", table: .localizable,
            fallback: "İlk önce firma seçimi yapın. Seçtiğiniz firmanın dosya arşivi hemen aşağıda açılır."))
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if companies.isEmpty {
            NovaCard(padding: 16) {
                NovaText(text: loading
                    ? RDLocalization.string("localizable.nova.file.loading", table: .localizable, fallback: "Dosyalar yükleniyor…")
                    : RDLocalization.string("localizable.nova.file.company.empty", table: .localizable,
                        fallback: "Dosya arşivi için önce bir firma ekleyin."), style: .metaQuiet)
            }
        } else if offered.isEmpty {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.file.company.nomatch", table: .localizable,
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
            TextField(RDLocalization.string("localizable.nova.file.company.search", table: .localizable, fallback: "Firma ara veya listeden seçin"),
                text: $companyQuery)
                .font(.custom("PlusJakartaSans-Medium", size: 13.5))
                .textInputAutocapitalization(.never)
                .focused($searchingCompany)
                .accessibilityIdentifier("file.company.search")
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
                        NovaIcon(symbol: "folder", size: 15)
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
                        // Two tags, not four: what is on file and what is not.
                        // The four counters open with the company underneath.
                        let waiting = summary.total - summary.filed
                        HStack(spacing: 5) {
                            NovaAnalysisTag(symbol: "checkmark.circle",
                                text: "\(NovaFileGroup.filed.title) \(summary.filed)",
                                status: summary.filed > 0 ? .success : .neutral)
                            if waiting > 0 {
                                NovaAnalysisTag(symbol: "tray",
                                    text: "\(RDLocalization.string("localizable.nova.file.company.waiting", table: .localizable, fallback: "Arşive alınmadı")) \(waiting)",
                                    status: .warning)
                            }
                            Spacer(minLength: 0)
                        }
                    } else if summary == nil && board != nil {
                        NovaAnalysisTag(symbol: "questionmark.circle",
                            text: RDLocalization.string("localizable.nova.file.company.untracked", table: .localizable, fallback: "Dosya yok"),
                            status: .neutral)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("file.company.\(option.id.uuidString.lowercased())")
    }

    private func tone(_ group: NovaFileGroup) -> NovaStatus {
        switch group {
        case .filed: return .success
        case .working: return .info
        case .rejected: return .danger
        case .unchecked: return .warning
        }
    }

    // MARK: the chosen company's archive

    @ViewBuilder private var archive: some View {
        if !isCompanyLocked { chosenCompany }
        stats
        hint
        search
        chips
        if initialCategories == nil { categoryChips }
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
            }.buttonStyle(.plain).accessibilityIdentifier("file.company.change")
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
    }

    /// Four counters in the home page's own card shape. Tapping one is the same
    /// filter the chips below carry, and it narrows to exactly what it counted.
    private var stats: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(NovaFileGroup.allCases) { value in
                    NovaFileStatCard(group: value, value: count(value),
                        isSelected: group == value) { group = group == value ? nil : value }
                }
            }.padding(.vertical, 2)
        }
    }

    /// What the archive is and is not, said out loud rather than left to a reader.
    private var hint: some View {
        NovaHelpHint(text: assurance.malwareScanningAvailable
            ? RDLocalization.string("localizable.nova.file.hint.scanned", table: .localizable,
                fallback: "Dosyalar biçim denetiminden ve virüs taramasından geçtikten sonra arşive alınır.")
            : RDLocalization.string("localizable.nova.file.hint", table: .localizable,
                fallback: "Dosyalar biçim denetiminden geçtikten sonra arşive alınır; bu bir virüs taraması değildir."))
    }

    private var search: some View {
        NovaAnalysisSearchField(text: $query,
            placeholder: RDLocalization.string("localizable.nova.file.search", table: .localizable, fallback: "Dosya ara"),
            identifier: "file.library.search")
            .onSubmit { shown = NovaFileQuery().limit; reload = UUID() }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                NovaAnalysisFilterChip(title: RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"),
                    isOn: group == nil, identifier: "file.library.filter.all") { group = nil }
                ForEach(NovaFileGroup.allCases) { value in
                    NovaAnalysisFilterChip(title: "\(value.title) \(count(value))",
                        isOn: group == value,
                        identifier: "file.library.filter.\(value.rawValue)") { group = value }
                }
            }
        }
    }

    /// The headings a file can be filed under, with what each one holds.
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                NovaAnalysisFilterChip(title: RDLocalization.string("localizable.nova.file.category.all", table: .localizable, fallback: "Tüm başlıklar"),
                    isOn: category == nil, identifier: "file.library.category.all") { category = nil }
                ForEach(catalogue) { entry in
                    let held = (board?.categoryCounts[entry.code] ?? [:]).values.reduce(0, +)
                    if held > 0 || category == entry.code {
                        NovaAnalysisFilterChip(title: "\(NovaFileWords.category(entry.code)) \(held)",
                            isOn: category == entry.code,
                            identifier: "file.library.category.\(entry.code)") { category = entry.code }
                    }
                }
            }
        }
    }

    @ViewBuilder private var list: some View {
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if board == nil {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.file.loading", table: .localizable,
                    fallback: "Dosyalar yükleniyor…"), style: .metaQuiet)
            }
        } else if board?.rows.isEmpty ?? true {
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: filedHere == 0
                        ? RDLocalization.string("localizable.nova.file.empty", table: .localizable,
                            fallback: "Bu firmada arşivlenmiş dosya yok. Saklamak istediğiniz belgeyi ekleyin.")
                        : RDLocalization.string("localizable.nova.file.empty.filtered", table: .localizable,
                            fallback: "Bu filtreye uyan dosya yok."), style: .metaQuiet)
                    if canWrite && filedHere == 0 {
                        NovaButton(label: RDLocalization.string("localizable.nova.file.add.title", table: .localizable, fallback: "Dosya ekle"),
                            symbol: "folder.badge.plus") { adding = true }
                            .accessibilityIdentifier("file.library.empty.add")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let board {
            ForEach(board.rows) { row in card(row) }
            footer(board)
        }
    }

    /// The page shows ten at a time and says how many are still behind it.
    @ViewBuilder private func footer(_ board: NovaFileLibrary) -> some View {
        HStack(spacing: 8) {
            NovaText(text: String(format: RDLocalization.string("localizable.nova.file.page", table: .localizable,
                fallback: "%1$d / %2$d dosya"), board.rows.count, board.total), style: .micro,
                color: NovaColorToken.textTertiary.color(in: scheme))
            Spacer(minLength: 0)
            if board.hasMore {
                Button {
                    shown += NovaFileQuery().limit
                    reload = UUID()
                } label: {
                    HStack(spacing: 5) {
                        if loading { NovaText(text: "…", style: .meta, color: NovaColorToken.accentInk.color(in: scheme)) }
                        else { Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)) }
                        NovaText(text: RDLocalization.string("localizable.nova.document.more", table: .localizable, fallback: "Daha fazla göster"),
                            style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                    }.foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 40)
                }.buttonStyle(.plain).disabled(loading)
                    .accessibilityIdentifier("file.library.more")
            }
        }
    }

    private func card(_ row: NovaFileEntry) -> some View {
        let state = NovaFileGroup.of(row.state)
        return Button { inspecting = row } label: {
            NovaCard(padding: 11) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 9) {
                        NovaIcon(symbol: NovaFileWords.symbol(row.state), size: 16)
                            .foregroundStyle(tone(state).tokens.ink.color(in: scheme))
                            .frame(width: 38, height: 38)
                            .background(tone(state).tokens.background.color(in: scheme),
                                        in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: row.title, style: .cardTitle).lineLimit(2)
                            // The file name is only a second line when the
                            // expert named the entry differently.
                            if row.fileName != row.title {
                                NovaText(text: row.fileName, style: .micro,
                                    color: NovaColorToken.textTertiary.color(in: scheme)).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        NovaStatusPill(label: NovaFileWords.state(row.state),
                            status: tone(state), showsDot: false)
                    }
                    HStack(spacing: 5) {
                        NovaAnalysisTag(symbol: "folder", text: NovaFileWords.category(row.category), status: .neutral)
                        if !row.fileExtension.isEmpty {
                            NovaAnalysisTag(symbol: "doc", text: row.fileExtension.uppercased(), status: .neutral)
                        }
                        NovaAnalysisTag(symbol: "externaldrive", text: NovaFileWords.size(row.bytes), status: .neutral)
                        Spacer(minLength: 0)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("file.library.row.\(row.id.uuidString.lowercased())")
    }

    private func refresh() async {
        error = nil
        loading = true
        defer { loading = false }
        if !started {
            started = true
            company = initialCompany
            companies = (try? await client.companies()) ?? []
            if let answer = try? await client.catalogue() {
                catalogue = answer.categories
                accepts = answer.accepts
                assurance = answer.assurance
            }
        }
        do { board = try await client.library(request) }
        catch is CancellationError { }
        catch let failure as NovaFileFailure {
            board = .init()
            error = NovaFileScreenWords.failure(failure)
        }
        catch {
            board = .init()
            self.error = RDLocalization.string("localizable.nova.file.failed", table: .localizable,
                fallback: "Dosyalar alınamadı. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
}

/// One company-page heading's filed documents: four counters and the way in.
/// The counts are the archive's own, so the heading and the archive can never
/// disagree about what is on file.
struct NovaFileSectionStrip: View {
    let counts: [NovaFileState: Int]
    var isLoading = false
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var scheme

    private func count(_ group: NovaFileGroup) -> Int {
        group.states.reduce(0) { $0 + (counts[$1] ?? 0) }
    }
    private var total: Int { NovaFileState.allCases.reduce(0) { $0 + (counts[$1] ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                NovaText(text: RDLocalization.string("localizable.nova.file.loading", table: .localizable,
                    fallback: "Dosyalar yükleniyor…"), style: .metaQuiet)
            } else if total == 0 {
                NovaText(text: RDLocalization.string("localizable.nova.file.section.empty", table: .localizable,
                    fallback: "Bu başlık için arşivlenmiş dosya yok."), style: .metaQuiet)
            } else {
                HStack(spacing: 6) {
                    ForEach(NovaFileGroup.allCases) { group in
                        let palette = NovaFileScreenWords.tone(group).tokens
                        VStack(spacing: 2) {
                            NovaText(text: "\(count(group))", style: .cardTitle,
                                color: palette.ink.color(in: scheme))
                            NovaText(text: group.title, style: .micro,
                                color: NovaColorToken.textTertiary.color(in: scheme)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(palette.background.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            NovaButton(label: RDLocalization.string("localizable.nova.file.section.open", table: .localizable, fallback: "Dosyaları aç"),
                symbol: "folder", variant: .surface, action: onOpen)
                .accessibilityIdentifier("company.section.files.open")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Words the archive screens share.
enum NovaFileScreenWords {
    static func tone(_ group: NovaFileGroup) -> NovaStatus {
        switch group {
        case .filed: return .success
        case .working: return .info
        case .rejected: return .danger
        case .unchecked: return .warning
        }
    }

    static func failure(_ failure: NovaFileFailure) -> String {
        switch failure {
        case .denied: return RDLocalization.string("localizable.nova.file.failure.denied", table: .localizable, fallback: "Bu firmanın dosyalarına erişim yok.")
        case .planRequired: return RDLocalization.string("localizable.nova.file.failure.plan", table: .localizable, fallback: "Dosya eklemek için Plus veya Pro plan gerekiyor.")
        case .versionConflict: return RDLocalization.string("localizable.nova.file.failure.version", table: .localizable, fallback: "Kayıt başka bir yerden değişmiş. Sayfayı yenileyip tekrar deneyin.")
        case .conflict: return RDLocalization.string("localizable.nova.file.failure.conflict", table: .localizable, fallback: "Bu işlem farklı bir içerikle zaten kaydedilmiş.")
        case .validation: return RDLocalization.string("localizable.nova.file.failure.validation", table: .localizable, fallback: "Bilgiler eksik veya geçersiz.")
        case .unsupportedFormat: return RDLocalization.string("localizable.nova.file.failure.format", table: .localizable, fallback: "Bu dosya türü kabul edilmiyor.")
        case .tooLarge: return RDLocalization.string("localizable.nova.file.failure.size", table: .localizable, fallback: "Dosya boyutu sınırın dışında.")
        case .uploadFailed: return RDLocalization.string("localizable.nova.file.failure.upload", table: .localizable, fallback: "Dosya gönderilemedi. Bağlantınızı kontrol edip tekrar deneyin.")
        case .notCancellable: return RDLocalization.string("localizable.nova.file.failure.cancel", table: .localizable, fallback: "Bu dosya arşive alınmış; iptal edilemez. Kaldırmak için arşivden çıkarın.")
        // The upload stays exactly where it really is. Nothing here reports a
        // file as cleared because the inspection could not be reached.
        case .inspectionUnavailable: return RDLocalization.string("localizable.nova.file.failure.inspection", table: .localizable, fallback: "Denetim şu anda çalıştırılamadı. Dosya arşive alınmadı; kaydın üzerinden tekrar deneyebilirsiniz.")
        case .unavailable: return RDLocalization.string("localizable.nova.file.failure.unavailable", table: .localizable, fallback: "Dosya servisi şu anda kullanılamıyor.")
        }
    }

    /// The document types the picker offers, from the server's own list.
    static func contentTypes(_ accepts: [NovaFileAcceptance]) -> [UTType] {
        let extensions = Set(accepts.flatMap(\.extensions))
        return extensions.compactMap { UTType(filenameExtension: $0) }
    }
}
