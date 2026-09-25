import SwiftUI

/// The colour family of a choice: its tile, its level bars and the dot next
/// to the chosen value.
enum NovaChoiceTone {
    case neutral, success, warning, danger

    func ink(in scheme: ColorScheme) -> Color {
        switch self {
        case .neutral: return NovaColorToken.accentInk.color(in: scheme)
        case .success: return NovaColorToken.statusSuccessInk.color(in: scheme)
        case .warning: return NovaColorToken.statusWarningInk.color(in: scheme)
        case .danger: return NovaColorToken.statusDangerInk.color(in: scheme)
        }
    }

    func soft(in scheme: ColorScheme) -> Color {
        switch self {
        case .neutral: return NovaColorToken.surfaceMuted.color(in: scheme)
        case .success: return NovaColorToken.statusSuccessBg.color(in: scheme)
        case .warning: return NovaColorToken.statusWarningBg.color(in: scheme)
        case .danger: return NovaColorToken.statusDangerBg.color(in: scheme)
        }
    }
}

/// One choice in a `NovaChoiceField` sheet.
struct NovaChoiceOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var detail: String? = nil
    var tone: NovaChoiceTone = .neutral
    /// 1...3 draws rising level bars in the tile (for ordered choices such as
    /// hazard classes); nil draws `symbol`.
    var level: Int? = nil
    var symbol: String? = nil
    var id: Value { value }
}

/// A form row that opens a bottom sheet of large, described choices. Nothing is
/// chosen until the user picks one: the row shows the placeholder, and the
/// sheet closes on its own right after a pick. Long lists get a search field
/// and open full height; an optional field offers `noneTitle` as its first row.
struct NovaChoiceField<Value: Hashable>: View {
    /// The row's name, shown above the chosen value ("Tehlike sınıfı *").
    let title: String
    /// Shown in the row while nothing is chosen, and as the sheet's heading.
    let placeholder: String
    let symbol: String
    var message: String? = nil
    let options: [NovaChoiceOption<Value>]
    @Binding var selection: Value?
    /// Accessibility identifier stem: the row, "<stem>.option.<index>",
    /// "<stem>.none" and "<stem>.search".
    var identifier: String
    /// For an optional field: the row that clears the choice ("Seçilmedi").
    var noneTitle: String? = nil
    /// nil: a search field once the list is longer than eight.
    var searchable: Bool? = nil
    /// A bordered field box, for forms whose other fields are boxes too;
    /// otherwise a plain row for a card with dividers.
    var boxed = false
    /// The sheet's heading when it should differ from the placeholder (e.g. a
    /// placeholder that reads as a value, "Firma geneli").
    var heading: String? = nil
    /// Opens the sheet from outside, e.g. right after the step that needs
    /// this answer; set back to false once the sheet is up.
    var openRequest: Binding<Bool>? = nil
    @State private var choosing = false
    @State private var query = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    private var chosen: NovaChoiceOption<Value>? { options.first { $0.value == selection } }
    private var searches: Bool { searchable ?? (options.count > 8) }
    private var matches: [(offset: Int, element: NovaChoiceOption<Value>)] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return options.enumerated().filter { needle.isEmpty || $0.element.title.localizedStandardContains(needle)
            || ($0.element.detail?.localizedStandardContains(needle) ?? false) }
    }

    var body: some View {
        Button { choosing = true } label: {
            HStack(spacing: 10) {
                NovaIcon(symbol: symbol, size: 17).frame(width: 22)
                if let chosen {
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: title, style: .metaQuiet, color: NovaColorToken.textMuted.color(in: scheme))
                        HStack(spacing: 7) {
                            if chosen.tone != .neutral || chosen.level != nil {
                                Circle().fill(chosen.tone.ink(in: scheme)).frame(width: 8, height: 8)
                            }
                            NovaText(text: chosen.title, style: .body).lineLimit(2)
                        }
                    }
                } else if let noneTitle {
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: title, style: .metaQuiet, color: NovaColorToken.textMuted.color(in: scheme))
                        NovaText(text: noneTitle, style: .body, color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                } else {
                    NovaText(text: placeholder, style: .body, color: NovaColorToken.textPlaceholder.color(in: scheme))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                    .frame(width: 26, height: 26)
                    .background(NovaColorToken.surfaceMuted.color(in: scheme), in: Circle())
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, boxed ? 12 : 0).padding(.vertical, boxed ? 2 : 0)
            .modifier(NovaChoiceBox(active: boxed))
            .contentShape(Rectangle())
        }
        .buttonStyle(NovaRowPressStyle())
        .opacity(enabled ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(chosen?.title ?? noneTitle ?? placeholder))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
        .onChange(of: openRequest?.wrappedValue ?? false) { open in
            guard open, enabled else { return }
            choosing = true
            openRequest?.wrappedValue = false
        }
        .sheet(isPresented: $choosing, onDismiss: { query = "" }) {
            if searches {
                VStack(alignment: .leading, spacing: 14) {
                    sheetHeading
                    searchField
                    ScrollView { list.padding(.bottom, 20) }
                        .scrollDismissesKeyboard(.interactively)
                }
                .padding(.horizontal, 20).padding(.top, 28)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            } else {
                RDContentSizedSheet {
                    VStack(alignment: .leading, spacing: 18) { sheetHeading; list }
                        .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 20)
                } footer: {
                    EmptyView()
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var sheetHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A field's name may serve as the heading; its required mark does not belong there.
            NovaText(text: (heading ?? placeholder).replacingOccurrences(of: " *", with: ""), style: .sheetTitle).accessibilityAddTraits(.isHeader)
            if let message {
                NovaText(text: message, style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            TextField(NovaChoiceText.search, text: $query)
                .font(NovaFont.font(.body)).autocorrectionDisabled().submitLabel(.search)
                .accessibilityIdentifier("\(identifier).search")
        }
        .padding(.horizontal, 14).frame(minHeight: 46)
        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NovaColorToken.borderMuted.color(in: scheme), lineWidth: 1))
    }

    private var list: some View {
        let found = matches
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Long lists (people, workplaces) draw only the rows on screen.
        return NovaChoiceStack(lazy: searches) {
            if let noneTitle, needle.isEmpty {
                card(title: noneTitle, detail: nil, tone: .neutral, tile: nil, picked: selection == nil) { pick(nil) }
                    .accessibilityIdentifier("\(identifier).none")
            }
            ForEach(found, id: \.element.id) { index, option in
                card(title: option.title, detail: option.detail, tone: option.tone,
                     tile: option.level != nil || option.symbol != nil ? option : nil,
                     picked: option.value == selection) { pick(option.value) }
                    .accessibilityIdentifier("\(identifier).option.\(index)")
            }
            if found.isEmpty {
                NovaText(text: NovaChoiceText.empty,
                    style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
    }

    private func pick(_ value: Value?) {
        selection = value
        NovaHaptics.selection()
        // Long enough to see the tick land, short enough to feel instant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { choosing = false }
    }

    /// A described choice is a large card with a tile; a plain one (a
    /// workplace, a person) is a compact row with the same tick.
    private func card(title: String, detail: String?, tone: NovaChoiceTone, tile option: NovaChoiceOption<Value>?,
                      picked: Bool, action: @escaping () -> Void) -> some View {
        let ink = tone.ink(in: scheme)
        let plain = option == nil && detail == nil
        return Button(action: action) {
            HStack(spacing: 14) {
                if let option { tile(option) }
                VStack(alignment: .leading, spacing: 3) {
                    NovaText(text: title, style: plain ? .body : .cardTitle)
                    if let detail {
                        NovaText(text: detail, style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().strokeBorder(picked ? ink : NovaColorToken.border.color(in: scheme), lineWidth: picked ? 0 : 1.5)
                    if picked {
                        Circle().fill(ink)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    }
                }
                .frame(width: 24, height: 24)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: picked)
            }
            .padding(.horizontal, 14).padding(.vertical, plain ? 12 : 14)
            .frame(maxWidth: .infinity, minHeight: plain ? 52 : 0, alignment: .leading)
            .background(picked ? (tone == .neutral ? NovaColorToken.accentSoft.color(in: scheme) : tone.soft(in: scheme).opacity(0.55))
                : NovaColorToken.surface.color(in: scheme),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(picked ? ink : NovaColorToken.borderMuted.color(in: scheme), lineWidth: picked ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    private func tile(_ option: NovaChoiceOption<Value>) -> some View {
        let ink = option.tone.ink(in: scheme)
        return ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(option.tone.soft(in: scheme))
            if let level = option.level {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(1...3, id: \.self) { bar in
                        Capsule().fill(bar <= level ? ink : ink.opacity(0.22))
                            .frame(width: 5, height: CGFloat(6 + bar * 5))
                    }
                }
            } else if let symbol = option.symbol {
                NovaIcon(symbol: symbol, size: 18).foregroundStyle(ink)
            }
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }
}

/// A column that builds its rows lazily when the list can be long.
private struct NovaChoiceStack<Content: View>: View {
    let lazy: Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        if lazy { LazyVStack(spacing: 10, content: content) } else { VStack(spacing: 10, content: content) }
    }
}

/// The chooser's own words.
enum NovaChoiceText {
    /// The row that clears an optional choice.
    static var none: String { RDLocalization.string("localizable.nova.choice.none", table: .localizable, fallback: "Seçilmedi") }
    static var search: String { RDLocalization.string("localizable.nova.choice.search", table: .localizable, fallback: "Ara") }
    static var empty: String { RDLocalization.string("localizable.nova.choice.empty", table: .localizable, fallback: "Sonuç bulunamadı") }
}

/// The field box other form controls use, when the chooser sits among them.
private struct NovaChoiceBox: ViewModifier {
    let active: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if active { content.novaControlBackground(cornerRadius: 14) } else { content }
    }
}

/// Hazard classes as described choices: what each class means for the expert's
/// daily work (renewal period of the risk assessment, minimum expert class).
enum NovaHazardChoice {
    static var placeholder: String {
        RDLocalization.string("localizable.nova.hazard.choice.placeholder", table: .localizable, fallback: "Tehlike sınıfı seçin")
    }
    static var message: String {
        RDLocalization.string("localizable.nova.hazard.choice.message", table: .localizable,
            fallback: "Resmî tehlike sınıfı, işyerinin NACE koduna göre belirlenir.")
    }
    static var options: [NovaChoiceOption<CompanyHazardClass>] {
        [.init(value: .low, title: CompanyHazardClass.low.title,
               detail: RDLocalization.string("localizable.nova.hazard.choice.low", table: .localizable,
                   fallback: "Risk değerlendirmesi 6 yılda bir yenilenir · en az C sınıfı uzman"), tone: .success, level: 1),
         .init(value: .medium, title: CompanyHazardClass.medium.title,
               detail: RDLocalization.string("localizable.nova.hazard.choice.medium", table: .localizable,
                   fallback: "Risk değerlendirmesi 4 yılda bir yenilenir · en az B sınıfı uzman"), tone: .warning, level: 2),
         .init(value: .high, title: CompanyHazardClass.high.title,
               detail: RDLocalization.string("localizable.nova.hazard.choice.high", table: .localizable,
                   fallback: "Risk değerlendirmesi 2 yılda bir yenilenir · A sınıfı uzman"), tone: .danger, level: 3)]
    }
}
