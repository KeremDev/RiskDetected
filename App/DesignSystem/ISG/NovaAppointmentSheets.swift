import SwiftUI

/// One appointment. Nothing here says the person is qualified, because nothing
/// anywhere does.
struct NovaAppointmentDetailSheet: View {
    let entry: NovaAppointment
    var canWrite: Bool = true
    let onEnd: () -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: entry.employeeName ?? RDLocalization.string(
                            "localizable.nova.appointment.row.person", table: .localizable, fallback: "Personel"),
                            style: .screenTitle)
                        NovaText(text: [entry.kind.title, entry.workplaceName, entry.companyName]
                            .compactMap { $0 }.joined(separator: " · "), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        NovaText(text: NovaAppointmentWords.explain(entry), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    facts
                    if canWrite {
                        NovaButton(label: entry.endsBefore == nil
                            ? RDLocalization.string("localizable.nova.appointment.detail.end",
                                table: .localizable, fallback: "Görevi sonlandır")
                            : RDLocalization.string("localizable.nova.appointment.detail.fix",
                                table: .localizable, fallback: "Bitiş tarihini düzelt"),
                            symbol: "calendar.badge.minus", variant: .primary, action: onEnd)
                    }
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .accessibilityIdentifier("nova.appointment.detail")
    }

    @ViewBuilder private var facts: some View {
        NovaCard(padding: 14) {
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                cell("calendar", RDLocalization.string("localizable.nova.appointment.row.starts",
                    table: .localizable, fallback: "Başlangıç"), entry.startsOn)
                cell("calendar.badge.minus", RDLocalization.string("localizable.nova.appointment.row.ends",
                    table: .localizable, fallback: "Bitiş"),
                    entry.endsBefore ?? RDLocalization.string("localizable.nova.appointment.unset",
                        table: .localizable, fallback: "Belirtilmedi"))
                cell(entry.basis?.symbol ?? "questionmark",
                    RDLocalization.string("localizable.nova.appointment.detail.basis",
                        table: .localizable, fallback: "Dayanak"),
                    entry.basis?.title ?? RDLocalization.string("localizable.nova.appointment.unset",
                        table: .localizable, fallback: "Belirtilmedi"),
                    detail: entry.basisNote ?? "")
                cell("person.text.rectangle", RDLocalization.string("localizable.nova.appointment.detail.letter",
                    table: .localizable, fallback: "Atama yazısı"),
                    entry.letterLocation ?? RDLocalization.string("localizable.nova.appointment.unset",
                        table: .localizable, fallback: "Belirtilmedi"))
            }
            // Both said on the record itself, not only at the top of the board.
            NovaHelpHint(text: NovaAppointmentWords.noQualificationNote)
            NovaText(text: NovaAppointmentWords.letterNote, style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
        }
    }

    @ViewBuilder private func cell(_ symbol: String, _ label: String, _ value: String,
                                   detail: String = "") -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            VStack(alignment: .leading, spacing: 1) {
                NovaSizedText(text: label, size: 9, weight: "Medium",
                    color: NovaColorToken.textMuted.color(in: scheme))
                NovaSizedText(text: value, size: 12, weight: "Bold")
                if !detail.isEmpty {
                    NovaSizedText(text: detail, size: 9.5, weight: "Medium",
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Recording an appointment. The basis is asked for, because saying whether
/// the person was elected or appointed is the point of the field.
struct NovaAppointmentSheet: View {
    @State var draft: NovaAppointmentDraft
    let catalogue: NovaAppointmentCatalogue?
    let onSave: (NovaAppointmentDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @State private var openChooser: String?
    @State private var personSearch = ""
    @Environment(\.colorScheme) private var scheme

    /// Filtered locally: the catalogue already scopes to the chosen company,
    /// so searching never re-asks the server.
    private var matchingEmployees: [NovaAppointmentCatalogue.Employee] {
        let all = catalogue?.employees ?? []
        let needle = personSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return all }
        return all.filter { $0.fullName.localizedCaseInsensitiveContains(needle) }
    }

    private var personTitle: String {
        catalogue?.employees.first { $0.id == draft.employeeID }?.fullName
            ?? RDLocalization.string("localizable.nova.appointment.form.pickperson", table: .localizable,
                fallback: "Personel seçin")
    }
    private var placeTitle: String {
        catalogue?.workplaces.first { $0.id == draft.workplaceID }?.name
            ?? RDLocalization.string("localizable.nova.appointment.form.pickplace", table: .localizable,
                fallback: "İşyeri seçin")
    }

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaText(text: RDLocalization.string("localizable.nova.appointment.form.title",
                        table: .localizable, fallback: "Görev ver"), style: .screenTitle)

                    NovaFileChooserButton(
                        label: RDLocalization.string("localizable.nova.appointment.form.person",
                            table: .localizable, fallback: "Personel"),
                        value: personTitle, isOpen: openChooser == "person",
                        identifier: "nova.appointment.form.person") {
                        openChooser = openChooser == "person" ? nil : "person"
                    }
                    if openChooser == "person" {
                        // Firma zaten seçili: burada yalnız o firmanın
                        // personeli içinde arama yapılır.
                        NovaAnalysisSearchField(text: $personSearch,
                            placeholder: RDLocalization.string("localizable.nova.appointment.form.person.search",
                                table: .localizable, fallback: "Personel ara"),
                            identifier: "nova.appointment.form.person.search")
                        if matchingEmployees.isEmpty {
                            NovaText(text: RDLocalization.string("localizable.nova.appointment.form.person.empty",
                                table: .localizable, fallback: "Eşleşen personel yok"), style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        } else {
                            NovaFileChooserPanel(
                                options: matchingEmployees.map { .init(id: $0.id.uuidString, title: $0.fullName) },
                                selected: draft.employeeID?.uuidString,
                                identifier: "nova.appointment.form.person.panel") { value in
                                draft.employeeID = value.flatMap(UUID.init(uuidString:))
                                openChooser = nil
                                personSearch = ""
                            }
                        }
                    }
                    NovaFileChooserButton(
                        label: RDLocalization.string("localizable.nova.appointment.form.workplace",
                            table: .localizable, fallback: "İşyeri"),
                        value: placeTitle, isOpen: openChooser == "place",
                        identifier: "nova.appointment.form.workplace") {
                        openChooser = openChooser == "place" ? nil : "place"
                    }
                    if openChooser == "place" {
                        NovaFileChooserPanel(
                            options: (catalogue?.workplaces ?? []).map {
                                .init(id: $0.id.uuidString, title: $0.name) },
                            selected: draft.workplaceID?.uuidString,
                            identifier: "nova.appointment.form.workplace.panel") { value in
                            draft.workplaceID = value.flatMap(UUID.init(uuidString:))
                            openChooser = nil
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        NovaText(text: RDLocalization.string("localizable.nova.appointment.form.role",
                            table: .localizable, fallback: "Görev"), style: .label)
                        // Only the roles the server accepts.
                        ForEach(catalogue?.roles
                            ?? NovaAppointmentKind.allCases.map { .init(kind: $0, usualBasis: .appointed) }) { role in
                            Button {
                                draft.kind = role.kind
                                // The usual basis fills the field; the expert
                                // still states what actually happened.
                                draft.basis = role.usualBasis
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: draft.kind == role.kind
                                        ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 13, weight: .semibold))
                                    NovaText(text: role.kind.title, style: .body)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(NovaColorToken.hairline.color(in: scheme), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .preference(key: NovaPopupBusyKey.self, value: saving)
        .accessibilityIdentifier("nova.appointment.form.role.\(role.kind.rawValue)")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        NovaText(text: RDLocalization.string("localizable.nova.appointment.detail.basis",
                            table: .localizable, fallback: "Dayanak"), style: .label)
                        HStack(spacing: 6) {
                            ForEach(catalogue?.bases ?? NovaAppointmentBasis.allCases) { basis in
                                Button { draft.basis = basis } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: basis.symbol).font(.system(size: 10, weight: .semibold))
                                        NovaSizedText(text: basis.title, size: 10.5,
                                            weight: draft.basis == basis ? "Bold" : "Medium")
                                    }
                                    .foregroundStyle(draft.basis == basis
                                        ? NovaColorToken.accentInk.color(in: scheme)
                                        : NovaColorToken.textSecondary.color(in: scheme))
                                    .padding(.vertical, 6).padding(.horizontal, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(NovaColorToken.hairline.color(in: scheme), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("nova.appointment.form.basis.\(basis.rawValue)")
                            }
                        }
                        TextField(RDLocalization.string("localizable.nova.appointment.form.basisnote",
                            table: .localizable, fallback: "Tutanak veya karar no"), text: $draft.basisNote)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("nova.appointment.form.basisnote")
                    }

                    NovaDayField(label: RDLocalization.string("localizable.nova.appointment.row.starts",
                        table: .localizable, fallback: "Başlangıç"),
                        value: $draft.startsOn, identifier: "nova.appointment.form.starts")
                    NovaDayField(label: RDLocalization.string("localizable.nova.appointment.row.ends",
                        table: .localizable, fallback: "Bitiş"),
                        value: $draft.endsBefore, identifier: "nova.appointment.form.ends", isClearable: true)

                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.appointment.form.letter",
                            table: .localizable, fallback: "Atama yazısı nerede"), style: .label)
                        TextField("", text: $draft.letterLocation).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("nova.appointment.form.letter")
                        NovaText(text: NovaAppointmentWords.letterNote, style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    NovaHelpHint(text: NovaAppointmentWords.noQualificationNote)

                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    HStack(spacing: 10) {
                        NovaButton(label: RDLocalization.string("localizable.nova.appointment.cancel",
                            table: .localizable, fallback: "Vazgeç"), symbol: "xmark",
                            variant: .surface, action: onClose).disabled(saving)
                        NovaButton(label: RDLocalization.string("localizable.nova.appointment.form.save",
                            table: .localizable, fallback: "Kaydet"), symbol: "checkmark",
                            variant: .primary) {
                            Task { saving = true; failure = await onSave(draft); saving = false }
                        }
                        .disabled(saving || draft.employeeID == nil || draft.workplaceID == nil)
                    }
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .accessibilityIdentifier("nova.appointment.form")
    }
}

/// Ending an appointment, or correcting the date it ended.
struct NovaAppointmentEndSheet: View {
    @State var draft: NovaAppointmentEndDraft
    let onSave: (NovaAppointmentEndDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaText(text: draft.isCorrection
                        ? RDLocalization.string("localizable.nova.appointment.detail.fix",
                            table: .localizable, fallback: "Bitiş tarihini düzelt")
                        : RDLocalization.string("localizable.nova.appointment.detail.end",
                            table: .localizable, fallback: "Görevi sonlandır"), style: .screenTitle)
                    if !draft.employeeName.isEmpty {
                        NovaText(text: draft.employeeName, style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    NovaHelpHint(text: String(format: RDLocalization.string(
                        "localizable.nova.appointment.end.after", table: .localizable,
                        fallback: "Görev %@ tarihinde başladı; bitiş bundan sonrası olmalı."), draft.startsOn))
                    NovaDayField(label: RDLocalization.string("localizable.nova.appointment.row.ends",
                        table: .localizable, fallback: "Bitiş"),
                        value: $draft.endsBefore, identifier: "nova.appointment.end.date")
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    HStack(spacing: 10) {
                        NovaButton(label: RDLocalization.string("localizable.nova.appointment.cancel",
                            table: .localizable, fallback: "Vazgeç"), symbol: "xmark",
                            variant: .surface, action: onClose).disabled(saving)
                        NovaButton(label: RDLocalization.string("localizable.nova.appointment.end.save",
                            table: .localizable, fallback: "Kaydet"), symbol: "checkmark",
                            variant: .primary) {
                            Task { saving = true; failure = await onSave(draft); saving = false }
                        }
                        .disabled(saving)
                    }
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .preference(key: NovaPopupBusyKey.self, value: saving)
        .accessibilityIdentifier("nova.appointment.end")
    }
}
