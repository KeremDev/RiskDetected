import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// module these closures.
struct NovaRiskClient {
    /// The workplaces, the rules a period may be attributed to and the warning
    /// window the server owns.
    let catalogue: (UUID?) async throws -> NovaRiskCatalogue
    /// The whole account in one answer: the tally, the per-company summary and
    /// one page of rows.
    let board: (NovaRiskQuery) async throws -> NovaRiskBoard
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    let detail: (UUID) async throws -> NovaRiskRow
    let open: (UUID, UUID) async throws -> NovaRiskRow?
    let draft: (UUID, NovaRiskVersionDraft) async throws -> NovaRiskRow?
    let finalize: (UUID, NovaRiskFinalizeDraft) async throws -> NovaRiskRow?
}

/// One counter, in the same shape the rest of the modules use.
struct NovaRiskStatCard: View {
    let group: NovaRiskGroup
    let value: Int
    var isSelected = false
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var tone: NovaColorToken {
        switch group {
        case .expired: return .statusDangerInk
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10).padding(.horizontal, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NovaColorToken.surface.color(in: scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? tone.color(in: scheme)
                                : NovaColorToken.hairline.color(in: scheme),
                                lineWidth: isSelected ? 1.6 : 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nova.risk.stat.\(group.rawValue)")
    }
}

/// One workplace's record as a row. The state and its reason come from the
/// server; nothing here decides what a date means.
struct NovaRiskRowCard: View {
    let row: NovaRiskRow
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var status: NovaStatus {
        switch row.group {
        case .expired: return .danger
        case .untracked: return .warning
        case .dueSoon: return .info
        case .current: return .success
        }
    }

    var body: some View {
        Button(action: onTap) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: row.workplaceName ?? RDLocalization.string(
                                "localizable.nova.risk.row.workplace", table: .localizable, fallback: "İşyeri"),
                                style: .cardTitle)
                            if let company = row.companyName {
                                NovaText(text: company, style: .meta,
                                    color: NovaColorToken.textSecondary.color(in: scheme))
                            }
                        }
                        Spacer(minLength: 0)
                        NovaStatusPill(label: NovaRiskWords.state(row.state), status: status)
                    }
                    NovaText(text: NovaRiskWords.explain(row), style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                    HStack(spacing: 10) {
                        if let until = row.validUntil {
                            fact("calendar", RDLocalization.string("localizable.nova.risk.row.until",
                                table: .localizable, fallback: "Geçerlilik"), until)
                        }
                        if let years = row.periodYears {
                            fact("clock.arrow.circlepath", RDLocalization.string("localizable.nova.risk.row.period",
                                table: .localizable, fallback: "Süre"),
                                String(format: RDLocalization.string("localizable.nova.risk.row.years",
                                    table: .localizable, fallback: "%d yıl"), years))
                        }
                        if row.currentVersion > 0 {
                            fact("number", RDLocalization.string("localizable.nova.risk.row.version",
                                table: .localizable, fallback: "Sürüm"), "v\(row.currentVersion)")
                        }
                    }
                    // Everything that needs the expert's eye, said plainly and
                    // never folded into the state pill.
                    VStack(alignment: .leading, spacing: 4) {
                        if let source = row.periodSource {
                            NovaAnalysisTag(symbol: source.needsReview ? "exclamationmark.circle" : "checkmark.seal",
                                text: source.title, status: source.needsReview ? .warning : .success)
                        }
                        if row.hasOpenDraft {
                            NovaAnalysisTag(symbol: "pencil.line",
                                text: RDLocalization.string("localizable.nova.risk.row.draft",
                                    table: .localizable, fallback: "Açık taslak var"), status: .info)
                        }
                        if row.sourceDrift {
                            NovaAnalysisTag(symbol: "arrow.triangle.branch",
                                text: RDLocalization.string("localizable.nova.risk.row.drift",
                                    table: .localizable, fallback: "Kaynak analiz değişti"), status: .warning)
                        }
                        if row.dateNeedsReview {
                            NovaAnalysisTag(symbol: "calendar.badge.exclamationmark",
                                text: RDLocalization.string("localizable.nova.risk.row.olddate",
                                    table: .localizable, fallback: "Tarih çok eski · gözden geçirin"), status: .warning)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nova.risk.row.\(row.id.uuidString)")
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

/// The Risk Değerlendirmesi surface. The page answers the whole account in one
/// read and narrows to one company only when the expert asks it to.
struct NovaRiskScreen: View {
    let client: NovaRiskClient
    let onBack: () -> Void
    var canWrite: Bool = true
    var initialCompany: UUID?
    var headingOverride: String?

    @State private var board: NovaRiskBoard?
    @State private var catalogue: NovaRiskCatalogue?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var query = NovaRiskQuery()
    @State private var loading = true
    @State private var failure: String?
    @State private var openChooser: String?
    @State private var detail: NovaRiskRow?
    @State private var newVersion: NovaRiskVersionDraft?
    @State private var finalizing: NovaRiskFinalizeDraft?
    @State private var opening = false
    @Environment(\.colorScheme) private var scheme

    private var allCompanies: String {
        RDLocalization.string("localizable.nova.risk.filter.companies", table: .localizable, fallback: "Tüm firmalar")
    }
    private var allStates: String {
        RDLocalization.string("localizable.nova.risk.filter.states", table: .localizable, fallback: "Tüm durumlar")
    }

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
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
        .task { await load(reset: true) }
        .sheet(item: $detail) { row in
            NovaRiskDetailSheet(row: row, canWrite: canWrite,
                onNewVersion: { start(from: row) },
                onFinalize: { version in
                    finalizing = .init(assessmentID: row.id, version: version,
                                       expectedCurrent: row.currentVersion)
                },
                onClose: { detail = nil })
        }
        .sheet(item: $newVersion) { draft in
            NovaRiskVersionSheet(draft: draft, catalogue: catalogue,
                onSave: { edited in await save(edited) }, onClose: { newVersion = nil })
        }
        .sheet(item: $finalizing) { draft in
            NovaRiskFinalizeSheet(draft: draft, catalogue: catalogue,
                onSave: { edited in await confirm(edited) }, onClose: { finalizing = nil })
        }
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                NovaButton(label: RDLocalization.string("localizable.nova.risk.back", table: .localizable, fallback: "Geri"),
                    symbol: "chevron.left", variant: .surface, action: onBack)
                Spacer(minLength: 0)
            }
            NovaText(text: headingOverride ?? NovaDestination.riskAssessments.title, style: .screenTitle)
            // Said once, at the top, rather than implied by a colour.
            NovaText(text: NovaRiskWords.periodAttribution, style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
        }
    }

    @ViewBuilder private func counters(_ board: NovaRiskBoard) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(NovaRiskGroup.allCases) { group in
                NovaRiskStatCard(group: group, value: board.count(group),
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
                    label: RDLocalization.string("localizable.nova.risk.filter.company", table: .localizable, fallback: "Firma"),
                    value: companies.first { $0.id == query.company }?.name ?? allCompanies,
                    isOpen: openChooser == "company",
                    identifier: "nova.risk.chooser.company") {
                    openChooser = openChooser == "company" ? nil : "company"
                }
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.risk.filter.state", table: .localizable, fallback: "Durum"),
                    value: stateTitle,
                    isOpen: openChooser == "state",
                    identifier: "nova.risk.chooser.state") {
                    openChooser = openChooser == "state" ? nil : "state"
                }
            }
            if openChooser == "company" {
                NovaFileChooserPanel(options: companyOptions, selected: query.company?.uuidString,
                    identifier: "nova.risk.panel.company") { value in
                    query.company = value.flatMap(UUID.init(uuidString:))
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            if openChooser == "state" {
                NovaFileChooserPanel(options: stateOptions, selected: query.state,
                    identifier: "nova.risk.panel.state") { value in
                    query.state = value
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            NovaAnalysisSearchField(
                text: $query.search,
                placeholder: RDLocalization.string("localizable.nova.risk.search", table: .localizable,
                    fallback: "İşyeri veya firma ara"),
                identifier: "nova.risk.search")
                .onSubmit { Task { await load(reset: true) } }
        }
    }

    private var stateTitle: String {
        guard let state = query.state else { return allStates }
        if let group = NovaRiskGroup(rawValue: state) { return group.title }
        if let value = NovaRiskState(rawValue: state) { return NovaRiskWords.state(value) }
        return allStates
    }
    private var companyOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allCompanies)]
            + companies.map { .init(id: $0.id.uuidString, title: $0.name) }
    }
    /// The four counters, then the five exact states, so a counter and the
    /// filter behind it are the same word the server accepts.
    private var stateOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allStates)]
            + NovaRiskGroup.allCases.map {
                .init(id: $0.rawValue, title: $0.title, count: board?.count($0), symbol: $0.symbol) }
            + NovaRiskState.allCases.map {
                .init(id: $0.rawValue, title: NovaRiskWords.state($0), count: board?.counts[$0.rawValue]) }
    }

    @ViewBuilder private func list(_ board: NovaRiskBoard) -> some View {
        if board.rows.isEmpty {
            NovaCard(padding: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    NovaText(text: RDLocalization.string("localizable.nova.risk.empty.title", table: .localizable,
                        fallback: "Kayıt yok"), style: .cardTitle)
                    NovaText(text: RDLocalization.string("localizable.nova.risk.empty.body", table: .localizable,
                        fallback: "Bir işyeri seçip risk değerlendirmesi kaydını başlatın."),
                        style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(board.rows) { row in
                    NovaRiskRowCard(row: row) { Task { await openDetail(row) } }
                }
                NovaText(text: String(format: RDLocalization.string("localizable.nova.risk.count",
                    table: .localizable, fallback: "%d / %d kayıt"), board.rows.count, board.total),
                    style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
                if board.hasMore {
                    NovaButton(label: RDLocalization.string("localizable.nova.risk.more", table: .localizable,
                        fallback: "Daha fazla göster"), symbol: "chevron.down", variant: .surface) {
                        Task { await load(reset: false) }
                    }
                }
            }
        }
        if canWrite, let catalogue, !catalogue.workplaces.isEmpty, query.company != nil {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: RDLocalization.string("localizable.nova.risk.start.title", table: .localizable,
                        fallback: "Kayıt başlat"), style: .cardTitle)
                    NovaText(text: RDLocalization.string("localizable.nova.risk.start.body", table: .localizable,
                        fallback: "Takibi olmayan bir işyeri için kaydı açın. Açmak belge oluşturmaz."),
                        style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                    ForEach(catalogue.workplaces) { workplace in
                        NovaButton(label: workplace.name, symbol: "plus.circle", variant: .surface) {
                            Task { await start(workplace: workplace.id) }
                        }
                        .disabled(opening)
                    }
                }
            }
        }
    }

    // MARK: work

    private func load(reset: Bool) async {
        if reset { query.offset = 0 } else { query.offset += query.limit }
        loading = true; failure = nil
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
        } catch let error as NovaRiskFailure {
            failure = error.message
        } catch {
            failure = NovaRiskFailure.unavailable.message
        }
        loading = false
    }

    private func openDetail(_ row: NovaRiskRow) async {
        do { detail = try await client.detail(row.id) }
        catch { detail = row }
    }

    private func start(workplace: UUID) async {
        guard let company = query.company else { return }
        opening = true; failure = nil
        do {
            _ = try await client.open(company, workplace)
            await load(reset: true)
        } catch let error as NovaRiskFailure { failure = error.message }
        catch { failure = NovaRiskFailure.unavailable.message }
        opening = false
    }

    private func start(from row: NovaRiskRow) {
        detail = nil
        newVersion = .init(assessmentID: row.id, kind: .full,
                           assessmentOn: NovaDayField.text(Date()),
                           expectedCurrent: row.currentVersion)
    }

    private func save(_ draft: NovaRiskVersionDraft) async -> String? {
        guard let company = query.company ?? board?.rows.first(where: { $0.id == draft.assessmentID })?.companyID
        else { return NovaRiskFailure.validation.message }
        do {
            _ = try await client.draft(company, draft)
            newVersion = nil
            await load(reset: true)
            return nil
        } catch let error as NovaRiskFailure { return error.message }
        catch { return NovaRiskFailure.unavailable.message }
    }

    private func confirm(_ draft: NovaRiskFinalizeDraft) async -> String? {
        guard let company = query.company ?? board?.rows.first(where: { $0.id == draft.assessmentID })?.companyID
        else { return NovaRiskFailure.validation.message }
        do {
            _ = try await client.finalize(company, draft)
            finalizing = nil
            await load(reset: true)
            return nil
        } catch let error as NovaRiskFailure { return error.message }
        catch { return NovaRiskFailure.unavailable.message }
    }
}

extension NovaRiskVersionDraft: Identifiable { var id: String { (assessmentID?.uuidString ?? "") + kind.rawValue } }
extension NovaRiskFinalizeDraft: Identifiable { var id: String { (assessmentID?.uuidString ?? "") + "\(version)" } }
