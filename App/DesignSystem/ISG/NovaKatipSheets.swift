import SwiftUI

/// One contract. The record repeats the two sentences the module is built
/// around: nothing was filed officially, and nobody here knows how much
/// service time is required.
struct NovaKatipDetailSheet: View {
    let entry: NovaKatipContract
    var canWrite: Bool = true
    let onEnd: () -> Void
    let onArchive: () async -> String?
    let onClose: () -> Void
    var openDocument: () async throws -> URL = { throw NovaKatipFailure.unavailable }
    @State private var openedDocument: URL?
    @State private var temporaryDocument: URL?
    var documents: (Int) async throws -> [NovaFileEntry] = { _ in [] }
    var onLink: (UUID?) async throws -> Void = { _ in }
    @State private var choosingDocument = false
    @State private var availableDocuments: [NovaFileEntry] = []
    @State private var moreDocuments = true
    @State private var documentOffset = 0
    @State private var failure: String?
    @State private var working = false
    @Environment(\.colorScheme) private var scheme

    private var unset: String {
        RDLocalization.string("localizable.nova.katip.unset", table: .localizable, fallback: "Belirtilmedi")
    }

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: entry.counterparty, style: .screenTitle)
                        NovaText(text: [entry.scope, entry.workplaceName, entry.companyName]
                            .compactMap { $0 }.joined(separator: " · "), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        NovaText(text: NovaKatipWords.explain(entry), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    facts
                    declared
                    document
                    if canWrite && entry.state != .archived {
                        HStack(spacing: 10) {
                            NovaButton(label: entry.endsBefore == nil
                                ? RDLocalization.string("localizable.nova.katip.detail.end",
                                    table: .localizable, fallback: "Sözleşmeyi bitir")
                                : RDLocalization.string("localizable.nova.katip.detail.fix",
                                    table: .localizable, fallback: "Bitiş tarihini düzelt"),
                                symbol: "calendar.badge.minus", variant: .primary, action: onEnd)
                            NovaButton(label: RDLocalization.string("localizable.nova.katip.detail.archive",
                                table: .localizable, fallback: "Arşivle"),
                                symbol: "archivebox", variant: .muted) {
                                Task { working = true; failure = await onArchive(); working = false }
                            }
                            .disabled(working)
                        }
                    }
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    NovaButton(label: RDLocalization.string("localizable.nova.katip.close",
                        table: .localizable, fallback: "Kapat"), symbol: "xmark",
                        variant: .surface, action: onClose)
                }
                .padding(20)
            }
        }
        .sheet(item: $openedDocument, onDismiss: {
            if let url = temporaryDocument { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            temporaryDocument = nil
        }) { url in NovaFileShareSheet(url: url) }
        .accessibilityIdentifier("nova.katip.detail")
    }

    @ViewBuilder private var facts: some View {
        NovaCard(padding: 14) {
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                cell("calendar", RDLocalization.string("localizable.nova.katip.row.starts",
                    table: .localizable, fallback: "Başlangıç"), entry.startsOn)
                cell("calendar.badge.minus", RDLocalization.string("localizable.nova.katip.row.ends",
                    table: .localizable, fallback: "Bitiş"),
                    // An open ended contract has no missing date: it has none.
                    entry.term == .openEnded
                        ? RDLocalization.string("localizable.nova.katip.term.open",
                            table: .localizable, fallback: "Süresiz")
                        : (entry.endsBefore ?? unset))
                cell("doc.text", RDLocalization.string("localizable.nova.katip.row.term",
                    table: .localizable, fallback: "Tür"), entry.term.title)
                cell("person", RDLocalization.string("localizable.nova.katip.row.expert",
                    table: .localizable, fallback: "Uzman"), entry.expertContact)
            }
            // Said on the record itself, not only at the top of the board.
            NovaHelpHint(text: NovaKatipWords.noIntegrationNote)
            if !entry.officialSubmissionMade {
                NovaAnalysisTag(symbol: "nosign",
                    text: RDLocalization.string("localizable.nova.katip.detail.nofiling",
                        table: .localizable, fallback: "Resmî sisteme hiçbir bildirim yapılmadı"),
                    status: .neutral)
            }
        }
    }

    @ViewBuilder private var declared: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                NovaText(text: RDLocalization.string("localizable.nova.katip.detail.declared",
                    table: .localizable, fallback: "Beyan edilen hizmet süresi"), style: .cardTitle)
                if let minutes = entry.declaredMonthlyMinutes {
                    NovaText(text: NovaKatipWords.service(minutes), style: .body)
                } else {
                    NovaText(text: unset, style: .body,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
                if let note = entry.declaredNote, !note.isEmpty {
                    NovaText(text: note, style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
                // The product never compares the declared time to a requirement,
                // because it does not hold one.
                NovaText(text: NovaKatipWords.declaredNote, style: .meta,
                    color: NovaColorToken.textSecondary.color(in: scheme))
                if !entry.requiredServiceTimeKnown {
                    NovaAnalysisTag(symbol: "questionmark.circle",
                        text: RDLocalization.string("localizable.nova.katip.detail.norequirement",
                            table: .localizable, fallback: "Gereken süre bilinmiyor"),
                        status: .neutral)
                }
            }
        }
    }

    @ViewBuilder private var document: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                NovaText(text: RDLocalization.string("localizable.nova.katip.detail.document",
                    table: .localizable, fallback: "Sözleşme aslı"), style: .cardTitle)
                NovaText(text: entry.contractLocation ?? unset, style: .body,
                    color: entry.contractLocation == nil
                        ? NovaColorToken.textSecondary.color(in: scheme)
                        : NovaColorToken.text.color(in: scheme))
                if let title = entry.documentTitle {
                    NovaText(text: title, style: .body)
                    if !entry.contractStored {
                        NovaText(text: "Bağlı dosya artık kullanılamıyor.", style: .meta)
                    }
                }
                if entry.contractStored {
                    NovaButton(label: "Dosyayı aç / paylaş", symbol: "square.and.arrow.up", variant: .surface) {
                        Task {
                            working = true; failure = nil
                            defer { working = false }
                            do {
                                let url = try await openDocument()
                                temporaryDocument = url; openedDocument = url
                            } catch { failure = "Dosya açılamadı. Yetkinizi ve bağlantınızı kontrol edin." }
                        }
                    }.disabled(working)
                }
                if canWrite && entry.state != .archived {
                    NovaButton(label: entry.fileEntryID == nil ? "Evraktan dosya bağla" : "Bağlı dosyayı değiştir",
                               symbol: "paperclip", variant: .surface) {
                        choosingDocument.toggle()
                        if choosingDocument { Task { await loadDocuments(reset: true) } }
                    }.disabled(working)
                    if entry.fileEntryID != nil {
                        NovaButton(label: "Dosya bağlantısını kaldır", symbol: "link", variant: .muted) {
                            Task { await link(nil) }
                        }.disabled(working)
                    }
                }
                if choosingDocument {
                    ForEach(availableDocuments) { file in
                        NovaButton(label: file.title, symbol: "doc", variant: .surface) {
                            Task { await link(file.id) }
                        }.disabled(working)
                    }
                    if moreDocuments {
                        NovaButton(label: "Daha fazla dosya", symbol: "chevron.down", variant: .muted) {
                            Task { await loadDocuments(reset: false) }
                        }.disabled(working)
                    }
                    if availableDocuments.isEmpty && !working {
                        NovaText(text: "Bu firmaya ait hazır dosya bulunamadı. Evraklar bölümünden dosya yükleyebilirsiniz.", style: .meta)
                    }
                }
            }
        }
    }

    private func loadDocuments(reset: Bool) async {
        guard !working else { return }
        working = true; failure = nil
        defer { working = false }
        do {
            let offset = reset ? 0 : documentOffset
            let page = try await documents(offset)
            availableDocuments = reset ? page : availableDocuments + page
            documentOffset = offset + page.count
            moreDocuments = page.count == 20
        } catch { failure = "Dosyalar alınamadı. Yeniden deneyin." }
    }

    private func link(_ file: UUID?) async {
        guard !working else { return }
        working = true; failure = nil
        defer { working = false }
        do { try await onLink(file); choosingDocument = false }
        catch let error as NovaKatipFailure { failure = error.message }
        catch { failure = "Dosya bağlantısı kaydedilemedi. Yeniden deneyin." }
    }

    @ViewBuilder private func cell(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            VStack(alignment: .leading, spacing: 1) {
                NovaSizedText(text: label, size: 9, weight: "Medium",
                    color: NovaColorToken.textMuted.color(in: scheme))
                NovaSizedText(text: value, size: 12, weight: "Bold")
            }
            Spacer(minLength: 0)
        }
    }
}

/// Recording a contract. Leaving the end date empty is a decision, not an
/// omission: it records an open ended contract.
struct NovaKatipContractSheet: View {
    @State var draft: NovaKatipDraft
    let catalogue: NovaKatipCatalogue?
    let onSave: (NovaKatipDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @State private var openChooser = false
    @Environment(\.colorScheme) private var scheme

    private var placeTitle: String {
        catalogue?.workplaces.first { $0.id == draft.workplaceID }?.name
            ?? RDLocalization.string("localizable.nova.katip.form.pickplace", table: .localizable,
                fallback: "İşyeri seçin")
    }
    private var canSave: Bool {
        draft.workplaceID != nil
            && !draft.counterparty.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.expertContact.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.scope.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaText(text: RDLocalization.string("localizable.nova.katip.form.title",
                        table: .localizable, fallback: "Sözleşme kaydet"), style: .screenTitle)
                    // First thing on the form, before any field.
                    NovaHelpHint(text: NovaKatipWords.noIntegrationNote)

                    // A company with no workplace has nothing to ask, and one
                    // with exactly one gets it silently — only a real choice
                    // among several is shown as a picker.
                    let workplaces = catalogue?.workplaces ?? []
                    if workplaces.count <= 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: RDLocalization.string("localizable.nova.katip.form.workplace",
                                table: .localizable, fallback: "İşyeri"), style: .label,
                                color: NovaColorToken.textTertiary.color(in: scheme))
                            NovaText(text: workplaces.isEmpty
                                ? RDLocalization.string("localizable.nova.katip.form.noworkplace", table: .localizable,
                                    fallback: "Bu firmada kayıt açılacak bir işyeri yok.")
                                : placeTitle, style: .cardTitle)
                        }
                    } else {
                        NovaFileChooserButton(
                            label: RDLocalization.string("localizable.nova.katip.form.workplace",
                                table: .localizable, fallback: "İşyeri"),
                            value: placeTitle, isOpen: openChooser,
                            identifier: "nova.katip.form.workplace") { openChooser.toggle() }
                        if openChooser {
                            NovaFileChooserPanel(
                                options: workplaces.map { .init(id: $0.id.uuidString, title: $0.name) },
                                selected: draft.workplaceID?.uuidString,
                                identifier: "nova.katip.form.workplace.panel") { value in
                                draft.workplaceID = value.flatMap(UUID.init(uuidString:))
                                openChooser = false
                            }
                        }
                    }

                    field(RDLocalization.string("localizable.nova.katip.form.counterparty",
                        table: .localizable, fallback: "Karşı taraf (OSGB veya işveren)"),
                        $draft.counterparty, "nova.katip.form.counterparty")
                    field(RDLocalization.string("localizable.nova.katip.form.expert",
                        table: .localizable, fallback: "Uzman / hekim"),
                        $draft.expertContact, "nova.katip.form.expert")
                    field(RDLocalization.string("localizable.nova.katip.form.scope",
                        table: .localizable, fallback: "Kapsam"),
                        $draft.scope, "nova.katip.form.scope")

                    NovaDayField(label: RDLocalization.string("localizable.nova.katip.row.starts",
                        table: .localizable, fallback: "Başlangıç"),
                        value: $draft.startsOn, identifier: "nova.katip.form.starts")
                    VStack(alignment: .leading, spacing: 4) {
                        NovaDayField(label: RDLocalization.string("localizable.nova.katip.row.ends",
                            table: .localizable, fallback: "Bitiş"),
                            value: $draft.endsBefore, identifier: "nova.katip.form.ends",
                            isClearable: true)
                        NovaText(text: RDLocalization.string("localizable.nova.katip.form.openhint",
                            table: .localizable,
                            fallback: "Bitiş tarihi boş bırakılırsa sözleşme süresiz olarak kaydedilir."),
                            style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.katip.form.minutes",
                            table: .localizable, fallback: "Beyan edilen aylık süre (dakika)"), style: .label)
                        TextField("", text: $draft.declaredMonthlyMinutes)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("nova.katip.form.minutes")
                        TextField(RDLocalization.string("localizable.nova.katip.form.declarednote",
                            table: .localizable, fallback: "Süreye dair not"), text: $draft.declaredNote)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("nova.katip.form.declarednote")
                        NovaText(text: NovaKatipWords.declaredNote, style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.katip.form.location",
                            table: .localizable, fallback: "Sözleşme aslı nerede"), style: .label)
                        TextField("", text: $draft.contractLocation)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("nova.katip.form.location")
                        NovaText(text: NovaKatipWords.documentNote, style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }

                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    HStack(spacing: 10) {
                        NovaButton(label: RDLocalization.string("localizable.nova.katip.cancel",
                            table: .localizable, fallback: "Vazgeç"), symbol: "xmark",
                            variant: .surface, action: onClose)
                        NovaButton(label: RDLocalization.string("localizable.nova.katip.form.save",
                            table: .localizable, fallback: "Kaydet"), symbol: "checkmark",
                            variant: .primary) {
                            Task { saving = true; failure = await onSave(draft); saving = false }
                        }
                        .disabled(saving || !canSave)
                    }
                }
                .padding(20)
            }
        }
        .accessibilityIdentifier("nova.katip.form")
        .onAppear {
            if draft.workplaceID == nil, let only = catalogue?.workplaces, only.count == 1 {
                draft.workplaceID = only[0].id
            }
        }
    }

    @ViewBuilder private func field(_ label: String, _ value: Binding<String>,
                                    _ identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: label, style: .label)
            TextField("", text: value).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// Ending a contract, or correcting the date it ended.
struct NovaKatipEndSheet: View {
    @State var draft: NovaKatipEndDraft
    let onSave: (NovaKatipEndDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaText(text: draft.isCorrection
                        ? RDLocalization.string("localizable.nova.katip.detail.fix",
                            table: .localizable, fallback: "Bitiş tarihini düzelt")
                        : RDLocalization.string("localizable.nova.katip.detail.end",
                            table: .localizable, fallback: "Sözleşmeyi bitir"), style: .screenTitle)
                    if !draft.counterparty.isEmpty {
                        NovaText(text: draft.counterparty, style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    NovaHelpHint(text: String(format: RDLocalization.string(
                        "localizable.nova.katip.end.after", table: .localizable,
                        fallback: "Sözleşme %@ tarihinde başladı; bitiş bundan önce olamaz."), draft.startsOn))
                    NovaDayField(label: RDLocalization.string("localizable.nova.katip.row.ends",
                        table: .localizable, fallback: "Bitiş"),
                        value: $draft.endsBefore, identifier: "nova.katip.end.date")
                    // Ending the record here ends nothing anywhere else.
                    NovaText(text: RDLocalization.string("localizable.nova.katip.end.note",
                        table: .localizable,
                        fallback: "Bu işlem yalnız sizin kaydınızı kapatır; resmî sistemde hiçbir şey değişmez."),
                        style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    HStack(spacing: 10) {
                        NovaButton(label: RDLocalization.string("localizable.nova.katip.cancel",
                            table: .localizable, fallback: "Vazgeç"), symbol: "xmark",
                            variant: .surface, action: onClose)
                        NovaButton(label: RDLocalization.string("localizable.nova.katip.end.save",
                            table: .localizable, fallback: "Kaydet"), symbol: "checkmark",
                            variant: .primary) {
                            Task { saving = true; failure = await onSave(draft); saving = false }
                        }
                        .disabled(saving)
                    }
                }
                .padding(20)
            }
        }
        .accessibilityIdentifier("nova.katip.end")
    }
}
