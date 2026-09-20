import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// module these closures.
struct NovaKatipClient {
    let catalogue: (UUID?) async throws -> NovaKatipCatalogue
    let board: (NovaKatipQuery) async throws -> NovaKatipBoard
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    let detail: (UUID) async throws -> NovaKatipContract
    let record: (UUID, NovaKatipDraft) async throws -> NovaKatipContract?
    let end: (UUID, NovaKatipEndDraft) async throws -> NovaKatipContract?
    let archive: (UUID, UUID) async throws -> NovaKatipContract?
    var openDocument: (UUID) async throws -> URL = { _ in throw NovaKatipFailure.unavailable }
    var documents: (UUID, Int) async throws -> [NovaFileEntry] = { _, _ in [] }
    var linkDocument: (NovaKatipContract, UUID?) async throws -> NovaKatipContract? = { _, _ in nil }
    var hasPending: () throws -> Bool = { false }
    var resume: () async throws -> NovaKatipContract? = { nil }
}

/// One counter, in the same shape the rest of the modules use.
struct NovaKatipStatCard: View {
    let group: NovaKatipGroup
    let value: Int
    var isSelected = false
    let onTap: () -> Void
    var body: some View {
        NovaListStat(title: group.title, symbol: group.symbol, value: value,
            isSelected: isSelected, onTap: onTap)
            .accessibilityIdentifier("nova.katip.stat.\(group.rawValue)")
    }
}

/// One contract as a row.
struct NovaKatipContractCard: View {
    let entry: NovaKatipContract
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var status: NovaStatus {
        switch entry.state {
        case .expired: return .danger
        case .expiring: return .warning
        case .active, .upcoming: return .success
        case .archived: return .neutral
        }
    }

    var body: some View {
        Button(action: onTap) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: entry.counterparty, style: .cardTitle)
                            NovaText(text: [entry.scope, entry.workplaceName, entry.companyName]
                                .compactMap { $0 }.joined(separator: " · "), style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        Spacer(minLength: 0)
                        NovaStatusPill(label: entry.state.title, status: status)
                    }
                    NovaText(text: NovaKatipWords.explain(entry), style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                    HStack(spacing: 10) {
                        fact("calendar", RDLocalization.string("localizable.nova.katip.row.starts",
                            table: .localizable, fallback: "Başlangıç"), entry.startsOn)
                        fact("doc.text", RDLocalization.string("localizable.nova.katip.row.term",
                            table: .localizable, fallback: "Tür"), entry.term.title)
                        fact("person", RDLocalization.string("localizable.nova.katip.row.expert",
                            table: .localizable, fallback: "Uzman"), entry.expertContact)
                    }
                    if let minutes = entry.declaredMonthlyMinutes {
                        NovaAnalysisTag(symbol: "clock",
                            text: RDLocalization.string("localizable.nova.katip.row.declared",
                                table: .localizable, fallback: "Beyan") + ": " + NovaKatipWords.service(minutes),
                            status: .info)
                    }
                }
            }
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityIdentifier("nova.katip.row.\(entry.id.uuidString)")
    }

    @ViewBuilder private func fact(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            VStack(alignment: .leading, spacing: 0) {
                NovaSizedText(text: label, size: 9, weight: "Medium",
                    color: NovaColorToken.textMuted.color(in: scheme))
                NovaSizedText(text: value, size: 11, weight: "Bold").lineLimit(1)
            }
        }
    }
}

/// The İSG-KATİP Sözleşmeleri surface.
struct NovaKatipScreen: View {
    let client: NovaKatipClient
    let onBack: () -> Void
    var canWrite: Bool = true
    var initialCompany: UUID?
    var headingOverride: String?

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var board: NovaKatipBoard?
    @State private var catalogue: NovaKatipCatalogue?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var query = NovaKatipQuery()
    @State private var pending = false
    @State private var resuming = false
    @State private var loading = true
    @State private var failure: String?
    @State private var openChooser: String?
    @State private var detail: NovaKatipContract?
    @State private var drafting: NovaKatipDraft?
    @State private var ending: NovaKatipEndDraft?
    @Environment(\.colorScheme) private var scheme

    private var allCompanies: String {
        RDLocalization.string("localizable.nova.katip.filter.companies", table: .localizable, fallback: "Tüm firmalar")
    }
    private var allStates: String {
        RDLocalization.string("localizable.nova.katip.filter.states", table: .localizable, fallback: "Tüm durumlar")
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    NovaHelpHint(text: "Firmanın sözleşmesini kaydedin; hizmet süresini ve belgesini takip edin.")
                    if let board { counters(board) }
                    filters
                    if pending && canWrite {
                        NovaCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                NovaText(text: "Gönderimi tamamlanmamış bir sözleşme işlemi var.", style: .body)
                                NovaButton(label: resuming ? "Tamamlanıyor…" : "Bekleyen işlemi tamamla",
                                           symbol: "arrow.clockwise", variant: .surface) {
                                    Task { await resumePending() }
                                }.disabled(resuming)
                            }
                        }
                    }
                    if loading && board == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if let failure {
                        NovaCard(padding: 16) {
                            NovaText(text: failure, style: .body,
                                color: NovaColorToken.statusDangerInk.color(in: scheme))
                        }
                    } else if let board {
                        list(board)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12)
                .padding(.bottom, 24 + novaTabBarInset)
            }
        }
        .task { await load(reset: true) }
        .novaPopup(item: $detail) { row in
            NovaKatipDetailSheet(entry: row, canWrite: canWrite,
                onEnd: {
                    detail = nil
                    ending = .init(contractID: row.id, counterparty: row.counterparty,
                                   startsOn: row.startsOn,
                                   endsBefore: row.endsBefore ?? NovaDayField.text(Date()),
                                   isCorrection: row.endsBefore != nil)
                },
                onArchive: { await archive(row) },
                onClose: { detail = nil },
                openDocument: { try await client.openDocument(row.id) },
                documents: { offset in
                    guard let company = row.companyID else { throw NovaKatipFailure.denied }
                    return try await client.documents(company, offset)
                },
                onLink: { file in
                    guard let updated = try await client.linkDocument(row, file) else { throw NovaKatipFailure.unavailable }
                    detail = updated
                })
        }
        .onChange(of: drafting == nil) { _ in pending = (try? client.hasPending()) ?? pending }
        .onChange(of: ending == nil) { _ in pending = (try? client.hasPending()) ?? pending }
        .novaPopup(item: $drafting) { draft in
            NovaKatipContractSheet(draft: draft, catalogue: catalogue,
                onSave: { edited in await save(edited) }, onClose: { drafting = nil })
        }
        .novaPopup(item: $ending) { draft in
            NovaKatipEndSheet(draft: draft,
                onSave: { edited in await finish(edited) }, onClose: { ending = nil })
        }
    }

    private var header: some View {
        NovaListHeading(title: headingOverride ?? NovaDestination.katipContracts.title, onBack: onBack) {
            if canWrite, query.company != nil {
                NovaButton(label: "Sözleşme Ekle", symbol: "plus", compact: true) { drafting = .init(startsOn: NovaDayField.text(Date())) }
            }
        }
    }

    @ViewBuilder private func counters(_ board: NovaKatipBoard) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(NovaKatipGroup.allCases) { group in
                NovaKatipStatCard(group: group, value: board.count(group),
                    isSelected: query.state == group.rawValue) {
                    query.state = query.state == group.rawValue ? nil : group.rawValue
                    Task { await load(reset: true) }
                }
            }
        }
    }

    /// Side by side, and the list opens below what was tapped.
    @ViewBuilder private var filters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.katip.filter.company", table: .localizable, fallback: "Firma"),
                    value: companies.first { $0.id == query.company }?.name ?? allCompanies,
                    isOpen: openChooser == "company",
                    identifier: "nova.katip.chooser.company") {
                    openChooser = openChooser == "company" ? nil : "company"
                }
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.katip.filter.state", table: .localizable, fallback: "Durum"),
                    value: stateTitle,
                    isOpen: openChooser == "state",
                    identifier: "nova.katip.chooser.state") {
                    openChooser = openChooser == "state" ? nil : "state"
                }
            }
            if openChooser == "company" {
                NovaFileChooserPanel(options: companyOptions, selected: query.company?.uuidString,
                    identifier: "nova.katip.panel.company") { value in
                    query.company = value.flatMap(UUID.init(uuidString:))
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            if openChooser == "state" {
                NovaFileChooserPanel(options: stateOptions, selected: query.state,
                    identifier: "nova.katip.panel.state") { value in
                    query.state = value
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            NovaAnalysisSearchField(
                text: $query.search,
                placeholder: RDLocalization.string("localizable.nova.katip.search", table: .localizable,
                    fallback: "Kurum, kapsam veya firma ara"),
                identifier: "nova.katip.search")
                .onSubmit { Task { await load(reset: true) } }
        }
    }

    private var stateTitle: String {
        guard let state = query.state else { return allStates }
        if let group = NovaKatipGroup(rawValue: state) { return group.title }
        if let value = NovaKatipState(rawValue: state) { return value.title }
        return allStates
    }
    private var companyOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allCompanies)]
            + companies.map { .init(id: $0.id.uuidString, title: $0.name) }
    }
    private var stateOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allStates)]
            + NovaKatipGroup.allCases.map {
                .init(id: $0.rawValue, title: $0.title, count: board?.count($0), symbol: $0.symbol) }
            + NovaKatipState.allCases.filter { state in !NovaKatipGroup.allCases.contains { $0.rawValue == state.rawValue } }.map {
                .init(id: $0.rawValue, title: $0.title, count: board?.counts[$0.rawValue]) }
    }

    @ViewBuilder private func list(_ board: NovaKatipBoard) -> some View {
        if board.rows.isEmpty {
            NovaEmptyState(title: RDLocalization.string("localizable.nova.katip.empty.title",
                table: .localizable, fallback: "Henüz sözleşme kaydı yok"),
                message: "İSG hizmeti sözleşmesini ekleyerek başlangıç, bitiş ve bağlı dosya bilgilerini takip edebilirsiniz.")
        } else {
            VStack(spacing: 10) {
                ForEach(board.rows) { row in
                    NovaKatipContractCard(entry: row) { Task { await openDetail(row) } }
                }
                NovaText(text: String(format: RDLocalization.string("localizable.nova.katip.count",
                    table: .localizable, fallback: "%d / %d sözleşme"), board.rows.count, board.total),
                    style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
                if board.hasMore {
                    NovaButton(label: RDLocalization.string("localizable.nova.katip.more", table: .localizable,
                        fallback: "Daha fazla göster"), symbol: "chevron.down", variant: .surface) {
                        Task { await load(reset: false) }
                    }
                }
            }
        }
    }

    // MARK: work

    private func resumePending() async {
        guard !resuming else { return }
        resuming = true
        do {
            _ = try await client.resume()
            await load(reset: true)
        } catch let error as NovaKatipFailure { failure = error.message }
        catch { failure = NovaKatipFailure.unavailable.message }
        pending = (try? client.hasPending()) ?? pending
        resuming = false
    }

    private func load(reset: Bool) async {
        if reset { query.offset = 0 } else { query.offset += query.limit }
        loading = true; failure = nil
        pending = (try? client.hasPending()) ?? pending
        do {
            if companies.isEmpty { companies = try await client.companies() }
            if query.company == nil, let initialCompany { query.company = initialCompany }
            catalogue = try await client.catalogue(query.company)
            let answer = try await client.board(query)
            if reset || board == nil { board = answer }
            else if let existing = board {
                board = .init(rows: existing.rows + answer.rows, counts: answer.counts,
                              companies: answer.companies, total: answer.total,
                              hasMore: answer.hasMore, offset: answer.offset,
                              noticeDays: answer.noticeDays)
            }
        } catch let error as NovaKatipFailure { failure = error.message }
        catch { failure = NovaKatipFailure.unavailable.message }
        loading = false
    }

    private func openDetail(_ row: NovaKatipContract) async {
        do { detail = try await client.detail(row.id) } catch { detail = row }
    }

    private func save(_ draft: NovaKatipDraft) async -> String? {
        guard let company = query.company else { return NovaKatipFailure.validation.message }
        do {
            _ = try await client.record(company, draft)
            drafting = nil
            await load(reset: true)
            return nil
        } catch let error as NovaKatipFailure { return error.message }
        catch { return NovaKatipFailure.unavailable.message }
    }

    private func finish(_ draft: NovaKatipEndDraft) async -> String? {
        guard let company = query.company else { return NovaKatipFailure.validation.message }
        do {
            _ = try await client.end(company, draft)
            ending = nil
            await load(reset: true)
            return nil
        } catch let error as NovaKatipFailure { return error.message }
        catch { return NovaKatipFailure.unavailable.message }
    }

    private func archive(_ row: NovaKatipContract) async -> String? {
        guard let company = row.companyID ?? query.company else { return NovaKatipFailure.validation.message }
        do {
            if let updated = try await client.archive(company, row.id) { detail = updated }
            await load(reset: true)
            return nil
        } catch let error as NovaKatipFailure { return error.message }
        catch { return NovaKatipFailure.unavailable.message }
    }
}

extension NovaKatipDraft: Identifiable { var id: String { (workplaceID?.uuidString ?? "new") + counterparty } }
extension NovaKatipEndDraft: Identifiable { var id: String { contractID?.uuidString ?? "new" } }
