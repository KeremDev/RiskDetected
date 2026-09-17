import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// module these closures.
struct NovaPPEClient {
    let catalogue: (UUID?) async throws -> NovaPPECatalogue
    let board: (NovaPPEQuery) async throws -> NovaPPEBoard
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    let detail: (UUID) async throws -> NovaPPEHandover
    let recordHandover: (UUID, NovaPPEHandoverDraft) async throws -> NovaPPEHandover?
    let recordReturn: (UUID, NovaPPEReturnDraft) async throws -> NovaPPEHandover?
    let removeReturn: (UUID, UUID, UUID) async throws -> NovaPPEHandover?
}

/// One counter, in the same shape the rest of the modules use.
struct NovaPPEStatCard: View {
    let state: NovaPPEState
    let value: Int
    var isSelected = false
    let onTap: () -> Void
    var body: some View {
        NovaListStat(title: state.title, symbol: state.symbol, value: value,
            isSelected: isSelected, onTap: onTap)
            .accessibilityIdentifier("nova.ppe.stat.\(state.rawValue)")
    }
}

/// One handover as a row.
struct NovaPPEHandoverCard: View {
    let handover: NovaPPEHandover
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var status: NovaStatus {
        switch handover.state {
        case .outstanding: return .warning
        case .partial: return .info
        case .closed: return .success
        }
    }

    var body: some View {
        Button(action: onTap) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: handover.item, style: .cardTitle)
                            NovaText(text: [handover.employeeName, handover.companyName]
                                .compactMap { $0 }.joined(separator: " · "), style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        Spacer(minLength: 0)
                        NovaStatusPill(label: handover.state.title, status: status)
                    }
                    NovaText(text: NovaPPEWords.explain(handover), style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                    HStack(spacing: 10) {
                        fact("shippingbox", RDLocalization.string("localizable.nova.ppe.row.handed",
                            table: .localizable, fallback: "Zimmet"),
                            NovaPPEWords.amount(handover.quantity, handover.unit))
                        fact("calendar", RDLocalization.string("localizable.nova.ppe.row.date",
                            table: .localizable, fallback: "Tarih"), handover.handedOn)
                        if let reference = handover.externalRef, !reference.isEmpty {
                            fact("number", RDLocalization.string("localizable.nova.ppe.row.ref",
                                table: .localizable, fallback: "Belge no"), reference)
                        }
                    }
                    if handover.lostQuantity > 0 {
                        NovaAnalysisTag(symbol: "questionmark.circle",
                            text: String(format: RDLocalization.string("localizable.nova.ppe.row.lost",
                                table: .localizable, fallback: "%@ kayıp olarak kaydedildi"),
                                NovaPPEWords.amount(handover.lostQuantity, handover.unit)),
                            status: .warning)
                    }
                    if handover.employeeArchived {
                        NovaAnalysisTag(symbol: "person.badge.minus",
                            text: RDLocalization.string("localizable.nova.ppe.row.archived",
                                table: .localizable, fallback: "Personel kaydı arşivlendi"),
                            status: .neutral)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nova.ppe.row.\(handover.id.uuidString)")
    }

    @ViewBuilder private func fact(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            VStack(alignment: .leading, spacing: 0) {
                NovaSizedText(text: label, size: 9, weight: "Medium",
                    color: NovaColorToken.textMuted.color(in: scheme))
                NovaSizedText(text: value, size: 11, weight: "Bold")
            }
        }
    }
}

/// The KKD Zimmetleri surface.
struct NovaPPEScreen: View {
    let client: NovaPPEClient
    let onBack: () -> Void
    var canWrite: Bool = true
    var initialCompany: UUID?
    var headingOverride: String?
    var startInAddMode = false
    var management: ((UUID, UUID) -> AnyView)?
    @State private var pendingCreate = false
    @State private var draftCompany: UUID?

    @State private var board: NovaPPEBoard?
    @State private var catalogue: NovaPPECatalogue?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var query = NovaPPEQuery()
    @State private var loading = true
    @State private var failure: String?
    @State private var openChooser: String?
    @State private var detail: NovaPPEHandover?
    @State private var handing: NovaPPEHandoverDraft?
    @State private var returning: NovaPPEReturnDraft?
    @Environment(\.colorScheme) private var scheme

    private var allCompanies: String {
        RDLocalization.string("localizable.nova.ppe.filter.companies", table: .localizable, fallback: "Tüm firmalar")
    }
    private var allStates: String {
        RDLocalization.string("localizable.nova.ppe.filter.states", table: .localizable, fallback: "Tüm durumlar")
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    NovaHelpHint(text: NovaPPEWords.signedCopyNote)
                    if let board { counters(board) }
                    filters
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
        .task {
            await load(reset: true)
            if startInAddMode && query.company != nil { startCreate() }
        }
        .novaPopup(item: $detail) { row in
            NovaPPEDetailSheet(handover: row, canWrite: canWrite,
                onReturn: {
                    detail = nil
                    returning = .init(handoverID: row.id, item: row.item, outstanding: row.outstanding,
                                      unit: row.unit, quantity: "",
                                      returnedOn: NovaDayField.text(Date()))
                },
                onRemoveReturn: { entry in await removeReturn(row, entry) },
                onClose: { detail = nil })
                .safeAreaInset(edge: .bottom) {
                    if canWrite, let company = row.companyID, let management {
                        NovaModuleManageAction(content: { management(company, row.id) }, onDone: {
                            detail = nil; Task { await load(reset: true) }
                        })
                    }
                }
        }
        .novaPopup(item: $handing) { draft in
            NovaPPEHandoverSheet(draft: draft, catalogue: catalogue,
                onSave: { edited in await save(edited) }, onClose: { handing = nil })
        }
        .novaPopup(item: $returning) { draft in
            NovaPPEReturnSheet(draft: draft, catalogue: catalogue,
                onSave: { edited in await giveBack(edited) }, onClose: { returning = nil })
        }
    }

    private var header: some View {
        NovaListHeading(title: headingOverride ?? NovaDestination.ppeHandovers.title, onBack: onBack) {
            if canWrite {
                NovaButton(label: "Zimmet Ekle", symbol: "plus", compact: true) { startCreate() }
            }
        }
    }

    @ViewBuilder private func counters(_ board: NovaPPEBoard) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                       GridItem(.flexible(), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(NovaPPEState.allCases) { state in
                NovaPPEStatCard(state: state, value: board.count(state),
                    isSelected: query.state == state.rawValue) {
                    query.state = query.state == state.rawValue ? nil : state.rawValue
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
                    label: RDLocalization.string("localizable.nova.ppe.filter.company", table: .localizable, fallback: "Firma"),
                    value: companies.first { $0.id == query.company }?.name ?? allCompanies,
                    isOpen: openChooser == "company",
                    identifier: "nova.ppe.chooser.company") {
                    openChooser = openChooser == "company" ? nil : "company"
                }
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.ppe.filter.state", table: .localizable, fallback: "Durum"),
                    value: query.state.flatMap { NovaPPEState(rawValue: $0)?.title } ?? allStates,
                    isOpen: openChooser == "state",
                    identifier: "nova.ppe.chooser.state") {
                    openChooser = openChooser == "state" ? nil : "state"
                }
            }
            if openChooser == "company" {
                NovaFileChooserPanel(options: companyOptions, selected: query.company?.uuidString,
                    identifier: "nova.ppe.panel.company") { value in
                    query.company = value.flatMap(UUID.init(uuidString:))
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            if openChooser == "state" {
                NovaFileChooserPanel(options: stateOptions, selected: query.state,
                    identifier: "nova.ppe.panel.state") { value in
                    query.state = value
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            NovaAnalysisSearchField(
                text: $query.search,
                placeholder: RDLocalization.string("localizable.nova.ppe.search", table: .localizable,
                    fallback: "Ekipman, kişi veya firma ara"),
                identifier: "nova.ppe.search")
                .onSubmit { Task { await load(reset: true) } }
        }
    }

    private var companyOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allCompanies)]
            + companies.map { .init(id: $0.id.uuidString, title: $0.name) }
    }
    private var stateOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allStates)]
            + NovaPPEState.allCases.map {
                .init(id: $0.rawValue, title: $0.title, count: board?.count($0), symbol: $0.symbol) }
    }

    @ViewBuilder private func list(_ board: NovaPPEBoard) -> some View {
        if board.rows.isEmpty {
            NovaEmptyState(title: RDLocalization.string("localizable.nova.ppe.empty.title",
                table: .localizable, fallback: "Henüz zimmet kaydı yok"),
                message: "Firma personeline verilen kişisel koruyucu donanımı kaydedebilir ve zimmet formunu oluşturabilirsiniz.")
        } else {
            VStack(spacing: 10) {
                ForEach(board.rows) { row in
                    NovaPPEHandoverCard(handover: row) { Task { await openDetail(row) } }
                }
                NovaText(text: String(format: RDLocalization.string("localizable.nova.ppe.count",
                    table: .localizable, fallback: "%d / %d zimmet"), board.rows.count, board.total),
                    style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
                if board.hasMore {
                    NovaButton(label: RDLocalization.string("localizable.nova.ppe.more", table: .localizable,
                        fallback: "Daha fazla göster"), symbol: "chevron.down", variant: .surface) {
                        Task { await load(reset: false) }
                    }
                }
            }
        }
    }

    // MARK: work

    private func startCreate() {
        draftCompany = query.company
        if query.company == nil { pendingCreate = true; openChooser = "company" }
        else { handing = .init(handedOn: NovaDayField.text(Date())) }
    }

    private func load(reset: Bool) async {
        if reset { query.offset = 0 } else { query.offset += query.limit }
        loading = true; failure = nil
        do {
            if companies.isEmpty { companies = try await client.companies() }
            if query.company == nil, let initialCompany { query.company = initialCompany }
            catalogue = try await client.catalogue(query.company)
            if pendingCreate, query.company != nil { pendingCreate = false; draftCompany = query.company; handing = .init(handedOn: NovaDayField.text(Date())) }
            let answer = try await client.board(query)
            if reset || board == nil { board = answer }
            else if let existing = board {
                board = .init(rows: existing.rows + answer.rows, counts: answer.counts,
                              companies: answer.companies, total: answer.total,
                              hasMore: answer.hasMore, offset: answer.offset)
            }
        } catch let error as NovaPPEFailure { failure = error.message }
        catch { failure = NovaPPEFailure.unavailable.message }
        loading = false
    }

    private func openDetail(_ row: NovaPPEHandover) async {
        draftCompany = row.companyID
        do {
            catalogue = try await client.catalogue(row.companyID)
            detail = try await client.detail(row.id)
        } catch { failure = "Kayıt açılamadı. Yeniden deneyin." }
    }

    private func save(_ draft: NovaPPEHandoverDraft) async -> String? {
        guard let company = draftCompany ?? query.company else { return NovaPPEFailure.validation.message }
        do {
            _ = try await client.recordHandover(company, draft)
            handing = nil
            await load(reset: true)
            return nil
        } catch let error as NovaPPEFailure { return error.message }
        catch { return NovaPPEFailure.unavailable.message }
    }

    private func giveBack(_ draft: NovaPPEReturnDraft) async -> String? {
        guard let company = draftCompany ?? query.company else { return NovaPPEFailure.validation.message }
        do {
            _ = try await client.recordReturn(company, draft)
            returning = nil
            await load(reset: true)
            return nil
        } catch let error as NovaPPEFailure { return error.message }
        catch { return NovaPPEFailure.unavailable.message }
    }

    private func removeReturn(_ row: NovaPPEHandover, _ entry: UUID) async -> String? {
        guard let company = row.companyID ?? query.company else { return NovaPPEFailure.validation.message }
        do {
            if let updated = try await client.removeReturn(company, row.id, entry) { detail = updated }
            await load(reset: true)
            return nil
        } catch let error as NovaPPEFailure { return error.message }
        catch { return NovaPPEFailure.unavailable.message }
    }
}

extension NovaPPEHandoverDraft: Identifiable { var id: String { (employeeID?.uuidString ?? "new") + item } }
extension NovaPPEReturnDraft: Identifiable { var id: String { handoverID?.uuidString ?? "new" } }
