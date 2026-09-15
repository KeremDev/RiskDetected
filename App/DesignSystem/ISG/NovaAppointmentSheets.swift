import SwiftUI

/// One appointment. Nothing here says the person is qualified, because nothing
/// anywhere does.
struct NovaAppointmentDetailSheet: View {
    let entry: NovaAppointment
    var canWrite: Bool = true
    let fileClient: NovaFileLibraryClient
    let onEnd: () -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var opened: URL?
    @State private var openFailure: String?
    @State private var opening = false

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
        .sheet(item: $opened) { url in NovaFileShareSheet(url: url) }
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
            }
            // Both said on the record itself, not only at the top of the board.
            NovaHelpHint(text: NovaAppointmentWords.noQualificationNote)
            if entry.assetDownload != nil { letterRow }
        }
    }

    @ViewBuilder private var letterRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NovaColorToken.statusSuccessInk.color(in: scheme))
            VStack(alignment: .leading, spacing: 1) {
                NovaText(text: RDLocalization.string("localizable.nova.appointment.detail.letter",
                    table: .localizable, fallback: "Atama yazısı"), style: .cardTitle)
                if let openFailure {
                    NovaText(text: openFailure, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
            }
            Spacer(minLength: 0)
            NovaButton(label: RDLocalization.string("localizable.nova.file.open", table: .localizable, fallback: "Dosyayı aç"),
                symbol: "arrow.up.right.square", variant: .surface, isEnabled: !opening, isLoading: opening) { open() }
                .accessibilityIdentifier("nova.appointment.detail.file.open")
        }
    }

    private func open() {
        guard let download = entry.assetDownload else { return }
        opening = true; openFailure = nil
        Task {
            do {
                let data = try await fileClient.download(download.bucket, download.path)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    .appendingPathComponent(download.path.components(separatedBy: "/").last ?? "belge")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try data.write(to: url, options: .completeFileProtection)
                opened = url
            } catch {
                openFailure = RDLocalization.string("localizable.nova.file.failure.unavailable", table: .localizable,
                    fallback: "Dosya servisi şu anda kullanılamıyor.")
            }
            opening = false
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
    let fileClient: NovaFileLibraryClient
    var fileCompany: UUID?
    let onSave: (NovaAppointmentDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @State private var openChooser: String?
    @State private var personSearch = ""
    @Environment(\.colorScheme) private var scheme

    init(draft: NovaAppointmentDraft, catalogue: NovaAppointmentCatalogue?, fileClient: NovaFileLibraryClient,
         fileCompany: UUID? = nil, onSave: @escaping (NovaAppointmentDraft) async -> String?,
         onClose: @escaping () -> Void) {
        var value = draft
        // One workplace is not a choice; asking for it again after the company
        // is already picked just repeats the same answer.
        if value.workplaceID == nil, let only = catalogue?.workplaces, only.count == 1 {
            value.workplaceID = only[0].id
        }
        _draft = State(initialValue: value)
        self.catalogue = catalogue; self.fileClient = fileClient; self.fileCompany = fileCompany
        self.onSave = onSave; self.onClose = onClose
    }

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

                    fieldCard("person.2") {
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
                    }
                    fieldCard("building.2") {
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
                    }

                    fieldCard("person.badge.shield.checkmark") {
                        VStack(alignment: .leading, spacing: 6) {
                            NovaText(text: RDLocalization.string("localizable.nova.appointment.form.role",
                                table: .localizable, fallback: "Görev"), style: .label,
                                color: NovaColorToken.textTertiary.color(in: scheme))
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
                                .accessibilityIdentifier("nova.appointment.form.role.\(role.kind.rawValue)")
                            }
                        }
                    }

                    fieldCard("checkmark.seal") {
                        VStack(alignment: .leading, spacing: 6) {
                            NovaText(text: RDLocalization.string("localizable.nova.appointment.detail.basis",
                                table: .localizable, fallback: "Dayanak"), style: .label,
                                color: NovaColorToken.textTertiary.color(in: scheme))
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
                                Spacer(minLength: 0)
                            }
                            TextField(RDLocalization.string("localizable.nova.appointment.form.basisnote",
                                table: .localizable, fallback: "Tutanak veya karar no"), text: $draft.basisNote)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("nova.appointment.form.basisnote")
                        }
                    }

                    fieldCard("calendar") {
                        HStack(spacing: 10) {
                            NovaDayField(label: RDLocalization.string("localizable.nova.appointment.row.starts",
                                table: .localizable, fallback: "Başlangıç"),
                                value: $draft.startsOn, identifier: "nova.appointment.form.starts")
                            NovaDayField(label: RDLocalization.string("localizable.nova.appointment.row.ends",
                                table: .localizable, fallback: "Bitiş"),
                                value: $draft.endsBefore, identifier: "nova.appointment.form.ends", isClearable: true)
                        }
                    }

                    fieldCard("paperclip") {
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: RDLocalization.string("localizable.nova.appointment.form.letter",
                                table: .localizable, fallback: "Atama yazısı"), style: .label,
                                color: NovaColorToken.textTertiary.color(in: scheme))
                            NovaInlineFileField(category: "personnel_document", company: fileCompany,
                                fileClient: fileClient, assetID: Binding(
                                    get: { draft.assetID?.uuidString ?? "" },
                                    set: { draft.assetID = UUID(uuidString: $0) }))
                        }
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

    /// A compact icon chip in front of one field's content, matching the
    /// manual nonconformity screen's field styling.
    @ViewBuilder private func fieldCard<V: View>(_ symbol: String, @ViewBuilder _ content: @escaping () -> V) -> some View {
        NovaCard(padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(width: 26, height: 26)
                    .background(NovaColorToken.statusSuccessBg.color(in: scheme), in: RoundedRectangle(cornerRadius: 8))
                content().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
