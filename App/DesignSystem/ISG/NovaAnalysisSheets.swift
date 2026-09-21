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

/// One item, in full: the picture it was read from, what it scored, and every
/// field behind the two lines the list showed.
struct NovaAnalysisItemSheet: View {
    let item: NovaAnalysisItem
    let section: NovaAnalysisSectionKind
    let method: NovaRiskMethod
    var photo: UIImage?
    var analysisTitle = ""
    var companyName: String?
    var createdOn = ""
    let reaction: NovaAnalysisReaction
    var canWrite = true
    var canEdit = true
    var canReact = true
    var canFile = true
    let react: (NovaAnalysisReaction) async throws -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onFile: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    @State private var chosen: NovaAnalysisReaction = .none
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false

    /// Only the scored findings are real analysis findings; the judgement
    /// sections have no editable record behind them.
    private var isEditable: Bool { canWrite && canEdit && section.isScored }
    private var band: String? { item.band(method) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                hero
                if isEditable { controls }
                if canWrite, canFile, section.isFileable, let onFile {
                    NovaButton(label: "Firmaya Uygunsuzluk Olarak Ekle", symbol: "building.2", variant: .surface, action: onFile)
                        .accessibilityIdentifier("analysis.finding.file")
                }
                scoreCard
                fields
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
            }.padding(16).novaPopupContentSize()
        }
        .onAppear { if !loaded { loaded = true; chosen = reaction } }
    }

    // MARK: hero

    private var hero: some View {
        // The picture is clamped and clipped first, so the caption below is
        // laid out against the visible frame rather than the image's own size.
        picture
            .frame(maxWidth: .infinity).frame(height: 200).clipped()
            .overlay(LinearGradient(colors: [.clear, NovaColorToken.inverse.color(in: scheme).opacity(0.88)],
                                    startPoint: .center, endPoint: .bottom))
            .overlay(alignment: .bottomLeading) { caption }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .topTrailing) {
                if canWrite && canReact { feedback.padding(9) }
            }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if let band {
                        NovaStatusPill(label: NovaNonconformityWords.band(band), status: NovaNonconformityWords.tone(band), showsDot: false)
                    } else {
                        NovaStatusPill(label: RDLocalization.string("localizable.nova.analysis.item.unscored", table: .localizable, fallback: "Skorsuz"),
                            status: .info, showsDot: false)
                    }
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.analysis.item.ordinal", table: .localizable,
                        fallback: "Kayıt #%d"), item.ordinal), style: .micro,
                        color: NovaColorToken.onInverse.color(in: scheme).opacity(0.8))
                    Spacer(minLength: 0)
                    if let value = item.value(method) {
                        NovaText(text: NovaNonconformityWords.score(value), style: .sheetTitle,
                            color: NovaColorToken.onInverse.color(in: scheme))
                    }
                }
                NovaText(text: item.title, style: .cardTitle, color: NovaColorToken.onInverse.color(in: scheme)).lineLimit(3)
                NovaText(text: subtitle, style: .micro, color: NovaColorToken.onInverse.color(in: scheme).opacity(0.72)).lineLimit(1)
        }.padding(12)
    }

    private var subtitle: String {
        [companyName, analysisTitle.isEmpty ? nil : analysisTitle, createdOn.isEmpty ? nil : createdOn]
            .compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private var picture: some View {
        if let photo {
            Image(uiImage: photo).resizable().scaledToFill()
        } else {
            NovaColorToken.surfaceMuted.color(in: scheme)
                .overlay(NovaIcon(symbol: "photo", size: 30)
                    .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme)))
        }
    }

    /// Two answers and a way back out of both: pressing the same one again
    /// withdraws it rather than leaving an opinion the expert changed.
    private var feedback: some View {
        HStack(spacing: 6) {
            reactionButton(.like, "hand.thumbsup",
                RDLocalization.string("localizable.nova.analysis.item.like", table: .localizable, fallback: "Faydalı"))
            reactionButton(.dislike, "hand.thumbsdown",
                RDLocalization.string("localizable.nova.analysis.item.dislike", table: .localizable, fallback: "Faydasız"))
        }
    }

    private func reactionButton(_ value: NovaAnalysisReaction, _ symbol: String, _ label: String) -> some View {
        let isOn = chosen == value
        return Button {
            let next: NovaAnalysisReaction = isOn ? .none : value
            Task {
                busy = true; error = nil
                do { try await react(next); chosen = next }
                catch {
                    self.error = RDLocalization.string("localizable.nova.analysis.item.reaction.failed", table: .localizable,
                        fallback: "Geri bildirim kaydedilemedi. Tekrar deneyin.")
                }
                busy = false
            }
        } label: {
            Image(systemName: isOn ? "\(symbol).fill" : symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.text.color(in: scheme))
                .frame(width: 38, height: 38)
        }.buttonStyle(NovaRowPressStyle()).disabled(busy)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityIdentifier("analysis.item.\(value.rawValue)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var controls: some View {
        HStack(spacing: 8) {
            control("square.and.pencil", RDLocalization.string("localizable.nova.analysis.edit", table: .localizable, fallback: "Bulguyu düzenle"),
                    id: "edit", status: .neutral, action: onEdit)
            control("trash", RDLocalization.string("localizable.nova.analysis.item.delete", table: .localizable, fallback: "Bulguyu sil"),
                    id: "delete", status: .danger, action: onDelete)
        }
    }

    private func control(_ symbol: String, _ label: String, id: String, status: NovaStatus, action: @escaping () -> Void) -> some View {
        let palette = status.tokens
        return Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                NovaText(text: label, style: .meta, color: palette.ink.color(in: scheme))
            }
            .foregroundStyle(palette.ink.color(in: scheme))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(palette.background.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("analysis.item.\(id)")
    }

    // MARK: score

    @ViewBuilder private var scoreCard: some View {
        if let score = item.score(method), let value = score.value {
            let palette = NovaNonconformityWords.tone(score.band).tokens
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    NovaText(text: NovaNonconformityWords.score(value), style: .screenTitle,
                        color: palette.ink.color(in: scheme))
                    NovaText(text: RDLocalization.string("localizable.nova.risk.score.unit", table: .localizable, fallback: "PUAN"),
                        style: .micro, color: palette.ink.color(in: scheme).opacity(0.8))
                    Spacer(minLength: 0)
                    NovaText(text: NovaNonconformityWords.method(method), style: .meta,
                        color: palette.ink.color(in: scheme))
                }
                if !score.factors.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(Array(score.factors.enumerated()), id: \.element.id) { at, factor in
                            if at > 0 {
                                NovaText(text: "×", style: .meta, color: palette.ink.color(in: scheme).opacity(0.6))
                            }
                            NovaText(text: "\(factor.label) \(NovaNonconformityWords.score(factor.value))", style: .badge,
                                color: palette.ink.color(in: scheme))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(NovaColorToken.surface.color(in: scheme).opacity(0.7), in: Capsule())
                        }
                        NovaText(text: "=", style: .meta, color: palette.ink.color(in: scheme).opacity(0.6))
                        NovaText(text: NovaNonconformityWords.score(value), style: .badge,
                            color: palette.ink.color(in: scheme))
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(palette.background.color(in: scheme), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: fields

    @ViewBuilder private var fields: some View {
        panel(RDLocalization.string("localizable.nova.analysis.field.body", table: .localizable, fallback: "Açıklama"),
              "text.alignleft", item.body, status: NovaNonconformityWords.tone(band))
        if let audience = item.audience {
            panel(RDLocalization.string("localizable.nova.analysis.field.audience", table: .localizable, fallback: "Kimler için"),
                  "person.2", audience, status: .info)
        }
        panel(RDLocalization.string("localizable.nova.analysis.field.root.cause", table: .localizable, fallback: "Kök neden"),
              "magnifyingglass", item.rootCause, status: .warning)
        measuresPanel
        panel(RDLocalization.string("localizable.nova.analysis.field.references", table: .localizable, fallback: "Mevzuat"),
              "book", item.references, status: .info)
        if let value = item.durationValue, let label = item.durationLabel {
            panel(label, "clock", [value, item.durationNote].compactMap { $0 }.joined(separator: "\n"), status: .neutral)
        }
    }

    /// The measures the item carries, each under its own name. When it carries
    /// none, the single recommended action stands in for them.
    @ViewBuilder private var measuresPanel: some View {
        if item.measures.isEmpty {
            panel(RDLocalization.string("localizable.nova.analysis.field.measure.corrective", table: .localizable, fallback: "Düzeltici önlem"),
                  "checkmark.seal", item.measure, status: .success)
        } else {
            ForEach(item.measures) { measure in
                panel(measure.title, measure.isPreventive ? "shield" : "checkmark.seal", measure.text,
                      status: measure.isPreventive ? .info : .success)
            }
        }
    }

    @ViewBuilder private func panel(_ label: String, _ symbol: String, _ value: String?, status: NovaStatus) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let palette = status.tokens
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.ink.color(in: scheme))
                    NovaText(text: label.uppercased(), style: .overline, color: palette.ink.color(in: scheme))
                }
                NovaText(text: value, style: .body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .novaControlBackground(cornerRadius: 16)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(palette.ink.color(in: scheme).opacity(0.55))
                    .frame(width: 3).padding(.vertical, 12).padding(.leading, 1)
            }
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
        }
    }
}

/// A finding opened from the nonconformity board. It deliberately reuses the
/// analysis item sheet; the only filing-specific change is that an item already
/// attached to a company has no "add to company" action.
struct NovaFiledFindingSheet: View {
    let entry: NovaNonconformityEntry
    let identity: NovaSessionIdentity
    let preferredMethod: RiskMethod
    let fallbackClient: NovaNonconformityRecordClient
    var canWrite = true
    @State private var source: NovaAnalysisWorkspace.RecordFindingPresentation?
    @State private var failed = false
    @State private var mode: Mode = .read
    @State private var reload = UUID()

    private enum Mode { case read, edit, delete }

    var body: some View {
        Group {
            if let source {
                switch mode {
                case .read:
                    NovaAnalysisItemSheet(item: source.item, section: source.section, method: source.method,
                        photo: source.photo, analysisTitle: source.analysisTitle,
                        companyName: source.companyName, createdOn: source.createdOn,
                        reaction: source.item.reaction, canWrite: canWrite,
                        react: { value in
                            try await NovaAnalysisWorkspace.react(analysisID: source.analysisID,
                                itemID: source.item.id, section: source.section, reaction: value)
                        },
                        onEdit: { mode = .edit }, onDelete: { mode = .delete }, onFile: nil)
                case .edit:
                    NovaAnalysisEditSheet(item: source.item, method: source.method) { values in
                        try await NovaAnalysisWorkspace.edit(.init(analysisID: source.analysisID,
                            findingID: source.item.id, title: values.title, category: values.category,
                            body: values.body, measure: values.measure, references: values.references,
                            score: values.score))
                        mode = .read
                        reload = UUID()
                    }
                case .delete:
                    NovaAnalysisDeleteSheet(item: source.item) {
                        try await NovaAnalysisWorkspace.remove(analysisID: source.analysisID,
                                                               findingID: source.item.id)
                        self.source = nil
                        failed = true
                        mode = .read
                    }
                }
            } else if failed {
                NovaNonconformityRecordSheet(entry: entry, client: fallbackClient, canWrite: canWrite)
            } else {
                NovaLoadingView(message: RDLocalization.string("localizable.nova.analysis.loading", table: .localizable,
                    fallback: "Bulgu yükleniyor…"))
                    .padding(20).novaPopupContentSize()
            }
        }
        .task(id: reload) { await load() }
    }

    private func load() async {
        failed = false
        do {
            source = try await NovaAnalysisWorkspace.recordFinding(entry, identity: identity,
                                                                    preferredMethod: preferredMethod)
        } catch is CancellationError { }
        catch { failed = true }
    }
}

/// Editing one scored finding. It is its own popup so the reading view above
/// never turns into a form the expert did not ask for.
struct NovaAnalysisEditSheet: View {
    let item: NovaAnalysisItem
    let method: NovaRiskMethod
    let save: (NovaFindingEditValues) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category = ""
    @State private var body_ = ""
    @State private var measure = ""
    @State private var references = ""
    @State private var score = NovaRiskScoreInput()
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.edit", table: .localizable, fallback: "Bulguyu düzenle"), style: .sheetTitle)
                NovaCard(padding: 13) {
                    VStack(alignment: .leading, spacing: 9) {
                        field(RDLocalization.string("localizable.nova.analysis.field.title", table: .localizable, fallback: "Başlık"), $title, id: "title")
                        field(RDLocalization.string("localizable.nova.analysis.field.category", table: .localizable, fallback: "Kategori"), $category, id: "category")
                        area(RDLocalization.string("localizable.nova.analysis.field.body", table: .localizable, fallback: "Açıklama"), $body_, id: "body")
                        area(RDLocalization.string("localizable.nova.analysis.field.measure", table: .localizable, fallback: "Önlem"), $measure, id: "measure")
                        area(RDLocalization.string("localizable.nova.analysis.field.references", table: .localizable, fallback: "Mevzuat"), $references, id: "references")
                    }
                }
                NovaRiskScoreEditor(score: $score, allowsClearing: false)
                NovaText(text: RDLocalization.string("localizable.nova.analysis.edit.hint", table: .localizable,
                    fallback: "Değişiklikleriniz bulguya işlenir; skoru yeniden girerseniz bandı sunucu hesaplar."), style: .metaQuiet)
                if let error { NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.edit.save", table: .localizable, fallback: "Değişiklikleri kaydet"),
                    symbol: "checkmark", isEnabled: !busy && !title.trimmingCharacters(in: .whitespaces).isEmpty,
                    isLoading: busy) { Task { await submit() } }
                    .accessibilityIdentifier("analysis.item.save")
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.item.cancel", table: .localizable, fallback: "Vazgeç"),
                    symbol: "xmark", variant: .surface, isEnabled: !busy) { dismiss() }
                    .accessibilityIdentifier("analysis.item.cancel")
            }.padding(16).novaPopupContentSize()
        }
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
            TextField(label, text: text).font(NovaFont.font(.body))
                .frame(minHeight: 36).accessibilityIdentifier("analysis.edit.\(id)")
        }
    }
    private func area(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextEditor(text: text).font(NovaFont.font(.body))
                .frame(minHeight: 70).scrollContentBackground(.hidden)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("analysis.edit.\(id)")
        }
    }

    private func submit() async {
        busy = true; error = nil
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
        busy = false
    }
}

/// Deleting one finding is its own step, and it says what will be lost before
/// it asks for the press that does it.
struct NovaAnalysisDeleteSheet: View {
    let item: NovaAnalysisItem
    let remove: () async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.item.delete", table: .localizable, fallback: "Bulguyu sil"), style: .sheetTitle)
                NovaCard(padding: 13, tint: NovaColorToken.statusDangerBg.color(in: scheme)) {
                    VStack(alignment: .leading, spacing: 6) {
                        NovaText(text: item.title, style: .cardTitle, color: NovaColorToken.statusDangerInk.color(in: scheme))
                        NovaText(text: RDLocalization.string("localizable.nova.analysis.item.delete.confirm", table: .localizable,
                            fallback: "Bu bulgu analizden kalıcı olarak silinecek."), style: .metaQuiet,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error { NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.item.delete.yes", table: .localizable, fallback: "Evet, sil"),
                    symbol: "trash", variant: .danger, isEnabled: !busy, isLoading: busy) { Task { await drop() } }
                    .accessibilityIdentifier("analysis.item.delete.confirm")
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.item.cancel", table: .localizable, fallback: "Vazgeç"),
                    symbol: "xmark", variant: .surface, isEnabled: !busy) { dismiss() }
            }.padding(16).novaPopupContentSize()
        }
    }

    private func drop() async {
        busy = true; error = nil
        do { try await remove() }
        catch {
            self.error = RDLocalization.string("localizable.nova.analysis.item.delete.failed", table: .localizable,
                fallback: "Bulgu silinemedi. Aynı işlemi tekrar deneyin.")
        }
        busy = false
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
                        }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("risk.method.none")
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
                .animation(NovaMotion.easeOut(0.14), value: isSelected)
        }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("risk.method.\(value.rawValue)")
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
                .animation(NovaMotion.easeOut(0.14), value: isSelected)
        }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier(identifier)
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
    /// The method the expert is reading the analysis with. The band that
    /// travels with a scored item is that method's band, never the other's.
    let method: NovaRiskMethod
    var targetCompany: UUID? = nil
    let loadWorkplaces: () async throws -> [NovaNonconformityWorkplace]
    let file: (NovaAnalysisFileRequest) async -> NovaFindingOutcome
    let onFinished: () -> Void
    let record: (UUID, NovaFindingOutcome) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.novaCelebrate) private var celebrate
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
        !section.isScored || item.band(method) == nil || item.isUnreadableBand(method)
    }
    private func isReady(_ item: NovaAnalysisItem) -> Bool {
        !needsSeverity(item) || severity[item.id] != nil
    }
    private var ready: [NovaAnalysisItem] { items.filter(isReady) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.file.title", table: .localizable, fallback: "Firmaya aktar"), style: .sheetTitle)
                NovaHelpHint(text: RDLocalization.string("localizable.nova.analysis.file.hint", table: .localizable,
                    fallback: "Analiz kaydı olduğu gibi kalır. Seçtikleriniz için firmada ayrı kayıt açılır."))
                if !section.isScored { kindPicker }
                workplacePicker
                ForEach(items) { item in row(item) }
                if let error { NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                footer
            }.padding(16).novaPopupContentSize()
        }
        .preference(key: NovaPopupBusyKey.self, value: running)
        .task {
            do {
                let loaded = try await loadWorkplaces()
                workplaces = loaded
                workplace = loaded.count == 1 ? loaded.first?.id : nil
                // "Firmaya Aktar" plus one company and one workplace is a
                // complete instruction. Do not make the user discover and tap
                // a second confirmation for an already-scored finding.
                if let only = loaded.first, loaded.count == 1,
                   !items.isEmpty, ready.count == items.count {
                    await run(target: only.id)
                }
            }
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
        } else if workplaces.count == 1 {
            // One workplace is not a choice; it is already selected.
            EmptyView()
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
                        }.buttonStyle(NovaRowPressStyle()).disabled(running)
                            .accessibilityIdentifier("analysis.file.workplace.\(place.id.uuidString.lowercased())")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ item: NovaAnalysisItem) -> some View {
        NovaCard(padding: 13) {
            VStack(alignment: .leading, spacing: 8) {
                NovaText(text: item.title, style: .cardTitle)
                if needsSeverity(item) {
                    NovaText(text: section.isScored
                        ? RDLocalization.string("localizable.nova.bridge.band.unreadable", table: .localizable,
                            fallback: "Bu bulgunun risk bandı okunamadı. Önem derecesini siz seçin.")
                        : RDLocalization.string("localizable.nova.analysis.file.unscored", table: .localizable,
                            fallback: "Bu madde skorsuz geliyor. Önem derecesini siz seçin."), style: .metaQuiet)
                    Picker(RDLocalization.string("localizable.nova.nonconformity.field.severity", table: .localizable,
                        fallback: "Önem derecesi"), selection: Binding<NovaNonconformitySeverity?>(
                        get: { severity[item.id] }, set: { severity[item.id] = $0 })) {
                        Text(RDLocalization.string("localizable.nova.analysis.severity.pick", table: .localizable,
                            fallback: "Önem derecesi seçin")).tag(NovaNonconformitySeverity?.none)
                        ForEach(NovaNonconformitySeverity.allCases) { value in
                            Text(verbatim: NovaNonconformityWords.severity(value)).tag(Optional(value))
                        }
                    }.pickerStyle(.menu).disabled(running)
                        .accessibilityIdentifier("analysis.file.severity.\(item.id.uuidString.lowercased())")
                } else if let band = item.band(method) {
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

    private func run(target explicitTarget: UUID? = nil) async {
        guard !running, let target = explicitTarget ?? workplace else { return }
        running = true
        var failed = false
        var succeeded = false
        for item in ready {
            let outcome = await file(.init(companyID: targetCompany, item: item, section: section, workplaceID: target,
                recordKind: section.isScored ? .nonconformity : kind,
                band: section.isScored ? item.band(method) : nil,
                severity: severity[item.id], sourceMethod: section.isScored ? method : nil))
            outcomes[item.id] = outcome
            record(item.id, outcome)
            switch outcome {
            case .opened, .alreadyOpen: succeeded = true
            case .failed: failed = true
            case .untouched: break
            }
        }
        running = false
        if succeeded && !failed {
            celebrate(NovaSuccessMessage.findingCreated)
            onFinished()
        } else {
            finished = true
        }
    }
}

/// PDF or Excel, under the expert's own method, filed against the company the
/// analysis belongs to.
struct NovaAnalysisReportSheet: View {
    let data: NovaAnalysisDetailData
    /// The method the detail screen is being read with; the report opens on it.
    var method: NovaRiskMethod = .fineKinney
    var selectedCount = 0
    let generate: (NovaAnalysisReportRequest) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var format: NovaAnalysisReportFormat?
    @State private var chosenMethod: NovaRiskMethod = .fineKinney
    @State private var attach = true
    @State private var running = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                heading
                option(.pdf, symbol: "doc.text",
                       title: RDLocalization.string("localizable.nova.analysis.report.pdf", table: .localizable, fallback: "Standart Rapor"),
                       detail: RDLocalization.string("localizable.nova.analysis.report.pdf.detail", table: .localizable,
                           fallback: "Analizin tüm bölümlerini içeren PDF dökümü."))
                option(.excel, symbol: "tablecells",
                       title: RDLocalization.string("localizable.nova.analysis.report.excel", table: .localizable, fallback: "Risk Analizi Tablosu"),
                       detail: RDLocalization.string("localizable.nova.analysis.report.excel.detail", table: .localizable,
                           fallback: "Bulguları seçtiğiniz metotla hesaplayan Excel tablosu."))
                methodRow
                companyRow
                if let error { NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                NovaButton(label: format == nil
                    ? RDLocalization.string("localizable.nova.analysis.report.pick", table: .localizable, fallback: "Rapor türü seçin")
                    : RDLocalization.string("localizable.nova.analysis.report.run", table: .localizable, fallback: "Oluştur"),
                    symbol: "arrow.down.doc", isEnabled: !running && format != nil, isLoading: running) { Task { await run() } }
                    .accessibilityIdentifier("analysis.report.run")
            }.padding(16).novaPopupContentSize()
        }
        .onAppear { if !loaded { loaded = true; chosenMethod = method } }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 10) {
            NovaIcon(symbol: "doc.text", size: 20)
                .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.report.title", table: .localizable, fallback: "Rapor oluştur"), style: .sheetTitle)
                NovaText(text: RDLocalization.string("localizable.nova.analysis.report.hint", table: .localizable,
                    fallback: "Rapor arşivinize kaydedilir. Firma seçiliyse Analiz Raporu olarak o firmaya işlenir."),
                    style: .metaQuiet)
                if selectedCount > 0 {
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.analysis.report.selected", table: .localizable,
                        fallback: "%d kayıt seçili"), selectedCount), style: .micro,
                        color: NovaColorToken.textTertiary.color(in: scheme))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func option(_ value: NovaAnalysisReportFormat, symbol: String, title: String, detail: String) -> some View {
        let isOn = format == value
        return Button { format = value } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    NovaText(text: title, style: .cardTitle)
                    NovaText(text: detail, style: .metaQuiet)
                }
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle").font(.system(size: 19))
                    .foregroundStyle(isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.borderStrong.color(in: scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .novaControlBackground(cornerRadius: 18)
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.border.color(in: scheme),
                              lineWidth: isOn ? 1.5 : 1))
        }.buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier("analysis.report.format.\(value.rawValue)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var methodRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            NovaText(text: RDLocalization.string("localizable.nova.risk.method", table: .localizable, fallback: "Risk metodu"), style: .label,
                color: NovaColorToken.textTertiary.color(in: scheme))
            NovaAnalysisMethodToggle(method: $chosenMethod)
        }
    }

    @ViewBuilder private var companyRow: some View {
        if let name = data.companyName {
            NovaCard(padding: 12) {
                Toggle(isOn: $attach) {
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.analysis.report.attach", table: .localizable,
                        fallback: "%@ firmasına işle"), name), style: .meta)
                }.accessibilityIdentifier("analysis.report.attach")
            }
        } else {
            NovaCard(padding: 12) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.report.no.company", table: .localizable,
                    fallback: "Analiz bir firmaya bağlı değil; rapor yalnız arşivinize kaydedilir."), style: .metaQuiet)
            }
        }
    }

    private func run() async {
        guard let format else { return }
        running = true; error = nil
        do {
            try await generate(.init(analysisID: data.analysisID, format: format, method: chosenMethod,
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
            VStack(alignment: .leading, spacing: 11) {
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
                    }.buttonStyle(NovaRowPressStyle()).disabled(running)
                        .accessibilityIdentifier("analysis.assign.\(company.id.uuidString.lowercased())")
                }
                if let error { NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                NovaButton(label: RDLocalization.string("localizable.nova.analysis.assign.run", table: .localizable, fallback: "Ata"),
                    symbol: "checkmark", isEnabled: !running && selected != nil, isLoading: running) { Task { await run() } }
                    .accessibilityIdentifier("analysis.assign.run")
            }.padding(16).novaPopupContentSize()
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
