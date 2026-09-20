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
    var startRecording = false
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
    @State private var addingReport = false
    @State private var fileCategories: [NovaFileCategory] = []
    @State private var fileAccepts: [NovaFileAcceptance] = []
    @State private var fileAssurance = NovaFileAssurance()
    @State private var correcting: NovaEquipmentInspection?
    @State private var busy = false
    @State private var error: String?
    @State private var opened: URL?
    @State private var opening: UUID?
    @State private var appliedStartMode = false
    @State private var inspectionSection = "control"

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
                if startRecording {
                    compactPeriod
                    if canWrite { recordPanel }
                } else {
                    explanation
                    facts
                    periodCard
                    if canWrite { recordPanel }
                    history
                }
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
                if !startRecording { controls }
            }.padding(16).novaPopupContentSize()
        }
        .task {
            guard let company = row.companyID else { return }
            reports = (try? await client.filedReports(company)) ?? []
            if current == nil { current = try? await client.detail(row.id) }
            if let filing = try? await client.fileClient.catalogue() {
                fileCategories = filing.categories; fileAccepts = filing.accepts; fileAssurance = filing.assurance
            }
        }
        .onAppear {
            guard startRecording, !appliedStartMode else { return }
            appliedStartMode = true
            recording = true
        }
        .novaFullScreenCover(isPresented: $editing) {
            NovaPopup {
                NovaEquipmentEditSheet(item: row, workplaces: workplaces) { value in
                    current = try await client.update(row, value)
                    editing = false
                    onChanged()
                }
            }
        }
        .novaFullScreenCover(item: $correcting) { entry in
            NovaPopup {
                NovaEquipmentReportEditSheet(report: entry, periodMonths: row.periodMonths,
                    reports: reports) { value in
                        current = try await client.updateInspection(row, entry, value)
                        correcting = nil
                        onChanged()
                    }
            }
        }
        .sheet(item: $opened) { url in NovaFileShareSheet(url: url) }
    }

    private func open(_ entry: NovaEquipmentInspection) {
        guard let download = entry.evidenceDownload else { return }
        opening = entry.id; error = nil
        Task {
            do {
                let data = try await client.fileClient.download(download.bucket, download.path)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    .appendingPathComponent(download.path.components(separatedBy: "/").last ?? "belge")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try data.write(to: url, options: .completeFileProtection)
                opened = url
            } catch {
                self.error = RDLocalization.string("localizable.nova.file.failure.unavailable", table: .localizable,
                    fallback: "Dosya servisi şu anda kullanılamıyor.")
            }
            opening = nil
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 10) {
            NovaIcon(symbol: row.group.symbol, size: 19)
                .foregroundStyle(tone.tokens.ink.color(in: scheme))
                .frame(width: 44, height: 44)
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
                     row.nextDueOn ?? RDLocalization.string("localizable.nova.equipment.no.due", table: .localizable, fallback: "Tarih yok"),
                     // Whose answer that date is, said rather than assumed.
                     detail: NovaEquipmentWords.due(row.dueSource))
                cell("person", RDLocalization.string("localizable.nova.equipment.field.inspector", table: .localizable, fallback: "Kontrolü yapan"),
                     row.lastInspector ?? "—")
                cell("building.2", RDLocalization.string("localizable.nova.document.field.scope", table: .localizable, fallback: "Kapsam"),
                     workplaces.first { $0.id == row.workplaceID }?.name ?? "—")
                cell("number", RDLocalization.string("localizable.nova.equipment.field.ref", table: .localizable, fallback: "Rapor no"),
                     row.lastExternalRef ?? "—")
                // Informational only: it moves no state and no counter, and the
                // detail line says whose statement it is.
                cell("text.bubble", RDLocalization.string("localizable.nova.equipment.field.katip", table: .localizable, fallback: "İSG-KATİP"),
                     row.katipDeclared
                        ? RDLocalization.string("localizable.nova.equipment.katip.yes", table: .localizable, fallback: "Atama yapıldı")
                        : RDLocalization.string("localizable.nova.equipment.katip.no", table: .localizable, fallback: "İşaretlenmedi"),
                     detail: row.katipDeclared
                        ? RDLocalization.string("localizable.nova.equipment.katip.declared", table: .localizable, fallback: "uzman beyanı")
                        : "")
            }
            if row.katipDeclared, let note = row.katipNote, !note.isEmpty {
                NovaText(text: note, style: .metaQuiet)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 7)
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
                        NovaText(text: row.periodSource == .regulationDefault
                            ? RDLocalization.string("localizable.nova.equipment.period.default.review", table: .localizable,
                                fallback: "Bu, ürünün bu tür için başlattığı genel süredir; bu firma için henüz onaylanmadı. Süreler ekranından onaylayın veya değiştirin.")
                            : RDLocalization.string("localizable.nova.equipment.period.review", table: .localizable,
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

    private var compactPeriod: some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass").font(.system(size: 13, weight: .semibold))
            NovaText(text: row.periodMonths.map { "Kontrol aralığı · \($0) ay" } ?? "Kontrol aralığı tanımlı değil", style: .meta)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).frame(minHeight: 42)
        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 13))
    }

    /// Recording a report, in the same popup. The next date is the server's
    /// answer; this panel never previews one it worked out itself.
    @ViewBuilder private var recordPanel: some View {
        if recording {
            VStack(alignment: .leading, spacing: 9) {
                inspectionStep("control", title: "1 · Kontrol", symbol: "calendar.badge.checkmark",
                    summary: NovaEquipmentWords.result(draft.result)) {
                    HStack(alignment: .top, spacing: 8) {
                        compactInspectionDate(label: "Kontrol", value: $draft.performedOn,
                            identifier: "equipment.inspection.performed")
                            .frame(maxWidth: .infinity)
                        if draft.result == "fail" {
                            NovaCard(padding: 10, tint: NovaColorToken.surfaceMuted.color(in: scheme)) {
                                NovaText(text: "Sonraki tarih yok", style: .metaQuiet).frame(maxWidth: .infinity, minHeight: 40)
                            }.frame(maxWidth: .infinity)
                        } else {
                            compactInspectionDate(label: "Sonraki", value: $draft.nextDueOn,
                                identifier: "equipment.inspection.due", isClearable: true)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    resultPicker
                    NovaButton(label: "Detaylara geç", symbol: "chevron.down", variant: .surface) {
                        withAnimation { inspectionSection = "details" }
                    }
                }
                inspectionStep("details", title: "2 · Detaylar", symbol: "text.justify.left",
                    summary: draft.inspector.isEmpty ? "İsteğe bağlı" : draft.inspector) {
                    field("Kontrolü yapan", $draft.inspector, id: "inspector")
                    field("Rapor no", $draft.externalRef, id: "ref")
                    katipField
                    field("Not", $draft.note, id: "note")
                    NovaButton(label: "Rapora geç", symbol: "chevron.down", variant: .surface) {
                        withAnimation { inspectionSection = "report" }
                    }
                }
                inspectionStep("report", title: "3 · Rapor", symbol: "doc",
                    summary: draft.evidenceTitle ?? "İsteğe bağlı") {
                    reportPicker
                }
                HStack(spacing: 8) {
                    NovaButton(label: RDLocalization.string("localizable.nova.document.cancel", table: .localizable, fallback: "Vazgeç"),
                        symbol: "xmark", variant: .surface) { recording = false }
                    NovaButton(label: RDLocalization.string("localizable.nova.document.save", table: .localizable, fallback: "Kaydet"),
                        symbol: "checkmark", isEnabled: !busy && draft.isReady, isLoading: busy) { save() }
                        .accessibilityIdentifier("equipment.inspection.save")
                }
            }
            .onAppear {
            if draft.performedOn.isEmpty { draft.performedOn = NovaDayField.text(Date()) }
            fillNextDue()
        }
        .onChange(of: draft.performedOn) { _ in fillNextDue() }
        .onChange(of: draft.result) { value in if value == "fail" { draft.nextDueOn = "" } else { fillNextDue() } }
        } else {
            NovaButton(label: RDLocalization.string("localizable.nova.equipment.record", table: .localizable, fallback: "Kontrol kaydet"),
                symbol: "plus.circle") { recording = true }
                .accessibilityIdentifier("equipment.record.open")
        }
    }

    private func inspectionStep<Content: View>(_ id: String, title: String, symbol: String,
                                                summary: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { inspectionSection = inspectionSection == id ? "" : id }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 20)
                    NovaText(text: title, style: .bodyStrong)
                    Spacer(minLength: 0)
                    NovaText(text: summary, style: .micro, color: NovaColorToken.textMuted.color(in: scheme)).lineLimit(1)
                    Image(systemName: inspectionSection == id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }.frame(minHeight: 42).contentShape(Rectangle())
            }.buttonStyle(NovaRowPressStyle())
            if inspectionSection == id {
                content().padding(.top, 2)
            }
        }
        .padding(11)
        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
    }

    /// The general date row is intentionally wide. Inspection dates sit in a
    /// two-column step, so they use a vertical caption and let both controls
    /// share the popup width without growing the sheet beyond the display.
    private func compactInspectionDate(label: String, value: Binding<String>,
                                       identifier: String, isClearable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 12, weight: .semibold))
                NovaText(text: label, style: .micro,
                    color: NovaColorToken.textTertiary.color(in: scheme))
            }
            HStack(spacing: 2) {
                if isClearable && value.wrappedValue.isEmpty {
                    Button { value.wrappedValue = NovaDayField.text(Date()) } label: {
                        NovaText(text: "Belirtilmedi", style: .meta).frame(minHeight: 32)
                    }
                    .buttonStyle(NovaRowPressStyle())
                    .accessibilityIdentifier("\(identifier).set")
                } else {
                    DatePicker("", selection: Binding(
                        get: { NovaDayField.date(value.wrappedValue) ?? Date() },
                        set: { value.wrappedValue = NovaDayField.text($0) }), displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                        .accessibilityIdentifier(identifier)
                        .accessibilityLabel(Text(verbatim: label))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if isClearable && !value.wrappedValue.isEmpty {
                    Button { value.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle").font(.system(size: 13))
                            .frame(width: 26, height: 32)
                    }
                    .buttonStyle(NovaRowPressStyle())
                    .accessibilityIdentifier("\(identifier).clear")
                    .accessibilityLabel("Temizle")
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .novaControlBackground(cornerRadius: 13)
    }

    /// The next date, filled from the type's period as soon as a report date is
    /// picked, and editable. Whether what is saved counts as the period's answer
    /// or the expert's is the server's call, not this field's.
    @ViewBuilder private var nextDueField: some View {
        if draft.result == "fail" {
            NovaText(text: RDLocalization.string("localizable.nova.equipment.fail.hint", table: .localizable,
                fallback: "Olumsuz sonuç için sonraki kontrol tarihi üretilmez."),
                style: .micro, color: NovaColorToken.statusWarningInk.color(in: scheme))
        } else {
            NovaDayField(label: RDLocalization.string("localizable.nova.equipment.field.next", table: .localizable, fallback: "Sonraki kontrol"),
                value: $draft.nextDueOn, identifier: "equipment.inspection.due", isClearable: true)
            if let months = row.periodMonths {
                NovaText(text: String(format: RDLocalization.string("localizable.nova.equipment.due.auto", table: .localizable,
                    fallback: "%d aylık süreden otomatik dolduruldu; değiştirebilirsiniz."), months),
                    style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
            }
        }
    }

    /// Optional, and never a verification: the product does not reach İSG-KATİP.
    @ViewBuilder private var katipField: some View {
        Button { draft.katipDeclared.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: draft.katipDeclared ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                NovaSizedText(text: RDLocalization.string("localizable.nova.equipment.katip.mark", table: .localizable,
                    fallback: "İSG-KATİP ataması yapıldı"), size: 12.5,
                    weight: draft.katipDeclared ? "Bold" : "Medium")
                Spacer(minLength: 0)
            }.frame(minHeight: 40)
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier("equipment.inspection.katip")
            .accessibilityAddTraits(draft.katipDeclared ? .isSelected : [])
        if draft.katipDeclared {
            field(RDLocalization.string("localizable.nova.equipment.katip.note", table: .localizable, fallback: "Atama notu"),
                  $draft.katipNote, id: "katip")
        }
        NovaText(text: "İsteğe bağlı uzman beyanı.", style: .micro,
            color: NovaColorToken.textTertiary.color(in: scheme))
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
                    }.buttonStyle(NovaRowPressStyle())
                        .accessibilityIdentifier("equipment.result.\(value)")
                        .accessibilityAddTraits(draft.result == value ? .isSelected : [])
                }
            }
        }
    }

    /// The report itself comes from the archive, so a check points at a file
    /// that really exists rather than carrying a second copy of one. A new
    /// one uploads right here — no redirect to Dosyalarım and back.
    @ViewBuilder private var reportPicker: some View {
        NovaFileChooserButton(
            label: RDLocalization.string("localizable.nova.equipment.field.report", table: .localizable, fallback: "Arşivdeki rapor"),
            value: draft.evidenceTitle
                ?? RDLocalization.string("localizable.nova.equipment.report.none", table: .localizable, fallback: "Seçilmedi"),
            symbol: "doc", isOpen: choosingReport, isAnswered: draft.evidenceAssetID != nil,
            identifier: "equipment.inspection.report") { choosingReport.toggle(); addingReport = false }
        if choosingReport {
            if !reports.isEmpty {
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
            if addingReport {
                NovaFileAddInline(companies: [], preselected: row.companyID,
                        categories: {
                            let scoped = fileCategories.filter { $0.code == "inspection_report" }
                            return scoped.isEmpty ? fileCategories : scoped
                        }(),
                        accepts: fileAccepts, assurance: fileAssurance, client: client.fileClient) { entry in
                            if let entry {
                                draft.evidenceAssetID = entry.assetID
                                draft.evidenceTitle = entry.title
                                reports.append(entry)
                            }
                            addingReport = false; choosingReport = false
                        }
            } else {
                NovaButton(label: RDLocalization.string("localizable.nova.equipment.report.add", table: .localizable,
                    fallback: "Yeni dosya ekle"), symbol: "plus", variant: .surface) { addingReport = true }
                    .accessibilityIdentifier("equipment.inspection.report.add")
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
            Button { if canWrite { correcting = entry } } label: { historyBody(entry) }
                .buttonStyle(NovaRowPressStyle()).disabled(!canWrite)
                .accessibilityIdentifier("equipment.history.\(entry.id.uuidString.lowercased())")
            if entry.evidenceDownload != nil {
                Button { open(entry) } label: {
                    if opening == entry.id { ProgressView() }
                    else { Image(systemName: "arrow.up.right.square").font(.system(size: 13)) }
                }.buttonStyle(NovaRowPressStyle()).disabled(opening != nil)
                    .accessibilityIdentifier("equipment.history.\(entry.id.uuidString.lowercased()).open")
            }
        }
        .padding(9)
        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
    }

    private func historyBody(_ entry: NovaEquipmentInspection) -> some View {
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
                HStack(spacing: 5) {
                    if entry.dueSource == .expert {
                        NovaAnalysisTag(symbol: "pencil", text: NovaEquipmentWords.due(.expert), status: .neutral)
                    }
                    if entry.katipDeclared {
                        NovaAnalysisTag(symbol: "text.bubble",
                            text: RDLocalization.string("localizable.nova.equipment.katip.tag", table: .localizable, fallback: "KATİP beyanı"),
                            status: .neutral)
                    }
                    Spacer(minLength: 0)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if canWrite {
                Image(systemName: "square.and.pencil").font(.system(size: 12))
                    .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            }
        }
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

    /// Fills the field from the type's period so the expert sees the date the
    /// server would produce, and can change it before saving. This is a form
    /// default; the server recomputes and decides what the saved date means.
    private func fillNextDue() {
        guard draft.result != "fail", let months = row.periodMonths,
              let performed = NovaDayField.date(draft.performedOn) else { return }
        guard let next = Calendar(identifier: .gregorian).date(byAdding: .month, value: months, to: performed)
        else { return }
        draft.nextDueOn = NovaDayField.text(next)
    }

    private func save() {
        run {
            current = try await client.recordInspection(row, draft)
            draft = NovaEquipmentInspectionDraft()
            draft.performedOn = NovaDayField.text(Date())
            fillNextDue()
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
        }.buttonStyle(NovaRowPressStyle()).disabled(busy)
            .accessibilityIdentifier("equipment.\(id)")
    }

    private func cell(_ symbol: String, _ label: String, _ value: String,
                      detail: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                NovaText(text: label, style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
            }
            NovaText(text: value, style: .meta).lineLimit(2)
            if !detail.isEmpty {
                NovaText(text: detail, style: .micro, color: NovaColorToken.textMuted.color(in: scheme))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(NovaFont.font(.body))
                .frame(minHeight: 34).accessibilityIdentifier("equipment.inspection.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Correcting a report that is already on file. The check date and the result
/// are shown and not edited: they are what the report is, and the screen says
/// what to do instead when one of them is wrong.
struct NovaEquipmentReportEditSheet: View {
    let report: NovaEquipmentInspection
    let periodMonths: Int?
    let reports: [NovaFileEntry]
    let save: (NovaEquipmentInspectionDraft) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var draft: NovaEquipmentInspectionDraft
    @State private var choosingReport = false
    @State private var busy = false
    @State private var error: String?

    init(report: NovaEquipmentInspection, periodMonths: Int?, reports: [NovaFileEntry],
         save: @escaping (NovaEquipmentInspectionDraft) async throws -> Void) {
        self.report = report; self.periodMonths = periodMonths; self.reports = reports; self.save = save
        var value = NovaEquipmentInspectionDraft()
        value.performedOn = report.performedOn
        value.result = report.result
        value.nextDueOn = report.nextDueOn ?? ""
        value.inspector = report.inspector ?? ""
        value.externalRef = report.externalRef ?? ""
        value.note = report.note ?? ""
        value.katipDeclared = report.katipDeclared
        value.katipNote = report.katipNote ?? ""
        value.evidenceAssetID = report.evidenceAssetID
        value.evidenceTitle = reports.first { $0.id == report.evidenceAssetID }?.title
        _draft = State(initialValue: value)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.report.edit.title", table: .localizable, fallback: "Kontrol kaydını düzelt"),
                    style: .sheetTitle)
                HStack(spacing: 5) {
                    NovaAnalysisTag(symbol: "calendar", text: report.performedOn, status: .neutral)
                    NovaAnalysisTag(symbol: "checkmark.seal", text: NovaEquipmentWords.result(report.result),
                        status: report.result == "fail" ? .danger : .neutral)
                    Spacer(minLength: 0)
                }
                NovaHelpHint(text: RDLocalization.string("localizable.nova.equipment.report.edit.hint", table: .localizable,
                    fallback: "Kontrol tarihi ve sonucu raporun kendisidir; buradan değiştirilmez. Yanlışsa doğru raporu ayrıca kaydedin."))
                if report.result == "fail" {
                    NovaText(text: RDLocalization.string("localizable.nova.equipment.fail.hint", table: .localizable,
                        fallback: "Olumsuz sonuç için sonraki kontrol tarihi üretilmez."),
                        style: .micro, color: NovaColorToken.statusWarningInk.color(in: scheme))
                } else {
                    NovaDayField(label: RDLocalization.string("localizable.nova.equipment.field.next", table: .localizable, fallback: "Sonraki kontrol"),
                        value: $draft.nextDueOn, identifier: "equipment.report.due", isClearable: true)
                    if let periodMonths {
                        NovaText(text: String(format: RDLocalization.string("localizable.nova.equipment.due.period.is", table: .localizable,
                            fallback: "Türün süresi %d ay. Değiştirirseniz kayıt, tarihin sizin belirlediğinizi söyler."), periodMonths),
                            style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                    }
                }
                field(RDLocalization.string("localizable.nova.equipment.field.inspector", table: .localizable, fallback: "Kontrolü yapan"),
                      $draft.inspector, id: "inspector")
                field(RDLocalization.string("localizable.nova.equipment.field.ref", table: .localizable, fallback: "Rapor no"),
                      $draft.externalRef, id: "ref")
                katipField
                field(RDLocalization.string("localizable.nova.document.field.note", table: .localizable, fallback: "Not"),
                      $draft.note, id: "note")
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
                NovaButton(label: RDLocalization.string("localizable.nova.document.save", table: .localizable, fallback: "Kaydet"),
                    symbol: "checkmark", isEnabled: !busy, isLoading: busy) {
                    Task {
                        busy = true; error = nil
                        do { try await save(draft) }
                        catch let failure as NovaEquipmentFailure { error = NovaEquipmentWords.failure(failure) }
                        catch { self.error = NovaEquipmentWords.failure(.validation) }
                        busy = false
                    }
                }.accessibilityIdentifier("equipment.report.save")
            }.padding(16).novaPopupContentSize()
        }
    }

    /// The same optional, informational mark the entry form carries.
    @ViewBuilder private var katipField: some View {
        Button { draft.katipDeclared.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: draft.katipDeclared ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                NovaSizedText(text: RDLocalization.string("localizable.nova.equipment.katip.mark", table: .localizable,
                    fallback: "İSG-KATİP ataması yapıldı"), size: 12.5,
                    weight: draft.katipDeclared ? "Bold" : "Medium")
                Spacer(minLength: 0)
            }.frame(minHeight: 40)
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier("equipment.report.katip")
            .accessibilityAddTraits(draft.katipDeclared ? .isSelected : [])
        if draft.katipDeclared {
            field(RDLocalization.string("localizable.nova.equipment.katip.note", table: .localizable, fallback: "Atama notu"),
                  $draft.katipNote, id: "katip")
        }
        NovaText(text: RDLocalization.string("localizable.nova.equipment.katip.hint", table: .localizable,
            fallback: "Bu işaret uzmanın kendi beyanıdır. Uygulama İSG-KATİP üzerinde sorgulama veya işlem yapmaz."),
            style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(NovaFont.font(.body))
                .frame(minHeight: 34).accessibilityIdentifier("equipment.report.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Starts a periodic control from the action the user asked for: first pick
/// the company's equipment, then enter that equipment's control and report.
/// Equipment registration remains available as the prerequisite when the
/// company has no inventory yet.
struct NovaEquipmentInspectionFlow: View {
    let items: [NovaEquipmentItem]
    let companies: [NovaAnalysisCompanyOption]
    let company: UUID
    let suggestions: [NovaEquipmentCheckService.Suggestion]
    let rules: [NovaEquipmentRule]
    let workplaces: [NovaDocumentWorkplace]
    let client: NovaEquipmentCheckClient
    var canWrite = true
    let onChanged: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var selected: NovaEquipmentItem?
    @State private var addingEquipment = false
    @State private var query = ""

    private var filtered: [NovaEquipmentItem] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? items : items.filter { $0.matches(query) }
    }

    var body: some View {
        if let selected {
            NovaEquipmentItemSheet(item: selected,
                rule: rules.first { $0.equipmentType == selected.equipmentType },
                workplaces: workplaces, client: client, canWrite: canWrite,
                startRecording: true, onChanged: onChanged,
                onClosed: { self.selected = nil })
        } else if addingEquipment {
            NovaEquipmentAddSheet(companies: companies, preselected: company,
                suggestions: suggestions, rules: rules, workplaces: workplaces, client: client) {
                    addingEquipment = false
                    onChanged()
                }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    NovaPopupHeading(text: "Periyodik kontrol ekle", symbol: "checkmark.shield",
                        subtitle: "Kontrolün uygulanacağı ekipmanı seçin.")
                    if !items.isEmpty {
                        NovaAnalysisSearchField(text: $query, placeholder: "Ekipman türü veya seri/kod ara",
                            identifier: "equipment.inspection.search")
                    }
                    if filtered.isEmpty {
                        NovaEmptyState(title: items.isEmpty ? "Önce ekipman ekleyin" : "Bu aramaya uyan ekipman yok",
                            message: items.isEmpty
                                ? "Ekipman firmaya bir kez kaydedilir; sonraki tüm periyodik kontroller ve raporlar bu ekipmanın geçmişine eklenir."
                                : "Aramayı temizleyerek firmanın diğer ekipmanlarını görüntüleyebilirsiniz.")
                    } else {
                        ForEach(filtered) { item in
                            Button { selected = item } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "shippingbox").font(.system(size: 16))
                                        .frame(width: 34, height: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        NovaText(text: NovaEquipmentWords.type(item.equipmentType), style: .cardTitle)
                                        NovaText(text: item.serialTag, style: .metaQuiet)
                                    }
                                    Spacer(minLength: 0)
                                    VStack(alignment: .trailing, spacing: 2) {
                                        NovaText(text: item.lastPerformedOn.map { "Son: \($0)" } ?? "Henüz kontrol yok", style: .micro)
                                        NovaText(text: item.nextDueOn.map { "Sonraki: \($0)" } ?? "Sonraki tarih yok", style: .micro,
                                            color: NovaColorToken.textTertiary.color(in: scheme))
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(NovaColorToken.text.color(in: scheme))
                                .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                                .novaControlBackground(cornerRadius: 14)
                            }.buttonStyle(NovaRowPressStyle())
                                .accessibilityIdentifier("equipment.inspection.choice.\(item.id.uuidString.lowercased())")
                        }
                    }
                    NovaButton(label: items.isEmpty ? "İlk ekipmanı ekle" : "Yeni ekipman ekle",
                        symbol: "plus", variant: .surface, isEnabled: canWrite) { addingEquipment = true }
                }.padding(16).novaPopupContentSize()
            }
        }
    }
}

/// Registering equipment. The type is chosen from the server's own names, and
/// the page says plainly that a name carries no period with it.
struct NovaEquipmentAddSheet: View {
    let companies: [NovaAnalysisCompanyOption]
    var preselected: UUID?
    let suggestions: [NovaEquipmentCheckService.Suggestion]
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
                options: suggestions.map { entry in
                    .init(id: entry.code, title: NovaEquipmentWords.type(entry.code),
                          count: entry.defaultPeriodMonths, symbol: "shippingbox")
                },
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
            } else if let months = suggestions.first(where: { $0.code == draft.equipmentType })?.defaultPeriodMonths {
                NovaText(text: String(format: RDLocalization.string("localizable.nova.equipment.period.starts", table: .localizable,
                    fallback: "Bu tür %1$d ay ile başlar · %2$@"), months,
                    NovaEquipmentWords.source(.regulationDefault)),
                    style: .micro, color: NovaColorToken.statusWarningInk.color(in: scheme))
            } else {
                NovaText(text: RDLocalization.string("localizable.nova.equipment.period.missing", table: .localizable,
                    fallback: "Bu tür için süre tanımlı değil. Süre tanımlanmadan sonraki kontrol tarihi hesaplanmaz."),
                    style: .micro, color: NovaColorToken.statusWarningInk.color(in: scheme))
            }
        }
    }

    // A company with no workplace has nothing to ask, and one with exactly
    // one gets it silently — only a real choice among several is shown.
    @ViewBuilder private var workplacePicker: some View {
        if workplaces.count <= 1 {
            VStack(alignment: .leading, spacing: 4) {
                NovaText(text: RDLocalization.string("localizable.nova.document.field.scope", table: .localizable, fallback: "Kapsam"),
                    style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                NovaText(text: workplaces.first?.name
                    ?? RDLocalization.string("localizable.nova.equipment.noworkplace", table: .localizable,
                        fallback: "Bu firmada kayıt açılacak bir işyeri yok."), style: .cardTitle)
            }
        } else {
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
            TextField(label, text: text).font(NovaFont.font(.body))
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
            TextField(label, text: text).font(NovaFont.font(.body))
                .frame(minHeight: 34).accessibilityIdentifier("equipment.edit.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The inspection periods, by type. Nothing is pre-filled: the expert types the
/// period and says where it came from, and an unverified source is labelled as
/// their own decision on every screen that shows it.
struct NovaEquipmentPeriodSheet: View {
    let company: UUID?
    let suggestions: [NovaEquipmentCheckService.Suggestion]
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
                options: suggestions.map { entry in
                    .init(id: entry.code, title: NovaEquipmentWords.type(entry.code),
                          count: current.first { $0.equipmentType == entry.code }?.periodMonths
                              ?? entry.defaultPeriodMonths,
                          symbol: "shippingbox")
                },
                selected: draft.equipmentType, identifier: "equipment.period.type") { picked in
                    draft.equipmentType = picked
                    // Pre-fill from what is already on file, or from the
                    // product's own starting period when nothing is.
                    if let picked {
                        if let existing = current.first(where: { $0.equipmentType == picked }) {
                            draft.periodMonths = String(existing.periodMonths)
                            draft.source = existing.source.needsReview ? .manufacturer : existing.source
                            draft.exceptionNote = existing.exceptionNote ?? ""
                        } else if let months = suggestions.first(where: { $0.code == picked })?.defaultPeriodMonths {
                            draft.periodMonths = String(months)
                        }
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
                // 'regulation_default' is the product's own label and is not
                // offered: choosing a source means standing behind it.
                ForEach(NovaEquipmentPeriodSource.choosable) { value in
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
                        .novaControlBackground(cornerRadius: 11)
                    }.buttonStyle(NovaRowPressStyle())
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
            TextField(label, text: text).font(NovaFont.font(.body))
                .keyboardType(id == "months" ? .numberPad : .default)
                .frame(minHeight: 34).accessibilityIdentifier("equipment.period.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
