import SwiftUI

/// Shared title/action layout. Titles wrap naturally; accessibility text stacks actions.
struct NovaListHeading<Action: View>: View {
    let title: String
    let onBack: () -> Void
    var actionBelow = false
    @ViewBuilder let action: () -> Action
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if actionBelow || typeSize.isAccessibilitySize {
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
    var status: NovaStatus = .neutral
    var isSelected = false
    let onTap: (() -> Void)?
    @Environment(\.colorScheme) private var scheme

    init(title: String, symbol: String, value: Int, status: NovaStatus = .neutral, isSelected: Bool = false,
         onTap: (() -> Void)? = nil) {
        self.title = title; self.symbol = symbol; self.value = String(value)
        self.status = status; self.isSelected = isSelected; self.onTap = onTap
    }

    init(title: String, symbol: String, value: String, status: NovaStatus = .neutral, isSelected: Bool = false,
         onTap: (() -> Void)? = nil) {
        self.title = title; self.symbol = symbol; self.value = value
        self.status = status; self.isSelected = isSelected; self.onTap = onTap
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
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 13, weight: .regular))
                    .foregroundStyle(status.tokens.ink.color(in: scheme))
                    .accessibilityHidden(true)
                Text(verbatim: value)
                    .font(.custom("PlusJakartaSans-SemiBold", size: 19, relativeTo: .body))
                    .foregroundStyle(NovaColorToken.text.color(in: scheme))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(verbatim: title)
                .font(.custom("PlusJakartaSans-Medium", size: 10, relativeTo: .caption))
                .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 26, alignment: .top)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
        .padding(.horizontal, 7).padding(.vertical, 8)
        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(isSelected ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.border.color(in: scheme), lineWidth: isSelected ? 1.4 : 1))
    }
}

/// The shared, compact explainer used above module lists.
struct NovaListHint: View {
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "lightbulb")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(NovaColorToken.statusWarningInk.color(in: scheme))
                .accessibilityHidden(true)
            NovaText(text: text, style: .metaQuiet,
                color: NovaColorToken.textSecondary.color(in: scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.custom("PlusJakartaSans-SemiBold", size: 12, relativeTo: .caption))
                    .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(NovaRowPressStyle())
            }
        }
        .padding(.leading, 12).padding(.trailing, actionTitle == nil ? 12 : 5)
        .frame(minHeight: 48)
        .background(NovaColorToken.surface.color(in: scheme), in: Capsule())
        .overlay(Capsule().strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
    }
}

/// The paired actions at the top of createable list pages.
struct NovaListActionButton: View {
    enum Tone { case primary, discovery }
    let title: String
    let symbol: String
    let tone: Tone
    var identifier: String? = nil
    var enabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var colors: (fill: Color, ink: Color, border: Color, symbol: Color) {
        switch tone {
        case .primary:
            return (NovaColorToken.statusInfoBg.color(in: scheme), NovaColorToken.statusInfoInk.color(in: scheme),
                    NovaColorToken.statusInfoDot.color(in: scheme).opacity(0.2), NovaColorToken.statusInfoInk.color(in: scheme))
        case .discovery:
            return (NovaColorToken.statusWarningBg.color(in: scheme), NovaColorToken.statusWarningInk.color(in: scheme),
                    NovaColorToken.statusWarningDot.color(in: scheme).opacity(0.22), NovaColorToken.statusWarningInk.color(in: scheme))
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(colors.symbol)
                Text(title).font(NovaFont.font(.buttonSm)).foregroundStyle(colors.ink)
                    .lineLimit(1).minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(colors.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(colors.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(NovaPressStyle())
        .disabled(!enabled)
    }

    @ViewBuilder var body: some View {
        if let identifier { button.accessibilityIdentifier(identifier) }
        else { button }
    }
}

/// Section title and its record count use one hierarchy throughout the lists.
struct NovaListSectionHeading: View {
    let title: String
    let count: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            NovaText(text: title, style: .screenTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            NovaText(text: count, style: .metaQuiet,
                color: NovaColorToken.textSubtle.color(in: scheme))
                .lineLimit(1)
        }
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
