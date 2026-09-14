import SwiftUI

/// One semantic scale for text and native controls across the pilot.
enum NovaFont {
    static let secondaryInk = Color(uiColor: UIColor { traits in
        let c = NovaColorToken.textSecondary.rgba(dark: traits.userInterfaceStyle == .dark)
        return UIColor(red: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255, blue: CGFloat(c.blue) / 255, alpha: c.alpha)
    })
    static func font(_ role: NovaTypeToken) -> Font {
        .custom(role.spec.fontName, size: role.spec.size, relativeTo: .body)
    }
    static func ink(_ requested: Color?, role: NovaTypeToken, scheme: ColorScheme) -> Color {
        let secondary: Set<NovaTypeToken> = [.meta, .metaQuiet, .micro, .overline]
        let fallback = (secondary.contains(role) ? NovaColorToken.textSecondary : .text).color(in: scheme)
        guard let requested else { return fallback }
        let neutral = [Color.primary, .secondary, .gray] + [NovaColorToken.text, .textSecondary, .textTertiary, .textMuted, .textSubtle].map { $0.color(in: scheme) }
        return neutral.contains(requested) ? fallback : requested
    }
}

private struct NovaHasHeaderKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var novaHasHeader: Bool {
        get { self[NovaHasHeaderKey.self] }
        set { self[NovaHasHeaderKey.self] = newValue }
    }
}

/// Standalone destinations retain the same brand header as shell destinations.
struct NovaStandaloneHeader: View {
    var body: some View {
        VStack(spacing: 1) {
            NovaText(text: "İSGADA", style: .brand)
            NovaText(text: "Saha denetim asistanı", style: .meta)
        }.frame(maxWidth: .infinity).padding(.vertical, 8)
            .accessibilityIdentifier("nova.standalone.header")
    }
}

extension View {
    func novaFullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        fullScreenCover(item: item, onDismiss: onDismiss) { item in
            content(item).environment(\.novaHasHeader, false)
        }
    }
    func novaFullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            content().environment(\.novaHasHeader, false)
        }
    }
}
