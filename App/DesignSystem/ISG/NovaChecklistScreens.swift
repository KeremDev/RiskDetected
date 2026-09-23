import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// module these closures.
struct NovaChecklistClient {
    let catalogue: (UUID?) async throws -> NovaChecklistCatalogue
    let library: (String, String?, String?, Int) async throws -> NovaChecklistLibrary
    let templateDetail: (String) async throws -> NovaChecklistTemplateDetail
    let templates: (UUID?) async throws -> [NovaChecklistTemplate]
    let assignments: (UUID) async throws -> [NovaChecklistAssignment]
    let board: (NovaChecklistQuery) async throws -> NovaChecklistBoard
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    let detail: (UUID) async throws -> NovaChecklistRun
    let startRun: (UUID?, UUID?, String, String, String, String, String) async throws -> NovaChecklistRun?
    let answer: (UUID?, NovaChecklistAnswerDraft) async throws -> NovaChecklistRun?
    let uploadEvidence: (UUID, IsgWorkspaceAttachmentDraft) async throws -> UUID
    let submit: (UUID?, UUID, Int64) async throws -> NovaChecklistRun?
    let cancel: (UUID?, UUID, Int64) async throws -> NovaChecklistRun?
    let revise: (UUID?, UUID, Int64, String) async throws -> NovaChecklistRun?
    let draftTemplate: (UUID?, String) async throws -> Void
    let setItem: (UUID?, String, Int, Int64, String, String, Bool, Int) async throws -> Void
    let copyItems: (UUID?, String, Int, Int64, [NovaChecklistItemSelection]) async throws -> Void
    let reorderItems: (UUID?, String, Int, Int64, [String]) async throws -> Void
    let removeItem: (UUID?, String, Int, Int64, String) async throws -> Void
    let publishTemplate: (UUID?, String, Int, Int64, String) async throws -> Void
    let copyTemplate: (UUID?, String, String?) async throws -> Void
    let assignTemplate: (UUID, UUID?, String) async throws -> Void
    let deactivateAssignment: (UUID, UUID) async throws -> Void
    let pendingAnswers: () -> (total: Int, conflicts: Int)
    let syncPendingAnswers: () async -> (total: Int, conflicts: Int)
}

/// The module opens on real controls. Reusable lists live on their own page,
/// because a template and a field control are different mental objects.
struct NovaChecklistScreen: View {
    let client: NovaChecklistClient
    let onBack: () -> Void
    var canWrite = true
    var initialCompany: UUID?
    var headingOverride: String?

    @State private var board: NovaChecklistBoard?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var query = NovaChecklistQuery(state: NovaChecklistRunState.open.rawValue)
    @State private var loading = true
    @State private var failure: String?
    @State private var showingFilters = false
    @State private var showingStart = false
    @State private var showingLists = false
    @State private var detail: NovaChecklistRun?
    @State private var startedRun: NovaChecklistRun?
    @State private var preselectedTemplate: String?
    @State private var pendingAnswerCount = 0
    @State private var conflictAnswerCount = 0
    @Environment(\.colorScheme) private var scheme

    private var selectedState: NovaChecklistRunState {
        NovaChecklistRunState(rawValue: query.state ?? "open") ?? .open
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    templateLibraryLink
                    offlineNotice
                    statePicker
                    searchAndFilter
                    summary
                    content
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24 + novaTabBarInset)
            }
            .refreshable { await syncPending(); await load(reset: true) }
        }
        .task { await syncPending(); await load(reset: true) }
        .task(id: query.search) {
            do { try await Task.sleep(nanoseconds: 280_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
        .sheet(isPresented: $showingFilters) {
            NovaChecklistRunFilterSheet(companies: companies, selectedCompany: $query.company) {
                showingFilters = false
                Task { await load(reset: true) }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .novaFullScreenCover(isPresented: $showingLists) {
            NovaChecklistListsScreen(client: client, canWrite: canWrite,
                initialCompany: initialCompany, onBack: { showingLists = false },
                onStart: { template in
                    preselectedTemplate = template
                    showingLists = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        startedRun = nil
                        showingStart = true
                    }
                })
        }
        .novaFullScreenCover(isPresented: $showingStart, onDismiss: finishStarting) {
            NovaChecklistStartFlowScreen(client: client, initialCompany: initialCompany,
                preselectedTemplate: preselectedTemplate, onStarted: { run in
                    startedRun = run
                    preselectedTemplate = nil
                    showingStart = false
                }, onClose: { showingStart = false })
        }
        .novaFullScreenCover(isPresented: detailPresentation) {
            if let run = detail {
                NovaChecklistRunTaskScreen(run: run, canWrite: canWrite,
                    onAnswer: answer,
                    onSubmit: { await submit(run) },
                    onCancel: { await cancel(run) },
                    onRevise: { await revise(run) },
                    onClose: { detail = nil })
            }
        }
    }

    private var header: some View {
        NovaListHeading(title: headingOverride ?? "Kontroller", onBack: onBack) {
            if canWrite {
                NovaButton(label: RDLocalization.string("localizable.nova.checklist.screens.yeni.kontrol.050e3985", table: .localizable, fallback: "Yeni kontrol"), symbol: "plus", compact: true) {
                    showingStart = true
                }
                .accessibilityIdentifier("nova.checklist.start")
            }
        }
    }

    private var templateLibraryLink: some View {
        Button { showingLists = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: RDLocalization.string("localizable.nova.checklist.screens.kontrol.listeleri.171e8622", table: .localizable, fallback: "Kontrol Listeleri"), style: .label)
                    NovaText(text: RDLocalization.string("localizable.nova.checklist.screens.hazir.listeleri.bulun.veya.kendi.listelerinizi.y.6de2e60f", table: .localizable, fallback: "Hazır listeleri bulun veya kendi listelerinizi yönetin."), style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityIdentifier("nova.checklist.lists.open")
    }

    @ViewBuilder private var offlineNotice: some View {
        if pendingAnswerCount > 0 {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: conflictAnswerCount > 0
                    ? "exclamationmark.arrow.triangle.2.circlepath" : "icloud.slash")
                NovaText(text: conflictAnswerCount > 0
                    ? "\(pendingAnswerCount) çevrimdışı yanıt bekliyor; \(conflictAnswerCount) yanıt yeniden doğrulanmalı."
                    : "Çevrimdışısınız. \(pendingAnswerCount) değişiklik cihazda güvenle bekliyor.",
                    style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
            }
            .padding(12)
            .background(NovaColorToken.statusWarningBg.color(in: scheme),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var statePicker: some View {
        Picker(RDLocalization.string("localizable.nova.checklist.screens.kontrol.durumu.984c5187", table: .localizable, fallback: "Kontrol durumu"), selection: Binding(get: { selectedState }, set: { state in
            query.state = state.rawValue
            Task { await load(reset: true) }
        })) {
            ForEach(NovaChecklistRunState.allCases) { state in Text(state.title).tag(state) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("nova.checklist.state.picker")
    }

    private var searchAndFilter: some View {
        HStack(spacing: 10) {
            NovaAnalysisSearchField(text: $query.search, placeholder: RDLocalization.string("localizable.nova.checklist.screens.kontrol.ara.bbfad064", table: .localizable, fallback: "Kontrol ara"),
                identifier: "nova.checklist.search")
            Button { showingFilters = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .background(NovaColorToken.surface.color(in: scheme),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if query.company != nil {
                        Circle().fill(NovaColorToken.accent.color(in: scheme))
                            .frame(width: 9, height: 9).padding(7)
                    }
                }
            }
            .buttonStyle(NovaRowPressStyle())
            .accessibilityLabel(query.company == nil ? "Filtre" : "Filtre, 1 etkin")
            .accessibilityIdentifier("nova.checklist.filter")
        }
    }

    @ViewBuilder private var summary: some View {
        if let board {
            HStack(spacing: 5) {
                NovaText(text: RDLocalization.format("localizable.nova.checklist.screens.1.devam.eden.ab38eb6c", table: .localizable, fallback: "%1$@ devam eden", arguments: [String(describing: board.count(.open))]), style: .meta,
                    color: NovaColorToken.textSecondary.color(in: scheme))
                NovaText(text: "·", style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
                NovaText(text: RDLocalization.format("localizable.nova.checklist.screens.1.tamamlanan.4d5af19d", table: .localizable, fallback: "%1$@ tamamlanan", arguments: [String(describing: board.count(.submitted))]), style: .meta,
                    color: NovaColorToken.textSecondary.color(in: scheme))
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var content: some View {
        if loading && board == nil {
            NovaChecklistRunSkeleton()
        } else if let failure {
            NovaChecklistMessageState(symbol: "wifi.exclamationmark",
                title: RDLocalization.string("localizable.nova.checklist.screens.kontrol.bilgileri.yuklenemedi.0f01a931", table: .localizable, fallback: "Kontrol bilgileri yüklenemedi"), message: failure,
                actionTitle: "Yeniden dene") { Task { await load(reset: true) } }
        } else if let board, board.rows.isEmpty {
            NovaChecklistMessageState(symbol: "checklist", title: emptyTitle,
                message: emptyMessage, actionTitle: nil, action: {})
        } else if let board {
            LazyVStack(spacing: 0) {
                ForEach(board.rows) { run in
                    NovaChecklistRunRow(run: run) { Task { await openDetail(run) } }
                    Divider().overlay(NovaColorToken.hairline.color(in: scheme))
                }
                if board.hasMore {
                    NovaButton(label: RDLocalization.string("localizable.nova.checklist.screens.daha.fazla.goster.e860eb49", table: .localizable, fallback: "Daha fazla göster"), symbol: "chevron.down", variant: .surface) {
                        Task { await load(reset: false) }
                    }
                    .padding(.top, 14)
                }
            }
        }
    }

    private var emptyTitle: String {
        switch selectedState {
        case .open: return RDLocalization.string("localizable.nova.checklist.screens.devam.eden.kontrol.yok.bd267bc2", table: .localizable, fallback: "Devam eden kontrol yok")
        case .submitted: return RDLocalization.string("localizable.nova.checklist.screens.tamamlanan.kontrol.yok.f0b16c2b", table: .localizable, fallback: "Tamamlanan kontrol yok")
        case .cancelled: return RDLocalization.string("localizable.nova.checklist.screens.iptal.edilen.kontrol.yok.b4527e1b", table: .localizable, fallback: "İptal edilen kontrol yok")
        }
    }

    private var emptyMessage: String {
        query.search.isEmpty && query.company == nil
            ? "Bu durumdaki kontroller burada görünecek."
            : "Arama kelimenizi veya filtreleri değiştirin."
    }

    private var detailPresentation: Binding<Bool> {
        Binding(get: { detail != nil }, set: { if !$0 { detail = nil } })
    }

    private func finishStarting() {
        if let startedRun {
            detail = startedRun
            self.startedRun = nil
        }
        Task { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        if reset { query.offset = 0 } else { query.offset += query.limit }
        loading = true
        failure = nil
        do {
            if companies.isEmpty { companies = try await client.companies() }
            if query.company == nil, let initialCompany { query.company = initialCompany }
            let answer = try await client.board(query)
            if reset || board == nil {
                board = answer
            } else if let current = board {
                board = .init(rows: current.rows + answer.rows, counts: answer.counts,
                    companies: answer.companies, total: answer.total,
                    hasMore: answer.hasMore, offset: answer.offset)
            }
        } catch let error as NovaChecklistFailure {
            failure = error.message
        } catch {
            failure = "İnternet bağlantınızı kontrol edip yeniden deneyin."
        }
        loading = false
    }

    private func openDetail(_ run: NovaChecklistRun) async {
        do { detail = try await client.detail(run.id) }
        catch { detail = run }
    }

    private func syncPending() async {
        let pending = await client.syncPendingAnswers()
        pendingAnswerCount = pending.total
        conflictAnswerCount = pending.conflicts
    }

    private func answer(_ input: NovaChecklistAnswerDraft) async -> String? {
        guard let current = detail else { return NovaChecklistFailure.validation.message }
        do {
            var draft = input
            draft.expectedRevision = current.revision
            if let attachment = draft.attachment {
                guard let company = current.companyID else {
                    return RDLocalization.string("localizable.nova.checklist.screens.bagimsiz.kontrole.firma.kaniti.eklenemez.a0719608", table: .localizable, fallback: "Bağımsız kontrole firma kanıtı eklenemez.")
                }
                draft.evidenceAssetID = try await client.uploadEvidence(company, attachment)
            }
            if let updated = try await client.answer(current.companyID, draft) {
                detail = updated
            } else {
                detail = NovaChecklistOptimisticAnswer.apply(draft, to: current)
            }
            let pending = client.pendingAnswers()
            pendingAnswerCount = pending.total
            conflictAnswerCount = pending.conflicts
            await load(reset: true)
            return nil
        } catch let error as NovaChecklistFailure {
            return error.message
        } catch {
            return NovaChecklistFailure.unavailable.message
        }
    }

    private func submit(_ run: NovaChecklistRun) async -> String? {
        do {
            if let updated = try await client.submit(run.companyID, run.id, run.revision) { detail = updated }
            await load(reset: true)
            return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func cancel(_ run: NovaChecklistRun) async -> String? {
        do {
            if let updated = try await client.cancel(run.companyID, run.id, run.revision) { detail = updated }
            await load(reset: true)
            return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func revise(_ run: NovaChecklistRun) async -> String? {
        do {
            if let updated = try await client.revise(run.companyID, run.id, run.revision,
                NovaDayField.text(Date())) { detail = updated }
            await load(reset: true)
            return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }
}

struct NovaChecklistRunRow: View {
    let run: NovaChecklistRun
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var scope: String {
        let text = [run.companyName, run.workplaceName].compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? "Bağımsız kontrol" : text
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        NovaText(text: run.templateTitle ?? run.templateCode, style: .cardTitle)
                        NovaText(text: scope, style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        NovaText(text: NovaChecklistUXDate.display(run.startedOn), style: .meta,
                            color: NovaColorToken.textMuted.color(in: scheme))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                        .frame(width: 32, height: 44)
                }
                if run.state == .open {
                    VStack(spacing: 6) {
                        HStack {
                            NovaText(text: "\(run.answered) / \(run.expected)", style: .meta)
                            Spacer()
                        }
                        ProgressView(value: Double(run.answered), total: Double(max(run.expected, 1)))
                            .tint(NovaColorToken.accentInk.color(in: scheme))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(RDLocalization.format("localizable.nova.checklist.screens.kontrol.ilerlemesi.1.sorudan.2.tamamlandi.908025c8", table: .localizable, fallback: "Kontrol ilerlemesi: %1$@ sorudan %2$@ tamamlandı", arguments: [String(describing: run.expected), String(describing: run.answered)]))
                } else if run.state == .submitted {
                    NovaText(text: RDLocalization.format("localizable.nova.checklist.screens.1.uygun.2.uygun.degil.3.uygulanamaz.23d4b702", table: .localizable, fallback: "%1$@ uygun · %2$@ uygun değil · %3$@ uygulanamaz", arguments: [String(describing: run.conform), String(describing: run.nonconform), String(describing: run.notApplicable)]),
                        style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                }
                if run.nonconformitiesOpened > 0 {
                    Label("\(run.nonconformitiesOpened) uygunsuzluk", systemImage: "exclamationmark.triangle")
                        .font(NovaFont.font(.meta))
                        .foregroundStyle(NovaColorToken.statusWarningInk.color(in: scheme))
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityIdentifier("nova.checklist.row.\(run.id.uuidString)")
    }
}

struct NovaChecklistRunFilterSheet: View {
    let companies: [NovaAnalysisCompanyOption]
    @Binding var selectedCompany: UUID?
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Firma") {
                    choice("Tüm firmalar", id: nil)
                    ForEach(companies) { company in choice(company.name, id: company.id) }
                }
                if selectedCompany != nil {
                    Section { Button(RDLocalization.string("localizable.nova.checklist.screens.tum.filtreleri.temizle.21ea37c5", table: .localizable, fallback: "Tüm filtreleri temizle")) { selectedCompany = nil } }
                }
            }
            .navigationTitle("Filtre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(RDLocalization.string("localizable.nova.checklist.screens.vazgec.58165a8d", table: .localizable, fallback: "Vazgeç")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uygula") { onApply(); dismiss() }
                }
            }
        }
    }

    private func choice(_ title: String, id: UUID?) -> some View {
        Button { selectedCompany = id } label: {
            HStack {
                Text(title)
                Spacer()
                if selectedCompany == id { Image(systemName: "checkmark") }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NovaChecklistRunSkeleton: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 4).frame(width: 230, height: 18)
                    RoundedRectangle(cornerRadius: 4).frame(width: 150, height: 12)
                    RoundedRectangle(cornerRadius: 4).frame(height: 5)
                }
                .padding(.vertical, 15)
                Divider()
            }
        }
        .foregroundStyle(.secondary.opacity(0.22))
        .redacted(reason: .placeholder)
        .accessibilityLabel(RDLocalization.string("localizable.nova.checklist.screens.kontroller.yukleniyor.18181086", table: .localizable, fallback: "Kontroller yükleniyor"))
    }
}

struct NovaChecklistMessageState: View {
    let symbol: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .regular))
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            NovaText(text: title, style: .cardTitle).multilineTextAlignment(.center)
            NovaText(text: message, style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
                .multilineTextAlignment(.center)
            if let actionTitle {
                NovaButton(label: actionTitle, symbol: "arrow.clockwise", variant: .surface, action: action)
                    .frame(maxWidth: 220)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

enum NovaChecklistUXDate {
    private static let input: DateFormatter = {
        let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX")
        value.dateFormat = "yyyy-MM-dd"; return value
    }()
    private static let output: DateFormatter = {
        let value = DateFormatter(); value.locale = Locale(identifier: "tr_TR")
        value.dateFormat = "d MMM yyyy"; return value
    }()
    static func display(_ value: String) -> String {
        input.date(from: value).map(output.string(from:)) ?? value
    }
}

/// The real server remains authoritative. This only keeps a queued offline
/// answer visible until replay succeeds; it never invents a submitted state.
enum NovaChecklistOptimisticAnswer {
    static func apply(_ draft: NovaChecklistAnswerDraft, to run: NovaChecklistRun) -> NovaChecklistRun {
        let answers = run.answers.map { answer -> NovaChecklistAnswer in
            guard answer.itemCode == draft.itemCode else { return answer }
            return .init(itemCode: answer.itemCode, prompt: answer.prompt, position: answer.position,
                atomicItemCode: answer.atomicItemCode, sectionTitle: answer.sectionTitle,
                scopeKey: answer.scopeKey, allowsNotApplicable: answer.allowsNotApplicable,
                verificationMethod: answer.verificationMethod, helpText: answer.helpText,
                tags: answer.tags, riskTopic: answer.riskTopic,
                naReasonRequired: answer.naReasonRequired,
                evidenceRecommended: answer.evidenceRecommended, photoRequired: answer.photoRequired,
                result: draft.result, note: draft.note,
                evidenceAssetID: draft.evidenceAssetID ?? answer.evidenceAssetID,
                nonconformityID: answer.nonconformityID)
        }
        let answered = answers.filter(\.isAnswered).count
        let conform = answers.filter { $0.result == .conform }.count
        let nonconform = answers.filter { $0.result == .nonconform }.count
        let notApplicable = answers.filter { $0.result == .notApplicable }.count
        return .init(id: run.id, companyID: run.companyID, companyName: run.companyName,
            workplaceID: run.workplaceID, workplaceName: run.workplaceName,
            templateCode: run.templateCode, templateTitle: run.templateTitle,
            templateVersion: run.templateVersion, state: run.state, startedOn: run.startedOn,
            submittedAt: run.submittedAt, revision: run.revision, revisesRunID: run.revisesRunID,
            areaLabel: run.areaLabel, equipmentLabel: run.equipmentLabel,
            documentNumber: run.documentNumber, expected: run.expected, answered: answered,
            remaining: max(0, run.expected - answered), conform: conform,
            nonconform: nonconform, notApplicable: notApplicable,
            progressPercent: run.expected > 0 ? Double(answered) * 100 / Double(run.expected) : nil,
            coveragePercent: run.coveragePercent, applicableCoveragePercent: run.applicableCoveragePercent,
            scorePercent: run.scorePercent, sourceIDs: run.sourceIDs,
            nonconformitiesOpened: run.nonconformitiesOpened, answers: answers)
    }
}
