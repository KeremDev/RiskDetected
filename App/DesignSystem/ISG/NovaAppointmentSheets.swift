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
                        NovaPopupHeading(text: entry.employeeName ?? RDLocalization.string(
                            "localizable.nova.appointment.row.person", table: .localizable, fallback: "Personel"), symbol: "person.badge.plus")
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
    @State private var step = 0
    @State private var saved = false
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
        // Large personnel registers must not render in full just because the
        // picker opened. Wait for a search term, then filter the already scoped
        // company catalogue locally.
        guard !needle.isEmpty else { return [] }
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
        Group {
            if saved {
                NovaTaskSuccessView(title: RDLocalization.string("localizable.nova.appointment.sheets.atama.kaydedildi.22d8d89a", table: .localizable, fallback: "Atama kaydedildi"),
                    message: RDLocalization.string("localizable.nova.appointment.sheets.gorev.sure.ve.varsa.atama.yazisi.personel.kaydin.b2ed734b", table: .localizable, fallback: "Görev, süre ve varsa atama yazısı personel kaydına eklendi."),
                    doneTitle: "Atamalara dön", onDone: onClose)
            } else {
                NovaPageSurface(onEdgeBack: goBack) {
                    VStack(spacing: 0) {
                        NovaTaskHeader(title: RDLocalization.string("localizable.nova.appointment.sheets.gorev.ver.af77d64e", table: .localizable, fallback: "Görev ver"), step: step + 1, total: 4,
                            stepTitle: ["Personel ve işyeri", "Görev ve dayanak", "Tarih", "Dosya ve kontrol"][step],
                            onClose: goBack)
                            .padding(.horizontal, 18).padding(.top, 10)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                stepContent
                                if let failure { NovaTaskErrorSummary(message: failure) }
                            }.padding(20).padding(.bottom, 18)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            NovaTaskStickyActions(primaryTitle: step == 3 ? "Atamayı kaydet" : "Devam",
                                primarySymbol: step == 3 ? "checkmark" : "arrow.right", isWorking: saving,
                                canGoBack: true, onBack: goBack, onPrimary: advance)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("nova.appointment.form")
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case 0: personAndWorkplace
        case 1: roleAndBasis
        case 2: dates
        default: fileAndReview
        }
    }

    private var personAndWorkplace: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaHelpHint(text: RDLocalization.string("localizable.nova.appointment.sheets.personel.ve.isyeri.secimi.sonraki.adimlara.otoma.97c9f86f", table: .localizable, fallback: "Personel ve işyeri seçimi sonraki adımlara otomatik taşınır."))
            fieldCard("person.2") {
                NovaFileChooserButton(label: "Personel", value: personTitle,
                    isOpen: openChooser == "person", identifier: "nova.appointment.form.person") {
                    openChooser = openChooser == "person" ? nil : "person"
                }
                if openChooser == "person" {
                    NovaAnalysisSearchField(text: $personSearch, placeholder: RDLocalization.string("localizable.nova.appointment.sheets.personel.ara.b1eb985f", table: .localizable, fallback: "Personel ara"),
                        identifier: "nova.appointment.form.person.search")
                    if matchingEmployees.isEmpty {
                        NovaText(text: personSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Personel adını yazarak arayın."
                            : "Aramanızla eşleşen personel bulunamadı.", style: .metaQuiet)
                            .padding(.vertical, 8)
                    } else {
                        NovaFileChooserPanel(options: matchingEmployees.map { .init(id: $0.id.uuidString, title: $0.fullName) },
                            selected: draft.employeeID?.uuidString,
                            identifier: "nova.appointment.form.person.panel") { value in
                            draft.employeeID = value.flatMap(UUID.init(uuidString:)); openChooser = nil; personSearch = ""
                        }
                    }
                }
            }
            fieldCard("building.2") {
                let count = catalogue?.workplaces.count ?? 0
                if count <= 1 {
                    NovaText(text: count == 1 ? placeTitle : "Bu firmada kayıt açılacak bir işyeri yok.", style: .cardTitle)
                } else {
                    NovaFileChooserButton(label: RDLocalization.string("localizable.nova.appointment.sheets.isyeri.1c1ca3c4", table: .localizable, fallback: "İşyeri"), value: placeTitle, isOpen: openChooser == "place",
                        identifier: "nova.appointment.form.workplace") { openChooser = openChooser == "place" ? nil : "place" }
                    if openChooser == "place" {
                        NovaFileChooserPanel(options: (catalogue?.workplaces ?? []).map { .init(id: $0.id.uuidString, title: $0.name) },
                            selected: draft.workplaceID?.uuidString, identifier: "nova.appointment.form.workplace.panel") {
                            draft.workplaceID = $0.flatMap(UUID.init(uuidString:)); openChooser = nil
                        }
                    }
                }
            }
        }
    }

    private var roleAndBasis: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldCard("person.badge.shield.checkmark") {
                VStack(alignment: .leading, spacing: 6) {
                    NovaText(text: RDLocalization.string("localizable.nova.appointment.sheets.gorev.a860afd9", table: .localizable, fallback: "Görev"), style: .label)
                    ForEach(catalogue?.roles ?? NovaAppointmentKind.allCases.map { .init(kind: $0, usualBasis: .appointed) }) { role in
                        Button { draft.kind = role.kind; draft.basis = role.usualBasis } label: {
                            HStack { Image(systemName: draft.kind == role.kind ? "largecircle.fill.circle" : "circle"); NovaText(text: role.kind.title, style: .body); Spacer() }
                                .frame(minHeight: 42).contentShape(Rectangle())
                        }.buttonStyle(NovaRowPressStyle())
                    }
                }
            }
            fieldCard("checkmark.seal") {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: "Dayanak", style: .label)
                    ForEach(catalogue?.bases ?? NovaAppointmentBasis.allCases) { basis in
                        Button { draft.basis = basis } label: {
                            HStack { Image(systemName: draft.basis == basis ? "checkmark.circle.fill" : "circle"); NovaText(text: basis.title, style: .body); Spacer() }
                                .frame(minHeight: 40).contentShape(Rectangle())
                        }.buttonStyle(NovaRowPressStyle())
                    }
                    TextField(RDLocalization.string("localizable.nova.appointment.sheets.tutanak.veya.karar.no.2df6343f", table: .localizable, fallback: "Tutanak veya karar no"), text: $draft.basisNote).textFieldStyle(.roundedBorder)
                }
            }
            NovaWhyDisclosure { NovaText(text: "\(NovaAppointmentWords.noQualificationNote) \(NovaAppointmentWords.noRequiredCountNote)", style: .metaQuiet) }
        }
    }

    private var dates: some View {
        fieldCard("calendar") {
            VStack(alignment: .leading, spacing: 12) {
                NovaDayField(label: RDLocalization.string("localizable.nova.appointment.sheets.baslangic.013b86dd", table: .localizable, fallback: "Başlangıç"), value: $draft.startsOn, identifier: "nova.appointment.form.starts")
                NovaDayField(label: RDLocalization.string("localizable.nova.appointment.sheets.bitis.59d3fd3d", table: .localizable, fallback: "Bitiş"), value: $draft.endsBefore, identifier: "nova.appointment.form.ends", isClearable: true)
            }
        }
    }

    private var fileAndReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaHelpHint(text: RDLocalization.format("localizable.nova.appointment.sheets.atama.yazisi.istege.baglidir.belgeyi.daha.sonra..9775896a", table: .localizable, fallback: "Atama yazısı isteğe bağlıdır; belgeyi daha sonra da ekleyebilirsiniz. %1$@", arguments: [String(describing: NovaAppointmentWords.letterNote)]))
            fieldCard("paperclip") {
                NovaInlineFileField(category: "personnel_document", company: fileCompany,
                    fileClient: fileClient, assetID: $draft.letterLocation)
            }
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: RDLocalization.string("localizable.nova.appointment.sheets.atama.ozeti.9f91d179", table: .localizable, fallback: "Atama özeti"), style: .bodyStrong)
                    NovaText(text: personTitle, style: .body)
                    NovaText(text: "\(placeTitle) · \(draft.kind.title) · \(draft.startsOn)", style: .metaQuiet)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func goBack() { failure = nil; if step > 0 { step -= 1 } else { onClose() } }
    private func advance() {
        failure = nil
        if step == 0 && (draft.employeeID == nil || draft.workplaceID == nil) {
            failure = "Personel ve işyeri seçimini tamamlayın."; return
        }
        if step < 3 { step += 1; return }
        Task {
            saving = true
            let result = await onSave(draft)
            saving = false
            if let result { failure = result } else { saved = true }
        }
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
                    NovaPopupHeading(text: draft.isCorrection
                        ? RDLocalization.string("localizable.nova.appointment.detail.fix",
                            table: .localizable, fallback: "Bitiş tarihini düzelt")
                        : RDLocalization.string("localizable.nova.appointment.detail.end",
                            table: .localizable, fallback: "Görevi sonlandır"), symbol: "person.badge.plus")
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
