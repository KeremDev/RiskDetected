import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// module these closures.
struct NovaEquipmentCheckClient {
    /// The type names to offer, the periods this company has set, its
    /// workplaces and the warning window the server owns.
    let catalogue: (UUID?) async throws -> (suggestions: [NovaEquipmentCheckService.Suggestion],
                                            rules: [NovaEquipmentRule],
                                            workplaces: [NovaDocumentWorkplace], noticeDays: Int)
    /// The whole account in one answer: the tally, the per-company summary, the
    /// per-type tally and one page of rows.
    let board: (NovaEquipmentQuery) async throws -> NovaEquipmentBoard
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    let detail: (UUID) async throws -> NovaEquipmentItem
    let register: (UUID, NovaEquipmentDraft) async throws -> NovaEquipmentItem
    let update: (NovaEquipmentItem, NovaEquipmentDraft) async throws -> NovaEquipmentItem
    let archive: (NovaEquipmentItem) async throws -> Void
    let setRule: (UUID, NovaEquipmentRuleDraft) async throws -> NovaEquipmentRule
    let recordInspection: (NovaEquipmentItem, NovaEquipmentInspectionDraft) async throws -> NovaEquipmentItem
    /// Corrects a report already on file. Its date and result are not editable.
    var updateInspection: (NovaEquipmentItem, NovaEquipmentInspection, NovaEquipmentInspectionDraft) async throws -> NovaEquipmentItem = { item, _, _ in item }
    /// Reports already filed in the archive, so a check can point at a real
    /// file instead of carrying a second copy of one.
    var filedReports: (UUID) async throws -> [NovaFileEntry] = { _ in [] }
}

/// One counter, in the same shape the home page uses for its summary.
struct NovaEquipmentStatCard: View {
    let group: NovaEquipmentGroup
    let value: Int
    var isSelected = false
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var tone: NovaColorToken {
        switch group {
        case .overdue: return .statusDangerInk
        case .failed: return .statusDangerInk
        case .untracked: return .statusWarningInk
        case .dueSoon: return .statusInfoInk
        case .current: return .statusSuccessInk
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
            .accessibilityIdentifier("equipment.stat.\(group.rawValue)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Periyodik Kontroller. A company is chosen first, because equipment belongs
/// to one; its inventory opens underneath. What the page says about an item is
/// always what the record says: a period nobody set produces no date, and the
/// row says so rather than showing a year nobody chose.
struct NovaEquipmentCheckScreen: View {
    let client: NovaEquipmentCheckClient
    let onBack: () -> Void
    var canWrite = true
    /// Opened from a company page: that company is already the answer.
    var initialCompany: UUID?
    var headingOverride: String?
    @Environment(\.colorScheme) private var scheme
    @State private var board: NovaEquipmentBoard?
    @State private var suggestions: [NovaEquipmentCheckService.Suggestion] = []
    @State private var rules: [NovaEquipmentRule] = []
    @State private var workplaces: [NovaDocumentWorkplace] = []
    @State private var noticeDays = 30
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var error: String?
    @State private var companyQuery = ""
    @State private var query = ""
    @State private var group: NovaEquipmentGroup?
    @State private var equipmentType: String?
    @State private var company: UUID?
    @State private var shown = NovaEquipmentQuery().limit
    @State private var inspecting: NovaEquipmentItem?
    @State private var adding = false
    @State private var editingPeriods = false
    @State private var loading = false
    @State private var reload = UUID()
    @State private var started = false
    @State private var openChooser: String?
    @FocusState private var searchingCompany: Bool

    private var isCompanyLocked: Bool { initialCompany != nil }
    private var selectedCompany: NovaEquipmentCompanySummary? { board?.companies.first { $0.id == company } }
    private var selectedName: String? {
        selectedCompany?.name ?? companies.first { $0.id == company }?.name
    }
    /// The counters follow what the page is actually showing: the chosen
    /// company, otherwise the whole account. The server's headline covers the
    /// account, so narrowing is read from the per-company tally it sends.
    private var visibleCounts: [NovaEquipmentState: Int] {
        guard let board else { return [:] }
        if let selectedCompany { return selectedCompany.counts }
        return board.counts
    }
    private func count(_ group: NovaEquipmentGroup) -> Int {
        group.states.reduce(0) { $0 + (visibleCounts[$1] ?? 0) }
    }
    private var trackedHere: Int { NovaEquipmentState.allCases.reduce(0) { $0 + (visibleCounts[$1] ?? 0) } }

    private var request: NovaEquipmentQuery {
        .init(query: query, state: group?.rawValue, company: company,
              equipmentType: equipmentType, limit: shown, offset: 0)
    }
    private var offered: [NovaAnalysisCompanyOption] {
        let needle = companyQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return companies }
        return companies.filter { $0.name.lowercased().contains(needle) || $0.detail.lowercased().contains(needle) }
    }
    private func rule(for type: String) -> NovaEquipmentRule? { rules.first { $0.equipmentType == type } }

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    if company == nil { picker } else { inventory }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) { await refresh() }
        .onChange(of: group) { _ in shown = NovaEquipmentQuery().limit; reload = UUID() }
        .onChange(of: equipmentType) { _ in shown = NovaEquipmentQuery().limit; reload = UUID() }
        .onChange(of: company) { _ in
            shown = NovaEquipmentQuery().limit
            group = nil; equipmentType = nil; query = ""; openChooser = nil
            reload = UUID()
        }
        .novaFullScreenCover(item: $inspecting) { row in
            NovaPopup {
                NovaEquipmentItemSheet(item: row, rule: rule(for: row.equipmentType),
                    workplaces: workplaces, client: client, canWrite: canWrite,
                    onChanged: { reload = UUID() }, onClosed: { inspecting = nil })
            }
        }
        .novaFullScreenCover(isPresented: $adding) {
            NovaPopup {
                NovaEquipmentAddSheet(companies: companies, preselected: company,
                    suggestions: suggestions, rules: rules, workplaces: workplaces, client: client) {
                        adding = false
                        reload = UUID()
                    }
            }
        }
        .novaFullScreenCover(isPresented: $editingPeriods) {
            NovaPopup {
                NovaEquipmentPeriodSheet(company: company, suggestions: suggestions, rules: rules,
                    client: client) {
                        editingPeriods = false
                        started = false
                        reload = UUID()
                    }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            NovaBackButton { onBack() }
            VStack(alignment: .leading, spacing: 2) {
                // "Periyodik Kontroller" is wider than the row once the add
                // control is beside it, so it scales rather than wrapping.
                NovaText(text: headingOverride ?? NovaDestination.periodicChecks.title, style: .screenTitle)
                    .lineLimit(1).minimumScaleFactor(0.72)
                if let selectedName { NovaText(text: selectedName, style: .metaQuiet) }
            }
            Spacer(minLength: 0)
            if canWrite && company != nil {
                Button { adding = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        NovaText(text: RDLocalization.string("localizable.nova.equipment.add.short", table: .localizable, fallback: "Ekipman"),
                            style: .buttonSm, color: NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    }
                    .foregroundStyle(NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(NovaColorToken.accent.color(in: scheme), in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("equipment.new")
            }
        }
    }

    // MARK: choosing a company

    @ViewBuilder private var picker: some View {
        companyField
        NovaHelpHint(text: RDLocalization.string("localizable.nova.equipment.pick.company", table: .localizable,
            fallback: "İlk önce firma seçimi yapın. Seçtiğiniz firmanın ekipman envanteri hemen aşağıda açılır."))
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if companies.isEmpty {
            NovaCard(padding: 16) {
                NovaText(text: loading
                    ? RDLocalization.string("localizable.nova.equipment.loading", table: .localizable, fallback: "Ekipman kayıtları yükleniyor…")
                    : RDLocalization.string("localizable.nova.equipment.company.empty", table: .localizable,
                        fallback: "Periyodik kontroller için önce bir firma ekleyin."), style: .metaQuiet)
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
                .accessibilityIdentifier("equipment.company.search")
            if !companyQuery.isEmpty {
                Button { companyQuery = "" } label: {
                    Image(systemName: "xmark.circle").font(.system(size: 14))
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

    private func companyRow(_ option: NovaAnalysisCompanyOption) -> some View {
        let summary = board?.companies.first { $0.id == option.id }
        return Button { company = option.id; searchingCompany = false } label: {
            NovaCard(padding: 11) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 9) {
                        NovaIcon(symbol: "checkmark.shield", size: 15)
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
                        // Two tags: what is on record and what needs looking at.
                        HStack(spacing: 5) {
                            NovaAnalysisTag(symbol: "shippingbox",
                                text: String(format: RDLocalization.string("localizable.nova.equipment.company.total", table: .localizable,
                                    fallback: "%d ekipman"), summary.total), status: .neutral)
                            if summary.needsAttention > 0 {
                                NovaAnalysisTag(symbol: "exclamationmark.triangle",
                                    text: String(format: RDLocalization.string("localizable.nova.equipment.company.attention", table: .localizable,
                                        fallback: "%d ilgi bekliyor"), summary.needsAttention), status: .danger)
                            }
                            Spacer(minLength: 0)
                        }
                    } else if summary == nil && board != nil {
                        NovaAnalysisTag(symbol: "questionmark.circle",
                            text: RDLocalization.string("localizable.nova.equipment.company.untracked", table: .localizable, fallback: "Envanter yok"),
                            status: .neutral)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("equipment.company.\(option.id.uuidString.lowercased())")
    }

    private func tone(_ group: NovaEquipmentGroup) -> NovaStatus {
        switch group {
        case .overdue, .failed: return .danger
        case .untracked: return .warning
        case .dueSoon: return .info
        case .current: return .success
        }
    }

    // MARK: the chosen company's inventory

    @ViewBuilder private var inventory: some View {
        if !isCompanyLocked { chosenCompany }
        stats
        hint
        periodsRow
        search
        filters
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
            }.buttonStyle(.plain).accessibilityIdentifier("equipment.company.change")
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
    }

    private var stats: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(NovaEquipmentGroup.allCases) { value in
                    NovaEquipmentStatCard(group: value, value: count(value),
                        isSelected: group == value) {
                            group = group == value ? nil : value
                            openChooser = nil
                        }
                }
            }.padding(.vertical, 2)
        }
    }

    /// What the module does and does not decide, said out loud.
    private var hint: some View {
        NovaHelpHint(text: String(format: RDLocalization.string("localizable.nova.equipment.hint", table: .localizable,
            fallback: "Her tür bir varsayılan kontrol süresiyle başlar ve sonraki tarih rapordan otomatik hesaplanır; süreyi de tarihi de değiştirebilirsiniz. Sayfa, tarihi %d gün önceden uyarır."), noticeDays))
    }

    /// How many types have a period on file, and the way into setting them.
    @ViewBuilder private var periodsRow: some View {
        let unreviewed = rules.filter(\.needsReview).count
        Button { editingPeriods = true } label: {
            HStack(spacing: 9) {
                NovaIcon(symbol: "hourglass", size: 14)
                    .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                VStack(alignment: .leading, spacing: 1) {
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.equipment.periods.count", table: .localizable,
                        fallback: "%d tür için süre tanımlı"), rules.count), style: .meta)
                    if unreviewed > 0 {
                        NovaText(text: String(format: RDLocalization.string("localizable.nova.equipment.periods.unreviewed", table: .localizable,
                            fallback: "%d tanesi uzman tarafından belirlenen süre"), unreviewed),
                            style: .micro, color: NovaColorToken.statusWarningInk.color(in: scheme))
                    }
                }
                Spacer(minLength: 0)
                NovaText(text: RDLocalization.string("localizable.nova.equipment.periods.open", table: .localizable, fallback: "Süreler"),
                    style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            }
            .padding(.horizontal, 12).frame(minHeight: 48)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier("equipment.periods.open")
    }

    private var search: some View {
        NovaAnalysisSearchField(text: $query,
            placeholder: RDLocalization.string("localizable.nova.equipment.search", table: .localizable, fallback: "Seri/kod veya tür ara"),
            identifier: "equipment.search")
            .onSubmit { shown = NovaEquipmentQuery().limit; reload = UUID() }
    }

    /// Two choosers side by side, the list opening underneath the one tapped.
    @ViewBuilder private var filters: some View {
        HStack(spacing: 8) {
            NovaFileChooserButton(
                label: RDLocalization.string("localizable.nova.file.filter.state", table: .localizable, fallback: "Durum"),
                value: group?.title ?? allStates, symbol: group?.symbol ?? "line.3.horizontal.decrease",
                isOpen: openChooser == "state", identifier: "equipment.filter") {
                    openChooser = openChooser == "state" ? nil : "state"
                }
            NovaFileChooserButton(
                label: RDLocalization.string("localizable.nova.equipment.filter.type", table: .localizable, fallback: "Tür"),
                value: equipmentType.map(NovaEquipmentWords.type) ?? allTypes, symbol: "shippingbox",
                isOpen: openChooser == "type", identifier: "equipment.type") {
                    openChooser = openChooser == "type" ? nil : "type"
                }
        }
        if openChooser == "state" {
            NovaFileChooserPanel(options: stateOptions, selected: group?.rawValue,
                identifier: "equipment.filter") { picked in
                    group = picked.flatMap(NovaEquipmentGroup.init(rawValue:))
                    openChooser = nil
                }
        }
        if openChooser == "type" {
            NovaFileChooserPanel(options: typeOptions, selected: equipmentType,
                identifier: "equipment.type") { picked in
                    equipmentType = picked
                    openChooser = nil
                }
        }
    }

    private var allStates: String {
        RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü")
    }
    private var allTypes: String {
        RDLocalization.string("localizable.nova.equipment.type.all", table: .localizable, fallback: "Tüm türler")
    }
    private var stateOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allStates, count: trackedHere, symbol: "square.grid.2x2")] +
        NovaEquipmentGroup.allCases.map { value in
            .init(id: value.rawValue, title: value.title, count: count(value),
                  symbol: value.symbol, tone: tone(value))
        }
    }
    private var typeOptions: [NovaFileChooserOption] {
        let held = { (code: String) in (board?.typeCounts[code] ?? [:]).values.reduce(0, +) }
        return [.init(id: nil, title: allTypes, count: trackedHere, symbol: "square.grid.2x2")] +
            suggestions.map(\.code).filter { held($0) > 0 || equipmentType == $0 }
                .map { .init(id: $0, title: NovaEquipmentWords.type($0), count: held($0), symbol: "shippingbox") }
    }

    @ViewBuilder private var list: some View {
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if board == nil {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.loading", table: .localizable,
                    fallback: "Ekipman kayıtları yükleniyor…"), style: .metaQuiet)
            }
        } else if board?.rows.isEmpty ?? true {
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: trackedHere == 0
                        ? RDLocalization.string("localizable.nova.equipment.empty", table: .localizable,
                            fallback: "Bu firmada kayıtlı ekipman yok. Periyodik kontrole giren ekipmanları ekleyin.")
                        : RDLocalization.string("localizable.nova.equipment.empty.filtered", table: .localizable,
                            fallback: "Bu filtreye uyan ekipman yok."), style: .metaQuiet)
                    if canWrite && trackedHere == 0 {
                        NovaButton(label: RDLocalization.string("localizable.nova.equipment.add.title", table: .localizable, fallback: "Ekipman ekle"),
                            symbol: "plus") { adding = true }
                            .accessibilityIdentifier("equipment.empty.add")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let board {
            ForEach(board.rows) { row in card(row) }
            footer(board)
        }
    }

    @ViewBuilder private func footer(_ board: NovaEquipmentBoard) -> some View {
        HStack(spacing: 8) {
            NovaText(text: String(format: RDLocalization.string("localizable.nova.equipment.page", table: .localizable,
                fallback: "%1$d / %2$d ekipman"), board.rows.count, board.total), style: .micro,
                color: NovaColorToken.textTertiary.color(in: scheme))
            Spacer(minLength: 0)
            if board.hasMore {
                Button {
                    shown += NovaEquipmentQuery().limit
                    reload = UUID()
                } label: {
                    HStack(spacing: 5) {
                        if loading { NovaText(text: "…", style: .meta, color: NovaColorToken.accentInk.color(in: scheme)) }
                        else { Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)) }
                        NovaText(text: RDLocalization.string("localizable.nova.document.more", table: .localizable, fallback: "Daha fazla göster"),
                            style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                    }.foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 40)
                }.buttonStyle(.plain).disabled(loading)
                    .accessibilityIdentifier("equipment.more")
            }
        }
    }

    private func card(_ row: NovaEquipmentItem) -> some View {
        let state = row.group
        return Button { inspecting = row } label: {
            NovaCard(padding: 11) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 9) {
                        NovaIcon(symbol: state.symbol, size: 16)
                            .foregroundStyle(tone(state).tokens.ink.color(in: scheme))
                            .frame(width: 38, height: 38)
                            .background(tone(state).tokens.background.color(in: scheme),
                                        in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: NovaEquipmentWords.type(row.equipmentType), style: .cardTitle).lineLimit(1)
                            NovaText(text: row.serialTag, style: .micro,
                                color: NovaColorToken.textTertiary.color(in: scheme)).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        NovaStatusPill(label: NovaEquipmentWords.state(row.state),
                            status: tone(state), showsDot: false)
                    }
                    HStack(spacing: 5) {
                        if let due = row.nextDueOn {
                            NovaAnalysisTag(symbol: "calendar", text: due, status: tone(state))
                        } else {
                            // No date rather than a blank: the absence is the fact.
                            NovaAnalysisTag(symbol: "calendar.badge.exclamationmark",
                                text: RDLocalization.string("localizable.nova.equipment.no.due", table: .localizable, fallback: "Tarih yok"),
                                status: .neutral)
                        }
                        if let months = row.periodMonths {
                            NovaAnalysisTag(symbol: "hourglass",
                                text: String(format: RDLocalization.string("localizable.nova.equipment.months", table: .localizable,
                                    fallback: "%d ay"), months),
                                status: row.periodNeedsReview == true ? .warning : .neutral)
                        }
                        if let place = row.locationNote, !place.isEmpty {
                            NovaAnalysisTag(symbol: "mappin", text: place, status: .neutral)
                        }
                        Spacer(minLength: 0)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("equipment.row.\(row.id.uuidString.lowercased())")
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
        if let answer = try? await client.catalogue(company) {
            suggestions = answer.suggestions
            rules = answer.rules
            workplaces = answer.workplaces
            noticeDays = answer.noticeDays
        }
        do { board = try await client.board(request) }
        catch is CancellationError { }
        catch let failure as NovaEquipmentFailure {
            board = .init()
            error = NovaEquipmentWords.failure(failure)
        }
        catch {
            board = .init()
            self.error = RDLocalization.string("localizable.nova.equipment.failed", table: .localizable,
                fallback: "Ekipman kayıtları alınamadı. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
}

/// One company-page heading's equipment standing: five counters and the way in.
/// The counts are the module's own, so the heading and the module can never
/// disagree about what is on record.
struct NovaEquipmentSectionStrip: View {
    let counts: [NovaEquipmentState: Int]
    var isLoading = false
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var scheme

    private func count(_ group: NovaEquipmentGroup) -> Int {
        group.states.reduce(0) { $0 + (counts[$1] ?? 0) }
    }
    private var total: Int { NovaEquipmentState.allCases.reduce(0) { $0 + (counts[$1] ?? 0) } }
    private func tone(_ group: NovaEquipmentGroup) -> NovaStatus {
        switch group {
        case .overdue, .failed: return .danger
        case .untracked: return .warning
        case .dueSoon: return .info
        case .current: return .success
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.loading", table: .localizable,
                    fallback: "Ekipman kayıtları yükleniyor…"), style: .metaQuiet)
            } else if total == 0 {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.section.empty", table: .localizable,
                    fallback: "Bu firmada kayıtlı ekipman yok."), style: .metaQuiet)
            } else {
                HStack(spacing: 6) {
                    ForEach(NovaEquipmentGroup.allCases) { group in
                        let palette = tone(group).tokens
                        VStack(spacing: 2) {
                            NovaText(text: "\(count(group))", style: .cardTitle,
                                color: palette.ink.color(in: scheme))
                            NovaText(text: group.title, style: .micro,
                                color: NovaColorToken.textTertiary.color(in: scheme))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(palette.background.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            NovaButton(label: RDLocalization.string("localizable.nova.equipment.section.open", table: .localizable, fallback: "Periyodik kontrolleri aç"),
                symbol: "checkmark.shield", variant: .surface, action: onOpen)
                .accessibilityIdentifier("company.section.equipment.open")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
