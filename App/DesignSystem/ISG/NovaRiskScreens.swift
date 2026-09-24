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

    private var statusInk: Color {
        switch group {
        case .expired: return NovaColorToken.statusDangerInk.color(in: scheme)
        case .untracked: return NovaColorToken.statusNeutralInk.color(in: scheme)
        case .dueSoon: return NovaColorToken.statusWarningInk.color(in: scheme)
        case .current: return NovaColorToken.statusSuccessInk.color(in: scheme)
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: group.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(statusInk)
                    Text(verbatim: String(value))
                        .font(.custom("PlusJakartaSans-SemiBold", size: 19, relativeTo: .body))
                        .foregroundStyle(NovaColorToken.text.color(in: scheme))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Text(verbatim: group.title)
                    .font(.custom("PlusJakartaSans-Medium", size: 11, relativeTo: .caption))
                    .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    .lineLimit(2).minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 5).padding(.vertical, 4)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15)
                .strokeBorder(isSelected ? Color(red: 11.0 / 255, green: 47.0 / 255, blue: 83.0 / 255).opacity(0.62) : NovaColorToken.border.color(in: scheme), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityLabel("\(group.title), \(value)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("nova.risk.stat.\(group.rawValue)")
    }
}

/// One workplace's record as a row. The state and its reason come from the
/// server; nothing here decides what a date means.
struct NovaRiskRowCard: View {
    let row: NovaRiskRow
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var statusDot: Color {
        switch row.group {
        case .expired: return NovaColorToken.statusDangerDot.color(in: scheme)
        case .untracked: return NovaColorToken.statusNeutralDot.color(in: scheme)
        case .dueSoon: return NovaColorToken.statusWarningDot.color(in: scheme)
        case .current: return NovaColorToken.statusSuccessDot.color(in: scheme)
        }
    }

    var body: some View {
        Button(action: onTap) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: row.companyName ?? row.workplaceName ?? "İşyeri", style: .cardTitle)
                                .fixedSize(horizontal: false, vertical: true)
                            if let workplace = row.workplaceName,
                               workplace.localizedStandardCompare(row.companyName ?? "") != .orderedSame {
                                NovaText(text: workplace, style: .metaQuiet)
                            }
                        }
                        Spacer(minLength: 0)
                        Circle()
                            .fill(statusDot)
                            .frame(width: 8, height: 8)
                            .accessibilityElement()
                            .accessibilityLabel(Text(verbatim: NovaRiskWords.state(row.state)))
                    }
                    HStack(spacing: 10) {
                        if let until = row.validUntil {
                            fact("calendar", RDLocalization.string("localizable.nova.risk.row.until",
                                table: .localizable, fallback: "Geçerlilik"), NovaStatisticsSnapshot.dayLabel(until))
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
        .buttonStyle(NovaRowPressStyle())
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
    /// Kept for source compatibility; list headings always provide back navigation.
    var showBackButton = true
    /// Opened from the company page's own empty-state "Ekle" action.
    var startInAddMode = false

    @Environment(\.dynamicTypeSize) private var typeSize
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
        // Opened straight into "add": skip mounting the whole board behind a
        // second sheet — the create flow itself, alone, is the entire cover,
        // so it blurs the real company page behind it instead of an empty
        // intermediate screen. See NovaPopup's own doc comment.
        if startInAddMode {
            addFlow
        } else {
            NovaPageSurface(onEdgeBack: onBack) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        NovaHelpHint(text: RDLocalization.format("localizable.nova.risk.screens.firmanin.risk.analizini.kapsamini.ve.dosyasini.k.6fbda573", table: .localizable, fallback: "Firmanın risk analizini, kapsamını ve dosyasını kaydedin; güncel sürümünü takip edin. %1$@", arguments: [String(describing: NovaRiskWords.periodAttribution)]))
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
            .novaFullScreenCover(isPresented: $creating, onDismiss: { Task { await load(reset: true) } }) { addFlow }
            .novaPopup(item: $detail) { row in
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
        .novaPopup(item: $newVersion) { draft in
            NovaRiskVersionSheet(draft: draft, catalogue: catalogue,
                onSave: { edited in await save(edited) }, onClose: { newVersion = nil })
        }
        .novaPopup(item: $cancelling) { row in
            NovaRiskCancelDraftSheet { reason in
                guard let company = row.companyID, let version = row.versions.first(where: { $0.isDraft }) else { return NovaRiskFailure.validation.message }
                do { _ = try await client.cancelDraft(company, row, version, reason); cancelling = nil; await load(reset: true); return nil }
                catch let error as NovaRiskFailure { return error.message }
                catch { return NovaRiskFailure.unavailable.message }
            }
        }
        .novaPopup(item: $finalizing) { draft in
            NovaRiskFinalizeSheet(draft: draft, catalogue: catalogue,
                onSave: { edited in await confirm(edited) }, onClose: { finalizing = nil })
        }
        }
    }
    private var addFlow: some View {
        NovaCompanyCreateFlow(title: RDLocalization.string("localizable.nova.risk.screens.risk.degerlendirmesi.ekle.828b54b4", table: .localizable, fallback: "Risk değerlendirmesi ekle"), companies: client.companies, catalogue: { co in try await client.catalogue(co) }, onSelect: { _ in }, fixedCompany: initialCompany, fullScreenTask: true,
            onClose: { if startInAddMode { onBack() } else { creating = false } }) { catalogue, co in
            NovaRiskQuickCreateSheet(client: client, company: co, catalogue: catalogue) {
                if startInAddMode { onBack() } else { creating = false }
            }
        }
    }

    private var header: some View {
        NovaListHeading(title: headingOverride ?? NovaDestination.riskAssessments.title, onBack: onBack) {
            if canWrite {
                NovaButton(label: RDLocalization.string("localizable.nova.risk.screens.kayit.ekle.b9721dfb", table: .localizable, fallback: "Kayıt Ekle"), symbol: "plus", compact: true) { creating = true }
            }
        }
    }

    @ViewBuilder private func counters(_ board: NovaRiskBoard) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4)
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
            + NovaRiskState.allCases.filter { state in !NovaRiskGroup.allCases.contains { $0.rawValue == state.rawValue } }.map {
                .init(id: $0.rawValue, title: NovaRiskWords.state($0), count: board?.counts[$0.rawValue]) }
    }

    @ViewBuilder private func list(_ board: NovaRiskBoard) -> some View {
        if board.rows.isEmpty {
            NovaEmptyState(title: RDLocalization.string("localizable.nova.risk.empty.title", table: .localizable,
                fallback: "Kayıt yok"),
                message: RDLocalization.string("localizable.nova.risk.screens.risk.degerlendirmesi.ekleyerek.surumleri.gecerli.61dc9388", table: .localizable, fallback: "Risk değerlendirmesi ekleyerek sürümleri, geçerlilik tarihini ve bağlı dosyayı tek yerden takip edebilirsiniz."))
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


/// Guided risk creation. The old implementation rendered every field and both
/// primary actions in one popup; this keeps the same service contract while
/// making the decision sequence visible and recoverable.
private struct NovaRiskQuickCreateSheet: View {
    private enum Step: String, CaseIterable { case details, file, review }
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
    @State private var currentStep: Step = .details
    @State private var didSave = false
    @State private var confirmingExit = false

    private var workplaces: [NovaRiskCatalogue.Workplace] { catalogue.workplaces }
    private var suggestedYears: Int? { workplaces.first { $0.id == workplaceID }?.suggestedPeriodYears }
    private var hasOpenDraft: Bool { row?.hasOpenDraft ?? false }
    private var stepNumber: Int { (Step.allCases.firstIndex(of: currentStep) ?? 0) + 1 }
    private var detailsReady: Bool {
        guard workplaceID != nil, row != nil, kindChosen else { return false }
        if kind == .full, !(Int(periodYears).map { $0 > 0 } ?? false) { return false }
        if kind.needsScope && scope.isEmpty { return false }
        if kind.needsReason && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }
    // Kept for the legacy form helper below; the guided flow uses detailsReady
    // and the sticky action instead.
    private var canSave: Bool { detailsReady && !saving }
    private var validUntil: String? {
        guard kind == .full, let years = Int(periodYears), years > 0,
              let date = NovaDayField.date(assessmentOn),
              let until = Calendar.current.date(byAdding: .year, value: years, to: date) else { return nil }
        return NovaDayField.text(until)
    }
    private var validityText: String { validUntil ?? "Geçerlilik bilgisi daha sonra kesinleştirilecek" }
    private var savedMessage: String {
        guard let validUntil else {
            return RDLocalization.string("localizable.nova.risk.saved.novalidity", table: .localizable,
                fallback: "Kayıt oluşturuldu. Geçerlilik tarihi daha sonra kesinleşecek; firma detayından sürümleri ve dosyayı takip edebilirsiniz.")
        }
        return RDLocalization.format("localizable.nova.risk.saved.validuntil", table: .localizable,
            fallback: "Kayıt %1$@ tarihine kadar geçerli olarak oluşturuldu. Firma detayından sürümleri ve dosyayı takip edebilirsiniz.",
            arguments: [validUntil])
    }

    var body: some View {
        Group {
            if didSave {
                NovaTaskSuccessView(title: RDLocalization.string("localizable.nova.risk.screens.risk.degerlendirmesi.kaydedildi.a123914b", table: .localizable, fallback: "Risk değerlendirmesi kaydedildi"),
                    message: savedMessage,
                    doneTitle: "Risk değerlendirmelerine dön", onDone: onClose)
            } else {
                NovaPageSurface(onEdgeBack: onClose) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            NovaTaskHeader(title: RDLocalization.string("localizable.nova.risk.screens.risk.degerlendirmesi.ekle.51b7f9e1", table: .localizable, fallback: "Risk değerlendirmesi ekle"), step: stepNumber,
                                total: Step.allCases.count, stepTitle: stepTitle(currentStep), onClose: { confirmingExit = true })
                            if let openError { NovaTaskErrorSummary(message: openError) }
                            if let saveError { NovaTaskErrorSummary(message: saveError) }
                            if workplaces.isEmpty {
                                NovaEmptyState(title: RDLocalization.string("localizable.nova.risk.screens.isyeri.bulunamadi.40699456", table: .localizable, fallback: "İşyeri bulunamadı"), message: RDLocalization.string("localizable.nova.risk.screens.once.firma.bilgilerinden.isyeri.ekleyin.5424d52f", table: .localizable, fallback: "Önce firma bilgilerinden işyeri ekleyin."))
                            } else if opening || row == nil {
                                NovaLoadingView(message: RDLocalization.string("localizable.nova.risk.screens.isyeri.ve.risk.surumu.hazirlaniyor.10b0fcd8", table: .localizable, fallback: "İşyeri ve risk sürümü hazırlanıyor…"))
                            } else {
                                stepContent(currentStep)
                            }
                        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 28)
                    }.scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) {
                        if !workplaces.isEmpty && !opening && row != nil {
                            NovaTaskStickyActions(primaryTitle: currentStep == .review ? "Kaydet" : "Devam",
                                primarySymbol: currentStep == .review ? "checkmark" : "arrow.right",
                                isWorking: saving, canGoBack: currentStep != .details,
                                onBack: previousStep, onPrimary: advance)
                        }
                    }
                }
            }
        }
        .task {
            if workplaces.count == 1 { workplaceID = workplaces[0].id }
        }
        .onChange(of: workplaceID) { _ in Task { await open() } }
        .confirmationDialog(RDLocalization.string("localizable.nova.risk.screens.risk.degerlendirmesi.akisindan.cikilsin.mi.55a3824f", table: .localizable, fallback: "Risk değerlendirmesi akışından çıkılsın mı?"), isPresented: $confirmingExit,
            titleVisibility: .visible) {
                Button(RDLocalization.string("localizable.nova.risk.screens.cik.ddcc09c9", table: .localizable, fallback: "Çık"), role: .destructive, action: onClose)
                Button(RDLocalization.string("localizable.nova.risk.screens.devam.et.ec818065", table: .localizable, fallback: "Devam et"), role: .cancel) {}
            } message: { Text(RDLocalization.string("localizable.nova.risk.screens.henuz.kaydedilmemis.bilgiler.silinir.53b38f32", table: .localizable, fallback: "Henüz kaydedilmemiş bilgiler silinir.")) }
    }

    @ViewBuilder private func stepContent(_ step: Step) -> some View {
        switch step {
        case .details: detailsStep
        case .file: fileStep
        case .review: reviewStep
        }
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
            NovaText(text: RDLocalization.string("localizable.nova.risk.screens.bu.isyerinde.kayitli.bir.degerlendirme.var.211bf54f", table: .localizable, fallback: "Bu işyerinde kayıtlı bir değerlendirme var."), style: .metaQuiet)
            NovaPopupOption(title: RDLocalization.string("localizable.nova.risk.screens.yeni.degerlendirme.e93fcbe2", table: .localizable, fallback: "Yeni değerlendirme"), symbol: "doc.badge.plus", subtitle: RDLocalization.string("localizable.nova.risk.screens.yeni.donem.icin.kayit.olusturun.7800be04", table: .localizable, fallback: "Yeni dönem için kayıt oluşturun.")) {
                kind = .full; primeSuggestedPeriod(); kindChosen = true
            }.accessibilityIdentifier("risk.quick.kind.new")
            NovaPopupOption(title: RDLocalization.string("localizable.nova.risk.screens.revize.et.dab3a1ef", table: .localizable, fallback: "Revize et"), symbol: "square.and.pencil", subtitle: RDLocalization.string("localizable.nova.risk.screens.mevcut.degerlendirmeyi.guncelleyin.4ffbb308", table: .localizable, fallback: "Mevcut değerlendirmeyi güncelleyin.")) {
                kind = .partial; kindChosen = true
            }.accessibilityIdentifier("risk.quick.kind.revise")
        }
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if workplaces.count > 1, workplaceID == nil {
                workplacePicker
            } else if row?.currentVersion ?? 0 > 0, !hasOpenDraft, !kindChosen {
                kindChooser
            } else {
                if kind.carriesAssessmentDate {
                    NovaDayField(label: RDLocalization.string("localizable.nova.risk.screens.degerlendirme.tarihi.a9067828", table: .localizable, fallback: "Değerlendirme tarihi"), value: $assessmentOn, identifier: "risk.quick.date")
                } else {
                    NovaFormValueRow(label: RDLocalization.string("localizable.nova.risk.screens.degerlendirme.tarihi.d2d6c150", table: .localizable, fallback: "Değerlendirme tarihi"), symbol: "calendar") {
                        NovaText(text: RDLocalization.string("localizable.nova.risk.screens.ilk.degerlendirme.tarihi.korunur.e7200e93", table: .localizable, fallback: "İlk değerlendirme tarihi korunur"), style: .bodyStrong)
                    }
                }
                if kind == .full {
                    NovaFormValueRow(label: RDLocalization.string("localizable.nova.risk.screens.gecerlilik.suresi.0743adc7", table: .localizable, fallback: "Geçerlilik süresi"), symbol: "calendar.badge.clock") {
                        HStack(spacing: 6) {
                            TextField("", text: $periodYears)
                                .keyboardType(.numberPad)
                                .font(NovaFont.font(.body))
                                .multilineTextAlignment(.trailing)
                                .frame(width: 46).frame(minHeight: 36)
                                .accessibilityLabel(RDLocalization.string("localizable.nova.risk.screens.gecerlilik.suresi.yil.769919bb", table: .localizable, fallback: "Geçerlilik süresi, yıl"))
                                .accessibilityIdentifier("risk.quick.years")
                            NovaText(text: RDLocalization.string("localizable.nova.risk.screens.yil.6cbc727b", table: .localizable, fallback: "yıl"), style: .meta)
                        }
                    }
                    NovaHelpHint(text: RDLocalization.format("localizable.nova.risk.screens.isyerinin.tehlike.sinifina.gore.otomatik.dolduru.ae52625c", table: .localizable, fallback: "İşyerinin tehlike sınıfına göre otomatik dolduruldu. Gerekirse değiştirebilirsiniz. Geçerlilik: %1$@", arguments: [String(describing: validityText)]))
                }
                if kind.needsScope { scopeField }
                if kind.needsReason {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.risk.screens.degisiklik.gerekcesi.c8cc0fb9", table: .localizable, fallback: "Değişiklik gerekçesi"), style: .label)
                        TextEditor(text: $reason).frame(minHeight: 70).accessibilityIdentifier("risk.quick.reason")
                    }.padding(12).novaControlBackground(cornerRadius: 14)
                }
                if hasOpenDraft {
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.risk.screens.bu.isyerinde.acik.bir.taslak.var.bilgileri.kontr.d092514d", table: .localizable, fallback: "Bu işyerinde açık bir taslak var. Bilgileri kontrol ederek tamamlayabilirsiniz."))
                }
            }
        }
    }

    private var fileStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaText(text: "Dosya", style: .sectionTitle)
            NovaInlineFileField(category: "risk_assessment", company: company,
                fileClient: client.fileClient, assetID: $assetID)
            NovaHelpHint(text: RDLocalization.string("localizable.nova.risk.screens.dosya.eklemek.zorunlu.degil.degerlendirmeyi.simd.1440bf6c", table: .localizable, fallback: "Dosya eklemek zorunlu değil; değerlendirmeyi şimdi kaydedip belgeyi daha sonra bağlayabilirsiniz."))
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            NovaText(text: RDLocalization.string("localizable.nova.risk.screens.kontrol.et.dc39e8df", table: .localizable, fallback: "Kontrol et"), style: .sectionTitle)
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    reviewRow("İşyeri", workplaces.first(where: { $0.id == workplaceID })?.name ?? "Belirtilmedi")
                    reviewRow("Değerlendirme", kind.carriesAssessmentDate ? assessmentOn : "İlk tarih korunuyor")
                    reviewRow("Geçerlilik", validityText)
                    if !scope.isEmpty { reviewRow("Kapsam", scope.joined(separator: ", ")) }
                    reviewRow("Dosya", assetID.isEmpty ? "Daha sonra eklenebilir" : "Dosya eklendi")
                }
            }
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .metaQuiet)
            NovaText(text: value, style: .bodyStrong)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepTitle(_ step: Step) -> String {
        switch step {
        case .details: return RDLocalization.string("localizable.nova.risk.screens.tarih.ve.gecerlilik.ed8c47e1", table: .localizable, fallback: "Tarih ve geçerlilik")
        case .file: return "Dosya"
        case .review: return RDLocalization.string("localizable.nova.risk.screens.kontrol.ve.kaydet.768f2931", table: .localizable, fallback: "Kontrol ve kaydet")
        }
    }

    private func advance() {
        saveError = nil
        guard currentStep != .review else { Task { await save() }; return }
        guard currentStep != .details || detailsReady else {
            saveError = "İşyeri, değerlendirme türü ve gerekli kapsam bilgilerini kontrol edin."
            return
        }
        guard let index = Step.allCases.firstIndex(of: currentStep) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { currentStep = Step.allCases[index + 1] }
    }

    private func previousStep() {
        saveError = nil
        guard let index = Step.allCases.firstIndex(of: currentStep), index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { currentStep = Step.allCases[index - 1] }
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
                    NovaFormValueRow(label: RDLocalization.string("localizable.nova.risk.screens.gecerlilik.suresi.76b1b51a", table: .localizable, fallback: "Geçerlilik süresi"), symbol: "clock") {
                        HStack(spacing: 6) {
                            TextField("", text: $periodYears).keyboardType(.numberPad)
                                .font(NovaFont.font(.body)).multilineTextAlignment(.trailing).frame(width: 46).frame(minHeight: 36)
                                .accessibilityLabel(RDLocalization.string("localizable.nova.risk.screens.gecerlilik.suresi.yil.457154e1", table: .localizable, fallback: "Geçerlilik süresi, yıl"))
                                .accessibilityIdentifier("risk.quick.years")
                            NovaText(text: RDLocalization.string("localizable.nova.risk.screens.yil.f63159d4", table: .localizable, fallback: "yıl"), style: .meta)
                        }
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
                    }.buttonStyle(NovaRowPressStyle())
                }
            }
        }
    }

    private func primeSuggestedPeriod() {
        guard periodYears.isEmpty else { return }
        periodYears = String(suggestedYears ?? 1)
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
            didSave = true
        } catch let e as NovaRiskFailure { saveError = e.message }
        catch { saveError = NovaRiskFailure.unavailable.message }
    }
}
