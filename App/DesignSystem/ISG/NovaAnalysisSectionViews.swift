import SwiftUI

/// The one restrained tone each analysis section is allowed. A section is told
/// apart by its icon and this single accent, never by a palette of its own.
struct NovaAnalysisSectionTone {
    let status: NovaStatus
    let symbol: String

    static func of(_ kind: NovaAnalysisSectionKind) -> NovaAnalysisSectionTone {
        switch kind {
        case .riskAnalysis: return .init(status: .danger, symbol: "exclamationmark.triangle")
        case .expertRecommendations: return .init(status: .warning, symbol: "person.crop.rectangle")
        // Not the shared asset alias: that one draws an award badge, which is
        // not what a training recommendation means.
        case .trainingRecommendations: return .init(status: .info, symbol: "graduationcap.fill")
        case .approvedNotebook: return .init(status: .neutral, symbol: "doc.text")
        }
    }
}

/// Words that belong to the analysis sections, in one place so a section is
/// never named one thing on the tab and another on its own header.
enum NovaAnalysisWords {
    static func sectionTitle(_ kind: NovaAnalysisSectionKind) -> String {
        switch kind {
        case .riskAnalysis:
            return RDLocalization.string("localizable.nova.analysis.section.risk", table: .localizable, fallback: "Risk Analizi")
        case .expertRecommendations:
            return RDLocalization.string("localizable.nova.analysis.section.expert", table: .localizable, fallback: "Uzman Görüşü")
        case .trainingRecommendations:
            return RDLocalization.string("localizable.nova.analysis.section.training", table: .localizable, fallback: "Eğitim Önerileri")
        case .approvedNotebook:
            return RDLocalization.string("localizable.nova.analysis.section.notebook", table: .localizable, fallback: "Onaylı Defter")
        }
    }

    /// The short word for one row of a section, used on the tab and in counts.
    static func unit(_ kind: NovaAnalysisSectionKind, _ count: Int) -> String {
        switch kind {
        case .riskAnalysis:
            return String(format: RDLocalization.string("localizable.nova.analysis.unit.finding", table: .localizable, fallback: "%d Bulgu"), count)
        case .expertRecommendations:
            return String(format: RDLocalization.string("localizable.nova.analysis.unit.opinion", table: .localizable, fallback: "%d Görüş"), count)
        case .trainingRecommendations:
            return String(format: RDLocalization.string("localizable.nova.analysis.unit.advice", table: .localizable, fallback: "%d Öneri"), count)
        case .approvedNotebook:
            return String(format: RDLocalization.string("localizable.nova.analysis.unit.entry", table: .localizable, fallback: "%d Kayıt"), count)
        }
    }

    static func sectionPurpose(_ kind: NovaAnalysisSectionKind) -> String {
        switch kind {
        case .riskAnalysis:
            return RDLocalization.string("localizable.nova.analysis.purpose.risk", table: .localizable,
                fallback: "Fotoğrafta görülen tehlikeler, seçtiğiniz metotla skorlanmış olarak listelenir. Seçtiklerinizi firmaya uygunsuzluk olarak aktarabilirsiniz.")
        case .expertRecommendations:
            return RDLocalization.string("localizable.nova.analysis.purpose.expert", table: .localizable,
                fallback: "Uzmanlık gerektiren, skorsuz gelen değerlendirmelerdir. İşyerinize uygunluğunu siz kontrol edersiniz.")
        case .trainingRecommendations:
            return RDLocalization.string("localizable.nova.analysis.purpose.training", table: .localizable,
                fallback: "Görülen tehlike ve ekipmanlara göre hangi eğitimlerin anlamlı olduğunu gösterir. Kişilerin mevcut belgeleri hakkında bir tespit içermez.")
        case .approvedNotebook:
            return RDLocalization.string("localizable.nova.analysis.purpose.notebook", table: .localizable,
                fallback: "Analiz bulgularından üretilen, uzman değerlendirmesine sunulan defter taslaklarıdır.")
        }
    }
}

/// The card that opens every section: what the section is and how many rows it
/// has, in the section's own single tone.
struct NovaAnalysisSectionHeader: View {
    let kind: NovaAnalysisSectionKind
    let count: Int
    var isTeaser = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tone = NovaAnalysisSectionTone.of(kind)
        let palette = tone.status.tokens
        NovaCard(padding: 13, tint: palette.background.color(in: scheme)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    NovaIcon(symbol: tone.symbol, size: 18)
                        .foregroundStyle(palette.ink.color(in: scheme))
                        .frame(width: 38, height: 38)
                        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        NovaText(text: NovaAnalysisWords.sectionTitle(kind), style: .cardTitle,
                            color: palette.ink.color(in: scheme))
                        NovaText(text: NovaAnalysisWords.unit(kind, count), style: .micro,
                            color: palette.ink.color(in: scheme))
                    }
                    Spacer(minLength: 0)
                    NovaText(text: "\(count)", style: .screenTitle, color: palette.ink.color(in: scheme))
                }
                NovaText(text: NovaAnalysisWords.sectionPurpose(kind), style: .metaQuiet,
                    color: NovaColorToken.textSecondary.color(in: scheme))
                if isTeaser {
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.teaser", table: .localizable,
                        fallback: "Bu bölümün tamamı planınıza dahil değil; yalnız bir özeti gösteriliyor."),
                        style: .metaQuiet, color: palette.ink.color(in: scheme))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// What the scored section adds up to under the method the expert is reading
/// it with. Every number here is counted from the rows on screen.
struct NovaAnalysisStatsCard: View {
    let section: NovaAnalysisSection
    let method: NovaRiskMethod
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let top = section.highest(method)
        NovaCard(padding: 12) {
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    figure(RDLocalization.string("localizable.nova.analysis.stat.findings", table: .localizable, fallback: "Toplam bulgu"),
                           "\(section.items.count)", caption: nil)
                    figure(RDLocalization.string("localizable.nova.analysis.stat.highest", table: .localizable, fallback: "En yüksek skor"),
                           top?.value(method).map(NovaNonconformityWords.score) ?? "—",
                           caption: top?.band(method).map(NovaNonconformityWords.band))
                }
                distribution
            }
        }
    }

    private func figure(_ label: String, _ value: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .micro, color: NovaColorToken.onInverse.color(in: scheme).opacity(0.66))
            NovaText(text: value, style: .sheetTitle, color: NovaColorToken.onInverse.color(in: scheme))
            if let caption {
                NovaText(text: caption, style: .badge, color: NovaColorToken.onInverse.color(in: scheme).opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(NovaColorToken.inverse.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
    }

    private var distribution: some View {
        HStack(spacing: 6) {
            ForEach(section.distribution(method), id: \.band) { entry in
                let palette = NovaNonconformityWords.tone(entry.band).tokens
                VStack(spacing: 2) {
                    NovaText(text: "\(entry.count)", style: .cardTitle, color: palette.ink.color(in: scheme))
                    NovaText(text: NovaNonconformityWords.band(entry.band), style: .micro,
                        color: NovaColorToken.textTertiary.color(in: scheme))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(palette.background.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The two published methods, side by side. Choosing one changes which score
/// the screen reads; it never changes what is stored.
struct NovaAnalysisMethodToggle: View {
    @Binding var method: NovaRiskMethod
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NovaRiskMethod.allCases) { value in cell(value) }
        }
    }

    private func cell(_ value: NovaRiskMethod) -> some View {
        let isOn = method == value
        return Button { method = value } label: {
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    if isOn {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    }
                    NovaText(text: NovaNonconformityWords.method(value), style: .cardTitle,
                        color: isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                }
                NovaText(text: formula(value), style: .micro,
                    color: isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textTertiary.color(in: scheme))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(isOn ? NovaColorToken.statusSuccessBg.color(in: scheme) : NovaColorToken.surface.color(in: scheme),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.border.color(in: scheme),
                              lineWidth: isOn ? 1.4 : 1))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("analysis.detail.method.\(value.rawValue)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The formula as the two methods publish it, so the toggle says what the
    /// score is made of rather than only naming the method.
    private func formula(_ value: NovaRiskMethod) -> String {
        switch value {
        case .fineKinney:
            return RDLocalization.string("localizable.nova.risk.formula.fine.kinney", table: .localizable, fallback: "R = O × F × Ş")
        case .matrix5x5:
            return RDLocalization.string("localizable.nova.risk.formula.matrix", table: .localizable, fallback: "R = O × Ş")
        }
    }
}

/// A small icon-and-text tag. Used for the fields a card carries but does not
/// spell out, so the row stays short.
struct NovaAnalysisTag: View {
    let symbol: String
    let text: String
    var status: NovaStatus = .neutral
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = status.tokens
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            NovaText(text: text, style: .micro, color: palette.ink.color(in: scheme))
        }
        .foregroundStyle(palette.ink.color(in: scheme))
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(palette.background.color(in: scheme), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }
}

/// The row of controls under an item. Editing and deleting are offered only
/// where a real record exists behind the row.
struct NovaAnalysisItemBar: View {
    let canEdit: Bool
    let reaction: NovaAnalysisReaction
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReact: (NovaAnalysisReaction) -> Void
    let onOpen: () -> Void
    var identifier: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            if canEdit {
                icon("pencil", RDLocalization.string("localizable.nova.analysis.edit", table: .localizable, fallback: "Bulguyu düzenle"),
                     id: "edit", isOn: false, action: onEdit)
                icon("trash", RDLocalization.string("localizable.nova.analysis.item.delete", table: .localizable, fallback: "Bulguyu sil"),
                     id: "delete", isOn: false, action: onDelete)
            }
            icon("hand.thumbsup", RDLocalization.string("localizable.nova.analysis.item.like", table: .localizable, fallback: "Faydalı"),
                 id: "like", isOn: reaction == .like) { onReact(reaction == .like ? .none : .like) }
            icon("hand.thumbsdown", RDLocalization.string("localizable.nova.analysis.item.dislike", table: .localizable, fallback: "Faydasız"),
                 id: "dislike", isOn: reaction == .dislike) { onReact(reaction == .dislike ? .none : .dislike) }
            Spacer(minLength: 0)
            Button(action: onOpen) {
                HStack(spacing: 4) {
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.item.more", table: .localizable, fallback: "Devamını incele"),
                        style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                }.frame(minHeight: 40).padding(.horizontal, 6)
            }.buttonStyle(.plain).accessibilityIdentifier("\(identifier).more")
        }
        .padding(.horizontal, 7)
        .background(NovaColorToken.surfaceMuted.color(in: scheme))
    }

    private func icon(_ symbol: String, _ label: String, id: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOn ? "\(symbol).fill" : symbol).font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOn ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                .frame(width: 40, height: 40)
        }.buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityIdentifier("\(identifier).\(id)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One scored finding, as its own card: what it is, how bad it is, the measure
/// that answers it, and the controls that act on it.
struct NovaAnalysisFindingCard: View {
    let item: NovaAnalysisItem
    let method: NovaRiskMethod
    let isSelected: Bool
    var isSelectable = true
    var canEdit = true
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReact: (NovaAnalysisReaction) -> Void
    @Environment(\.colorScheme) private var scheme

    private var identifier: String { "analysis.finding.\(item.id.uuidString.lowercased())" }
    private var band: String? { item.band(method) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                head
                NovaText(text: item.title, style: .cardTitle).lineLimit(2)
                if !item.body.isEmpty { NovaText(text: item.body, style: .metaQuiet).lineLimit(3) }
                measureBox
                tags
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(height: 1)
            NovaAnalysisItemBar(canEdit: canEdit, reaction: item.reaction, onEdit: onEdit, onDelete: onDelete,
                onReact: onReact, onOpen: onOpen, identifier: identifier)
        }
        .background(NovaColorToken.surface.color(in: scheme))
        .clipShape(RoundedRectangle(cornerRadius: NovaDimensionToken.radiusCard.value))
        .overlay(RoundedRectangle(cornerRadius: NovaDimensionToken.radiusCard.value)
            .strokeBorder(isSelected ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.border.color(in: scheme),
                          lineWidth: isSelected ? 1.5 : 1))
    }

    private var head: some View {
        HStack(alignment: .center, spacing: 7) {
            NovaText(text: "\(item.ordinal)", style: .badge, color: NovaColorToken.onInverse.color(in: scheme))
                .frame(width: 22, height: 22)
                .background(NovaColorToken.inverse.color(in: scheme), in: Circle())
            if let band {
                NovaStatusPill(label: NovaNonconformityWords.band(band), status: NovaNonconformityWords.tone(band), showsDot: false)
            }
            if let value = item.value(method) {
                NovaText(text: NovaNonconformityWords.score(value), style: .cardTitle)
            }
            Spacer(minLength: 0)
            if isSelectable { selectButton }
        }
    }

    private var selectButton: some View {
        Button(action: onSelect) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19))
                .foregroundStyle(isSelected ? NovaColorToken.accentInk.color(in: scheme)
                                            : NovaColorToken.borderStrong.color(in: scheme))
                .frame(width: 34, height: 34)
        }.buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: item.title))
            .accessibilityIdentifier("analysis.detail.select.\(item.id.uuidString.lowercased())")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var measureBox: some View {
        if let measure = item.measure?.trimmingCharacters(in: .whitespacesAndNewlines), !measure.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 10))
                        .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    NovaText(text: RDLocalization.string("localizable.nova.analysis.field.measure.corrective", table: .localizable,
                        fallback: "Düzeltici önlem"), style: .micro, color: NovaColorToken.accentInk.color(in: scheme))
                }
                NovaText(text: measure, style: .metaQuiet).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(NovaColorToken.statusSuccessBg.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder private var tags: some View {
        let entries = tagEntries
        if !entries.isEmpty {
            HStack(spacing: 5) {
                ForEach(entries, id: \.text) { entry in
                    NovaAnalysisTag(symbol: entry.symbol, text: entry.text, status: entry.status)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var tagEntries: [(symbol: String, text: String, status: NovaStatus)] {
        var result: [(String, String, NovaStatus)] = []
        if item.hasRootCause {
            result.append(("magnifyingglass", RDLocalization.string("localizable.nova.analysis.field.root.cause", table: .localizable,
                fallback: "Kök neden"), .warning))
        }
        if item.hasPreventive {
            result.append(("shield", RDLocalization.string("localizable.nova.analysis.tag.preventive", table: .localizable,
                fallback: "Önleyici"), .success))
        }
        if item.hasReferences {
            result.append(("book", RDLocalization.string("localizable.nova.analysis.field.references", table: .localizable,
                fallback: "Mevzuat"), .info))
        }
        if !item.photoIndices.isEmpty {
            result.append(("photo", String(format: RDLocalization.string("localizable.nova.analysis.tag.photo.index", table: .localizable,
                fallback: "Foto %@"), item.photoIndices.map(String.init).joined(separator: ", ")), .neutral))
        }
        return result
    }
}

/// One unscored row of the judgement sections. It is never painted as if it
/// carried a band, because it does not.
struct NovaAnalysisAdviceCard: View {
    let item: NovaAnalysisItem
    let kind: NovaAnalysisSectionKind
    let isSelected: Bool
    var isSelectable = true
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onReact: (NovaAnalysisReaction) -> Void
    @Environment(\.colorScheme) private var scheme

    private var identifier: String { "analysis.advice.\(item.id.uuidString.lowercased())" }

    var body: some View {
        let tone = NovaAnalysisSectionTone.of(kind)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    NovaIcon(symbol: tone.symbol, size: 13)
                        .foregroundStyle(tone.status.tokens.ink.color(in: scheme))
                    if let overline = item.category ?? item.audience {
                        NovaText(text: overline.uppercased(), style: .micro,
                            color: tone.status.tokens.ink.color(in: scheme)).lineLimit(1)
                    } else {
                        NovaText(text: String(format: RDLocalization.string("localizable.nova.analysis.item.ordinal", table: .localizable,
                            fallback: "Kayıt #%d"), item.ordinal), style: .micro,
                            color: tone.status.tokens.ink.color(in: scheme))
                    }
                    Spacer(minLength: 0)
                    if isSelectable { selectButton }
                }
                NovaText(text: item.title, style: .cardTitle).lineLimit(3)
                if let audience = item.audience, item.category != nil {
                    HStack(spacing: 5) {
                        Image(systemName: "person.2").font(.system(size: 10))
                            .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                        NovaText(text: audience, style: .meta, color: NovaColorToken.textSecondary.color(in: scheme)).lineLimit(1)
                    }
                }
                if !item.body.isEmpty { NovaText(text: item.body, style: .metaQuiet).lineLimit(4) }
                if let value = item.durationValue, let label = item.durationLabel {
                    NovaAnalysisTag(symbol: "clock", text: "\(label): \(value)", status: .neutral)
                }
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(height: 1)
            NovaAnalysisItemBar(canEdit: false, reaction: item.reaction, onEdit: {}, onDelete: {},
                onReact: onReact, onOpen: onOpen, identifier: identifier)
        }
        .background(NovaColorToken.surface.color(in: scheme))
        .clipShape(RoundedRectangle(cornerRadius: NovaDimensionToken.radiusCard.value))
        .overlay(RoundedRectangle(cornerRadius: NovaDimensionToken.radiusCard.value)
            .strokeBorder(isSelected ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.border.color(in: scheme),
                          lineWidth: isSelected ? 1.5 : 1))
    }

    private var selectButton: some View {
        Button(action: onSelect) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 19))
                .foregroundStyle(isSelected ? NovaColorToken.accentInk.color(in: scheme)
                                            : NovaColorToken.borderStrong.color(in: scheme))
                .frame(width: 34, height: 34)
        }.buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: item.title))
            .accessibilityIdentifier("analysis.detail.select.\(item.id.uuidString.lowercased())")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The ruled lines of a notebook page: one margin rule down the left and a
/// writing line under every row of text.
struct NovaNotebookRules: Shape {
    var lineHeight: CGFloat = 27
    var margin: CGFloat = 30
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var y = lineHeight
        while y < rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += lineHeight
        }
        path.move(to: CGPoint(x: rect.minX + margin, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + margin, y: rect.maxY))
        return path
    }
}

/// The approved notebook, written on a page that looks like one. The entries
/// are the server's text; the page is only the surface under them.
struct NovaNotebookPanel: View {
    let items: [NovaAnalysisItem]
    let onOpen: (NovaAnalysisItem) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NovaText(text: RDLocalization.string("localizable.nova.analysis.notebook.heading", table: .localizable,
                fallback: "ONAYLI DEFTER KAYITLARI"), style: .overline,
                color: NovaColorToken.textTertiary.color(in: scheme))
                .padding(.leading, 42).padding(.top, 14).padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(items) { item in entry(item) }
            }.padding(.leading, 42).padding(.trailing, 16).padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                NovaColorToken.surface.color(in: scheme)
                NovaNotebookRules().stroke(NovaColorToken.hairline.color(in: scheme), lineWidth: 1)
                NovaNotebookRules(lineHeight: .greatestFiniteMagnitude)
                    .stroke(NovaColorToken.statusDangerInk.color(in: scheme).opacity(0.35), lineWidth: 1.4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NovaDimensionToken.radiusCard.value))
        .overlay(RoundedRectangle(cornerRadius: NovaDimensionToken.radiusCard.value)
            .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
    }

    private func entry(_ item: NovaAnalysisItem) -> some View {
        Button { onOpen(item) } label: {
            HStack(alignment: .top, spacing: 8) {
                NovaText(text: "\(item.ordinal)-", style: .cardTitle,
                    color: NovaColorToken.statusDangerInk.color(in: scheme))
                VStack(alignment: .leading, spacing: 3) {
                    NovaText(text: notebookText(item), style: .body)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
            .accessibilityIdentifier("analysis.notebook.\(item.id.uuidString.lowercased())")
    }

    /// The notebook reads as one continuous entry: the title and what follows
    /// it are one sentence, exactly as the section wrote them.
    private func notebookText(_ item: NovaAnalysisItem) -> String {
        let body = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let measure = (item.measure ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return [item.title, body, measure].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
