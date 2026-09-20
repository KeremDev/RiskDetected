import SwiftUI

/// Shared title/action layout. Titles wrap naturally; accessibility text stacks actions.
struct NovaListHeading<Action: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder let action: () -> Action
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                NovaPageHeading(title: title, onBack: onBack)
                action()
            }
        } else {
            HStack(spacing: 10) {
                NovaPageHeading(title: title, onBack: onBack)
                action().fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

/// A compact, monochrome counter shared by module lists.
struct NovaListStat: View {
    let title: String
    let symbol: String
    let value: String
    var isSelected = false
    let onTap: (() -> Void)?
    @Environment(\.colorScheme) private var scheme

    init(title: String, symbol: String, value: Int, isSelected: Bool = false,
         onTap: (() -> Void)? = nil) {
        self.title = title; self.symbol = symbol; self.value = String(value)
        self.isSelected = isSelected; self.onTap = onTap
    }

    init(title: String, symbol: String, value: String, isSelected: Bool = false,
         onTap: (() -> Void)? = nil) {
        self.title = title; self.symbol = symbol; self.value = value
        self.isSelected = isSelected; self.onTap = onTap
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { tile }.buttonStyle(NovaRowPressStyle())
            } else {
                tile
            }
        }
            .accessibilityLabel("\(title), \(value)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 13, weight: .regular))
                    .accessibilityHidden(true)
                Text(verbatim: value)
                    .font(.custom("PlusJakartaSans-SemiBold", size: 19, relativeTo: .body))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(verbatim: title)
                .font(.custom("PlusJakartaSans-Medium", size: 10, relativeTo: .caption))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 26, alignment: .topLeading)
        }
        .foregroundStyle(NovaColorToken.text.color(in: scheme))
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(.horizontal, 9).padding(.vertical, 10)
        .novaControlBackground(cornerRadius: 16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(isSelected ? NovaColorToken.text.color(in: scheme) : .clear, lineWidth: 1))
    }
}

/// Compact in-card action shared by company-detail summaries. It keeps a
/// full 44pt hit target without turning a secondary action into a large CTA.
struct NovaCompactActionButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var enabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.custom("PlusJakartaSans-SemiBold", size: 11, relativeTo: .caption))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(prominent ? Color.white : NovaColorToken.text.color(in: scheme))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(prominent ? Color.black : NovaColorToken.surfaceMuted.color(in: scheme),
                in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(prominent ? Color.clear : NovaColorToken.border.color(in: scheme), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(NovaPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// One full-width answer for an empty list. The title names what is missing;
/// the lightbulb line explains the useful next action for that page.
struct NovaEmptyState: View {
    let title: String
    let message: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                NovaText(text: title, style: .cardTitle)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(NovaColorToken.statusWarningInk.color(in: scheme))
                        .frame(width: 18, height: 20)
                        .accessibilityHidden(true)
                    NovaText(text: message, style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Single filters use exactly the same searchable panel as multi-filter rows.
struct NovaFilterField: View {
    let label: String
    let options: [NovaFileChooserOption]
    let selected: String?
    let identifier: String
    let onPick: (String?) -> Void
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            NovaFileChooserButton(label: label,
                value: options.first { $0.id == selected }?.title ?? "Tümü",
                isOpen: expanded, identifier: identifier) { expanded.toggle() }
            if expanded {
                NovaFileChooserPanel(options: options, selected: selected,
                    identifier: "\(identifier).options") { value in
                    onPick(value)
                    expanded = false
                }
                // The panel belongs to the button above it, so it grows from
                // that edge rather than fading in place, and it leaves the same
                // way it arrived. Without this the rows below it teleport.
                .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.97, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(NovaMotion.gated(NovaMotion.easeOut(NovaMotion.Duration.dropdown),
                                    reduceMotion: reduceMotion),
                   value: expanded)
    }
}
