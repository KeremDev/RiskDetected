import SwiftUI

struct NovaNonconformityRecordClient {
    let load: () async throws -> NovaNonconformityRow
    let transition: (NovaNonconformityState, String, String) async throws -> NovaNonconformityRow
    let addAction: (String, String, String?) async throws -> NovaNonconformityRow
    let verify: (Bool, String) async throws -> NovaNonconformityRow
    let saveDetail: (NovaNonconformityDetailDraft) async throws -> NovaNonconformityRow
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

/// One record, and every operation the server allows on it.
struct NovaNonconformityRecordScreen: View {
    let entry: NovaNonconformityEntry
    let client: NovaNonconformityRecordClient
    let onBack: () -> Void
    var canWrite = true
    @Environment(\.colorScheme) private var scheme
    @State private var row: NovaNonconformityRow?
    @State private var error: String?
    @State private var notice: String?
    @State private var busy = false
    @State private var editing = false
    @State private var addingAction = false
    @State private var verifying = false
    @State private var pendingMove: NovaNonconformityEdge?

    private var current: NovaNonconformityRow { row ?? entry.row }
    private var state: NovaNonconformityState {
        NovaNonconformityState(rawValue: current.state) ?? .draft
    }

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if let error { NovaCard(padding: 14) { NovaText(text: error, style: .metaQuiet) } }
                    meta
                    detailCard
                    transitions
                    actionsCard
                    verificationCard
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
        .task { await reload() }
        .fullScreenCover(isPresented: $editing) {
            NovaPopup {
                NovaNonconformityDetailSheet(draft: NovaNonconformityDetailDraft(current.detail)) { draft in
                    row = try await client.saveDetail(draft)
                    editing = false
                }
            }
        }
        .fullScreenCover(isPresented: $addingAction) {
            NovaPopup {
                NovaCorrectiveActionSheet { description, assignee, due in
                    row = try await client.addAction(description, assignee, due)
                    addingAction = false
                }
            }
        }
        .fullScreenCover(isPresented: $verifying) {
            NovaPopup {
                NovaVerificationSheet { accepted, note in
                    row = try await client.verify(accepted, note)
                    verifying = false
                }
            }
        }
        .fullScreenCover(item: $pendingMove) { edge in
            NovaPopup {
                NovaTransitionSheet(edge: edge) { reason, assignee in
                    row = try await client.transition(edge.to, reason, assignee)
                    pendingMove = nil
                }
            }
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(RDLocalization.string("localizable.nova.bridge.alert.ok", table: .localizable, fallback: "Tamam")) { notice = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            NovaBackButton(isEnabled: !busy) { onBack() }
            VStack(alignment: .leading, spacing: 5) {
                NovaText(text: current.title, style: .screenTitle)
                HStack(spacing: 6) {
                    NovaStatusPill(label: NovaNonconformityWords.band(current.severity),
                        status: NovaNonconformityWords.tone(current.severity))
                    NovaStatusPill(label: NovaNonconformityWords.state(current.state), status: .neutral, showsDot: false)
                    if current.kind == .improvement {
                        NovaStatusPill(label: NovaNonconformityWords.recordKind(.improvement), status: .info, showsDot: false)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var meta: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 7) {
                line("building.2", [entry.companyName, entry.workplaceName].compactMap { $0 }.joined(separator: " · "))
                line("calendar", String(format: RDLocalization.string("localizable.nova.nonconformity.opened.on", table: .localizable,
                    fallback: "Açılış %@"), current.opened_on))
                if let due = current.due_on {
                    line("clock", String(format: RDLocalization.string("localizable.nova.nonconformity.due.on", table: .localizable,
                        fallback: "Termin %@"), due))
                }
                if let closed = current.closed_on {
                    line("checkmark.seal", String(format: RDLocalization.string("localizable.nova.nonconformity.closed.on", table: .localizable,
                        fallback: "Kapanış %@"), closed))
                }
                if let assignee = current.assignee_contact, !assignee.isEmpty {
                    line("person.crop.rectangle", assignee)
                }
                if current.camefromFinding || current.camefromExpertItem {
                    line("sparkle", current.camefromFinding
                        ? RDLocalization.string("localizable.nova.nonconformity.from.analysis", table: .localizable, fallback: "Fotoğraf analizinden geldi")
                        : RDLocalization.string("localizable.nova.nonconformity.from.expert", table: .localizable, fallback: "Uzman görüşü maddesinden geldi"))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            NovaIcon(symbol: symbol, size: 14).foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: text, style: .metaQuiet)
            Spacer(minLength: 0)
        }
    }

    private var detailCard: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.detail.title", table: .localizable, fallback: "Kayıt detayı"), style: .sectionTitle)
                    Spacer(minLength: 0)
                    if canWrite {
                        Button { editing = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "square.and.pencil").font(.system(size: 12))
                                NovaText(text: RDLocalization.string("localizable.nova.nonconformity.detail.edit", table: .localizable, fallback: "Düzenle"),
                                    style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                            }.foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 36)
                        }.buttonStyle(.plain).accessibilityIdentifier("nonconformity.detail.edit")
                    }
                }
                if let detail = current.detail {
                    field(RDLocalization.string("localizable.nova.manual.hazard.description", table: .localizable, fallback: "Açıklama"), detail.description)
                    field(RDLocalization.string("localizable.nova.manual.hazard.measure", table: .localizable, fallback: "Önlem"), detail.control_measure)
                    field(RDLocalization.string("localizable.nova.manual.step.legislation", table: .localizable, fallback: "Mevzuat bilgisi"), detail.legislation_ref)
                    field(RDLocalization.string("localizable.nova.manual.step.responsible", table: .localizable, fallback: "Firma sorumlusu"), detail.responsible_contact)
                    if let method = detail.risk_method.flatMap(NovaRiskMethod.init(rawValue:)), let score = detail.risk_score {
                        HStack(spacing: 7) {
                            NovaStatusPill(label: NovaNonconformityWords.band(detail.risk_band),
                                status: NovaNonconformityWords.tone(detail.risk_band))
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

    @ViewBuilder private func field(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                NovaText(text: value, style: .metaQuiet)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var transitions: some View {
        let moves = NovaNonconformityMachine.moves(from: state)
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 9) {
                NovaText(text: RDLocalization.string("localizable.nova.nonconformity.state.title", table: .localizable, fallback: "Durum"), style: .sectionTitle)
                if moves.isEmpty {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.state.terminal", table: .localizable,
                        fallback: "Bu kayıt için başka bir durum geçişi yok."), style: .metaQuiet)
                } else if !canWrite {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.read.only", table: .localizable,
                        fallback: "Salt okunur · yeni kayıt açılamıyor"), style: .metaQuiet)
                } else {
                    ForEach(moves) { edge in
                        NovaButton(label: NovaNonconformityWords.state(edge.to.rawValue), symbol: symbol(edge.to),
                            variant: edge.to == .cancelled ? .danger : .surface, isEnabled: !busy) {
                            if edge.requiresVerification && !hasAcceptedVerification {
                                notice = RDLocalization.string("localizable.nova.nonconformity.needs.verification", table: .localizable,
                                    fallback: "Kapatmadan önce kabul edilmiş bir doğrulama gerekiyor.")
                            } else {
                                pendingMove = edge
                            }
                        }.accessibilityIdentifier("nonconformity.move.\(edge.to.rawValue)")
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Closing needs a verification accepted in this cycle; the screen says so
    /// instead of offering a move the server will refuse.
    private var hasAcceptedVerification: Bool {
        (current.verifications ?? []).contains { $0.outcome == "accepted" }
    }

    private func symbol(_ state: NovaNonconformityState) -> String {
        switch state {
        case .open: return "envelope.open"
        case .assigned: return "person.crop.rectangle"
        case .in_progress: return "hammer"
        case .pending_verification: return "checkmark.shield"
        case .closed: return "checkmark.seal"
        case .reopened: return "arrow.counterclockwise"
        case .cancelled: return "xmark.circle"
        case .draft: return "doc"
        }
    }

    private var actionsCard: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.actions.title", table: .localizable, fallback: "Düzeltici aksiyonlar"), style: .sectionTitle)
                    Spacer(minLength: 0)
                    if canWrite {
                        Button { addingAction = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus").font(.system(size: 12))
                                NovaText(text: RDLocalization.string("localizable.nova.nonconformity.actions.add", table: .localizable, fallback: "Ekle"),
                                    style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                            }.foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 36)
                        }.buttonStyle(.plain).accessibilityIdentifier("nonconformity.action.add")
                    }
                }
                let actions = current.actions ?? []
                if actions.isEmpty {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.actions.empty", table: .localizable,
                        fallback: "Henüz düzeltici aksiyon yok."), style: .metaQuiet)
                } else {
                    ForEach(actions) { action in
                        VStack(alignment: .leading, spacing: 3) {
                            NovaText(text: action.description, style: .bodyStrong)
                            NovaText(text: [action.assignee, action.due_on].compactMap { $0 }.joined(separator: " · "), style: .metaQuiet)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var verificationCard: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.verification.title", table: .localizable, fallback: "Uzman doğrulaması"), style: .sectionTitle)
                    Spacer(minLength: 0)
                    if canWrite {
                        Button { verifying = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.shield").font(.system(size: 12))
                                NovaText(text: RDLocalization.string("localizable.nova.nonconformity.verification.add", table: .localizable, fallback: "Doğrula"),
                                    style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                            }.foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 36)
                        }.buttonStyle(.plain).accessibilityIdentifier("nonconformity.verify")
                    }
                }
                let records = current.verifications ?? []
                if records.isEmpty {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.verification.empty", table: .localizable,
                        fallback: "Henüz doğrulama kaydı yok."), style: .metaQuiet)
                } else {
                    ForEach(records) { record in
                        HStack(spacing: 7) {
                            NovaStatusPill(label: record.outcome == "accepted"
                                ? RDLocalization.string("localizable.nova.nonconformity.verification.accepted", table: .localizable, fallback: "Kabul")
                                : RDLocalization.string("localizable.nova.nonconformity.verification.rejected", table: .localizable, fallback: "Ret"),
                                status: record.outcome == "accepted" ? .success : .danger)
                            NovaText(text: record.verified_on, style: .metaQuiet)
                            Spacer(minLength: 0)
                        }.padding(.vertical, 2)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reload() async {
        busy = true; error = nil
        do { row = try await client.load() }
        catch is CancellationError { }
        catch let failure as NovaNonconformityFailure { error = NovaNonconformityWords.failure(failure) }
        catch {
            self.error = RDLocalization.string("localizable.nova.nonconformity.error.detail", table: .localizable,
                fallback: "Kayıt yüklenemedi. Tekrar deneyin.")
        }
        busy = false
    }
}
