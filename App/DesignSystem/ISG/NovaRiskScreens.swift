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
    var cancelDraft: (UUID, NovaRiskRow, NovaRiskVersion, String) async throws -> NovaRiskRow? = { _,_,_,_ in throw NovaRiskFailure.unavailable }
    let fileClient: NovaFileLibraryClient
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
                        .foregroundStyle(NovaColorToken.text.color(in: scheme))
                    NovaText(text: "\(value)", style: .cardTitle)
                }
                NovaText(text: group.title, style: .meta)
                    .lineLimit(2).minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
                NovaText(text: group.footer, style: .micro,
                    color: value > 0 ? tone.color(in: scheme) : nil)
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
    /// False when the shell's own top bar already shows a back chevron for
    /// this screen (reached by navigating from home) — a second one here
    /// would only duplicate it. True (the default) is for a context with no
    /// shell chrome at all, such as the company-management cover, where this
    /// is the only way back.
    var showBackButton = true
    /// Opened from the company page's own empty-state "Ekle" action.
    var startInAddMode = false

    @State private var board: NovaRiskBoard?
    @State private var catalogue: NovaRiskCatalogue?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var query = NovaRiskQuery()
    @State private var loading = true
    @State private var failure: String?
    @State private var openChooser: String?
    @State private var detail: NovaRiskRow?
    @State private var newVersion: NovaRiskVersionDraft?
    @State private var cancelling: NovaRiskRow?
    @State private var finalizing: NovaRiskFinalizeDraft?
    @State private var opening = false
    @State private var creating = false
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
        .onAppear { if startInAddMode && canWrite { creating = true } }
        .sheet(isPresented: $creating, onDismiss: { Task { await load(reset: true) } }) {
            NovaCompanyCreateFlow(title: "Risk değerlendirmesi kaydı", companies: client.companies, catalogue: { co in try await client.catalogue(co) }, onSelect: { _ in }, fixedCompany: initialCompany) { catalogue, co in
                NovaRiskQuickCreateSheet(client: client, company: co, catalogue: catalogue) { creating = false }
            }
        }
        .sheet(item: $detail) { row in
            NovaRiskDetailSheet(row: row, canWrite: canWrite,
                onNewVersion: { start(from: row) },
                onEdit: { version in
                    detail = nil
                    newVersion = .init(assessmentID: row.id, kind: version.kind, assessmentOn: version.assessmentOn, revisionOn: version.revisionOn ?? "", scope: version.scope, reason: version.reason ?? "", expectedCurrent: row.currentVersion, versionToEdit: version.version, editRevision: version.editRevision)
                },
                onCancelDraft: { detail = nil; cancelling = row },
                onFinalize: { version in
                    detail = nil
                    let suggested = row.workplaceSuggestedPeriodYears
                    finalizing = .init(assessmentID: row.id, version: version,
                                       expectedCurrent: row.currentVersion,
                                       periodYears: suggested.map(String.init) ?? "",
                                       kind: row.draftKind ?? .full, editRevision: row.versions.first(where: { $0.version == version })?.editRevision ?? 0,
                                       suggestedYears: suggested)
                },
                onClose: { detail = nil })
        }
        .sheet(item: $newVersion) { draft in
            NovaRiskVersionSheet(draft: draft, catalogue: catalogue,
                onSave: { edited in await save(edited) }, onClose: { newVersion = nil })
        }
        .sheet(item: $cancelling) { row in
            NovaRiskCancelDraftSheet { reason in
                guard let company = row.companyID, let version = row.versions.first(where: { $0.isDraft }) else { return NovaRiskFailure.validation.message }
                do { _ = try await client.cancelDraft(company, row, version, reason); cancelling = nil; await load(reset: true); return nil }
                catch let error as NovaRiskFailure { return error.message }
                catch { return NovaRiskFailure.unavailable.message }
            }
        }
        .sheet(item: $finalizing) { draft in
            NovaRiskFinalizeSheet(draft: draft, catalogue: catalogue,
                onSave: { edited in await confirm(edited) }, onClose: { finalizing = nil })
        }
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if showBackButton { NovaBackButton(action: onBack) }
                NovaText(text: headingOverride ?? NovaDestination.riskAssessments.title, style: .screenTitle)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                NovaButton(label: "Kayıt ekle", symbol: "plus", isEnabled: canWrite) { creating = true }
            }
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
    }

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


/// One page: pick the workplace (skipped when there is only one), answer a
/// quick "new or revise" question only when a prior assessment exists, fill
/// in the date/period/file, save. No separate "taslak" step to come back to —
/// draft and finalize happen back to back, behind one button and one spinner.
private struct NovaRiskQuickCreateSheet: View {
    let client: NovaRiskClient
    let company: UUID
    let catalogue: NovaRiskCatalogue
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    @State private var workplaceID: UUID?
    @State private var row: NovaRiskRow?
    @State private var opening = false
    @State private var openError: String?
    @State private var kindChosen = false
    @State private var kind: NovaRiskKind = .full
    @State private var assessmentOn = NovaDayField.text(Date())
    @State private var periodYears = ""
    @State private var scope: [String] = []
    @State private var scopeEntry = ""
    @State private var reason = ""
    @State private var assetID = ""
    @State private var saving = false
    @State private var saveError: String?

    private var workplaces: [NovaRiskCatalogue.Workplace] { catalogue.workplaces }
    private var suggestedYears: Int? { workplaces.first { $0.id == workplaceID }?.suggestedPeriodYears }
    private var hasOpenDraft: Bool { row?.hasOpenDraft ?? false }
    private var canSave: Bool {
        guard row != nil, !saving else { return false }
        if hasOpenDraft { return true }
        if kind.needsScope && scope.isEmpty { return false }
        if kind.needsReason && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaText(text: RDLocalization.string("localizable.nova.risk.quick.title", table: .localizable,
                fallback: "Risk değerlendirmesi"), style: .screenTitle)
            if workplaces.isEmpty {
                NovaText(text: RDLocalization.string("localizable.nova.risk.quick.noworkplace", table: .localizable,
                    fallback: "Önce firma bilgilerinden işyeri ekleyin."), style: .body)
            } else if workplaceID == nil, workplaces.count > 1 {
                workplacePicker
            } else if let openError {
                NovaText(text: openError, style: .meta, color: NovaColorToken.statusDangerInk.color(in: scheme))
                NovaButton(label: RDLocalization.string("localizable.nova.risk.quick.retry", table: .localizable,
                    fallback: "Tekrar dene"), symbol: "arrow.clockwise", variant: .surface) { Task { await open() } }
            } else if opening || row == nil {
                ProgressView(RDLocalization.string("localizable.nova.risk.quick.opening", table: .localizable,
                    fallback: "Kayıt açılıyor…"))
            } else if row!.currentVersion > 0, !hasOpenDraft, !kindChosen {
                kindChooser
            } else {
                form
            }
            if let saveError {
                NovaText(text: saveError, style: .meta, color: NovaColorToken.statusDangerInk.color(in: scheme))
            }
        }
        .novaPopupContentSize()
        .preference(key: NovaPopupBusyKey.self, value: opening || saving)
        .task {
            if workplaces.count == 1 { workplaceID = workplaces[0].id }
        }
        .onChange(of: workplaceID) { _ in Task { await open() } }
    }

    private var workplacePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.risk.quick.pickworkplace", table: .localizable,
                fallback: "İşyeri seçin"), style: .cardTitle)
            ForEach(workplaces) { workplace in
                Button(workplace.name) { workplaceID = workplace.id }
                    .accessibilityIdentifier("risk.quick.workplace.\(workplace.id.uuidString.lowercased())")
            }
        }
    }

    private var kindChooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaText(text: RDLocalization.string("localizable.nova.risk.quick.priorexists", table: .localizable,
                fallback: "Bu işyeri için daha önce tamamlanmış bir değerlendirme var."), style: .body)
            HStack(spacing: 10) {
                NovaButton(label: RDLocalization.string("localizable.nova.risk.quick.new", table: .localizable,
                    fallback: "Yeni değerlendirme"), symbol: "doc.badge.plus", variant: .surface) {
                    kind = .full; primeSuggestedPeriod(); kindChosen = true
                }.accessibilityIdentifier("risk.quick.kind.new")
                NovaButton(label: RDLocalization.string("localizable.nova.risk.quick.revise", table: .localizable,
                    fallback: "Revize et"), symbol: "pencil", variant: .primary) {
                    kind = .partial; kindChosen = true
                }.accessibilityIdentifier("risk.quick.kind.revise")
            }
        }
    }

    @ViewBuilder private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasOpenDraft {
                NovaHelpHint(text: RDLocalization.string("localizable.nova.risk.quick.draftexists", table: .localizable,
                    fallback: "Bu işyerinde açık bir taslak var. Aşağıdaki bilgilerle tamamlayabilirsiniz."))
            } else {
                if kind.carriesAssessmentDate {
                    NovaDayField(label: RDLocalization.string("localizable.nova.risk.fact.assessment",
                        table: .localizable, fallback: "Değerlendirme tarihi"),
                        value: $assessmentOn, identifier: "risk.quick.date")
                } else {
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.risk.version.keepdate", table: .localizable,
                        fallback: "Bu tür, belgenin özgün değerlendirme tarihini korur."))
                }
                if kind.needsScope { scopeField }
                if kind.needsReason {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.risk.version.reason",
                            table: .localizable, fallback: "Gerekçe"), style: .label)
                        TextEditor(text: $reason).frame(minHeight: 70)
                            .accessibilityIdentifier("risk.quick.reason")
                    }
                }
                if kind == .full {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.risk.finalize.years",
                            table: .localizable, fallback: "Geçerlilik süresi (yıl)"), style: .label)
                        TextField("", text: $periodYears).keyboardType(.numberPad)
                            .accessibilityIdentifier("risk.quick.years")
                    }
                    if let years = suggestedYears {
                        NovaHelpHint(text: String(format: RDLocalization.string("localizable.nova.risk.finalize.hazard.hint",
                            table: .localizable,
                            fallback: "İşyerinin tehlike sınıfına göre %d yıl otomatik dolduruldu. Gerekirse değiştirebilirsiniz."), years))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    NovaText(text: RDLocalization.string("localizable.nova.risk.quick.file", table: .localizable,
                        fallback: "Dosya"), style: .label)
                    NovaInlineFileField(category: "risk_assessment", company: company,
                        fileClient: client.fileClient, assetID: $assetID)
                }
            }
            HStack(spacing: 10) {
                NovaButton(label: RDLocalization.string("localizable.nova.risk.cancel", table: .localizable,
                    fallback: "Vazgeç"), symbol: "xmark", variant: .surface, action: onClose).disabled(saving)
                NovaButton(label: saving
                    ? RDLocalization.string("localizable.nova.risk.quick.saving", table: .localizable, fallback: "Kaydediliyor…")
                    : RDLocalization.string("localizable.nova.risk.quick.save", table: .localizable, fallback: "Kaydet"),
                    symbol: "checkmark.seal", variant: .primary, isEnabled: canSave) { Task { await save() } }
                    .accessibilityIdentifier("risk.quick.save")
            }
        }
    }

    private var scopeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: RDLocalization.string("localizable.nova.risk.scope", table: .localizable,
                fallback: "Kapsam"), style: .label)
            HStack(spacing: 8) {
                TextField(RDLocalization.string("localizable.nova.risk.scope.add", table: .localizable,
                    fallback: "Bölüm adı"), text: $scopeEntry)
                    .accessibilityIdentifier("risk.quick.scope.entry")
                NovaButton(label: RDLocalization.string("localizable.nova.risk.scope.button", table: .localizable,
                    fallback: "Ekle"), symbol: "plus", variant: .surface) {
                    let value = scopeEntry.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, scope.count < 50 else { return }
                    scope.append(value); scopeEntry = ""
                }
            }
            ForEach(scope, id: \.self) { entry in
                HStack(spacing: 6) {
                    NovaAnalysisTag(symbol: "square.dashed", text: entry, status: .info)
                    Button { scope.removeAll { $0 == entry } } label: {
                        Image(systemName: "xmark.circle").font(.system(size: 12))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func primeSuggestedPeriod() {
        guard periodYears.isEmpty, let years = suggestedYears else { return }
        periodYears = String(years)
    }

    private func open() async {
        guard let workplaceID else { return }
        opening = true; openError = nil
        defer { opening = false }
        do {
            let opened = try await client.open(company, workplaceID)
            row = opened
            if let draft = opened?.versions.first(where: { $0.isDraft }) {
                kind = draft.kind; assessmentOn = draft.assessmentOn
                scope = draft.scope; reason = draft.reason ?? ""
                kindChosen = true
            } else if (opened?.currentVersion ?? 0) == 0 {
                kind = .full; primeSuggestedPeriod(); kindChosen = true
            }
        } catch let e as NovaRiskFailure { openError = e.message }
        catch { openError = NovaRiskFailure.unavailable.message }
    }

    private func save() async {
        guard let row else { return }
        saving = true; saveError = nil
        defer { saving = false }
        do {
            var afterDraft = row
            if !hasOpenDraft {
                var draft = NovaRiskVersionDraft(assessmentID: row.id, kind: kind,
                    assessmentOn: kind.carriesAssessmentDate ? assessmentOn : "",
                    scope: scope, reason: reason, expectedCurrent: row.currentVersion)
                if let asset = UUID(uuidString: assetID) { draft.fileAssetID = asset }
                guard let updated = try await client.draft(company, draft) else {
                    saveError = NovaRiskFailure.unavailable.message; return
                }
                afterDraft = updated
            }
            guard let draftVersion = afterDraft.versions.first(where: { $0.isDraft }) else {
                saveError = NovaRiskFailure.unavailable.message; return
            }
            var finalize = NovaRiskFinalizeDraft(assessmentID: row.id, version: draftVersion.version,
                expectedCurrent: afterDraft.currentVersion, kind: draftVersion.kind,
                editRevision: draftVersion.editRevision)
            if draftVersion.kind == .full { finalize.periodYears = periodYears }
            _ = try await client.finalize(company, finalize)
            onClose()
        } catch let e as NovaRiskFailure { saveError = e.message }
        catch { saveError = NovaRiskFailure.unavailable.message }
    }
}
