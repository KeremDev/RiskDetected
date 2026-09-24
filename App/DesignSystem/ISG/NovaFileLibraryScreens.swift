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
    let file: (UUID?, NovaFileDraft, Data) async throws -> NovaFileEntry
    let rename: (NovaFileEntry, String, String, String) async throws -> NovaFileEntry
    let archive: (NovaFileEntry) async throws -> Void
    let cancel: (NovaFileEntry) async throws -> Void
    let recheck: (NovaFileEntry) async throws -> NovaFileEntry
    let contents: (NovaFileEntry) async throws -> Data
    /// The same download, for a caller that only has a bucket/path a module's
    /// own row resolved rather than a whole library entry.
    let download: (String, String) async throws -> Data
    var detail: ((UUID) async throws -> NovaFileEntry)? = nil
}

/// One counter, in the same shape the home page uses for its summary: a toned
/// icon beside the number, the name under it and a short factual footer.
struct NovaFileStatCard: View {
    let group: NovaFileGroup
    let value: Int
    var isSelected = false
    let onTap: () -> Void
    var body: some View {
        NovaListStat(title: group.title, symbol: group.symbol, value: value,
            status: NovaFileScreenWords.tone(group), isSelected: isSelected, onTap: onTap)
            .accessibilityIdentifier("file.stat.\(group.rawValue)")
    }
}

/// One option inside a chooser: what it is called, how many rows it covers and
/// the tone the archive uses for it.
struct NovaFileChooserOption: Identifiable, Equatable {
    /// nil is the unfiltered answer ("Tümü" / "Tüm başlıklar").
    let id: String?
    let title: String
    var count: Int?
    var symbol: String?
    var tone: NovaStatus = .neutral
    var identity: String { id ?? "all" }
}

/// The closed half of a chooser: the field name above, the current answer and a
/// chevron. Two of these sit side by side and the list opens underneath, so a
/// long set of headings never runs off the side of the screen.
struct NovaFileChooserButton: View {
    let label: String
    let value: String
    var symbol: String?
    var isOpen = false
    var isAnswered = true
    let identifier: String
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label).font(.custom("PlusJakartaSans-Medium", size: 10, relativeTo: .caption))
                    .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                HStack(spacing: 6) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    }
                    Text(verbatim: value).font(.custom("PlusJakartaSans-Medium", size: 13, relativeTo: .body))
                        .foregroundStyle(NovaColorToken.text.color(in: scheme))
                        .lineLimit(1).minimumScaleFactor(0.78)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .novaControlBackground(cornerRadius: 14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isOpen ? NovaColorToken.accentInk.color(in: scheme)
                                     : NovaColorToken.border.color(in: scheme),
                              lineWidth: isOpen ? 1.4 : 1))
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier(identifier)
            .accessibilityValue(Text(verbatim: value))
    }
}

/// Search stays visible while compact choices scroll within a bounded panel.
struct NovaFileChooserPanel: View {
    let options: [NovaFileChooserOption]
    let selected: String?
    let identifier: String
    let onPick: (String?) -> Void
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .body) private var rowHeight = 44.0
    @State private var search = ""

    private var matches: [NovaFileChooserOption] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? options : options.filter { $0.title.localizedStandardContains(query) }
    }
    private var panelHeight: CGFloat { min(CGFloat(max(options.count, 1)) * rowHeight, 220) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).accessibilityHidden(true)
                TextField("Ara…", text: $search)
                    .font(.custom("PlusJakartaSans-Regular", size: 13, relativeTo: .body))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel(RDLocalization.string("localizable.nova.file.library.screens.seceneklerde.ara.5f9e18f3", table: .localizable, fallback: "Seçeneklerde ara"))
                    .accessibilityIdentifier("\(identifier).search")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark").frame(width: 32, height: 36) }
                        .accessibilityLabel(RDLocalization.string("localizable.nova.file.library.screens.aramayi.temizle.7e5db71a", table: .localizable, fallback: "Aramayı temizle"))
                }
            }
            .foregroundStyle(NovaColorToken.text.color(in: scheme))
            .padding(.horizontal, 10).frame(minHeight: 40)
            .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
            ScrollView {
                LazyVStack(spacing: 0) {
                    if matches.isEmpty {
                        NovaText(text: RDLocalization.string("localizable.nova.file.library.screens.sonuc.bulunamadi.42ce3aa2", table: .localizable, fallback: "Sonuç bulunamadı"), style: .metaQuiet)
                            .frame(maxWidth: .infinity, minHeight: rowHeight)
                    }
                    ForEach(matches, id: \.identity) { option in cell(option) }
                }
            }
            .frame(height: panelHeight)
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(10)
        .novaControlBackground(cornerRadius: 16)
        .onChange(of: identifier) { _ in search = "" }
    }

    private func cell(_ option: NovaFileChooserOption) -> some View {
        let isOn = selected == option.id
        return Button { onPick(option.id) } label: {
            HStack(spacing: 8) {
                if let symbol = option.symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .regular)).frame(width: 18)
                }
                Text(verbatim: option.title)
                    .font(.custom(isOn ? "PlusJakartaSans-SemiBold" : "PlusJakartaSans-Regular", size: 13, relativeTo: .body))
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let count = option.count {
                    NovaText(text: "\(count)", style: .micro)
                }
                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                    .opacity(isOn ? 1 : 0).frame(width: 18)
            }
            .foregroundStyle(NovaColorToken.text.color(in: scheme))
            .padding(.horizontal, 10).padding(.vertical, 7).frame(minHeight: rowHeight)
            .background(isOn ? NovaColorToken.surfaceMuted.color(in: scheme) : .clear,
                in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .animation(NovaMotion.easeOut(0.14), value: isOn)
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier("\(identifier).\(option.identity)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
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
    /// A tracker row opens this exact archive entry, even when it is beyond the first page.
    var initialEntryID: UUID?
    /// Opens onto one heading of the company page, such as periodic checks.
    var initialCategories: [String]?
    var headingOverride: String?
    /// Opened from the quick-add menu's "Dosya Ekle": the upload sheet opens
    /// immediately instead of landing on the list first.
    var startInAddMode = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
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
    @State private var choosingCompanyFilter = false
    @State private var loading = false
    @State private var reload = UUID()
    @State private var started = false
    /// Which chooser is open, if any. One at a time keeps the page short.
    @State private var openChooser: String?
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
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    NovaListHint(text: RDLocalization.string("localizable.nova.file.library.screens.modullerdeki.ve.ayrica.yuklediginiz.dosyalari.fi.7357f36b", table: .localizable, fallback: "Modüllerdeki ve ayrıca yüklediğiniz dosyaları firma ve başlığa göre bulun."))
                    archive
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) { await refresh() }
        .task(id: initialEntryID) {
            guard let initialEntryID, let detail = client.detail else { return }
            do { inspecting = try await detail(initialEntryID) }
            catch { self.error = "Dosya detayı açılamadı. Yeniden deneyin." }
        }
        .onChange(of: group) { _ in shown = NovaFileQuery().limit; reload = UUID() }
        .onChange(of: category) { _ in shown = NovaFileQuery().limit; reload = UUID() }
        .onChange(of: company) { _ in
            shown = NovaFileQuery().limit
            group = nil
            category = nil
            query = ""
            openChooser = nil
            reload = UUID()
        }
        .novaPopup(isPresented: $choosingCompanyFilter) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaText(text: RDLocalization.string("localizable.nova.file.library.screens.firma.filtresi.024c118b", table: .localizable, fallback: "Firma filtresi"), style: .sheetTitle)
                    NovaButton(label: RDLocalization.string("localizable.nova.file.library.screens.tum.dosyalar.97fcc025", table: .localizable, fallback: "Tüm dosyalar"), symbol: "folder", variant: .surface) {
                        company = nil; choosingCompanyFilter = false
                    }
                    picker
                }.padding(16).novaPopupContentSize()
            }
        }
        .novaPopupCover(item: $inspecting) { row in
            NovaPopup {
                NovaFileEntrySheet(entry: row, catalogue: catalogue, assurance: assurance,
                    client: client, canWrite: canWrite,
                    onChanged: { reload = UUID() }, onClosed: { inspecting = nil })
            }
        }
        .novaPopupCover(isPresented: $adding) {
            NovaPopup {
                NovaFileAddSheet(companies: companies, preselected: company,
                    categories: offeredCategories, accepts: accepts, assurance: assurance,
                    client: client) { _ in
                        adding = false
                        reload = UUID()
                    }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NovaBackButton { onBack() }
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: headingOverride ?? NovaDestination.documents.title, style: .screenTitle)
                    if let selectedName { NovaText(text: selectedName, style: .metaQuiet) }
                }
                Spacer(minLength: 0)
            }
            // Personal and company files share one archive.
            if canWrite {
                NovaListActionButton(title: RDLocalization.string("localizable.nova.file.add.short", table: .localizable, fallback: "Dosya Ekle"),
                    symbol: "plus", tone: .primary, identifier: "file.library.new") { adding = true }
            }
        }
    }

    // MARK: choosing a company

    @ViewBuilder private var picker: some View {
        companyField
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if companies.isEmpty {
            NovaCard(padding: 16) {
                NovaText(text: loading
                    ? RDLocalization.string("localizable.nova.file.loading", table: .localizable, fallback: "Dosyalar yükleniyor…")
                    : "Henüz firma yok. Kişisel dosyalarınızı firma eklemeden yükleyebilirsiniz.", style: .metaQuiet)
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
                .font(NovaFont.font(.body))
                .textInputAutocapitalization(.never)
                .focused($searchingCompany)
                .accessibilityIdentifier("file.company.search")
            if !companyQuery.isEmpty {
                Button { companyQuery = "" } label: {
                    Image(systemName: "xmark.circle").font(.system(size: 14))
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                }.buttonStyle(NovaRowPressStyle())
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
        return Button { company = option.id; searchingCompany = false; choosingCompanyFilter = false } label: {
            NovaCard(padding: 11) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 9) {
                        NovaIcon(symbol: "folder", size: 15)
                            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                            .frame(width: 36, height: 36)
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
        }.buttonStyle(NovaRowPressStyle())
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
        search
        filters
        list
    }

    private var chosenCompany: some View {
        NovaFilterField(label: "Firma", options: [.init(id: nil, title: RDLocalization.string("localizable.nova.file.library.screens.tum.firmalar.623eb3ca", table: .localizable, fallback: "Tüm firmalar"))] + companies.map { .init(id: $0.id.uuidString, title: $0.name) },
            selected: company?.uuidString, identifier: "file.company.filter") { company = $0.flatMap(UUID.init(uuidString:)) }
    }

    /// Four counters in the home page's own card shape. Tapping one is the same
    /// filter the chips below carry, and it narrows to exactly what it counted.
    private var stats: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8),
                            count: typeSize.isAccessibilitySize ? 2 : 4)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(NovaFileGroup.allCases) { value in
                NovaFileStatCard(group: value, value: count(value),
                    isSelected: group == value) {
                        group = group == value ? nil : value
                        openChooser = nil
                    }
            }
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

    /// Two choosers side by side. The list opens underneath the one that was
    /// tapped, so thirteen headings stay reachable without a strip that runs
    /// off the side of the screen.
    @ViewBuilder private var filters: some View {
        HStack(spacing: 8) {
            NovaFileChooserButton(
                label: RDLocalization.string("localizable.nova.file.filter.state", table: .localizable, fallback: "Durum"),
                value: group?.title ?? allStates,
                symbol: group?.symbol ?? "line.3.horizontal.decrease",
                isOpen: openChooser == "state", identifier: "file.library.filter") {
                    openChooser = openChooser == "state" ? nil : "state"
                }
            if initialCategories == nil {
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.file.filter.category", table: .localizable, fallback: "Başlık"),
                    value: category.map(NovaFileWords.category) ?? allCategories,
                    symbol: "folder",
                    isOpen: openChooser == "category", identifier: "file.library.category") {
                        openChooser = openChooser == "category" ? nil : "category"
                    }
            }
        }
        if openChooser == "state" {
            NovaFileChooserPanel(options: stateOptions, selected: group?.rawValue,
                identifier: "file.library.filter") { picked in
                    group = picked.flatMap(NovaFileGroup.init(rawValue:))
                    openChooser = nil
                }
        }
        if openChooser == "category" {
            NovaFileChooserPanel(options: categoryOptions, selected: category,
                identifier: "file.library.category") { picked in
                    category = picked
                    openChooser = nil
                }
        }
    }

    private var allStates: String {
        RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü")
    }
    private var allCategories: String {
        RDLocalization.string("localizable.nova.file.category.all", table: .localizable, fallback: "Tüm başlıklar")
    }

    private var stateOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allStates, count: filedHere, symbol: "square.grid.2x2")] +
        NovaFileGroup.allCases.map { value in
            .init(id: value.rawValue, title: value.title, count: count(value),
                  symbol: value.symbol, tone: tone(value))
        }
    }

    /// Every heading the archive holds something under, plus the one in force,
    /// so a filter can always be seen and cleared.
    private var categoryOptions: [NovaFileChooserOption] {
        let held = { (code: String) in (board?.categoryCounts[code] ?? [:]).values.reduce(0, +) }
        return [.init(id: nil, title: allCategories, count: filedHere, symbol: "square.grid.2x2")] +
            catalogue.filter { held($0.code) > 0 || category == $0.code }
                .map { .init(id: $0.code, title: NovaFileWords.category($0.code),
                             count: held($0.code), symbol: "folder") }
    }

    @ViewBuilder private var list: some View {
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if board == nil {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.file.loading", table: .localizable,
                    fallback: "Dosyalar yükleniyor…"), style: .metaQuiet)
            }
        } else if let board {
            VStack(alignment: .leading, spacing: 10) {
                NovaListSectionHeading(title: headingOverride ?? NovaDestination.documents.title,
                    count: String(format: RDLocalization.string("localizable.nova.file.page", table: .localizable,
                        fallback: "%1$d / %2$d dosya"), board.rows.count, board.total))
                if board.rows.isEmpty {
                    NovaEmptyState(title: filedHere == 0 ? "Henüz dosya yok" : "Bu filtreye uyan dosya yok",
                        message: filedHere == 0
                            ? "Dosya ekleyerek belgelerinizi etiket, not ve bağlı kayıt bilgileriyle tek arşivde saklayabilirsiniz."
                            : "Arama veya filtreleri değiştirerek diğer dosyaları görüntüleyebilirsiniz.")
                    if canWrite && filedHere == 0 {
                        NovaButton(label: RDLocalization.string("localizable.nova.file.add.title", table: .localizable,
                            fallback: "Dosya ekle"), symbol: "folder.badge.plus") { adding = true }
                            .accessibilityIdentifier("file.library.empty.add")
                    }
                } else {
                    ForEach(board.rows) { row in card(row) }
                }
                footer(board)
            }
        }
    }

    /// The page shows ten at a time and says how many are still behind it.
    @ViewBuilder private func footer(_ board: NovaFileLibrary) -> some View {
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
                }.buttonStyle(NovaRowPressStyle()).disabled(loading)
                    .accessibilityIdentifier("file.library.more")
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
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier("file.library.row.\(row.id.uuidString.lowercased())")
    }

    private func refresh() async {
        error = nil
        loading = true
        defer { loading = false }
        if !started {
            started = true
            company = initialCompany
            if startInAddMode { adding = true }
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

/// One company-page heading's filed documents: the shared four-card counter
/// standard and the way into the archive.
struct NovaFileSectionStrip: View {
    let counts: [NovaFileState: Int]
    var isLoading = false
    let onOpen: () -> Void

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
                NovaEmptyState(title: RDLocalization.string("localizable.nova.file.library.screens.henuz.dosya.yok.a8671016", table: .localizable, fallback: "Henüz dosya yok"),
                    message: RDLocalization.string("localizable.nova.file.library.screens.bu.basliga.dosya.ekleyerek.kayitlari.tek.yerde.s.bf382c86", table: .localizable, fallback: "Bu başlığa dosya ekleyerek kayıtları tek yerde saklayabilir ve gerektiğinde hızlıca açabilirsiniz."))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(NovaFileGroup.allCases) { group in
                            NovaListStat(title: group.title, symbol: group.symbol, value: count(group)).frame(width: 98)
                        }
                    }.padding(.vertical, 2)
                }
            }
            NovaCompactActionButton(title: RDLocalization.string("localizable.nova.file.section.open", table: .localizable,
                fallback: "Dosyaları aç"), symbol: "folder", action: onOpen)
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

/// Single filters use exactly the same searchable panel as multi-filter rows.
struct NovaFilterField: View {
    let label: String
    let options: [NovaFileChooserOption]
    let selected: String?
    let identifier: String
    let onPick: (String?) -> Void
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            NovaFileChooserButton(label: label,
                value: options.first { $0.id == selected }?.title ?? "Tümü",
                isOpen: expanded, identifier: identifier) { expanded.toggle() }
            if expanded {
                NovaFileChooserPanel(options: options, selected: selected,
                    identifier: "\(identifier).options") { value in
                    onPick(value)
                    expanded = false
                }
                // The panel belongs to the button above it, so it grows from
                // that edge rather than fading in place, and it leaves the same
                // way it arrived. Without this the rows below it teleport.
                .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.97, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(NovaMotion.gated(NovaMotion.easeOut(NovaMotion.Duration.dropdown),
                                    reduceMotion: reduceMotion),
                   value: expanded)
    }
}
