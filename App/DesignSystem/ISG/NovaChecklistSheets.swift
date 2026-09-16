import SwiftUI

/// One run, question by question. A failing answer is offered a record; it is
/// never turned into one on its own.
struct NovaChecklistRunSheet: View {
    let run: NovaChecklistRun
    var canWrite: Bool = true
    let onAnswer: (NovaChecklistAnswerDraft) async -> String?
    let onSubmit: () async -> String?
    let onCancel: () async -> String?
    let onClose: () -> Void
    @State private var draft: NovaChecklistAnswerDraft?
    @State private var failure: String?
    @State private var working = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaPopupHeading(text: run.templateTitle ?? run.templateCode, symbol: "checklist")
                        NovaText(text: [run.workplaceName, run.companyName]
                            .compactMap { $0 }.joined(separator: " · "), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        NovaText(text: NovaChecklistWords.explain(run), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    // The version is a fact about the run, not a detail: it is
                    // what the run was filled against and cannot change.
                    NovaHelpHint(text: String(format: RDLocalization.string(
                        "localizable.nova.checklist.run.pinned", table: .localizable,
                        fallback: "Bu kontrol listenin %d. sürümüyle dolduruldu. Sonradan yayımlanan sürüm bu kaydı değiştirmez."),
                        run.templateVersion))
                    NovaText(text: NovaChecklistWords.neverAutomatic, style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    questions
                    if canWrite && run.state == .open { actions }
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .novaPopup(item: $draft) { entry in
            NovaChecklistAnswerSheet(draft: entry,
                onSave: { edited in
                    let error = await onAnswer(edited)
                    if error == nil { draft = nil }
                    return error
                },
                onClose: { draft = nil })
        }
        .accessibilityIdentifier("nova.checklist.run")
    }

    @ViewBuilder private var questions: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.checklist.run.questions", table: .localizable,
                fallback: "Sorular"), style: .cardTitle)
            ForEach(run.answers) { answer in
                Button {
                    guard canWrite, run.state == .open else { return }
                    draft = .init(runID: run.id, itemCode: answer.itemCode, prompt: answer.prompt,
                                  allowsNotApplicable: answer.allowsNotApplicable,
                                  result: answer.result ?? .conform,
                                  note: answer.note ?? "",
                                  openNonconformity: answer.nonconformityID != nil)
                } label: {
                    NovaCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                NovaSizedText(text: "\(answer.position).", size: 12, weight: "Bold",
                                    color: NovaColorToken.textMuted.color(in: scheme))
                                NovaText(text: answer.prompt, style: .body)
                                Spacer(minLength: 0)
                                if let result = answer.result {
                                    NovaStatusPill(label: result.title, status: tone(result))
                                } else {
                                    NovaStatusPill(label: RDLocalization.string(
                                        "localizable.nova.checklist.run.unanswered", table: .localizable,
                                        fallback: "Yanıtsız"), status: .neutral)
                                }
                            }
                            if let note = answer.note, !note.isEmpty {
                                NovaText(text: note, style: .meta,
                                    color: NovaColorToken.textSecondary.color(in: scheme))
                            }
                            if answer.nonconformityID != nil {
                                NovaAnalysisTag(symbol: "exclamationmark.triangle",
                                    text: RDLocalization.string("localizable.nova.checklist.run.opened",
                                        table: .localizable, fallback: "Uygunsuzluk kaydı açıldı"),
                                    status: .warning)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nova.checklist.question.\(answer.itemCode)")
            }
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if run.remaining > 0 {
                NovaHelpHint(text: String(format: RDLocalization.string(
                    "localizable.nova.checklist.run.remaining", table: .localizable,
                    fallback: "%d soru yanıtsız. Hepsi yanıtlanmadan tamamlanamaz."), run.remaining))
            }
            HStack(spacing: 10) {
                NovaButton(label: RDLocalization.string("localizable.nova.checklist.run.cancel",
                    table: .localizable, fallback: "Vazgeç"), symbol: "xmark.circle", variant: .surface) {
                    Task { working = true; failure = await onCancel(); working = false }
                }
                .disabled(working)
                NovaButton(label: RDLocalization.string("localizable.nova.checklist.run.submit",
                    table: .localizable, fallback: "Kontrolü tamamla"), symbol: "checkmark.circle",
                    variant: .primary) {
                    Task { working = true; failure = await onSubmit(); working = false }
                }
                .disabled(working || run.remaining > 0)
            }
        }
    }

    private func tone(_ result: NovaChecklistResult) -> NovaStatus {
        switch result {
        case .conform: return .success
        case .nonconform: return .warning
        case .notApplicable: return .neutral
        }
    }
}

/// Answering one question. The record offer only appears once the answer is
/// "uygun değil", and it is always an offer.
struct NovaChecklistAnswerSheet: View {
    @State var draft: NovaChecklistAnswerDraft
    let onSave: (NovaChecklistAnswerDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @Environment(\.colorScheme) private var scheme

    private var results: [NovaChecklistResult] {
        draft.allowsNotApplicable ? NovaChecklistResult.allCases : [.conform, .nonconform]
    }

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaPopupHeading(text: draft.prompt, symbol: "checklist")
                    if !draft.allowsNotApplicable {
                        NovaHelpHint(text: RDLocalization.string("localizable.nova.checklist.answer.nona",
                            table: .localizable,
                            fallback: "Bu soru için \"Uygulanamaz\" seçeneği listede kapalı bırakılmış."))
                    }
                    VStack(spacing: 6) {
                        ForEach(results) { result in
                            Button { draft.result = result } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: draft.result == result ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 14, weight: .semibold))
                                    Image(systemName: result.symbol).font(.system(size: 12, weight: .semibold))
                                    NovaText(text: result.title, style: .body)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 8).padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(NovaColorToken.hairline.color(in: scheme), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("nova.checklist.answer.\(result.rawValue)")
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.checklist.answer.note",
                            table: .localizable, fallback: "Not"), style: .label)
                        TextEditor(text: $draft.note).frame(minHeight: 60)
                            .accessibilityIdentifier("nova.checklist.answer.note")
                    }
                    if draft.result == .nonconform { record }
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    HStack(spacing: 10) {
                        NovaButton(label: RDLocalization.string("localizable.nova.checklist.cancel",
                            table: .localizable, fallback: "Vazgeç"), symbol: "xmark",
                            variant: .surface, action: onClose)
                        NovaButton(label: RDLocalization.string("localizable.nova.checklist.answer.save",
                            table: .localizable, fallback: "Yanıtı kaydet"), symbol: "checkmark",
                            variant: .primary) {
                            Task { saving = true; failure = await onSave(draft); saving = false }
                        }
                        .disabled(saving)
                    }
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .accessibilityIdentifier("nova.checklist.answer.sheet")
    }

    /// The offer. Off by default, and the sentence beside it says why.
    @ViewBuilder private var record: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Button { draft.openNonconformity.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: draft.openNonconformity ? "checkmark.square.fill" : "square")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(draft.openNonconformity
                                ? NovaColorToken.accentInk.color(in: scheme)
                                : NovaColorToken.textMuted.color(in: scheme))
                        NovaText(text: RDLocalization.string("localizable.nova.checklist.answer.open",
                            table: .localizable, fallback: "Bu madde için uygunsuzluk kaydı aç"), style: .body)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nova.checklist.answer.open")
                NovaText(text: NovaChecklistWords.neverAutomatic, style: .meta,
                    color: NovaColorToken.textSecondary.color(in: scheme))
                if draft.openNonconformity {
                    VStack(alignment: .leading, spacing: 6) {
                        NovaText(text: RDLocalization.string("localizable.nova.checklist.answer.severity",
                            table: .localizable, fallback: "Önem"), style: .label)
                        HStack(spacing: 6) {
                            ForEach(NovaChecklistSeverity.allCases) { severity in
                                Button { draft.severity = severity } label: {
                                    NovaSizedText(text: severity.title, size: 11,
                                        weight: draft.severity == severity ? "Bold" : "Medium",
                                        color: draft.severity == severity
                                            ? NovaColorToken.accentInk.color(in: scheme)
                                            : NovaColorToken.textSecondary.color(in: scheme))
                                        .padding(.vertical, 6).padding(.horizontal, 9)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(NovaColorToken.hairline.color(in: scheme), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("nova.checklist.answer.severity.\(severity.rawValue)")
                            }
                        }
                        NovaDayField(label: RDLocalization.string("localizable.nova.checklist.answer.due",
                            table: .localizable, fallback: "Termin"),
                            value: $draft.dueOn, identifier: "nova.checklist.answer.due", isClearable: true)
                    }
                }
            }
        }
    }
}

/// The expert's own lists. A published version is shown but never editable;
/// changing a list means opening a new version.
struct NovaChecklistTemplateSheet: View {
    let templates: [NovaChecklistTemplate]
    var canWrite: Bool = true
    let onDraft: (String) async -> String?
    let onSetItem: (String, Int, String, String, Bool, Int) async -> String?
    let onRemoveItem: (String, Int, String) async -> String?
    let onPublish: (String, Int, String) async -> String?
    let onClose: () -> Void
    @State private var newTitle = ""
    @State private var prompt = ""
    @State private var allowsNA = true
    @State private var editing: String?
    @State private var approvalNote = ""
    @State private var failure: String?
    @State private var working = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NovaPopupHeading(text: RDLocalization.string("localizable.nova.checklist.templates.title",
                        table: .localizable, fallback: "Kontrol listelerim"), symbol: "checklist")
                    NovaText(text: NovaChecklistWords.noProductList, style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    if canWrite { creator }
                    ForEach(templates) { template in card(template) }
                    NovaButton(label: RDLocalization.string("localizable.nova.checklist.close",
                        table: .localizable, fallback: "Kapat"), symbol: "xmark",
                        variant: .surface, action: onClose)
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .accessibilityIdentifier("nova.checklist.templates")
    }

    @ViewBuilder private var creator: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                NovaText(text: RDLocalization.string("localizable.nova.checklist.templates.new",
                    table: .localizable, fallback: "Yeni liste"), style: .cardTitle)
                TextField(RDLocalization.string("localizable.nova.checklist.templates.name",
                    table: .localizable, fallback: "Liste adı"), text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("nova.checklist.templates.name")
                NovaButton(label: RDLocalization.string("localizable.nova.checklist.templates.create",
                    table: .localizable, fallback: "Taslak oluştur"), symbol: "plus", variant: .primary) {
                    let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    Task { working = true; failure = await onDraft(title); newTitle = ""; working = false }
                }
                .disabled(working)
            }
        }
    }

    @ViewBuilder private func card(_ template: NovaChecklistTemplate) -> some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    NovaText(text: template.title, style: .cardTitle)
                    Spacer(minLength: 0)
                    if template.isProduct {
                        NovaAnalysisTag(symbol: "shippingbox",
                            text: RDLocalization.string("localizable.nova.checklist.templates.product",
                                table: .localizable, fallback: "Ürün listesi"), status: .neutral)
                    }
                }
                ForEach(template.versions) { version in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            NovaSizedText(text: "v\(version.version)", size: 12, weight: "Bold")
                            NovaStatusPill(label: version.statusTitle,
                                status: version.isPublished ? .success : version.isDraft ? .info : .neutral)
                            Spacer(minLength: 0)
                            NovaSizedText(text: String(format: RDLocalization.string(
                                "localizable.nova.checklist.templates.items", table: .localizable,
                                fallback: "%d soru"), version.items.count), size: 10.5, weight: "Medium",
                                color: NovaColorToken.textMuted.color(in: scheme))
                        }
                        if let note = version.approvalNote, !note.isEmpty {
                            NovaText(text: note, style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        ForEach(version.items) { item in
                            HStack(spacing: 6) {
                                NovaSizedText(text: "\(item.position).", size: 10.5, weight: "Bold",
                                    color: NovaColorToken.textMuted.color(in: scheme))
                                NovaText(text: item.prompt, style: .meta)
                                Spacer(minLength: 0)
                                if canWrite && version.isDraft && !template.isProduct {
                                    Button {
                                        Task {
                                            working = true
                                            failure = await onRemoveItem(template.templateCode, version.version, item.itemCode)
                                            working = false
                                        }
                                    } label: {
                                        Image(systemName: "trash").font(.system(size: 11))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("nova.checklist.templates.remove.\(item.itemCode)")
                                }
                            }
                        }
                        if canWrite && version.isDraft && !template.isProduct {
                            draftEditor(template, version)
                        }
                        if version.isPublished {
                            NovaText(text: NovaChecklistWords.selfApproved, style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder private func draftEditor(_ template: NovaChecklistTemplate,
                                          _ version: NovaChecklistTemplateVersion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(RDLocalization.string("localizable.nova.checklist.templates.prompt",
                table: .localizable, fallback: "Soru metni"), text: $prompt)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("nova.checklist.templates.prompt")
            Button { allowsNA.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: allowsNA ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13, weight: .semibold))
                    NovaText(text: RDLocalization.string("localizable.nova.checklist.templates.allowna",
                        table: .localizable, fallback: "\"Uygulanamaz\" yanıtına izin ver"), style: .meta)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("nova.checklist.templates.allowna")
            NovaButton(label: RDLocalization.string("localizable.nova.checklist.templates.add",
                table: .localizable, fallback: "Soru ekle"), symbol: "plus.circle", variant: .surface) {
                let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                // The stored code is derived from the position so the expert
                // never has to invent one.
                let position = version.items.count + 1
                Task {
                    working = true
                    failure = await onSetItem(template.templateCode, version.version,
                                              "q\(position)", text, allowsNA, position)
                    prompt = ""; working = false
                }
            }
            .disabled(working)
            TextField(RDLocalization.string("localizable.nova.checklist.templates.note",
                table: .localizable, fallback: "Yayımlama notu"), text: $approvalNote)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("nova.checklist.templates.note")
            NovaButton(label: RDLocalization.string("localizable.nova.checklist.templates.publish",
                table: .localizable, fallback: "Yayımla"), symbol: "checkmark.seal", variant: .primary) {
                let note = approvalNote.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !note.isEmpty, !version.items.isEmpty else { return }
                Task {
                    working = true
                    failure = await onPublish(template.templateCode, version.version, note)
                    approvalNote = ""; working = false
                }
            }
            .disabled(working || version.items.isEmpty)
            NovaText(text: NovaChecklistWords.selfApproved, style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
        }
    }
}

extension NovaChecklistAnswerDraft: Identifiable { var id: String { (runID?.uuidString ?? "") + itemCode } }

struct NovaChecklistAuthoring: View {
    let client: NovaChecklistClient
    let company: UUID
    let onClose: () -> Void
    @State private var templates: [NovaChecklistTemplate] = []
    @State private var failure: String?
    var body: some View {
        NovaChecklistTemplateSheet(templates: templates, canWrite: true,
            onDraft: { title in await mutate { try await client.draftTemplate(company,title) } },
            onSetItem: { code,version,item,prompt,na,position in await mutate { try await client.setItem(company,code,version,item,prompt,na,position) } },
            onRemoveItem: { code,version,item in await mutate { try await client.removeItem(company,code,version,item) } },
            onPublish: { code,version,note in await mutate { try await client.publishTemplate(company,code,version,note) } },
            onClose: onClose)
            .task { do { templates = try await client.templates(company) } catch { failure = "Listeler yüklenemedi." } }
            .overlay(alignment:.bottom) { if let failure { Text(failure).padding().background(.regularMaterial) } }
    }
    private func mutate(_ operation: () async throws -> Void) async -> String? {
        do { try await operation(); templates = try await client.templates(company); return nil }
        catch let error as NovaChecklistFailure { return error.message }
        catch { return "İşlem tamamlanamadı. Yeniden deneyin." }
    }
}


struct NovaChecklistStartForm: View {
    let catalogue: NovaChecklistCatalogue
    let onStart: (UUID, String, String) async -> String?
    @State private var workplace: UUID?
    @State private var template = ""
    @State private var day = Date()
    @State private var busy = false
    @State private var failure: String?
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            NovaPopupHeading(text: "Kontrol başlat", symbol: "checklist")
            if catalogue.starters.isEmpty {
                NovaText(text: "Önce Listelerim bölümünden sorularınızı ekleyip listeyi yayımlayın.", style: .body)
            } else if catalogue.workplaces.isEmpty {
                NovaText(text: "Önce firma detayından işyeri ekleyin.", style: .body)
            } else {
                // A company with exactly one workplace has nothing to ask —
                // only a real choice among several is shown as a picker.
                if catalogue.workplaces.count > 1 {
                    Picker("İşyeri", selection: $workplace) {
                        Text("İşyeri seçin").tag(UUID?.none)
                        ForEach(catalogue.workplaces) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Picker("Kontrol listesi", selection: $template) {
                    Text("Liste seçin").tag("")
                    ForEach(catalogue.starters) { Text($0.title + " · v\($0.version)").tag($0.templateCode) }
                }
                DatePicker("Kontrol tarihi", selection: $day, in: ...Date(), displayedComponents: .date)
                if let failure { NovaText(text: failure, style: .body) }
                NovaButton(label: busy ? "Başlatılıyor…" : "Başlat", symbol: "play", variant: .primary) {
                    guard let workplace else { return }
                    Task {
                        busy = true
                        failure = await onStart(workplace, template, NovaDayField.text(day))
                        busy = false
                    }
                }.disabled(busy || workplace == nil || template.isEmpty)
            }
        }.padding(20).novaPopupContentSize().disabled(busy)
        }
            .preference(key: NovaPopupBusyKey.self, value: busy)
            .task { if catalogue.workplaces.count == 1 { workplace = catalogue.workplaces.first?.id } }
    }
}
