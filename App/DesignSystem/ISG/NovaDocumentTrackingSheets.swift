import SwiftUI

/// One tracked obligation in full: what it is, who says it is owed, which
/// copies are on file and what the tracker makes of them today.
struct NovaDocumentObligationSheet: View {
    let obligation: NovaDocumentObligation
    let kinds: [NovaDocumentKind]
    let places: [NovaDocumentWorkplace]
    var canWrite = true
    let client: NovaDocumentTrackingClient
    let onChanged: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var current: NovaDocumentObligation?
    @State private var editing = false
    @State private var recording = false
    @State private var confirmingArchive = false
    @State private var busy = false
    @State private var error: String?

    private var row: NovaDocumentObligation { current ?? obligation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                heading
                facts
                copies
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
                controls
            }.padding(16).novaPopupContentSize()
        }
        .fullScreenCover(isPresented: $editing) {
            NovaPopup {
                NovaDocumentObligationForm(title: RDLocalization.string("localizable.nova.document.edit.title", table: .localizable, fallback: "Takip kaydını düzenle"),
                    kinds: kinds, places: places, draft: draft(row), isKindLocked: true) { value in
                        current = try await client.update(row, value)
                        editing = false
                        onChanged()
                    }
            }
        }
        .fullScreenCover(isPresented: $recording) {
            NovaPopup {
                NovaDocumentCopyForm(obligation: row) { value in
                    current = try await client.recordCopy(row, value)
                    recording = false
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
            VStack(alignment: .leading, spacing: 4) {
                NovaText(text: row.title, style: .sheetTitle)
                if NovaDocumentWords.kind(row.kindCode) != row.title {
                    NovaText(text: NovaDocumentWords.kind(row.kindCode), style: .metaQuiet)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var facts: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    NovaStatusPill(label: NovaDocumentWords.status(row.status),
                        status: NovaDocumentWords.tone(row.status))
                    NovaAnalysisTag(symbol: row.basis == .legal ? "book" : "person",
                        text: NovaDocumentWords.basis(row.basis), status: .neutral)
                    Spacer(minLength: 0)
                }
                // The basis is the expert's own, so it is attributed to them
                // rather than presented as the product's finding.
                if row.basis == .legal, let reference = row.legalRef {
                    fact(RDLocalization.string("localizable.nova.document.field.legal.ref", table: .localizable,
                        fallback: "Uzmanın dayandığı mevzuat"), reference)
                }
                grid
                if let note = row.note, !note.isEmpty {
                    fact(RDLocalization.string("localizable.nova.document.field.note", table: .localizable, fallback: "Not"), note)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var grid: some View {
        VStack(spacing: 7) {
            HStack(alignment: .top, spacing: 9) {
                cell(RDLocalization.string("localizable.nova.document.field.scope", table: .localizable, fallback: "Kapsam"),
                     row.workplaceName ?? RDLocalization.string("localizable.nova.document.scope.company", table: .localizable, fallback: "Tüm firma"))
                cell(RDLocalization.string("localizable.nova.document.field.validity", table: .localizable, fallback: "Geçerlilik"),
                     row.validityDays.map { String(format: RDLocalization.string("localizable.nova.document.validity.days", table: .localizable,
                        fallback: "%d gün"), $0) }
                        ?? RDLocalization.string("localizable.nova.document.validity.none", table: .localizable, fallback: "Süresiz"))
            }
            HStack(alignment: .top, spacing: 9) {
                cell(RDLocalization.string("localizable.nova.document.field.notice", table: .localizable, fallback: "Uyarı penceresi"),
                     String(format: RDLocalization.string("localizable.nova.document.validity.days", table: .localizable, fallback: "%d gün"), row.noticeDays))
                cell(RDLocalization.string("localizable.nova.document.field.responsible", table: .localizable, fallback: "Sorumlu"),
                     row.responsibleContact ?? "—")
            }
        }
    }

    private func cell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NovaText(text: label, style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: value, style: .meta)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NovaText(text: label, style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
            NovaText(text: value, style: .body)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copies: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    NovaText(text: RDLocalization.string("localizable.nova.document.copies", table: .localizable, fallback: "Dosyadaki kopyalar"), style: .cardTitle)
                    Spacer(minLength: 0)
                    NovaText(text: "\(row.copies.count)", style: .badge, color: NovaColorToken.textTertiary.color(in: scheme))
                }
                // The tracker keeps a reference, never the document itself.
                NovaText(text: RDLocalization.string("localizable.nova.document.copies.hint", table: .localizable,
                    fallback: "Dosyanın kendisi burada saklanmaz; aslının nerede olduğuna dair kaydınız tutulur."),
                    style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                if row.copies.isEmpty {
                    NovaText(text: RDLocalization.string("localizable.nova.document.copies.empty", table: .localizable,
                        fallback: "Henüz kopya kaydedilmedi."), style: .metaQuiet)
                } else {
                    ForEach(row.copies) { copy in copyRow(copy) }
                }
                if canWrite && !row.isArchived {
                    NovaButton(label: RDLocalization.string("localizable.nova.document.copy.add", table: .localizable, fallback: "Kopya kaydet"),
                        symbol: "plus", variant: .surface, isEnabled: !busy) { recording = true }
                        .accessibilityIdentifier("document.copy.add")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyRow(_ copy: NovaDocumentCopy) -> some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    NovaAnalysisTag(symbol: "calendar", text: copy.issuedOn, status: .neutral)
                    if let until = copy.validUntil {
                        NovaAnalysisTag(symbol: "hourglass", text: until, status: .neutral)
                    } else {
                        NovaAnalysisTag(symbol: "infinity",
                            text: RDLocalization.string("localizable.nova.document.validity.none", table: .localizable, fallback: "Süresiz"),
                            status: .neutral)
                    }
                }
                if let number = copy.documentNo, !number.isEmpty {
                    NovaText(text: number, style: .meta)
                }
                if let place = copy.locationNote, !place.isEmpty {
                    NovaText(text: place, style: .metaQuiet)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if canWrite {
                Button {
                    Task {
                        busy = true; error = nil
                        do { current = try await client.removeCopy(row, copy); onChanged() }
                        catch let failure as NovaDocumentFailure { error = NovaDocumentWords.failure(failure) }
                        catch { self.error = NovaDocumentWords.failure(.validation) }
                        busy = false
                    }
                } label: {
                    Image(systemName: "trash").font(.system(size: 13))
                        .foregroundStyle(NovaColorToken.statusDangerInk.color(in: scheme))
                        .frame(width: 38, height: 38)
                }.buttonStyle(.plain).disabled(busy)
                    .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.document.copy.remove", table: .localizable, fallback: "Kopyayı sil")))
                    .accessibilityIdentifier("document.copy.remove.\(copy.id.uuidString.lowercased())")
            }
        }
        .padding(9)
        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var controls: some View {
        if canWrite && !row.isArchived {
            NovaButton(label: RDLocalization.string("localizable.nova.document.edit.title", table: .localizable, fallback: "Takip kaydını düzenle"),
                symbol: "square.and.pencil", variant: .surface, isEnabled: !busy) { editing = true }
                .accessibilityIdentifier("document.obligation.edit")
            if confirmingArchive {
                NovaText(text: RDLocalization.string("localizable.nova.document.archive.confirm", table: .localizable,
                    fallback: "Kayıt listeden çıkar; kaydedilmiş kopyalar silinmez."), style: .metaQuiet)
                NovaButton(label: RDLocalization.string("localizable.nova.document.archive.yes", table: .localizable, fallback: "Evet, arşivle"),
                    symbol: "archivebox", variant: .danger, isEnabled: !busy, isLoading: busy) {
                    Task {
                        busy = true; error = nil
                        do { try await client.archive(row); onChanged() }
                        catch let failure as NovaDocumentFailure { error = NovaDocumentWords.failure(failure) }
                        catch { self.error = NovaDocumentWords.failure(.validation) }
                        busy = false
                    }
                }.accessibilityIdentifier("document.obligation.archive.confirm")
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.item.cancel", table: .localizable, fallback: "Vazgeç"),
                    symbol: "xmark", variant: .surface, isEnabled: !busy) { confirmingArchive = false }
            } else {
                NovaButton(label: RDLocalization.string("localizable.nova.document.archive", table: .localizable, fallback: "Takipten çıkar"),
                    symbol: "archivebox", variant: .danger, isEnabled: !busy) { confirmingArchive = true }
                    .accessibilityIdentifier("document.obligation.archive")
            }
        }
    }

    private func draft(_ value: NovaDocumentObligation) -> NovaDocumentDraft {
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

/// Adding or editing one tracked obligation.
struct NovaDocumentObligationForm: View {
    let title: String
    let kinds: [NovaDocumentKind]
    let places: [NovaDocumentWorkplace]
    @State var draft: NovaDocumentDraft
    var isKindLocked = false
    let save: (NovaDocumentDraft) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: title, style: .sheetTitle)
                kindPicker
                NovaCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        field(RDLocalization.string("localizable.nova.document.field.title", table: .localizable, fallback: "Kayıt adı"),
                              $draft.title, id: "title")
                        scopePicker
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
            NovaCard(padding: 12) {
                HStack(spacing: 9) {
                    NovaIcon(symbol: NovaDocumentWords.kindSymbol(code), size: 16)
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
                ForEach(kinds) { kind in
                    Button {
                        draft.kindCode = kind.code
                        if draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
                            draft.title = NovaDocumentWords.kind(kind.code)
                        }
                        if draft.validityDays.isEmpty, let days = kind.defaultValidityDays {
                            draft.validityDays = String(days)
                        }
                    } label: {
                        HStack(spacing: 9) {
                            NovaIcon(symbol: NovaDocumentWords.kindSymbol(kind.code), size: 15)
                                .foregroundStyle(draft.kindCode == kind.code ? NovaColorToken.accentInk.color(in: scheme)
                                                                             : NovaColorToken.textSecondary.color(in: scheme))
                            NovaText(text: NovaDocumentWords.kind(kind.code), style: .meta)
                            Spacer(minLength: 0)
                            Image(systemName: draft.kindCode == kind.code ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.kindCode == kind.code ? NovaColorToken.accentInk.color(in: scheme)
                                                                            : NovaColorToken.borderStrong.color(in: scheme))
                        }
                        .padding(.horizontal, 11).frame(minHeight: 46)
                        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(draft.kindCode == kind.code ? NovaColorToken.accentInk.color(in: scheme)
                                                                      : NovaColorToken.border.color(in: scheme),
                                          lineWidth: draft.kindCode == kind.code ? 1.4 : 1))
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("document.kind.\(kind.code)")
                        .accessibilityAddTraits(draft.kindCode == kind.code ? .isSelected : [])
                }
            }
        }
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
                        }.buttonStyle(.plain)
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
            TextField(label, text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .frame(minHeight: 36).accessibilityIdentifier("document.field.\(id)")
        }
    }
    private func number(_ label: String, _ text: Binding<String>, id: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(hint, text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .keyboardType(.numberPad).frame(minHeight: 36)
                .accessibilityIdentifier("document.field.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func area(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextEditor(text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
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

/// Recording one copy the company holds.
struct NovaDocumentCopyForm: View {
    let obligation: NovaDocumentObligation
    let save: (NovaDocumentCopyDraft) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var draft = NovaDocumentCopyDraft()
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: RDLocalization.string("localizable.nova.document.copy.add", table: .localizable, fallback: "Kopya kaydet"), style: .sheetTitle)
                NovaText(text: obligation.title, style: .metaQuiet)
                NovaCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        NovaDayField(label: RDLocalization.string("localizable.nova.document.field.issued", table: .localizable, fallback: "Düzenlenme tarihi"),
                            value: $draft.issuedOn, identifier: "document.copy.issued")
                        NovaDayField(label: RDLocalization.string("localizable.nova.document.field.valid.until", table: .localizable, fallback: "Geçerlilik bitişi"),
                            value: $draft.validUntil, identifier: "document.copy.until", isClearable: true)
                        NovaText(text: endDateHint, style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                        field(RDLocalization.string("localizable.nova.document.field.no", table: .localizable, fallback: "Belge no"),
                              $draft.documentNo, id: "no")
                        field(RDLocalization.string("localizable.nova.document.field.location", table: .localizable, fallback: "Aslı nerede"),
                              $draft.locationNote, id: "location")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                NovaText(text: RDLocalization.string("localizable.nova.document.copies.hint", table: .localizable,
                    fallback: "Dosyanın kendisi burada saklanmaz; aslının nerede olduğuna dair kaydınız tutulur."),
                    style: .metaQuiet)
                if let error { NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                NovaButton(label: RDLocalization.string("localizable.nova.document.save", table: .localizable, fallback: "Kaydet"),
                    symbol: "checkmark", isEnabled: !busy && draft.isReady, isLoading: busy) { Task { await submit() } }
                    .accessibilityIdentifier("document.copy.save")
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.item.cancel", table: .localizable, fallback: "Vazgeç"),
                    symbol: "xmark", variant: .surface, isEnabled: !busy) { dismiss() }
            }.padding(16).novaPopupContentSize()
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft.issuedOn = NovaDayField.text(Date())
        }
    }

    /// The end date the server will use when the field is left empty. The
    /// screen says which rule applies instead of leaving it to be guessed.
    private var endDateHint: String {
        guard draft.validUntil.isEmpty else {
            return RDLocalization.string("localizable.nova.document.valid.until.explicit", table: .localizable,
                fallback: "Girdiğiniz bitiş tarihi kullanılır.")
        }
        if let days = obligation.validityDays {
            return String(format: RDLocalization.string("localizable.nova.document.valid.until.derived", table: .localizable,
                fallback: "Boş bırakırsanız düzenlenme tarihine %d gün eklenir."), days)
        }
        return RDLocalization.string("localizable.nova.document.valid.until.open", table: .localizable,
            fallback: "Bu kayıt süresiz; boş bırakırsanız kopya süresiz sayılır.")
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .frame(minHeight: 36).accessibilityIdentifier("document.copy.\(id)")
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
