import SwiftUI

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
    @State private var busy = false
    @State private var contentHeight: CGFloat = 0
    @ViewBuilder var body: some View {
        if nested { content() } else { presentation }
    }
    private var presentation: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                Color.black.opacity(0.16).ignoresSafeArea()
                ZStack(alignment: .topTrailing) {
                    // Reserve the close-control row so headings and their
                    // trailing actions never sit underneath the X button.
                    content().environment(\.isNovaPopup, true).padding(.top, 48)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)

                    }.buttonStyle(.plain).disabled(busy)
                        .accessibilityLabel(RDLocalization.string("localizable.nova.company.management.gate.kapat.3148ed17", table: .localizable, fallback: "Kapat"))
                        .accessibilityIdentifier("nova.popup.close")
                        .padding(.top, 8).padding(.trailing, 8)
                }
                .frame(maxWidth: 540)
                .frame(height: min(max(140, geometry.size.height - 32), contentHeight > 0 ? contentHeight + 68 : 360))
                .onPreferenceChange(NovaPopupHeightKey.self) { height in
                    if height > 0, abs(contentHeight - height) > 1 { contentHeight = height }
                }
                .background(NovaColorToken.canvas.color(in: scheme))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
                .padding(.horizontal, 16)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.font(NovaFont.font(.body)).foregroundStyle(NovaColorToken.text.color(in: scheme)).tint(NovaColorToken.text.color(in: scheme))
        .modifier(NovaTransparentPresentation())
            .onPreferenceChange(NovaPopupBusyKey.self) { busy = $0 }
            .interactiveDismissDisabled(busy)
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
