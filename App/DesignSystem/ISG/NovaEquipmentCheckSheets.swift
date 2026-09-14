import SwiftUI

/// One item in full, and every action on it, in one popup: what it is, what the
/// record says today and why, the period behind that answer, the reports on
/// file and the compact panel that records another one.
struct NovaEquipmentItemSheet: View {
    let item: NovaEquipmentItem
    let rule: NovaEquipmentRule?
    let workplaces: [NovaDocumentWorkplace]
    let client: NovaEquipmentCheckClient
    var canWrite = true
    let onChanged: () -> Void
    let onClosed: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var current: NovaEquipmentItem?
    @State private var recording = false
    @State private var editing = false
    @State private var confirmingArchive = false
    @State private var draft = NovaEquipmentInspectionDraft()
    @State private var reports: [NovaFileEntry] = []
    @State private var choosingReport = false
    @State private var busy = false
    @State private var error: String?

    private var row: NovaEquipmentItem { current ?? item }
    private var tone: NovaStatus {
        switch row.group {
        case .overdue, .failed: return .danger
        case .untracked: return .warning
        case .dueSoon: return .info
        case .current: return .success
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                heading
                chips
                explanation
                facts
                periodCard
                if canWrite { recordPanel }
                history
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
                controls
            }.padding(16).novaPopupContentSize()
        }
        .task {
            guard let company = row.companyID else { return }
            reports = (try? await client.filedReports(company)) ?? []
            if current == nil { current = try? await client.detail(row.id) }
        }
        .fullScreenCover(isPresented: $editing) {
            NovaPopup {
                NovaEquipmentEditSheet(item: row, workplaces: workplaces) { value in
                    current = try await client.update(row, value)
                    editing = false
                    onChanged()
                }
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 10) {
            NovaIcon(symbol: row.group.symbol, size: 19)
                .foregroundStyle(tone.tokens.ink.color(in: scheme))
                .frame(width: 44, height: 44)
                .background(tone.tokens.background.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                NovaText(text: NovaEquipmentWords.type(row.equipmentType), style: .sheetTitle).lineLimit(2)
                NovaText(text: row.serialTag, style: .metaQuiet)
            }
            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        HStack(spacing: 5) {
            NovaStatusPill(label: NovaEquipmentWords.state(row.state), status: tone)
            if let name = row.companyName {
                NovaAnalysisTag(symbol: "building.2", text: name, status: .neutral)
            }
            if let place = row.locationNote, !place.isEmpty {
                NovaAnalysisTag(symbol: "mappin", text: place, status: .neutral)
            }
            Spacer(minLength: 0)
        }
    }

    /// Why the record says what it says. Always present, because a date that is
    /// missing needs a reason more than a date that is there.
    private var explanation: some View {
        NovaCard(padding: 11, tint: tone.tokens.background.color(in: scheme)) {
            NovaText(text: NovaEquipmentWords.explain(row), style: .meta)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var facts: some View {
        NovaCard(padding: 11) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)],
                      alignment: .leading, spacing: 7) {
                cell("calendar", RDLocalization.string("localizable.nova.equipment.field.last", table: .localizable, fallback: "Son kontrol"),
                     row.lastPerformedOn ?? "—")
                cell("checkmark.seal", RDLocalization.string("localizable.nova.equipment.field.result", table: .localizable, fallback: "Sonuç"),
                     NovaEquipmentWords.result(row.lastResult))
                cell("calendar.badge.clock", RDLocalization.string("localizable.nova.equipment.field.next", table: .localizable, fallback: "Sonraki kontrol"),
                     row.nextDueOn ?? RDLocalization.string("localizable.nova.equipment.no.due", table: .localizable, fallback: "Tarih yok"))
                cell("person", RDLocalization.string("localizable.nova.equipment.field.inspector", table: .localizable, fallback: "Kontrolü yapan"),
                     row.lastInspector ?? "—")
                cell("building.2", RDLocalization.string("localizable.nova.document.field.scope", table: .localizable, fallback: "Kapsam"),
                     workplaces.first { $0.id == row.workplaceID }?.name ?? "—")
                cell("number", RDLocalization.string("localizable.nova.equipment.field.ref", table: .localizable, fallback: "Rapor no"),
                     row.lastExternalRef ?? "—")
            }
        }
    }

    /// The period and where it came from, together. A duration never appears on
    /// screen without the expert's own attribution beside it.
    private var periodCard: some View {
        NovaCard(padding: 11, tint: NovaColorToken.surfaceMuted.color(in: scheme)) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                    NovaText(text: RDLocalization.string("localizable.nova.equipment.period.title", table: .localizable, fallback: "Kontrol süresi"),
                        style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                }
                if let months = row.periodMonths {
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.equipment.period.value", table: .localizable,
                        fallback: "%1$d ay · %2$@"), months, NovaEquipmentWords.source(row.periodSource)), style: .meta)
                    if row.periodNeedsReview == true {
                        NovaText(text: RDLocalization.string("localizable.nova.equipment.period.review", table: .localizable,
                            fallback: "Bu süre uzmanın kendi kararıdır; doğrulanmış bir mevzuat kaynağına bağlanmadı."),
                            style: .micro, color: NovaColorToken.statusWarningInk.color(in: scheme))
                    }
                    if let note = row.periodExceptionNote, !note.isEmpty {
                        NovaText(text: note, style: .metaQuiet)
                    }
                } else {
                    NovaText(text: RDLocalization.string("localizable.nova.equipment.period.none", table: .localizable,
                        fallback: "Bu tür için süre tanımlı değil. Süre tanımlanana kadar sonraki kontrol tarihi üretilmez."),
                        style: .metaQuiet)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Recording a report, in the same popup. The next date is the server's
    /// answer; this panel never previews one it worked out itself.
    @ViewBuilder private var recordPanel: some View {
        if recording {
            VStack(alignment: .leading, spacing: 8) {
                NovaDayField(label: RDLocalization.string("localizable.nova.equipment.field.performed", table: .localizable, fallback: "Kontrol tarihi"),
                    value: $draft.performedOn, identifier: "equipment.inspection.performed")
                resultPicker
                field(RDLocalization.string("localizable.nova.equipment.field.inspector", table: .localizable, fallback: "Kontrolü yapan"),
                      $draft.inspector, id: "inspector")
                field(RDLocalization.string("localizable.nova.equipment.field.ref", table: .localizable, fallback: "Rapor no"),
                      $draft.externalRef, id: "ref")
                reportPicker
                field(RDLocalization.string("localizable.nova.document.field.note", table: .localizable, fallback: "Not"),
                      $draft.note, id: "note")
                if draft.result == "fail" {
                    NovaText(text: RDLocalization.string("localizable.nova.equipment.fail.hint", table: .localizable,
                        fallback: "Olumsuz sonuç için sonraki kontrol tarihi üretilmez."),
                        style: .micro, color: NovaColorToken.statusWarningInk.color(in: scheme))
                }
                HStack(spacing: 8) {
                    NovaButton(label: RDLocalization.string("localizable.nova.document.cancel", table: .localizable, fallback: "Vazgeç"),
                        symbol: "xmark", variant: .surface) { recording = false }
                    NovaButton(label: RDLocalization.string("localizable.nova.document.save", table: .localizable, fallback: "Kaydet"),
                        symbol: "checkmark", isEnabled: !busy && draft.isReady, isLoading: busy) { save() }
                        .accessibilityIdentifier("equipment.inspection.save")
                }
            }
            .padding(10)
            .background(NovaColorToken.statusSuccessBg.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
            .onAppear { if draft.performedOn.isEmpty { draft.performedOn = NovaDayField.text(Date()) } }
        } else {
            NovaButton(label: RDLocalization.string("localizable.nova.equipment.record", table: .localizable, fallback: "Kontrol kaydet"),
                symbol: "plus.circle") { recording = true }
                .accessibilityIdentifier("equipment.record.open")
        }
    }

    private var resultPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            NovaText(text: RDLocalization.string("localizable.nova.equipment.field.result", table: .localizable, fallback: "Sonuç"),
                style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            HStack(spacing: 7) {
                ForEach(["pass", "conditional", "fail"], id: \.self) { value in
                    Button { draft.result = value } label: {
                        NovaSizedText(text: NovaEquipmentWords.result(value), size: 12,
                            weight: draft.result == value ? "Bold" : "Medium")
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(draft.result == value ? NovaColorToken.surface.color(in: scheme)
                                                              : NovaColorToken.surfaceMuted.color(in: scheme),
                                        in: RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11)
                                .strokeBorder(draft.result == value ? NovaColorToken.accentInk.color(in: scheme) : .clear,
                                              lineWidth: 1.2))
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("equipment.result.\(value)")
                        .accessibilityAddTraits(draft.result == value ? .isSelected : [])
                }
            }
        }
    }

    /// The report itself comes from the archive, so a check points at a file
    /// that really exists rather than carrying a second copy of one.
    @ViewBuilder private var reportPicker: some View {
        NovaFileChooserButton(
            label: RDLocalization.string("localizable.nova.equipment.field.report", table: .localizable, fallback: "Arşivdeki rapor"),
            value: draft.evidenceTitle
                ?? RDLocalization.string("localizable.nova.equipment.report.none", table: .localizable, fallback: "Seçilmedi"),
            symbol: "doc", isOpen: choosingReport, isAnswered: draft.evidenceAssetID != nil,
            identifier: "equipment.inspection.report") { choosingReport.toggle() }
        if choosingReport {
            if reports.isEmpty {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.report.empty", table: .localizable,
                    fallback: "Bu firmada arşivlenmiş kontrol raporu yok. Diğer Dosyalar'dan ekleyebilirsiniz."),
                    style: .metaQuiet)
            } else {
                NovaFileChooserPanel(
                    options: [.init(id: nil, title: RDLocalization.string("localizable.nova.equipment.report.none", table: .localizable, fallback: "Seçilmedi"), symbol: "xmark")]
                        + reports.map { .init(id: $0.id.uuidString, title: $0.title, symbol: "doc") },
                    selected: draft.evidenceAssetID?.uuidString, identifier: "equipment.inspection.report") { picked in
                        let entry = reports.first { $0.id.uuidString == picked }
                        draft.evidenceAssetID = entry?.id
                        draft.evidenceTitle = entry?.title
                        choosingReport = false
                    }
            }
        }
    }

    @ViewBuilder private var history: some View {
        if !row.inspections.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.history", table: .localizable, fallback: "Kontrol geçmişi"),
                    style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                ForEach(row.inspections) { entry in historyRow(entry) }
            }
        }
    }

    private func historyRow(_ entry: NovaEquipmentInspection) -> some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    NovaAnalysisTag(symbol: "calendar", text: entry.performedOn, status: .neutral)
                    NovaAnalysisTag(symbol: "checkmark.seal", text: NovaEquipmentWords.result(entry.result),
                        status: entry.result == "fail" ? .danger : .neutral)
                    if let due = entry.nextDueOn {
                        NovaAnalysisTag(symbol: "calendar.badge.clock", text: due, status: .neutral)
                    }
                }
                if let who = entry.inspector, !who.isEmpty { NovaText(text: who, style: .meta) }
                if let reference = entry.externalRef, !reference.isEmpty {
                    NovaText(text: reference, style: .metaQuiet)
                }
                if let note = entry.note, !note.isEmpty { NovaText(text: note, style: .metaQuiet) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var controls: some View {
        if canWrite {
            HStack(spacing: 8) {
                action("square.and.pencil", RDLocalization.string("localizable.nova.document.edit.short", table: .localizable, fallback: "Düzenle"),
                       id: "edit", status: .neutral) { editing = true }
                action("archivebox", RDLocalization.string("localizable.nova.equipment.archive", table: .localizable, fallback: "Envanterden çıkar"),
                       id: "archive", status: .danger) { confirmingArchive = true }
            }
            if confirmingArchive {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.archive.confirm", table: .localizable,
                    fallback: "Ekipman listeden çıkar; kayıtlı kontrol raporları silinmez."), style: .metaQuiet)
                NovaButton(label: RDLocalization.string("localizable.nova.document.archive.yes", table: .localizable, fallback: "Evet, arşivle"),
                    symbol: "archivebox", variant: .danger, isEnabled: !busy, isLoading: busy) {
                    run { try await client.archive(row); onChanged(); onClosed() }
                }.accessibilityIdentifier("equipment.archive.confirm")
            }
        }
    }

    private func save() {
        run {
            current = try await client.recordInspection(row, draft)
            draft = NovaEquipmentInspectionDraft()
            draft.performedOn = NovaDayField.text(Date())
            recording = false
            onChanged()
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            busy = true; error = nil
            do { try await work() }
            catch let failure as NovaEquipmentFailure { error = NovaEquipmentWords.failure(failure) }
            catch { self.error = NovaEquipmentWords.failure(.unavailable) }
            busy = false
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
        }.buttonStyle(.plain).disabled(busy)
            .accessibilityIdentifier("equipment.\(id)")
    }

    private func cell(_ symbol: String, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                NovaText(text: label, style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
            }
            NovaText(text: value, style: .meta).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .frame(minHeight: 34).accessibilityIdentifier("equipment.inspection.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Registering equipment. The type is chosen from the server's own names, and
/// the page says plainly that a name carries no period with it.
struct NovaEquipmentAddSheet: View {
    let companies: [NovaAnalysisCompanyOption]
    var preselected: UUID?
    let suggestions: [String]
    let rules: [NovaEquipmentRule]
    let workplaces: [NovaDocumentWorkplace]
    let client: NovaEquipmentCheckClient
    let onDone: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var company: UUID?
    @State private var draft = NovaEquipmentDraft()
    @State private var choosing: String?
    @State private var busy = false
    @State private var error: String?

    private var rule: NovaEquipmentRule? {
        draft.equipmentType.flatMap { type in rules.first { $0.equipmentType == type } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.add.title", table: .localizable, fallback: "Ekipman ekle"),
                    style: .sheetTitle)
                typePicker
                periodNote
                workplacePicker
                field(RDLocalization.string("localizable.nova.equipment.field.serial", table: .localizable, fallback: "Seri / kod"),
                      $draft.serialTag, id: "serial")
                field(RDLocalization.string("localizable.nova.equipment.field.location", table: .localizable, fallback: "Yeri (isteğe bağlı)"),
                      $draft.locationNote, id: "location")
                NovaDayField(label: RDLocalization.string("localizable.nova.equipment.field.acquired", table: .localizable, fallback: "Ediniliş tarihi"),
                    value: $draft.acquiredOn, identifier: "equipment.add.acquired", isClearable: true)
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
                NovaButton(label: RDLocalization.string("localizable.nova.equipment.add.save", table: .localizable, fallback: "Envantere ekle"),
                    symbol: "checkmark", isEnabled: !busy && draft.isReady && company != nil, isLoading: busy) { save() }
                    .accessibilityIdentifier("equipment.add.save")
            }.padding(16).novaPopupContentSize()
        }
        .onAppear {
            if company == nil { company = preselected ?? companies.first?.id }
            if draft.workplaceID == nil { draft.workplaceID = workplaces.first?.id }
        }
    }

    @ViewBuilder private var typePicker: some View {
        NovaFileChooserButton(
            label: RDLocalization.string("localizable.nova.equipment.field.type", table: .localizable, fallback: "Ekipman türü"),
            value: draft.equipmentType.map(NovaEquipmentWords.type)
                ?? RDLocalization.string("localizable.nova.equipment.type.choose", table: .localizable, fallback: "Tür seçin"),
            symbol: "shippingbox", isOpen: choosing == "type", isAnswered: draft.equipmentType != nil,
            identifier: "equipment.add.type") { choosing = choosing == "type" ? nil : "type" }
        if choosing == "type" {
            NovaFileChooserPanel(
                options: suggestions.map { .init(id: $0, title: NovaEquipmentWords.type($0), symbol: "shippingbox") },
                selected: draft.equipmentType, identifier: "equipment.add.type") { picked in
                    draft.equipmentType = picked
                    choosing = nil
                }
        }
    }

    /// A chosen name never arrives with a period. Either this company already
    /// set one for the type, or the screen says there is none yet.
    @ViewBuilder private var periodNote: some View {
        if draft.equipmentType != nil {
            if let rule {
                NovaText(text: String(format: RDLocalization.string("localizable.nova.equipment.period.value", table: .localizable,
                    fallback: "%1$d ay · %2$@"), rule.periodMonths, NovaEquipmentWords.source(rule.source)),
                    style: .micro, color: rule.needsReview ? NovaColorToken.statusWarningInk.color(in: scheme)
                                                           : NovaColorToken.textTertiary.color(in: scheme))
            } else {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.period.missing", table: .localizable,
                    fallback: "Bu tür için süre tanımlı değil. Süre tanımlanmadan sonraki kontrol tarihi hesaplanmaz."),
                    style: .micro, color: NovaColorToken.statusWarningInk.color(in: scheme))
            }
        }
    }

    @ViewBuilder private var workplacePicker: some View {
        NovaFileChooserButton(
            label: RDLocalization.string("localizable.nova.document.field.scope", table: .localizable, fallback: "Kapsam"),
            value: workplaces.first { $0.id == draft.workplaceID }?.name
                ?? RDLocalization.string("localizable.nova.equipment.workplace.choose", table: .localizable, fallback: "İşyeri seçin"),
            symbol: "building.2", isOpen: choosing == "workplace", isAnswered: draft.workplaceID != nil,
            identifier: "equipment.add.workplace") { choosing = choosing == "workplace" ? nil : "workplace" }
        if choosing == "workplace" {
            NovaFileChooserPanel(
                options: workplaces.map { .init(id: $0.id.uuidString, title: $0.name, symbol: "building.2") },
                selected: draft.workplaceID?.uuidString, identifier: "equipment.add.workplace") { picked in
                    draft.workplaceID = picked.flatMap(UUID.init(uuidString:))
                    choosing = nil
                }
        }
    }

    private func save() {
        guard let company else { return }
        Task {
            busy = true; error = nil
            do { _ = try await client.register(company, draft); onDone() }
            catch let failure as NovaEquipmentFailure { error = NovaEquipmentWords.failure(failure) }
            catch { self.error = NovaEquipmentWords.failure(.unavailable) }
            busy = false
        }
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .frame(minHeight: 34).accessibilityIdentifier("equipment.add.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Editing what the item is, never what its record says.
struct NovaEquipmentEditSheet: View {
    let item: NovaEquipmentItem
    let workplaces: [NovaDocumentWorkplace]
    let save: (NovaEquipmentDraft) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var draft: NovaEquipmentDraft
    @State private var choosing = false
    @State private var busy = false
    @State private var error: String?

    init(item: NovaEquipmentItem, workplaces: [NovaDocumentWorkplace],
         save: @escaping (NovaEquipmentDraft) async throws -> Void) {
        self.item = item; self.workplaces = workplaces; self.save = save
        var value = NovaEquipmentDraft()
        value.equipmentType = item.equipmentType
        value.serialTag = item.serialTag
        value.workplaceID = item.workplaceID
        value.acquiredOn = item.acquiredOn ?? ""
        value.locationNote = item.locationNote ?? ""
        _draft = State(initialValue: value)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.edit.title", table: .localizable, fallback: "Ekipman kaydını düzenle"),
                    style: .sheetTitle)
                // The type is what the period hangs on, so it is shown and not
                // edited: a different type is a different item.
                NovaText(text: NovaEquipmentWords.type(item.equipmentType), style: .metaQuiet)
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.document.field.scope", table: .localizable, fallback: "Kapsam"),
                    value: workplaces.first { $0.id == draft.workplaceID }?.name ?? "—",
                    symbol: "building.2", isOpen: choosing, identifier: "equipment.edit.workplace") { choosing.toggle() }
                if choosing {
                    NovaFileChooserPanel(
                        options: workplaces.map { .init(id: $0.id.uuidString, title: $0.name, symbol: "building.2") },
                        selected: draft.workplaceID?.uuidString, identifier: "equipment.edit.workplace") { picked in
                            draft.workplaceID = picked.flatMap(UUID.init(uuidString:))
                            choosing = false
                        }
                }
                field(RDLocalization.string("localizable.nova.equipment.field.serial", table: .localizable, fallback: "Seri / kod"),
                      $draft.serialTag, id: "serial")
                field(RDLocalization.string("localizable.nova.equipment.field.location", table: .localizable, fallback: "Yeri (isteğe bağlı)"),
                      $draft.locationNote, id: "location")
                NovaDayField(label: RDLocalization.string("localizable.nova.equipment.field.acquired", table: .localizable, fallback: "Ediniliş tarihi"),
                    value: $draft.acquiredOn, identifier: "equipment.edit.acquired", isClearable: true)
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
                NovaButton(label: RDLocalization.string("localizable.nova.document.save", table: .localizable, fallback: "Kaydet"),
                    symbol: "checkmark", isEnabled: !busy && draft.isReady, isLoading: busy) {
                    Task {
                        busy = true; error = nil
                        do { try await save(draft) }
                        catch let failure as NovaEquipmentFailure { error = NovaEquipmentWords.failure(failure) }
                        catch { self.error = NovaEquipmentWords.failure(.validation) }
                        busy = false
                    }
                }.accessibilityIdentifier("equipment.edit.save")
            }.padding(16).novaPopupContentSize()
        }
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .frame(minHeight: 34).accessibilityIdentifier("equipment.edit.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The inspection periods, by type. Nothing is pre-filled: the expert types the
/// period and says where it came from, and an unverified source is labelled as
/// their own decision on every screen that shows it.
struct NovaEquipmentPeriodSheet: View {
    let company: UUID?
    let suggestions: [String]
    let rules: [NovaEquipmentRule]
    let client: NovaEquipmentCheckClient
    let onDone: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var draft = NovaEquipmentRuleDraft()
    @State private var saved: [NovaEquipmentRule] = []
    @State private var choosing: String?
    @State private var busy = false
    @State private var error: String?

    private var current: [NovaEquipmentRule] {
        saved.isEmpty ? rules : saved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.periods.title", table: .localizable, fallback: "Kontrol süreleri"),
                    style: .sheetTitle)
                NovaHelpHint(text: RDLocalization.string("localizable.nova.equipment.periods.hint", table: .localizable,
                    fallback: "Süre ekipman türüne göre tanımlanır ve hiçbir tür için önceden doldurulmaz. Doğrulanmış bir kaynağa dayanmayan süre, uzman kararı olarak işaretlenir."))
                typePicker
                field(RDLocalization.string("localizable.nova.equipment.field.months", table: .localizable, fallback: "Süre (ay)"),
                      $draft.periodMonths, id: "months")
                sourcePicker
                if draft.source == .unapprovedFixture {
                    field(RDLocalization.string("localizable.nova.equipment.field.exception", table: .localizable, fallback: "Gerekçe"),
                          $draft.exceptionNote, id: "exception")
                }
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
                NovaButton(label: RDLocalization.string("localizable.nova.equipment.periods.save", table: .localizable, fallback: "Süreyi kaydet"),
                    symbol: "checkmark", isEnabled: !busy && draft.isReady && company != nil, isLoading: busy) { save() }
                    .accessibilityIdentifier("equipment.period.save")
                if !current.isEmpty {
                    NovaText(text: RDLocalization.string("localizable.nova.equipment.periods.existing", table: .localizable, fallback: "Tanımlı süreler"),
                        style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                    ForEach(current) { rule in ruleRow(rule) }
                }
                NovaButton(label: RDLocalization.string("localizable.nova.document.close", table: .localizable, fallback: "Kapat"),
                    symbol: "xmark", variant: .surface) { onDone() }
                    .accessibilityIdentifier("equipment.periods.close")
            }.padding(16).novaPopupContentSize()
        }
    }

    @ViewBuilder private var typePicker: some View {
        NovaFileChooserButton(
            label: RDLocalization.string("localizable.nova.equipment.field.type", table: .localizable, fallback: "Ekipman türü"),
            value: draft.equipmentType.map(NovaEquipmentWords.type)
                ?? RDLocalization.string("localizable.nova.equipment.type.choose", table: .localizable, fallback: "Tür seçin"),
            symbol: "shippingbox", isOpen: choosing == "type", isAnswered: draft.equipmentType != nil,
            identifier: "equipment.period.type") { choosing = choosing == "type" ? nil : "type" }
        if choosing == "type" {
            NovaFileChooserPanel(
                options: suggestions.map { code in
                    .init(id: code, title: NovaEquipmentWords.type(code),
                          count: current.first { $0.equipmentType == code }?.periodMonths, symbol: "shippingbox")
                },
                selected: draft.equipmentType, identifier: "equipment.period.type") { picked in
                    draft.equipmentType = picked
                    if let picked, let existing = current.first(where: { $0.equipmentType == picked }) {
                        draft.periodMonths = String(existing.periodMonths)
                        draft.source = existing.source
                        draft.exceptionNote = existing.exceptionNote ?? ""
                    }
                    choosing = nil
                }
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            NovaText(text: RDLocalization.string("localizable.nova.equipment.field.source", table: .localizable, fallback: "Sürenin kaynağı"),
                style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            VStack(spacing: 6) {
                ForEach(NovaEquipmentPeriodSource.allCases) { value in
                    Button { draft.source = value } label: {
                        HStack(spacing: 8) {
                            Image(systemName: draft.source == value ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                            NovaSizedText(text: NovaEquipmentWords.source(value), size: 12.5,
                                weight: draft.source == value ? "Bold" : "Medium")
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).frame(minHeight: 40)
                        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("equipment.period.source.\(value.rawValue)")
                        .accessibilityAddTraits(draft.source == value ? .isSelected : [])
                }
            }
        }
    }

    private func ruleRow(_ rule: NovaEquipmentRule) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: NovaEquipmentWords.type(rule.equipmentType), style: .meta)
                NovaText(text: String(format: RDLocalization.string("localizable.nova.equipment.period.value", table: .localizable,
                    fallback: "%1$d ay · %2$@"), rule.periodMonths, NovaEquipmentWords.source(rule.source)),
                    style: .micro, color: rule.needsReview ? NovaColorToken.statusWarningInk.color(in: scheme)
                                                           : NovaColorToken.textTertiary.color(in: scheme))
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
    }

    private func save() {
        guard let company else { return }
        Task {
            busy = true; error = nil
            do {
                let rule = try await client.setRule(company, draft)
                saved = current.filter { $0.equipmentType != rule.equipmentType } + [rule]
                draft = NovaEquipmentRuleDraft()
            }
            catch let failure as NovaEquipmentFailure { error = NovaEquipmentWords.failure(failure) }
            catch { self.error = NovaEquipmentWords.failure(.validation) }
            busy = false
        }
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .keyboardType(id == "months" ? .numberPad : .default)
                .frame(minHeight: 34).accessibilityIdentifier("equipment.period.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
