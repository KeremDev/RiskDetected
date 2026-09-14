import SwiftUI

/// What the edit form collected. The screen turns it into the patch the
/// analysis service sends.
struct NovaFindingEditValues: Equatable {
    var title: String?
    var category: String?
    var body: String?
    var measure: String?
    var references: String?
    var score = NovaRiskScoreInput()
}

/// Every detail of a scored finding, editable. The score is re-entered on the
/// published scales, never typed as a free number.
struct NovaFindingEditSheet: View {
    let item: NovaAnalysisItem
    let method: NovaRiskMethod
    let save: (NovaFindingEditValues) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var title = ""
    @State private var category = ""
    @State private var body_ = ""
    @State private var measure = ""
    @State private var references = ""
    @State private var score = NovaRiskScoreInput()
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.edit.title", table: .localizable, fallback: "Bulguyu düzenle"), style: .sheetTitle)
                NovaHelpHint(text: RDLocalization.string("localizable.nova.analysis.edit.hint", table: .localizable,
                    fallback: "Değişiklikleriniz bulguya işlenir; skoru yeniden girerseniz bandı sunucu hesaplar."))
                NovaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        field(RDLocalization.string("localizable.nova.analysis.field.title", table: .localizable, fallback: "Başlık"), $title, id: "title")
                        field(RDLocalization.string("localizable.nova.analysis.field.category", table: .localizable, fallback: "Kategori"), $category, id: "category")
                        area(RDLocalization.string("localizable.nova.analysis.field.body", table: .localizable, fallback: "Açıklama"), $body_, id: "body")
                        area(RDLocalization.string("localizable.nova.analysis.field.measure", table: .localizable, fallback: "Önlem"), $measure, id: "measure")
                        area(RDLocalization.string("localizable.nova.analysis.field.references", table: .localizable, fallback: "Mevzuat"), $references, id: "references")
                    }
                }
                NovaRiskScoreEditor(score: $score, allowsClearing: false)
                if let error { NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.edit.save", table: .localizable, fallback: "Değişiklikleri kaydet"),
                    symbol: "checkmark", isEnabled: !saving && !title.trimmingCharacters(in: .whitespaces).isEmpty,
                    isLoading: saving) { Task { await submit() } }
                    .accessibilityIdentifier("analysis.edit.save")
            }.padding(20).novaPopupContentSize()
        }
        .background(NovaKeyboardDismissArea())
        .onAppear {
            guard !loaded else { return }
            loaded = true
            title = item.title
            category = item.category ?? ""
            body_ = item.body
            measure = item.measure ?? ""
            references = item.references ?? ""
            score = NovaRiskScoreInput(method: method)
        }
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .frame(minHeight: 36).accessibilityIdentifier("analysis.edit.\(id)")
        }
    }
    private func area(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextEditor(text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .frame(minHeight: 72).scrollContentBackground(.hidden)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("analysis.edit.\(id)")
        }
    }

    private func submit() async {
        saving = true; error = nil
        var values = NovaFindingEditValues()
        values.title = title
        values.category = category
        values.body = body_
        values.measure = measure
        values.references = references
        // A score the expert did not finish is not sent at all, so a partial
        // entry can never overwrite the numbers the analysis produced.
        values.score = score.isComplete ? score : NovaRiskScoreInput()
        do { try await save(values) }
        catch let failure as NovaNonconformityFailure { error = NovaNonconformityWords.failure(failure) }
        catch {
            self.error = RDLocalization.string("localizable.nova.analysis.edit.failed", table: .localizable,
                fallback: "Bulgu güncellenemedi. Aynı işlemi tekrar deneyin.")
        }
        saving = false
    }
}

/// The two published scales, as pickers. Nothing here computes what is stored:
/// the band shown is a preview of the same published rule the server applies.
struct NovaRiskScoreEditor: View {
    @Binding var score: NovaRiskScoreInput
    var allowsClearing = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                NovaText(text: RDLocalization.string("localizable.nova.risk.method", table: .localizable, fallback: "Risk metodu"), style: .label,
                    color: NovaColorToken.textTertiary.color(in: scheme))
                HStack(spacing: 8) {
                    ForEach(NovaRiskMethod.allCases) { value in
                        methodChip(value)
                    }
                    if allowsClearing && score.method != nil {
                        Button { score.select(nil) } label: {
                            NovaText(text: RDLocalization.string("localizable.nova.risk.method.clear", table: .localizable, fallback: "Skorsuz"), style: .meta)
                                .padding(.horizontal, 12).frame(minHeight: 40)
                        }.buttonStyle(.plain).accessibilityIdentifier("risk.method.none")
                    }
                }
                switch score.method {
                case .fineKinney:
                    scale(RDLocalization.string("localizable.nova.risk.probability", table: .localizable, fallback: "Olasılık"),
                          NovaRiskMethod.probabilityScale, $score.probability, id: "probability")
                    scale(RDLocalization.string("localizable.nova.risk.frequency", table: .localizable, fallback: "Frekans"),
                          NovaRiskMethod.frequencyScale, $score.frequency, id: "frequency")
                    scale(RDLocalization.string("localizable.nova.risk.severity", table: .localizable, fallback: "Şiddet"),
                          NovaRiskMethod.severityScale, $score.severity, id: "severity")
                case .matrix5x5:
                    matrix(RDLocalization.string("localizable.nova.risk.probability", table: .localizable, fallback: "Olasılık"),
                           $score.matrixProbability, id: "probability")
                    matrix(RDLocalization.string("localizable.nova.risk.severity", table: .localizable, fallback: "Şiddet"),
                           $score.matrixSeverity, id: "severity")
                case .none:
                    NovaText(text: RDLocalization.string("localizable.nova.risk.method.pick", table: .localizable,
                        fallback: "Skorlamak için bir metot seçin."), style: .metaQuiet)
                }
                result
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func methodChip(_ value: NovaRiskMethod) -> some View {
        let isSelected = score.method == value
        return Button { score.select(value) } label: {
            NovaText(text: NovaNonconformityWords.method(value), style: .meta,
                color: isSelected ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(isSelected ? NovaColorToken.statusSuccessBg.color(in: scheme) : NovaColorToken.surfaceMuted.color(in: scheme),
                    in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("risk.method.\(value.rawValue)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func scale(_ label: String, _ values: [Double], _ binding: Binding<Double?>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(values, id: \.self) { value in
                        chip(text: NovaNonconformityWords.score(value), isSelected: binding.wrappedValue == value,
                             identifier: "risk.\(id).\(NovaNonconformityWords.score(value))") { binding.wrappedValue = value }
                    }
                }
            }
        }
    }

    private func matrix(_ label: String, _ binding: Binding<Int?>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            HStack(spacing: 6) {
                ForEach(NovaRiskMethod.matrixScale, id: \.self) { value in
                    chip(text: String(value), isSelected: binding.wrappedValue == value,
                         identifier: "risk.\(id).\(value)") { binding.wrappedValue = value }
                }
            }
        }
    }

    private func chip(text: String, isSelected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaText(text: text, style: .meta,
                color: isSelected ? NovaColorToken.onInverse.color(in: scheme) : NovaColorToken.text.color(in: scheme))
                .padding(.horizontal, 14).frame(minWidth: 44, minHeight: 40)
                .background(isSelected ? NovaColorToken.inverse.color(in: scheme) : NovaColorToken.surfaceMuted.color(in: scheme),
                    in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var result: some View {
        if let value = score.score, let band = score.band {
            HStack(spacing: 8) {
                NovaStatusPill(label: NovaNonconformityWords.band(band.rawValue), status: NovaNonconformityWords.tone(band.rawValue))
                NovaText(text: String(format: RDLocalization.string("localizable.nova.risk.score.preview", table: .localizable,
                    fallback: "Skor %@ · kaydedilen bandı sunucu hesaplar"), NovaNonconformityWords.score(value)), style: .metaQuiet)
            }
        } else if score.method != nil {
            NovaText(text: RDLocalization.string("localizable.nova.risk.score.incomplete", table: .localizable,
                fallback: "Skor için tüm değerleri seçin."), style: .metaQuiet)
        }
    }
}

/// Turns the chosen items into records on the company, one by one, and says
/// what happened to each of them.
struct NovaAnalysisFileSheet: View {
    let items: [NovaAnalysisItem]
    let section: NovaAnalysisSectionKind
    let loadWorkplaces: () async throws -> [NovaNonconformityWorkplace]
    let file: (NovaAnalysisFileRequest) async -> NovaFindingOutcome
    let onFinished: () -> Void
    let record: (UUID, NovaFindingOutcome) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var workplaces: [NovaNonconformityWorkplace] = []
    @State private var workplace: UUID?
    @State private var kind: NovaNonconformityRecordKind = .nonconformity
    @State private var severity: [UUID: NovaNonconformitySeverity] = [:]
    @State private var outcomes: [UUID: NovaFindingOutcome] = [:]
    @State private var running = false
    @State private var finished = false
    @State private var error: String?

    /// An unscored item, or one whose band cannot be read, needs a severity
    /// from a person before it can be filed at all.
    private func needsSeverity(_ item: NovaAnalysisItem) -> Bool {
        !section.isScored || item.band == nil || item.isUnreadableBand
    }
    private func isReady(_ item: NovaAnalysisItem) -> Bool {
        !needsSeverity(item) || severity[item.id] != nil
    }
    private var ready: [NovaAnalysisItem] { items.filter(isReady) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.file.title", table: .localizable, fallback: "Firmaya aktar"), style: .sheetTitle)
                NovaHelpHint(text: RDLocalization.string("localizable.nova.analysis.file.hint", table: .localizable,
                    fallback: "Analiz kaydı olduğu gibi kalır. Seçtikleriniz için firmada ayrı kayıt açılır."))
                if !section.isScored { kindPicker }
                workplacePicker
                ForEach(items) { item in row(item) }
                if let error { NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                footer
            }.padding(20).novaPopupContentSize()
        }
        .task {
            do { workplaces = try await loadWorkplaces(); workplace = workplaces.first?.id }
            catch {
                self.error = RDLocalization.string("localizable.nova.nonconformity.error.workplaces", table: .localizable,
                    fallback: "İşyeri listesi alınamadı. Tekrar deneyin.")
            }
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: RDLocalization.string("localizable.nova.analysis.file.kind", table: .localizable, fallback: "Kayıt türü"), style: .label,
                color: NovaColorToken.textTertiary.color(in: scheme))
            Picker("", selection: $kind) {
                ForEach(NovaNonconformityRecordKind.allCases) { value in
                    Text(verbatim: NovaNonconformityWords.recordKind(value)).tag(value)
                }
            }.pickerStyle(.segmented).disabled(running)
                .accessibilityIdentifier("analysis.file.kind")
        }
    }

    @ViewBuilder private var workplacePicker: some View {
        if workplaces.isEmpty {
            NovaCard(padding: 14) {
                NovaText(text: RDLocalization.string("localizable.nova.bridge.no.workplace", table: .localizable,
                    fallback: "Bu firmada kayıt açılacak bir işyeri yok."), style: .metaQuiet)
            }
        } else {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.field.workplace", table: .localizable, fallback: "İşyeri"), style: .label,
                        color: NovaColorToken.textTertiary.color(in: scheme))
                    ForEach(workplaces) { place in
                        Button { workplace = place.id } label: {
                            HStack(spacing: 8) {
                                Image(systemName: workplace == place.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(workplace == place.id ? NovaColorToken.accentInk.color(in: scheme)
                                                                           : NovaColorToken.borderStrong.color(in: scheme))
                                NovaText(text: place.name)
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain).disabled(running)
                            .accessibilityIdentifier("analysis.file.workplace.\(place.id.uuidString.lowercased())")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ item: NovaAnalysisItem) -> some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                NovaText(text: item.title, style: .cardTitle)
                if needsSeverity(item) {
                    NovaText(text: section.isScored
                        ? RDLocalization.string("localizable.nova.bridge.band.unreadable", table: .localizable,
                            fallback: "Bu bulgunun risk bandı okunamadı. Önem derecesini siz seçin.")
                        : RDLocalization.string("localizable.nova.analysis.file.unscored", table: .localizable,
                            fallback: "Bu madde skorsuz geliyor. Önem derecesini siz seçin."), style: .metaQuiet)
                    Picker("", selection: Binding(get: { severity[item.id] ?? .medium },
                                                  set: { severity[item.id] = $0 })) {
                        ForEach(NovaNonconformitySeverity.allCases) { value in
                            Text(verbatim: NovaNonconformityWords.severity(value)).tag(value)
                        }
                    }.pickerStyle(.segmented).disabled(running)
                        .accessibilityIdentifier("analysis.file.severity.\(item.id.uuidString.lowercased())")
                } else if let band = item.band {
                    NovaStatusPill(label: NovaNonconformityWords.band(band), status: NovaNonconformityWords.tone(band))
                }
                if let outcome = outcomes[item.id] { outcomeLine(outcome) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func outcomeLine(_ outcome: NovaFindingOutcome) -> some View {
        switch outcome {
        case .untouched: EmptyView()
        case .opened:
            NovaText(text: RDLocalization.string("localizable.nova.bridge.outcome.opened", table: .localizable, fallback: "Uygunsuzluk açıldı"), style: .metaQuiet)
        case .alreadyOpen:
            NovaText(text: RDLocalization.string("localizable.nova.bridge.outcome.existing", table: .localizable, fallback: "Bu bulgunun uygunsuzluğu zaten vardı"), style: .metaQuiet)
        case .failed(let reason):
            NovaText(text: reason, style: .metaQuiet)
        }
    }

    @ViewBuilder private var footer: some View {
        if finished {
            VStack(alignment: .leading, spacing: 8) {
                // No blanket success line: each row above carries its own result.
                NovaText(text: RDLocalization.string("localizable.nova.bridge.finished", table: .localizable,
                    fallback: "İşlem bitti. Her bulgunun sonucu kendi satırında yazıyor."), style: .metaQuiet)
                NovaButton(label: RDLocalization.string("localizable.nova.bridge.done", table: .localizable, fallback: "Listeye dön"),
                    symbol: "list.bullet", variant: .surface) { onFinished() }
                    .accessibilityIdentifier("analysis.file.done")
            }
        } else {
            NovaButton(label: RDLocalization.string("localizable.nova.analysis.file.run", table: .localizable, fallback: "Seçilenleri aç"),
                symbol: "checkmark", isEnabled: !running && workplace != nil && !ready.isEmpty, isLoading: running) {
                Task { await run() }
            }.accessibilityIdentifier("analysis.file.run")
        }
    }

    private func run() async {
        guard let target = workplace else { return }
        running = true
        for item in ready {
            let outcome = await file(.init(item: item, section: section, workplaceID: target,
                recordKind: section.isScored ? .nonconformity : kind, severity: severity[item.id]))
            outcomes[item.id] = outcome
            record(item.id, outcome)
        }
        running = false
        finished = true
    }
}

/// PDF or Excel, under the expert's own method, filed against the company the
/// analysis belongs to.
struct NovaAnalysisReportSheet: View {
    let data: NovaAnalysisDetailData
    let generate: (NovaAnalysisReportRequest) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var format: NovaAnalysisReportFormat = .pdf
    @State private var method: NovaRiskMethod = .fineKinney
    @State private var attach = true
    @State private var running = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.report.title", table: .localizable, fallback: "Rapor oluştur"), style: .sheetTitle)
                NovaHelpHint(text: RDLocalization.string("localizable.nova.analysis.report.hint", table: .localizable,
                    fallback: "Rapor arşivinize kaydedilir. Firma seçiliyse Analiz Raporu olarak o firmaya işlenir."))
                NovaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("", selection: $format) {
                            Text(verbatim: "PDF").tag(NovaAnalysisReportFormat.pdf)
                            Text(verbatim: "Excel").tag(NovaAnalysisReportFormat.excel)
                        }.pickerStyle(.segmented).accessibilityIdentifier("analysis.report.format")
                        Picker("", selection: $method) {
                            ForEach(NovaRiskMethod.allCases) { value in
                                Text(verbatim: NovaNonconformityWords.method(value)).tag(value)
                            }
                        }.pickerStyle(.segmented).accessibilityIdentifier("analysis.report.method")
                        if let name = data.companyName {
                            Toggle(isOn: $attach) {
                                NovaText(text: String(format: RDLocalization.string("localizable.nova.analysis.report.attach", table: .localizable,
                                    fallback: "%@ firmasına işle"), name), style: .metaQuiet)
                            }.accessibilityIdentifier("analysis.report.attach")
                        } else {
                            NovaText(text: RDLocalization.string("localizable.nova.analysis.report.no.company", table: .localizable,
                                fallback: "Analiz bir firmaya bağlı değil; rapor yalnız arşivinize kaydedilir."), style: .metaQuiet)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error { NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.report.run", table: .localizable, fallback: "Oluştur"),
                    symbol: "doc.text", isEnabled: !running, isLoading: running) { Task { await run() } }
                    .accessibilityIdentifier("analysis.report.run")
            }.padding(20).novaPopupContentSize()
        }
        .onAppear { if !loaded { loaded = true; method = data.method } }
    }

    private func run() async {
        running = true; error = nil
        do {
            try await generate(.init(analysisID: data.analysisID, format: format, method: method,
                companyID: attach ? data.companyID : nil))
        } catch {
            // The server owns the report quota; its refusal is shown as it is.
            self.error = (error as? LocalizedError)?.errorDescription
                ?? RDLocalization.string("localizable.nova.analysis.report.failed", table: .localizable,
                    fallback: "Rapor oluşturulamadı. Aynı işlemi tekrar deneyin.")
        }
        running = false
    }
}

/// Picks the company an analysis is assigned to, later than the intake step.
struct NovaAnalysisCompanySheet: View {
    let load: () async throws -> [NovaAnalysisCompanyOption]
    let assign: (UUID) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var selected: UUID?
    @State private var running = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.assign.title", table: .localizable, fallback: "Firmaya ata"), style: .sheetTitle)
                if companies.isEmpty && error == nil {
                    NovaCard(padding: 14) {
                        NovaText(text: RDLocalization.string("localizable.nova.analysis.assign.empty", table: .localizable,
                            fallback: "Atanacak pilot firma bulunamadı."), style: .metaQuiet)
                    }
                }
                ForEach(companies) { company in
                    Button { selected = company.id } label: {
                        NovaCard(padding: 14, border: selected == company.id ? NovaColorToken.accentInk.color(in: scheme) : .clear) {
                            HStack(spacing: 8) {
                                Image(systemName: selected == company.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected == company.id ? NovaColorToken.accentInk.color(in: scheme)
                                                                            : NovaColorToken.borderStrong.color(in: scheme))
                                VStack(alignment: .leading, spacing: 2) {
                                    NovaText(text: company.name, style: .cardTitle)
                                    if !company.detail.isEmpty { NovaText(text: company.detail, style: .metaQuiet) }
                                }
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }.buttonStyle(.plain).disabled(running)
                        .accessibilityIdentifier("analysis.assign.\(company.id.uuidString.lowercased())")
                }
                if let error { NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.assign.run", table: .localizable, fallback: "Ata"),
                    symbol: "checkmark", isEnabled: !running && selected != nil, isLoading: running) { Task { await run() } }
                    .accessibilityIdentifier("analysis.assign.run")
            }.padding(20).novaPopupContentSize()
        }
        .task {
            do { companies = try await load() }
            catch {
                self.error = RDLocalization.string("localizable.nova.analysis.assign.failed.load", table: .localizable,
                    fallback: "Firma listesi alınamadı. Tekrar deneyin.")
            }
        }
    }

    private func run() async {
        guard let company = selected else { return }
        running = true; error = nil
        do { try await assign(company) }
        catch {
            self.error = RDLocalization.string("localizable.nova.analysis.assign.failed", table: .localizable,
                fallback: "Analiz firmaya bağlanamadı. Tekrar deneyin.")
        }
        running = false
    }
}
