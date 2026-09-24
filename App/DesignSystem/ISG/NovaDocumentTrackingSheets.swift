import SwiftUI

/// One tracked obligation in full, and every action on it, in one popup: what
/// it is, who says it is owed, which copies are on file, and the compact panel
/// that records another one.
struct NovaDocumentObligationSheet: View {
    let obligation: NovaDocumentObligation
    let client: NovaDocumentTrackingClient
    var canWrite = true
    let onChanged: () -> Void
    let onClosed: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var current: NovaDocumentObligation?
    @State private var kinds: [NovaDocumentKind] = []
    @State private var places: [NovaDocumentWorkplace] = []
    @State private var editing = false
    @State private var recording = false
    @State private var confirmingArchive = false
    @State private var copy = NovaDocumentCopyDraft()
    @State private var busy = false
    @State private var error: String?

    private var row: NovaDocumentObligation { current ?? obligation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                heading
                chips
                facts
                copies
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
                controls
            }.padding(16).novaPopupContentSize()
        }
        .task {
            guard let company = row.companyID else { return }
            kinds = (try? await client.kinds(company)) ?? []
            places = (try? await client.workplaces(company)) ?? []
        }
        .novaPopupCover(isPresented: $editing) {
            NovaPopup {
                NovaDocumentObligationForm(title: RDLocalization.string("localizable.nova.document.edit.title", table: .localizable, fallback: "Takip kaydını düzenle"),
                    kinds: kinds, places: places, draft: Self.draft(row), isKindLocked: true) { value in
                        current = try await client.update(row, value)
                        editing = false
                        onChanged()
                    }
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 10) {
            NovaIcon(symbol: NovaDocumentWords.kindSymbol(row.kindCode), size: 19)
                .foregroundStyle(NovaDocumentWords.tone(row.status).tokens.ink.color(in: scheme))
                .frame(width: 44, height: 44)
                .background(NovaDocumentWords.tone(row.status).tokens.background.color(in: scheme),
                            in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                NovaText(text: row.title, style: .sheetTitle).lineLimit(2)
                if NovaDocumentWords.kind(row.kindCode) != row.title {
                    NovaText(text: NovaDocumentWords.kind(row.kindCode), style: .metaQuiet)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        HStack(spacing: 5) {
            NovaStatusPill(label: NovaDocumentWords.status(row.status),
                status: NovaDocumentWords.tone(row.status))
            if let name = row.companyName {
                NovaAnalysisTag(symbol: "building.2", text: name, status: .neutral)
            }
            NovaAnalysisTag(symbol: row.basis == .legal ? "book" : "person",
                text: NovaDocumentWords.basis(row.basis), status: .neutral)
            Spacer(minLength: 0)
        }
    }

    private var facts: some View {
        NovaCard(padding: 11) {
            VStack(alignment: .leading, spacing: 8) {
                // The basis is the expert's own, so it is attributed to them
                // rather than presented as the product's finding.
                if row.basis == .legal, let reference = row.legalRef {
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: RDLocalization.string("localizable.nova.document.field.legal.ref", table: .localizable,
                            fallback: "Uzmanın dayandığı mevzuat"), style: .micro,
                            color: NovaColorToken.textTertiary.color(in: scheme))
                        NovaText(text: reference, style: .meta)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)],
                          alignment: .leading, spacing: 7) {
                    cell("building.2", RDLocalization.string("localizable.nova.document.field.scope", table: .localizable, fallback: "Kapsam"),
                         row.workplaceName ?? RDLocalization.string("localizable.nova.document.scope.company", table: .localizable, fallback: "Tüm firma"))
                    cell("hourglass", RDLocalization.string("localizable.nova.document.field.validity", table: .localizable, fallback: "Geçerlilik"),
                         row.validityDays.map { String(format: RDLocalization.string("localizable.nova.document.validity.days", table: .localizable,
                            fallback: "%d gün"), $0) }
                            ?? RDLocalization.string("localizable.nova.document.validity.none", table: .localizable, fallback: "Süresiz"))
                    cell("bell", RDLocalization.string("localizable.nova.document.field.notice", table: .localizable, fallback: "Uyarı penceresi"),
                         String(format: RDLocalization.string("localizable.nova.document.validity.days", table: .localizable, fallback: "%d gün"), row.noticeDays))
                    cell("person", RDLocalization.string("localizable.nova.document.field.responsible", table: .localizable, fallback: "Sorumlu"),
                         row.responsibleContact ?? "—")
                }
                if let note = row.note, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: RDLocalization.string("localizable.nova.document.field.note", table: .localizable, fallback: "Not"),
                            style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                        NovaText(text: note, style: .metaQuiet)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cell(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                NovaText(text: label, style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                NovaText(text: value, style: .meta).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 11))
    }

    private var copies: some View {
        NovaCard(padding: 11) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    NovaText(text: RDLocalization.string("localizable.nova.document.copies", table: .localizable, fallback: "Dosyadaki kopyalar"), style: .cardTitle)
                    Spacer(minLength: 0)
                    if canWrite && !row.isArchived {
                        Button { recording.toggle(); error = nil } label: {
                            HStack(spacing: 4) {
                                Image(systemName: recording ? "xmark" : "plus").font(.system(size: 10, weight: .bold))
                                NovaText(text: recording
                                    ? RDLocalization.string("localizable.nova.analysis.item.cancel", table: .localizable, fallback: "Vazgeç")
                                    : RDLocalization.string("localizable.nova.document.copy.add", table: .localizable, fallback: "Kopya kaydet"),
                                    style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                            }
                            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                            .padding(.horizontal, 10).frame(minHeight: 34)
                            .background(NovaColorToken.statusSuccessBg.color(in: scheme), in: Capsule())
                        }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("document.copy.add")
                    }
                }
                // The tracker keeps a reference, never the document itself.
                NovaText(text: RDLocalization.string("localizable.nova.document.copies.hint", table: .localizable,
                    fallback: "Dosyanın kendisi burada saklanmaz; aslının nerede olduğuna dair kaydınız tutulur."),
                    style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                if recording { recorder }
                if row.copies.isEmpty && !recording {
                    NovaText(text: RDLocalization.string("localizable.nova.document.copies.empty", table: .localizable,
                        fallback: "Henüz kopya kaydedilmedi."), style: .metaQuiet)
                } else {
                    ForEach(row.copies) { entry in copyRow(entry) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Recording a copy happens in place: two dates and two references, without
    /// leaving the record that is being read.
    private var recorder: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                NovaDayField(label: RDLocalization.string("localizable.nova.document.field.issued", table: .localizable, fallback: "Düzenlenme tarihi"),
                    value: $copy.issuedOn, identifier: "document.copy.issued")
                NovaDayField(label: RDLocalization.string("localizable.nova.document.field.valid.until", table: .localizable, fallback: "Geçerlilik bitişi"),
                    value: $copy.validUntil, identifier: "document.copy.until", isClearable: true)
            }
            NovaText(text: endDateHint, style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
            HStack(spacing: 9) {
                field(RDLocalization.string("localizable.nova.document.field.no", table: .localizable, fallback: "Belge no"), $copy.documentNo, id: "no")
                field(RDLocalization.string("localizable.nova.document.field.location", table: .localizable, fallback: "Aslı nerede"), $copy.locationNote, id: "location")
            }
            NovaButton(label: RDLocalization.string("localizable.nova.document.save", table: .localizable, fallback: "Kaydet"),
                symbol: "checkmark", isEnabled: !busy && copy.isReady, isLoading: busy) {
                Task {
                    busy = true; error = nil
                    do {
                        current = try await client.recordCopy(row, copy)
                        copy = NovaDocumentCopyDraft()
                        copy.issuedOn = NovaDayField.text(Date())
                        recording = false
                        onChanged()
                    }
                    catch let failure as NovaDocumentFailure { error = NovaDocumentWords.failure(failure) }
                    catch { self.error = NovaDocumentWords.failure(.validation) }
                    busy = false
                }
            }.accessibilityIdentifier("document.copy.save")
        }
        .padding(10)
        .background(NovaColorToken.statusSuccessBg.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
        .onAppear { if copy.issuedOn.isEmpty { copy.issuedOn = NovaDayField.text(Date()) } }
    }

    /// The end date the server will use when the field is left empty.
    private var endDateHint: String {
        guard copy.validUntil.isEmpty else {
            return RDLocalization.string("localizable.nova.document.valid.until.explicit", table: .localizable,
                fallback: "Girdiğiniz bitiş tarihi kullanılır.")
        }
        if let days = row.validityDays {
            return String(format: RDLocalization.string("localizable.nova.document.valid.until.derived", table: .localizable,
                fallback: "Boş bırakırsanız düzenlenme tarihine %d gün eklenir."), days)
        }
        return RDLocalization.string("localizable.nova.document.valid.until.open", table: .localizable,
            fallback: "Bu kayıt süresiz; boş bırakırsanız kopya süresiz sayılır.")
    }

    private func copyRow(_ entry: NovaDocumentCopy) -> some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    NovaAnalysisTag(symbol: "calendar", text: entry.issuedOn, status: .neutral)
                    if let until = entry.validUntil {
                        NovaAnalysisTag(symbol: "hourglass", text: until, status: .neutral)
                    } else {
                        NovaAnalysisTag(symbol: "infinity",
                            text: RDLocalization.string("localizable.nova.document.validity.none", table: .localizable, fallback: "Süresiz"),
                            status: .neutral)
                    }
                }
                if let number = entry.documentNo, !number.isEmpty { NovaText(text: number, style: .meta) }
                if let place = entry.locationNote, !place.isEmpty { NovaText(text: place, style: .metaQuiet) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if canWrite {
                Button {
                    Task {
                        busy = true; error = nil
                        do { current = try await client.removeCopy(row, entry); onChanged() }
                        catch let failure as NovaDocumentFailure { error = NovaDocumentWords.failure(failure) }
                        catch { self.error = NovaDocumentWords.failure(.validation) }
                        busy = false
                    }
                } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                        .foregroundStyle(NovaColorToken.statusDangerInk.color(in: scheme))
                        .frame(width: 34, height: 34)
                }.buttonStyle(NovaRowPressStyle()).disabled(busy)
                    .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.document.copy.remove", table: .localizable, fallback: "Kopyayı sil")))
                    .accessibilityIdentifier("document.copy.remove.\(entry.id.uuidString.lowercased())")
            }
        }
        .padding(9)
        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var controls: some View {
        if canWrite && !row.isArchived {
            HStack(spacing: 8) {
                action("square.and.pencil", RDLocalization.string("localizable.nova.document.edit.short", table: .localizable, fallback: "Düzenle"),
                       id: "edit", status: .neutral) { editing = true }
                action("archivebox", RDLocalization.string("localizable.nova.document.archive", table: .localizable, fallback: "Takipten çıkar"),
                       id: "archive", status: .danger) { confirmingArchive = true }
            }
            if confirmingArchive {
                NovaText(text: RDLocalization.string("localizable.nova.document.archive.confirm", table: .localizable,
                    fallback: "Kayıt listeden çıkar; kaydedilmiş kopyalar silinmez."), style: .metaQuiet)
                NovaButton(label: RDLocalization.string("localizable.nova.document.archive.yes", table: .localizable, fallback: "Evet, arşivle"),
                    symbol: "archivebox", variant: .danger, isEnabled: !busy, isLoading: busy) {
                    Task {
                        busy = true; error = nil
                        do { try await client.archive(row); onChanged(); onClosed() }
                        catch let failure as NovaDocumentFailure { error = NovaDocumentWords.failure(failure) }
                        catch { self.error = NovaDocumentWords.failure(.validation) }
                        busy = false
                    }
                }.accessibilityIdentifier("document.obligation.archive.confirm")
            }
        }
    }

    private func action(_ symbol: String, _ label: String, id: String, status: NovaStatus,
                        run: @escaping () -> Void) -> some View {
        let palette = status.tokens
        return Button(action: run) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                NovaText(text: label, style: .meta, color: palette.ink.color(in: scheme))
            }
            .foregroundStyle(palette.ink.color(in: scheme))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(palette.background.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(NovaRowPressStyle()).disabled(busy)
            .accessibilityIdentifier("document.obligation.\(id)")
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(NovaFont.font(.body))
                .frame(minHeight: 34).accessibilityIdentifier("document.copy.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    static func draft(_ value: NovaDocumentObligation) -> NovaDocumentDraft {
        var result = NovaDocumentDraft()
        result.kindCode = value.kindCode
        result.title = value.title
        result.workplaceID = value.workplaceID
        result.basis = value.basis
        result.legalRef = value.legalRef ?? ""
        result.validityDays = value.validityDays.map(String.init) ?? ""
        result.noticeDays = String(value.noticeDays)
        result.responsibleContact = value.responsibleContact ?? ""
        result.note = value.note ?? ""
        return result
    }
}

/// Adding a tracked document. The company comes first, because an obligation
/// belongs to one and the catalogue and workplaces are read for it.
struct NovaDocumentAddSheet: View {
    let companies: [NovaAnalysisCompanyOption]
    var preselected: UUID?
    var allowedKinds: [String]?
    let client: NovaDocumentTrackingClient
    let onSaved: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var company: UUID?
    @State private var kinds: [NovaDocumentKind] = []
    @State private var places: [NovaDocumentWorkplace] = []
    @State private var loading = false
    @State private var loaded = false

    var body: some View {
        Group {
            if let company {
                NovaDocumentObligationForm(
                    title: RDLocalization.string("localizable.nova.document.add.title", table: .localizable, fallback: "Takibe evrak ekle"),
                    kinds: kinds, places: places, draft: NovaDocumentDraft(),
                    companyName: companies.first { $0.id == company }?.name,
                    onChangeCompany: companies.count > 1 ? { self.company = nil; loaded = false } : nil) { draft in
                        _ = try await client.add(company, draft)
                        onSaved()
                    }
                    .task(id: company) { await load(company) }
            } else {
                picker
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            company = preselected ?? (companies.count == 1 ? companies.first?.id : nil)
        }
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: RDLocalization.string("localizable.nova.document.add.company", table: .localizable, fallback: "Hangi firma için?"), style: .sheetTitle)
                if companies.isEmpty {
                    NovaCard(padding: 14) {
                        NovaText(text: RDLocalization.string("localizable.nova.document.company.empty", table: .localizable,
                            fallback: "Evrak takibi için önce bir firma ekleyin."), style: .metaQuiet)
                    }
                }
                ForEach(companies) { option in
                    Button { company = option.id } label: {
                        NovaCard(padding: 13) {
                            HStack(spacing: 9) {
                                NovaIcon(symbol: "building.2", size: 15)
                                    .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                                VStack(alignment: .leading, spacing: 2) {
                                    NovaText(text: option.name, style: .cardTitle)
                                    if !option.detail.isEmpty { NovaText(text: option.detail, style: .metaQuiet) }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(NovaRowPressStyle())
                        .accessibilityIdentifier("document.add.company.\(option.id.uuidString.lowercased())")
                }
            }.padding(16).novaPopupContentSize()
        }
    }

    private func load(_ target: UUID) async {
        guard !loading else { return }
        loading = true
        var catalogue = (try? await client.kinds(target)) ?? []
        if let allowedKinds { catalogue = catalogue.filter { allowedKinds.contains($0.code) } }
        kinds = catalogue
        places = (try? await client.workplaces(target)) ?? []
        loading = false
    }
}

/// Adding or editing one tracked obligation.
struct NovaDocumentObligationForm: View {
    let title: String
    let kinds: [NovaDocumentKind]
    let places: [NovaDocumentWorkplace]
    @State var draft: NovaDocumentDraft
    var isKindLocked = false
    var companyName: String?
    var onChangeCompany: (() -> Void)?
    let save: (NovaDocumentDraft) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: title, style: .sheetTitle)
                        if let companyName { NovaText(text: companyName, style: .metaQuiet) }
                    }
                    Spacer(minLength: 0)
                    if let onChangeCompany {
                        Button(action: onChangeCompany) {
                            NovaText(text: RDLocalization.string("localizable.nova.document.add.change.company", table: .localizable, fallback: "Firmayı değiştir"),
                                style: .micro, color: NovaColorToken.accentInk.color(in: scheme))
                        }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("document.add.change.company")
                    }
                }
                kindPicker
                NovaCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        field(RDLocalization.string("localizable.nova.document.field.title", table: .localizable, fallback: "Kayıt adı"),
                              $draft.title, id: "title")
                        if !places.isEmpty { scopePicker }
                        field(RDLocalization.string("localizable.nova.document.field.responsible", table: .localizable, fallback: "Sorumlu"),
                              $draft.responsibleContact, id: "responsible")
                        HStack(spacing: 9) {
                            number(RDLocalization.string("localizable.nova.document.field.validity", table: .localizable, fallback: "Geçerlilik"),
                                   $draft.validityDays, id: "validity",
                                   hint: RDLocalization.string("localizable.nova.document.validity.none", table: .localizable, fallback: "Süresiz"))
                            number(RDLocalization.string("localizable.nova.document.field.notice", table: .localizable, fallback: "Uyarı penceresi"),
                                   $draft.noticeDays, id: "notice", hint: "30")
                        }
                        area(RDLocalization.string("localizable.nova.document.field.note", table: .localizable, fallback: "Not"),
                             $draft.note, id: "note")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                basisPicker
                if let error { NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                NovaButton(label: RDLocalization.string("localizable.nova.document.save", table: .localizable, fallback: "Kaydet"),
                    symbol: "checkmark", isEnabled: !busy && draft.isReady, isLoading: busy) { Task { await submit() } }
                    .accessibilityIdentifier("document.obligation.save")
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.item.cancel", table: .localizable, fallback: "Vazgeç"),
                    symbol: "xmark", variant: .surface, isEnabled: !busy) { dismiss() }
            }.padding(16).novaPopupContentSize()
        }
    }

    @ViewBuilder private var kindPicker: some View {
        if isKindLocked, let code = draft.kindCode {
            NovaCard(padding: 11) {
                HStack(spacing: 9) {
                    NovaIcon(symbol: NovaDocumentWords.kindSymbol(code), size: 15)
                        .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    NovaText(text: NovaDocumentWords.kind(code), style: .cardTitle)
                    Spacer(minLength: 0)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                NovaText(text: RDLocalization.string("localizable.nova.document.field.kind", table: .localizable, fallback: "Evrak türü"),
                    style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                // Health records are absent because the server's catalogue has
                // no code for one; the screen offers exactly what it sends.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)],
                          alignment: .leading, spacing: 7) {
                    ForEach(kinds) { kind in kindCell(kind) }
                }
            }
        }
    }

    private func kindCell(_ kind: NovaDocumentKind) -> some View {
        let isOn = draft.kindCode == kind.code
        return Button {
            draft.kindCode = kind.code
            if draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
                draft.title = NovaDocumentWords.kind(kind.code)
            }
            if draft.validityDays.isEmpty, let days = kind.defaultValidityDays {
                draft.validityDays = String(days)
            }
        } label: {
            HStack(spacing: 7) {
                NovaIcon(symbol: NovaDocumentWords.kindSymbol(kind.code), size: 14)
                    .foregroundStyle(isOn ? NovaColorToken.accentInk.color(in: scheme)
                                          : NovaColorToken.textSecondary.color(in: scheme))
                NovaText(text: NovaDocumentWords.kind(kind.code), style: .micro,
                    color: isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.text.color(in: scheme))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).frame(minHeight: 46)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? NovaColorToken.statusSuccessBg.color(in: scheme) : NovaColorToken.surface.color(in: scheme),
                        in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13)
                .strokeBorder(isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.border.color(in: scheme),
                              lineWidth: isOn ? 1.4 : 1))
            .animation(NovaMotion.easeOut(0.14), value: isOn)
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier("document.kind.\(kind.code)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: RDLocalization.string("localizable.nova.document.field.scope", table: .localizable, fallback: "Kapsam"),
                style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            Menu {
                Button(RDLocalization.string("localizable.nova.document.scope.company", table: .localizable, fallback: "Tüm firma")) { draft.workplaceID = nil }
                ForEach(places) { place in Button(place.name) { draft.workplaceID = place.id } }
            } label: {
                HStack(spacing: 7) {
                    NovaText(text: places.first { $0.id == draft.workplaceID }?.name
                        ?? RDLocalization.string("localizable.nova.document.scope.company", table: .localizable, fallback: "Tüm firma"),
                        style: .meta)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                }
                .padding(.horizontal, 11).frame(minHeight: 44)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityIdentifier("document.obligation.scope")
        }
    }

    /// A legal basis is only accepted with the reference the expert relies on,
    /// so the record can never claim a duty with nothing behind it.
    private var basisPicker: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                NovaText(text: RDLocalization.string("localizable.nova.document.field.basis", table: .localizable, fallback: "Dayanak"),
                    style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                HStack(spacing: 8) {
                    ForEach(NovaDocumentBasis.allCases) { value in
                        Button { draft.basis = value } label: {
                            NovaText(text: NovaDocumentWords.basis(value), style: .meta,
                                color: draft.basis == value ? NovaColorToken.accentInk.color(in: scheme)
                                                            : NovaColorToken.textSecondary.color(in: scheme))
                                .padding(.horizontal, 12).frame(minHeight: 40)
                                .background(draft.basis == value ? NovaColorToken.statusSuccessBg.color(in: scheme)
                                                                : NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
                                .animation(NovaMotion.easeOut(0.14), value: draft.basis)
                        }.buttonStyle(NovaRowPressStyle())
                            .accessibilityIdentifier("document.basis.\(value.rawValue)")
                            .accessibilityAddTraits(draft.basis == value ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
                if draft.basis == .legal {
                    field(RDLocalization.string("localizable.nova.document.field.legal.ref", table: .localizable, fallback: "Uzmanın dayandığı mevzuat"),
                          $draft.legalRef, id: "legal")
                    NovaText(text: RDLocalization.string("localizable.nova.document.basis.legal.hint", table: .localizable,
                        fallback: "Bu dayanak sizin beyanınızdır; uygulama kendi başına bir yasal yükümlülük tespit etmez."),
                        style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(NovaFont.font(.body))
                .frame(minHeight: 36).accessibilityIdentifier("document.field.\(id)")
        }
    }
    private func number(_ label: String, _ text: Binding<String>, id: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(hint, text: text).font(NovaFont.font(.body))
                .keyboardType(.numberPad).frame(minHeight: 36)
                .accessibilityIdentifier("document.field.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func area(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextEditor(text: text).font(NovaFont.font(.body))
                .frame(minHeight: 64).scrollContentBackground(.hidden)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("document.field.\(id)")
        }
    }

    private func submit() async {
        busy = true; error = nil
        do { try await save(draft) }
        catch let failure as NovaDocumentFailure { error = NovaDocumentWords.failure(failure) }
        catch {
            self.error = RDLocalization.string("localizable.nova.document.save.failed", table: .localizable,
                fallback: "Kayıt tamamlanamadı. Bilgileri kontrol edip tekrar deneyin.")
        }
        busy = false
    }
}
