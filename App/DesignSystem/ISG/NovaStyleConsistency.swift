import SwiftUI

/// One semantic scale for text and native controls across the pilot.
enum NovaFont {
    static let secondaryInk = Color(uiColor: UIColor { traits in
        let c = NovaColorToken.textSecondary.rgba(dark: traits.userInterfaceStyle == .dark)
        return UIColor(red: CGFloat(c.red) / 255, green: CGFloat(c.green) / 255, blue: CGFloat(c.blue) / 255, alpha: c.alpha)
    })
    /// Pilot presentation scale; generated cross-platform reference tokens remain unchanged.
    static func spec(_ role: NovaTypeToken) -> NovaTypeSpec {
        if role == .screenTitle { return NovaTypeSpec(fontName: "PlusJakartaSans-SemiBold", weight: 600, size: 20, tracking: -0.3, lineHeight: 27) }
        if role == .sheetTitle { return NovaTypeSpec(fontName: "PlusJakartaSans-SemiBold", weight: 600, size: 18, tracking: -0.25, lineHeight: 25) }
        return role.spec
    }
    static func font(_ role: NovaTypeToken) -> Font {
        .custom(spec(role).fontName, size: spec(role).size, relativeTo: .body)
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
struct NovaHeaderContext {
    let current: NovaDestination
    let userName: String
    let unreadCount: Int
    let hasUnread: Bool
    let notificationsAvailable: Bool
    let send: (NovaNavigationEvent) -> Void
}
private struct NovaHeaderContextKey: EnvironmentKey { static let defaultValue: NovaHeaderContext? = nil }
extension EnvironmentValues {
    var novaHeaderContext: NovaHeaderContext? {
        get { self[NovaHeaderContextKey.self] }
        set { self[NovaHeaderContextKey.self] = newValue }
    }
}

/// The same functioning menu, bell and profile controls on full-page destinations.
struct NovaStandaloneHeader: View {
    @Environment(\.novaHeaderContext) private var context
    var body: some View {
        if let context {
            NovaShellTopBar(current: context.current, userName: context.userName,
                hasUnread: context.hasUnread, unreadCount: context.unreadCount,
                canGoBack: false, notificationsAvailable: context.notificationsAvailable, send: context.send)
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.style.consistency.isgada.be46a6b6", table: .localizable, fallback: "İSGADA"), style: .brand).frame(maxWidth: .infinity).padding(.vertical, 8)
        }
    }
}

/// Only the current shell's presentations react; another account/preview cannot dismiss them.
struct NovaPresentationNavigation: ViewModifier {
    let epoch: String?
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.shell.navigate"))) { event in
            if let epoch, event.object as? String == epoch { dismiss() }
        }
    }
}
private struct NovaPresentationEpochKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var novaPresentationEpoch: String? {
        get { self[NovaPresentationEpochKey.self] }
        set { self[NovaPresentationEpochKey.self] = newValue }
    }
}
struct NovaPresentationHost<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.novaPresentationEpoch) private var epoch
    var body: some View {
        content().environment(\.novaHasHeader, false).environment(\.isNovaPopup, false)
            .modifier(NovaPresentationNavigation(epoch: epoch))
    }
}

extension View {
    func novaFullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        fullScreenCover(item: item, onDismiss: onDismiss) { item in
            NovaPresentationHost { content(item) }
        }
    }
    func novaFullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            NovaPresentationHost { content() }
        }
    }
}
