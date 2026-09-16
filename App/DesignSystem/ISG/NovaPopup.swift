import SwiftUI

enum NovaPopupStyle {
    static let materialOpacity = 0.60
    static let dimOpacity = 0.18
    static let sourceBlur: CGFloat = 4

    static func background(in scheme: ColorScheme) -> Color {
        NovaColorToken.surface.color(in: scheme)
    }
    static func controlBackground(in scheme: ColorScheme, inPopup: Bool) -> Color {
        (inPopup ? NovaColorToken.surfaceMuted : .surface).color(in: scheme)
    }
}

private struct NovaPopupEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while a page is rendered inside the centered İSGADA popup.
    /// Child pages use this to avoid duplicating a second back affordance.
    var isNovaPopup: Bool {
        get { self[NovaPopupEnvironmentKey.self] }
        set { self[NovaPopupEnvironmentKey.self] = newValue }
    }
}

/// A centered, keyboard-safe modal. The native presentation retains dismissal and focus semantics.
///
/// The blur/dim behind the card only ever shows whatever is directly behind
/// THIS presentation layer — not the screen the user actually came from, if
/// there's another cover or sheet stacked in between. So every "open straight
/// into this form" entry point (a company page's own empty-state "Ekle", a
/// home-card row, a drawer shortcut) must present the NovaPopup-wrapped form
/// as its OWN single cover directly from that origin screen — never render a
/// full intermediate board/list screen first and then layer the form as a
/// second, nested presentation on top of it. See the `startInAddMode` screens
/// (NovaRiskScreen, NovaAppointmentScreen, NovaEmergencyPlanScreen,
/// NovaPilotProcessGate, NovaPilotPPEGate) for the pattern: the whole `body`
/// branches to return just the NovaPopup content when opened this way,
/// instead of mounting the normal screen and opening a child sheet on it.
struct NovaPopup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isNovaPopup) private var nested
    @Environment(\.novaSuccessStore) private var successStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var busy = false
    @State private var contentHeight: CGFloat = 0
    @ViewBuilder var body: some View {
        if nested { content() } else { presentation }
    }
    private var presentation: some View {
        GeometryReader { geometry in
            ZStack {
                if !reduceTransparency { Rectangle().fill(.thinMaterial).opacity(NovaPopupStyle.materialOpacity).ignoresSafeArea() }
                Color.black.opacity(NovaPopupStyle.dimOpacity).ignoresSafeArea()
                ZStack(alignment: .topTrailing) {
                    // Reserve the close-control row so headings and their
                    // trailing actions never sit underneath the X button.
                    content().environment(\.isNovaPopup, true).padding(.top, 40)
                    NovaPopupCloseButton(identifier: "nova.popup.close") { dismiss() }
                        .disabled(busy)
                        .padding(.top, 8).padding(.trailing, 8)
                }
                .frame(maxWidth: 540)
                .frame(height: min(max(140, geometry.size.height - 32), contentHeight > 0 ? contentHeight + 52 : 360))
                .onPreferenceChange(NovaPopupHeightKey.self) { height in
                    if height > 0, abs(contentHeight - height) > 1 { contentHeight = height }
                }
                .background(NovaPopupStyle.background(in: scheme))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
                .padding(.horizontal, 16)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.font(NovaFont.font(.body)).foregroundStyle(NovaColorToken.text.color(in: scheme)).tint(NovaColorToken.text.color(in: scheme))
        .modifier(NovaTransparentPresentation())
            .overlay { if let successStore { NovaSuccessOverlay(store: successStore) } }
            .onPreferenceChange(NovaPopupBusyKey.self) { busy = $0 }
            .interactiveDismissDisabled(busy)
    }
}

/// A visible 48-point circular target. The complete circle dismisses the
/// popup, so the user never has to land precisely on the small x glyph.
struct NovaPopupCloseButton: View {
    var identifier = "nova.popup.close"
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NovaColorToken.text.color(in: scheme))
                .frame(width: 48, height: 48)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: Circle())
                .overlay(Circle().strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(NovaPopupClosePressStyle())
        .accessibilityLabel(RDLocalization.string("localizable.nova.company.management.gate.kapat.3148ed17", table: .localizable, fallback: "Kapat"))
        .accessibilityIdentifier(identifier)
    }
}

private struct NovaPopupClosePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct NovaPopupHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    func novaPopupContentSize(extra: CGFloat = 0) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: NovaPopupHeightKey.self, value: proxy.size.height + extra)
        })
    }
}

private struct NovaTransparentPresentation: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(.clear)
        } else {
            content
        }
    }
}

struct NovaPopupBusyKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}


extension View {
    /// App forms use this centered presentation. System camera/document/share controllers retain native presentation.
    func novaPopup<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        novaFullScreenCover(item: item, onDismiss: onDismiss) { value in
            NovaPopup { content(value) }
        }
    }
    func novaPopup<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content) -> some View {
        novaFullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            NovaPopup { content() }
        }
    }
}

/// Popup cards/fields contrast with the white container; regular pages retain their surface.
private struct NovaControlBackground: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isNovaPopup) private var inPopup
    func body(content: Content) -> some View {
        content.background(NovaPopupStyle.controlBackground(in: scheme, inPopup: inPopup),
            in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func novaControlBackground(cornerRadius: CGFloat) -> some View {
        modifier(NovaControlBackground(cornerRadius: cornerRadius))
    }
}
