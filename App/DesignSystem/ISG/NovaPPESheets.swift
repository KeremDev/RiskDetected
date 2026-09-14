import SwiftUI

/// One handover with everything that came back against it. What is still out
/// is the server's count, never a number worked out here.
struct NovaPPEDetailSheet: View {
    let handover: NovaPPEHandover
    var canWrite: Bool = true
    let onReturn: () -> Void
    let onRemoveReturn: (UUID) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var working = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: handover.item, style: .screenTitle)
                        NovaText(text: [handover.employeeName, handover.companyName]
                            .compactMap { $0 }.joined(separator: " · "), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        NovaText(text: NovaPPEWords.explain(handover), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    facts
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    if canWrite && handover.outstanding > 0 {
                        NovaButton(label: RDLocalization.string("localizable.nova.ppe.detail.return",
                            table: .localizable, fallback: "İade kaydet"),
                            symbol: "arrow.uturn.backward", variant: .primary, action: onReturn)
                    }
                    returns
                }
                .padding(20)
            }
        }
        .accessibilityIdentifier("nova.ppe.detail")
    }

    @ViewBuilder private var facts: some View {
        NovaCard(padding: 14) {
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                cell("shippingbox", RDLocalization.string("localizable.nova.ppe.row.handed",
                    table: .localizable, fallback: "Zimmet"),
                    NovaPPEWords.amount(handover.quantity, handover.unit))
                cell("arrow.uturn.backward", RDLocalization.string("localizable.nova.ppe.detail.returned",
                    table: .localizable, fallback: "İade edilen"),
                    NovaPPEWords.amount(handover.returnedQuantity, handover.unit))
                cell("person.badge.shield.checkmark", RDLocalization.string("localizable.nova.ppe.detail.outstanding",
                    table: .localizable, fallback: "Hâlâ zimmette"),
                    NovaPPEWords.amount(handover.outstanding, handover.unit))
                cell("calendar", RDLocalization.string("localizable.nova.ppe.row.date",
                    table: .localizable, fallback: "Tarih"), handover.handedOn)
            }
            // The product holds no file; only where the form is says anything.
            if let location = handover.signedCopyLocation, !location.isEmpty {
                NovaHelpHint(text: String(format: RDLocalization.string("localizable.nova.ppe.detail.location",
                    table: .localizable, fallback: "İmzalı form: %@"), location))
            }
            NovaText(text: NovaPPEWords.signedCopyNote, style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
        }
    }

    @ViewBuilder private var returns: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.ppe.detail.history", table: .localizable,
                fallback: "İadeler"), style: .cardTitle)
            if handover.returns.isEmpty {
                NovaText(text: RDLocalization.string("localizable.nova.ppe.detail.noreturns", table: .localizable,
                    fallback: "Henüz iade kaydı yok."), style: .meta,
                    color: NovaColorToken.textMuted.color(in: scheme))
            }
            ForEach(handover.returns) { entry in
                NovaCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: entry.condition.symbol).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                            NovaText(text: NovaPPEWords.amount(entry.quantity, handover.unit)
                                + " · " + entry.condition.title, style: .body)
                            Spacer(minLength: 0)
                            NovaSizedText(text: entry.returnedOn, size: 10.5, weight: "Medium",
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        if let note = entry.note, !note.isEmpty {
                            NovaText(text: note, style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        if canWrite {
                            // A correction, not a rewrite: the outstanding
                            // amount is recounted rather than patched.
                            NovaButton(label: RDLocalization.string("localizable.nova.ppe.detail.remove",
                                table: .localizable, fallback: "Bu iadeyi geri al"),
                                symbol: "arrow.uturn.left", variant: .surface) {
                                Task { working = true; failure = await onRemoveReturn(entry.id); working = false }
                            }
                            .disabled(working)
                        }
                    }
                }
            }
        }
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

/// Recording a handover. There is no field for a signed copy, because the
/// product holds no file — only a note of where the form is.
struct NovaPPEHandoverSheet: View {
    @State var draft: NovaPPEHandoverDraft
    let catalogue: NovaPPECatalogue?
    let onSave: (NovaPPEHandoverDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @State private var choosingPerson = false
    @Environment(\.colorScheme) private var scheme

    private var personTitle: String {
        catalogue?.employees.first { $0.id == draft.employeeID }?.fullName
            ?? RDLocalization.string("localizable.nova.ppe.form.pickperson", table: .localizable,
                fallback: "Personel seçin")
    }

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaText(text: RDLocalization.string("localizable.nova.ppe.form.title",
                        table: .localizable, fallback: "Zimmet ver"), style: .screenTitle)
                    NovaFileChooserButton(
                        label: RDLocalization.string("localizable.nova.ppe.form.person",
                            table: .localizable, fallback: "Personel"),
                        value: personTitle, isOpen: choosingPerson,
                        identifier: "nova.ppe.form.person") { choosingPerson.toggle() }
                    if choosingPerson {
                        NovaFileChooserPanel(
                            options: (catalogue?.employees ?? []).map {
                                .init(id: $0.id.uuidString, title: $0.fullName) },
                            selected: draft.employeeID?.uuidString,
                            identifier: "nova.ppe.form.person.panel") { value in
                            draft.employeeID = value.flatMap(UUID.init(uuidString:))
                            choosingPerson = false
                        }
                    }
                    if catalogue?.employees.isEmpty ?? true {
                        NovaHelpHint(text: RDLocalization.string("localizable.nova.ppe.form.nopeople",
                            table: .localizable, fallback: "Bu firmada aktif personel kaydı yok."))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.ppe.form.item",
                            table: .localizable, fallback: "Ekipman"), style: .label)
                        TextField("", text: $draft.item).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("nova.ppe.form.item")
                        NovaText(text: NovaPPEWords.noCatalogueNote, style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: RDLocalization.string("localizable.nova.ppe.form.quantity",
                                table: .localizable, fallback: "Miktar"), style: .label)
                            TextField("", text: $draft.quantity)
                                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("nova.ppe.form.quantity")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: RDLocalization.string("localizable.nova.ppe.form.unit",
                                table: .localizable, fallback: "Birim"), style: .label)
                            // Only the units the server accepts.
                            HStack(spacing: 5) {
                                ForEach(catalogue?.units ?? NovaPPEUnit.allCases) { unit in
                                    Button { draft.unit = unit } label: {
                                        NovaSizedText(text: unit.title, size: 10,
                                            weight: draft.unit == unit ? "Bold" : "Medium",
                                            color: draft.unit == unit
                                                ? NovaColorToken.accentInk.color(in: scheme)
                                                : NovaColorToken.textSecondary.color(in: scheme))
                                            .padding(.vertical, 5).padding(.horizontal, 7)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(NovaColorToken.hairline.color(in: scheme), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("nova.ppe.form.unit.\(unit.rawValue)")
                                }
                            }
                        }
                    }
                    NovaDayField(label: RDLocalization.string("localizable.nova.ppe.row.date",
                        table: .localizable, fallback: "Tarih"),
                        value: $draft.handedOn, identifier: "nova.ppe.form.date")
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.ppe.row.ref",
                            table: .localizable, fallback: "Belge no"), style: .label)
                        TextField("", text: $draft.externalRef).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("nova.ppe.form.ref")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.ppe.form.location",
                            table: .localizable, fallback: "İmzalı form nerede"), style: .label)
                        TextField("", text: $draft.signedCopyLocation).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("nova.ppe.form.location")
                        NovaText(text: NovaPPEWords.signedCopyNote, style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    HStack(spacing: 10) {
                        NovaButton(label: RDLocalization.string("localizable.nova.ppe.cancel",
                            table: .localizable, fallback: "Vazgeç"), symbol: "xmark",
                            variant: .surface, action: onClose)
                        NovaButton(label: RDLocalization.string("localizable.nova.ppe.form.save",
                            table: .localizable, fallback: "Kaydet"), symbol: "checkmark",
                            variant: .primary) {
                            Task { saving = true; failure = await onSave(draft); saving = false }
                        }
                        .disabled(saving || draft.employeeID == nil
                            || draft.item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(20)
            }
        }
        .accessibilityIdentifier("nova.ppe.form")
    }
}

/// Recording a return. The form says what is still out, and the server refuses
/// anything above it.
struct NovaPPEReturnSheet: View {
    @State var draft: NovaPPEReturnDraft
    let catalogue: NovaPPECatalogue?
    let onSave: (NovaPPEReturnDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaText(text: RDLocalization.string("localizable.nova.ppe.return.title",
                        table: .localizable, fallback: "İade kaydet"), style: .screenTitle)
                    if !draft.item.isEmpty {
                        NovaText(text: draft.item, style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    NovaHelpHint(text: String(format: RDLocalization.string(
                        "localizable.nova.ppe.return.outstanding", table: .localizable,
                        fallback: "Hâlâ zimmette olan: %@. Bundan fazlası kaydedilemez."),
                        NovaPPEWords.amount(draft.outstanding, draft.unit)))
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.ppe.form.quantity",
                            table: .localizable, fallback: "Miktar"), style: .label)
                        TextField("", text: $draft.quantity)
                            .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("nova.ppe.return.quantity")
                    }
                    NovaDayField(label: RDLocalization.string("localizable.nova.ppe.return.date",
                        table: .localizable, fallback: "İade tarihi"),
                        value: $draft.returnedOn, identifier: "nova.ppe.return.date")
                    VStack(alignment: .leading, spacing: 6) {
                        NovaText(text: RDLocalization.string("localizable.nova.ppe.return.condition",
                            table: .localizable, fallback: "Durum"), style: .label)
                        // Only the conditions the server accepts.
                        HStack(spacing: 6) {
                            ForEach(catalogue?.conditions ?? NovaPPECondition.allCases) { condition in
                                Button { draft.condition = condition } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: condition.symbol).font(.system(size: 10, weight: .semibold))
                                        NovaSizedText(text: condition.title, size: 10,
                                            weight: draft.condition == condition ? "Bold" : "Medium")
                                    }
                                    .foregroundStyle(draft.condition == condition
                                        ? NovaColorToken.accentInk.color(in: scheme)
                                        : NovaColorToken.textSecondary.color(in: scheme))
                                    .padding(.vertical, 6).padding(.horizontal, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(NovaColorToken.hairline.color(in: scheme), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("nova.ppe.return.condition.\(condition.rawValue)")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.ppe.return.note",
                            table: .localizable, fallback: "Not"), style: .label)
                        TextEditor(text: $draft.note).frame(minHeight: 60)
                            .accessibilityIdentifier("nova.ppe.return.note")
                    }
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    HStack(spacing: 10) {
                        NovaButton(label: RDLocalization.string("localizable.nova.ppe.cancel",
                            table: .localizable, fallback: "Vazgeç"), symbol: "xmark",
                            variant: .surface, action: onClose)
                        NovaButton(label: RDLocalization.string("localizable.nova.ppe.return.save",
                            table: .localizable, fallback: "İadeyi kaydet"), symbol: "checkmark",
                            variant: .primary) {
                            Task { saving = true; failure = await onSave(draft); saving = false }
                        }
                        .disabled(saving || draft.quantity.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(20)
            }
        }
        .accessibilityIdentifier("nova.ppe.return")
    }
}
