import SwiftUI

struct NovaNonconformityRecordClient {
    let load: () async throws -> NovaNonconformityRow
    let transition: (NovaNonconformityState, String, String) async throws -> NovaNonconformityRow
    let addAction: (String, String, String?) async throws -> NovaNonconformityRow
    let verify: (Bool, String) async throws -> NovaNonconformityRow
    let saveDetail: (NovaNonconformityDetailDraft) async throws -> NovaNonconformityRow
    /// The same bucket/path download every other module's evidence uses.
    let download: (String, String) async throws -> Data
}

/// What the detail editor is holding. Separate from the manual-entry draft so
/// editing an existing record cannot touch its title, severity or workplace.
struct NovaNonconformityDetailDraft: Equatable {
    var description = ""
    var measure = ""
    var legislation = ""
    var responsible = ""
    var score = NovaRiskScoreInput()

    init() {}
    init(_ detail: NovaNonconformityDetail?) {
        description = detail?.description ?? ""
        measure = detail?.control_measure ?? ""
        legislation = detail?.legislation_ref ?? ""
        responsible = detail?.responsible_contact ?? ""
        score = detail?.scoreInput ?? NovaRiskScoreInput()
    }
}

/// One record, in a popup. Reading, editing, moving its state, adding a
/// corrective action and verifying it all happen here; nothing opens a second
/// page on top of this one.
struct NovaNonconformityRecordSheet: View {
    let entry: NovaNonconformityEntry
    let client: NovaNonconformityRecordClient
    var canWrite = true
    @Environment(\.colorScheme) private var scheme
    @State private var row: NovaNonconformityRow?
    @State private var error: String?
    @State private var busy = false
    @State private var panel: Panel = .none
    @State private var move: NovaNonconformityEdge?
    @State private var reason = ""
    @State private var assignee = ""
    @State private var actionText = ""
    @State private var actionAssignee = ""
    @State private var verifyAccepted = true
    @State private var verifyNote = ""
    @State private var detail = NovaNonconformityDetailDraft()
    @State private var opened: URL?
    @State private var openingIndex: Int?

    private enum Panel: Equatable { case none, detail, state, action, verify }

    private var current: NovaNonconformityRow { row ?? entry.row }
    private var state: NovaNonconformityState { NovaNonconformityState(rawValue: current.state) ?? .draft }
    private var hasAcceptedVerification: Bool {
        (current.verifications ?? []).contains { $0.outcome == "accepted" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                heading
                facts
                detailCard
                evidenceCard
                if canWrite { operations }
                history
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
            }.padding(20).novaPopupContentSize()
        }
        .background(NovaKeyboardDismissArea())
        .task { await reload() }
        .sheet(item: $opened) { url in NovaFileShareSheet(url: url) }
    }

    // MARK: heading and facts

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            NovaText(text: current.title, style: .sheetTitle)
            HStack(spacing: 6) {
                NovaStatusPill(label: NovaNonconformityWords.band(current.severity),
                    status: NovaNonconformityWords.tone(current.severity))
                NovaStatusPill(label: NovaNonconformityWords.state(current.state), status: .neutral, showsDot: false)
                if current.kind == .improvement {
                    NovaStatusPill(label: NovaNonconformityWords.recordKind(.improvement), status: .info, showsDot: false)
                }
            }
        }
    }

    /// Two columns of icon and value: the same facts, a third of the height.
    private var facts: some View {
        NovaCard(padding: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                GridItem(.flexible(), alignment: .topLeading)], spacing: 9) {
                fact("building.2", entry.companyName)
                if let place = entry.workplaceName { fact("mappin", place) }
                fact("calendar", current.opened_on)
                if let due = current.due_on { fact("clock", due) }
                if let closed = current.closed_on { fact("checkmark.seal", closed) }
                if let who = current.assignee_contact, !who.isEmpty { fact("person.crop.rectangle", who) }
                if current.camefromFinding || current.camefromExpertItem {
                    fact("sparkle", current.camefromFinding
                        ? RDLocalization.string("localizable.nova.nonconformity.from.analysis", table: .localizable, fallback: "Fotoğraf analizinden geldi")
                        : RDLocalization.string("localizable.nova.nonconformity.from.expert", table: .localizable, fallback: "Uzman görüşü maddesinden geldi"))
                }
            }
        }
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            NovaIcon(symbol: symbol, size: 13).foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: text, style: .metaQuiet)
            Spacer(minLength: 0)
        }
    }

    // MARK: detail

    private var detailCard: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.detail.title", table: .localizable, fallback: "Kayıt detayı"), style: .sectionTitle)
                    Spacer(minLength: 0)
                    if canWrite {
                        Button {
                            detail = NovaNonconformityDetailDraft(current.detail)
                            panel = panel == .detail ? .none : .detail
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: panel == .detail ? "xmark" : "square.and.pencil").font(.system(size: 12))
                                NovaText(text: panel == .detail
                                    ? RDLocalization.string("localizable.nova.analysis.item.cancel", table: .localizable, fallback: "Vazgeç")
                                    : RDLocalization.string("localizable.nova.nonconformity.detail.edit", table: .localizable, fallback: "Düzenle"),
                                    style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                            }.foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 34)
                        }.buttonStyle(.plain).accessibilityIdentifier("nonconformity.detail.edit")
                    }
                }
                if panel == .detail {
                    area(RDLocalization.string("localizable.nova.manual.hazard.description", table: .localizable, fallback: "Açıklama"), $detail.description, id: "description")
                    area(RDLocalization.string("localizable.nova.manual.hazard.measure", table: .localizable, fallback: "Önlem"), $detail.measure, id: "measure")
                    area(RDLocalization.string("localizable.nova.manual.step.legislation", table: .localizable, fallback: "Mevzuat bilgisi"), $detail.legislation, id: "legislation")
                    field(RDLocalization.string("localizable.nova.manual.step.responsible", table: .localizable, fallback: "Firma sorumlusu"), $detail.responsible, id: "responsible")
                    NovaRiskScoreEditor(score: $detail.score)
                    NovaButton(label: RDLocalization.string("localizable.nova.analysis.edit.save", table: .localizable, fallback: "Değişiklikleri kaydet"),
                        symbol: "checkmark", isEnabled: !busy && (detail.score.isEmpty || detail.score.isComplete), isLoading: busy) {
                        run { row = try await client.saveDetail(detail); panel = .none }
                    }.accessibilityIdentifier("nonconformity.detail.save")
                } else if let stored = current.detail {
                    value(RDLocalization.string("localizable.nova.manual.hazard.description", table: .localizable, fallback: "Açıklama"), stored.description)
                    value(RDLocalization.string("localizable.nova.manual.hazard.measure", table: .localizable, fallback: "Önlem"), stored.control_measure)
                    value(RDLocalization.string("localizable.nova.manual.step.legislation", table: .localizable, fallback: "Mevzuat bilgisi"), stored.legislation_ref)
                    value(RDLocalization.string("localizable.nova.manual.step.responsible", table: .localizable, fallback: "Firma sorumlusu"), stored.responsible_contact)
                    if let method = stored.risk_method.flatMap(NovaRiskMethod.init(rawValue:)), let score = stored.risk_score {
                        HStack(spacing: 6) {
                            NovaStatusPill(label: NovaNonconformityWords.band(stored.risk_band),
                                status: NovaNonconformityWords.tone(stored.risk_band))
                            NovaText(text: "\(NovaNonconformityWords.score(score)) · \(NovaNonconformityWords.method(method))", style: .metaQuiet)
                        }
                    }
                } else {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.detail.empty", table: .localizable,
                        fallback: "Bu kayıtta henüz detay yok."), style: .metaQuiet)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func value(_ label: String, _ text: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                NovaText(text: text, style: .metaQuiet)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: evidence

    @ViewBuilder private var evidenceCard: some View {
        let downloads = current.evidence_downloads ?? []
        if !downloads.isEmpty {
            NovaCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.evidence.title", table: .localizable,
                        fallback: "Kanıt fotoğrafları"), style: .sectionTitle)
                    HStack(spacing: 8) {
                        ForEach(Array(downloads.enumerated()), id: \.offset) { index, download in
                            Button { open(index, download) } label: {
                                VStack(spacing: 4) {
                                    if openingIndex == index {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "photo").font(.system(size: 16))
                                            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                                    }
                                    NovaText(text: String(format: RDLocalization.string("localizable.nova.nonconformity.evidence.item",
                                        table: .localizable, fallback: "Foto %d"), index + 1), style: .micro)
                                }.frame(width: 64, height: 64)
                                    .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).disabled(openingIndex != nil)
                                .accessibilityIdentifier("nonconformity.evidence.\(index)")
                        }
                        Spacer(minLength: 0)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func open(_ index: Int, _ download: NovaEvidenceDownload) {
        openingIndex = index; error = nil
        Task {
            do {
                let data = try await client.download(download.bucket, download.path)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    .appendingPathComponent(download.path.components(separatedBy: "/").last ?? "kanit.jpg")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .completeFileProtection)
                opened = url
            } catch {
                self.error = RDLocalization.string("localizable.nova.file.failure.unavailable", table: .localizable,
                    fallback: "Dosya servisi şu anda kullanılamıyor.")
            }
            openingIndex = nil
        }
    }

    // MARK: operations

    /// Three inline panels rather than three more popups on top of this one.
    private var operations: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                operationButton(.state, "arrow.triangle.branch",
                    RDLocalization.string("localizable.nova.nonconformity.state.title", table: .localizable, fallback: "Durum"))
                operationButton(.action, "hammer",
                    RDLocalization.string("localizable.nova.nonconformity.actions.short", table: .localizable, fallback: "Aksiyon"))
                operationButton(.verify, "checkmark.shield",
                    RDLocalization.string("localizable.nova.nonconformity.verification.add", table: .localizable, fallback: "Doğrula"))
            }
            switch panel {
            case .state: statePanel
            case .action: actionPanel
            case .verify: verifyPanel
            default: EmptyView()
            }
        }
    }

    private func operationButton(_ target: Panel, _ symbol: String, _ title: String) -> some View {
        let isOn = panel == target
        return Button { panel = isOn ? .none : target } label: {
            VStack(spacing: 4) {
                NovaIcon(symbol: symbol, size: 17)
                NovaText(text: title, style: .micro,
                    color: isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
            }
            .foregroundStyle(isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(isOn ? NovaColorToken.statusSuccessBg.color(in: scheme) : NovaColorToken.surface.color(in: scheme),
                in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("nonconformity.panel.\(target == .state ? "state" : target == .action ? "action" : "verify")")
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder private var statePanel: some View {
        let moves = NovaNonconformityMachine.moves(from: state)
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                if moves.isEmpty {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.state.terminal", table: .localizable,
                        fallback: "Bu kayıt için başka bir durum geçişi yok."), style: .metaQuiet)
                } else {
                    HStack(spacing: 6) {
                        ForEach(moves) { edge in
                            Button {
                                if edge.requiresVerification && !hasAcceptedVerification {
                                    error = RDLocalization.string("localizable.nova.nonconformity.needs.verification", table: .localizable,
                                        fallback: "Kapatmadan önce kabul edilmiş bir doğrulama gerekiyor.")
                                } else {
                                    error = nil; move = edge; reason = ""; assignee = ""
                                }
                            } label: {
                                NovaText(text: NovaNonconformityWords.state(edge.to.rawValue), style: .meta,
                                    color: move?.id == edge.id ? NovaColorToken.accentInk.color(in: scheme)
                                                               : NovaColorToken.textSecondary.color(in: scheme))
                                    .padding(.horizontal, 11).frame(minHeight: 38)
                                    .background(move?.id == edge.id ? NovaColorToken.statusSuccessBg.color(in: scheme)
                                                                    : NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("nonconformity.move.\(edge.to.rawValue)")
                                .accessibilityAddTraits(move?.id == edge.id ? .isSelected : [])
                        }
                    }
                    if let edge = move {
                        if edge.requiresAssignee {
                            field(RDLocalization.string("localizable.nova.nonconformity.move.assignee", table: .localizable, fallback: "Atanan kişi"), $assignee, id: "assignee")
                        }
                        area(edge.requiresReason
                            ? RDLocalization.string("localizable.nova.nonconformity.move.reason.required", table: .localizable, fallback: "Gerekçe *")
                            : RDLocalization.string("localizable.nova.nonconformity.move.reason", table: .localizable, fallback: "Gerekçe"),
                            $reason, id: "reason")
                        if edge.requiresReason {
                            NovaText(text: RDLocalization.string("localizable.nova.nonconformity.move.reason.hint", table: .localizable,
                                fallback: "Bu geçiş gerekçesiz kaydedilmez; en az beş karakter yazın."), style: .micro,
                                color: NovaColorToken.textTertiary.color(in: scheme))
                        }
                        NovaButton(label: RDLocalization.string("localizable.nova.nonconformity.move.action", table: .localizable, fallback: "Geçişi kaydet"),
                            symbol: "arrow.right", isEnabled: !busy && ready(edge), isLoading: busy) {
                            run {
                                row = try await client.transition(edge.to, reason, assignee)
                                move = nil; panel = .none
                            }
                        }.accessibilityIdentifier("nonconformity.move.save")
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ready(_ edge: NovaNonconformityEdge) -> Bool {
        if edge.requiresReason && reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 { return false }
        if edge.requiresAssignee && assignee.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    private var actionPanel: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                area(RDLocalization.string("localizable.nova.nonconformity.actions.description", table: .localizable, fallback: "Yapılacak iş"), $actionText, id: "action")
                field(RDLocalization.string("localizable.nova.nonconformity.actions.assignee", table: .localizable, fallback: "Sorumlu"), $actionAssignee, id: "action.assignee")
                NovaText(text: RDLocalization.string("localizable.nova.nonconformity.actions.hint", table: .localizable,
                    fallback: "Aksiyonun sorumlusu bir uygulama kullanıcısı değildir; yalnız kayıtta görünür."), style: .micro,
                    color: NovaColorToken.textTertiary.color(in: scheme))
                NovaButton(label: RDLocalization.string("localizable.nova.nonconformity.actions.add", table: .localizable, fallback: "Ekle"),
                    symbol: "plus", isEnabled: !busy && !actionText.trimmingCharacters(in: .whitespaces).isEmpty, isLoading: busy) {
                    run {
                        row = try await client.addAction(actionText, actionAssignee, nil)
                        actionText = ""; actionAssignee = ""; panel = .none
                    }
                }.accessibilityIdentifier("nonconformity.action.add")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var verifyPanel: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $verifyAccepted) {
                    Text(verbatim: RDLocalization.string("localizable.nova.nonconformity.verification.accepted", table: .localizable, fallback: "Kabul")).tag(true)
                    Text(verbatim: RDLocalization.string("localizable.nova.nonconformity.verification.rejected", table: .localizable, fallback: "Ret")).tag(false)
                }.pickerStyle(.segmented).accessibilityIdentifier("record.verify.outcome")
                area(RDLocalization.string("localizable.nova.nonconformity.verification.note", table: .localizable, fallback: "Not"), $verifyNote, id: "verify.note")
                NovaText(text: RDLocalization.string("localizable.nova.nonconformity.verification.hint", table: .localizable,
                    fallback: "Reddedilen doğrulama kaydı kapatmaz; yeni bir döngü başlatır."), style: .micro,
                    color: NovaColorToken.textTertiary.color(in: scheme))
                NovaButton(label: RDLocalization.string("localizable.nova.nonconformity.verification.add", table: .localizable, fallback: "Doğrula"),
                    symbol: "checkmark.shield", isEnabled: !busy, isLoading: busy) {
                    run { row = try await client.verify(verifyAccepted, verifyNote); verifyNote = ""; panel = .none }
                }.accessibilityIdentifier("nonconformity.verify")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: history

    @ViewBuilder private var history: some View {
        let actions = current.actions ?? []
        let records = current.verifications ?? []
        if !actions.isEmpty || !records.isEmpty {
            NovaCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    if !actions.isEmpty {
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.actions.title", table: .localizable, fallback: "Düzeltici aksiyonlar"), style: .sectionTitle)
                        ForEach(actions) { action in
                            HStack(alignment: .top, spacing: 7) {
                                NovaIcon(symbol: "hammer", size: 12).foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                                VStack(alignment: .leading, spacing: 2) {
                                    NovaText(text: action.description, style: .metaQuiet)
                                    if let extra = [action.assignee, action.due_on].compactMap({ $0 }).first {
                                        NovaText(text: extra, style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    if !records.isEmpty {
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.verification.title", table: .localizable, fallback: "Uzman doğrulaması"), style: .sectionTitle)
                        ForEach(records) { record in
                            HStack(spacing: 7) {
                                NovaStatusPill(label: record.outcome == "accepted"
                                    ? RDLocalization.string("localizable.nova.nonconformity.verification.accepted", table: .localizable, fallback: "Kabul")
                                    : RDLocalization.string("localizable.nova.nonconformity.verification.rejected", table: .localizable, fallback: "Ret"),
                                    status: record.outcome == "accepted" ? .success : .danger)
                                NovaText(text: record.verified_on, style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: plumbing

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(NovaFont.font(.body))
                .frame(minHeight: 36).accessibilityIdentifier("record.\(id)")
        }
    }
    private func area(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextEditor(text: text).font(NovaFont.font(.body))
                .frame(minHeight: 64).scrollContentBackground(.hidden)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("record.\(id)")
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            busy = true; error = nil
            do { try await work() }
            catch let failure as NovaNonconformityFailure { error = NovaNonconformityWords.failure(failure) }
            catch {
                self.error = RDLocalization.string("localizable.nova.nonconformity.error.save", table: .localizable,
                    fallback: "Kayıt açılamadı. Bilgileri kontrol edip aynı işlemi tekrar deneyin.")
            }
            busy = false
        }
    }

    private func reload() async {
        do { row = try await client.load() }
        catch is CancellationError { }
        catch let failure as NovaNonconformityFailure { error = NovaNonconformityWords.failure(failure) }
        catch {
            self.error = RDLocalization.string("localizable.nova.nonconformity.error.detail", table: .localizable,
                fallback: "Kayıt yüklenemedi. Tekrar deneyin.")
        }
    }
}
