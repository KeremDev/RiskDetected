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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.novaPopupVisible) private var visible
    @State private var busy = false
    @State private var contentHeight: CGFloat = 0
    @ViewBuilder var body: some View {
        if nested { content() } else { presentation }
    }
    private var presentation: some View {
        GeometryReader { geometry in
            ZStack {
                // The backdrop fades and the card scales; neither travels. See
                // NovaPopupTransition for why the cover's own slide is gone.
                Group {
                    if !reduceTransparency { Rectangle().fill(.thinMaterial).opacity(NovaPopupStyle.materialOpacity).ignoresSafeArea() }
                    Color.black.opacity(NovaPopupStyle.dimOpacity).ignoresSafeArea()
                }.opacity(visible ? 1 : 0)
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
                .scaleEffect(reduceMotion || visible ? 1 : NovaPopupTransition.enterScale)
                .opacity(visible ? 1 : 0)
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
        // A 48pt circle can take a deeper press than a full-width button without
        // reading as a collapse, so this one overrides the shared scale.
        .buttonStyle(NovaPressStyle(scale: 0.92, pressedOpacity: 0.72))
        .accessibilityLabel(RDLocalization.string("localizable.nova.company.management.gate.kapat.3148ed17", table: .localizable, fallback: "Kapat"))
        .accessibilityIdentifier(identifier)
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


/// How a centered popup arrives and leaves.
///
/// `fullScreenCover` stays the presentation — it is what keeps the keyboard,
/// focus and dismissal semantics correct, and swapping it for an in-hierarchy
/// overlay would mean rebuilding all of that by hand. What it cannot do is
/// choose its own transition: it always slides the whole cover up from the
/// bottom edge. For a card that lives in the middle of the screen that is the
/// wrong path, and it drags the blur and the dim up with it, so the backdrop
/// arrives as a moving panel instead of settling behind the card.
///
/// So the cover's slide is suppressed — the presentation binding is written
/// inside a transaction with animations disabled — and the card runs its own
/// motion instead: the backdrop fades, the card scales up from 0.94. The exit
/// is the same path reversed, which is why the modifier holds the dismissal
/// back for the length of the exit before it actually tears the cover down.
///
/// A `NovaPopup` presented some other way still renders normally: the
/// environment flag defaults to visible, so the card is simply on screen from
/// the first frame and the cover animates the way it always did.
enum NovaPopupTransition {
    static let enterScale: CGFloat = 0.94
    static var enter: Animation { NovaMotion.easeOut(0.24) }
    static var exit: Animation { NovaMotion.easeOut(0.16) }
    /// Kept in step with `exit` — the cover is torn down once the card has
    /// finished leaving, not before.
    static let exitSeconds = 0.16

    /// Writes a presentation binding without letting the cover animate itself.
    static func silently(_ write: @escaping () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, write)
    }
}

private struct NovaPopupVisibleKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// False while the popup card is off-stage — before it has scaled in, and
    /// again while it scales out ahead of the cover being removed.
    var novaPopupVisible: Bool {
        get { self[NovaPopupVisibleKey.self] }
        set { self[NovaPopupVisibleKey.self] = newValue }
    }
}

/// Drives the enter and exit for a popup bound to an optional item.
private struct NovaPopupItemPresentation<Item: Identifiable, PopupContent: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    @ViewBuilder let popupContent: (Item) -> PopupContent
    @State private var visible = false
    @State private var closing = false

    func body(content: Content) -> some View {
        content.novaFullScreenCover(item: gate, onDismiss: {
            visible = false
            closing = false
            onDismiss?()
        }) { value in
            popupContent(value)
                .environment(\.novaPopupVisible, visible)
                .onAppear(perform: reveal)
        }
    }

    /// A frame later, so the card is laid out at its start value and the change
    /// actually animates instead of being folded into the first render.
    private func reveal() {
        guard !visible else { return }
        DispatchQueue.main.async {
            withAnimation(NovaPopupTransition.enter) { visible = true }
        }
    }

    private var gate: Binding<Item?> {
        Binding(get: { item }, set: { value in
            guard let value else { return requestClose() }
            NovaPopupTransition.silently { item = value }
        })
    }

    /// Runs the exit, then removes the cover. Re-entrant dismissals — a close
    /// button tapped twice, or a form dismissing itself as the user also taps
    /// the X — collapse into the first one.
    private func requestClose() {
        guard !closing else { return }
        closing = true
        withAnimation(NovaPopupTransition.exit) { visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + NovaPopupTransition.exitSeconds) {
            NovaPopupTransition.silently { item = nil }
        }
    }
}

/// The same driver for a popup bound to a flag.
private struct NovaPopupFlagPresentation<PopupContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    @ViewBuilder let popupContent: () -> PopupContent
    @State private var visible = false
    @State private var closing = false

    func body(content: Content) -> some View {
        content.novaFullScreenCover(isPresented: gate, onDismiss: {
            visible = false
            closing = false
            onDismiss?()
        }) {
            popupContent()
                .environment(\.novaPopupVisible, visible)
                .onAppear(perform: reveal)
        }
    }

    private func reveal() {
        guard !visible else { return }
        DispatchQueue.main.async {
            withAnimation(NovaPopupTransition.enter) { visible = true }
        }
    }

    private var gate: Binding<Bool> {
        Binding(get: { isPresented }, set: { value in
            guard value else { return requestClose() }
            NovaPopupTransition.silently { isPresented = true }
        })
    }

    private func requestClose() {
        guard !closing else { return }
        closing = true
        withAnimation(NovaPopupTransition.exit) { visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + NovaPopupTransition.exitSeconds) {
            NovaPopupTransition.silently { isPresented = false }
        }
    }
}

extension View {
    /// App forms use this centered presentation. System camera/document/share controllers retain native presentation.
    func novaPopup<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        novaPopupCover(item: item, onDismiss: onDismiss) { value in
            NovaPopup { content(value) }
        }
    }
    func novaPopup<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content) -> some View {
        novaPopupCover(isPresented: isPresented, onDismiss: onDismiss) {
            NovaPopup { content() }
        }
    }

    /// For the screens that wrap themselves in a `NovaPopup` — the ones opened
    /// straight into their create form — so they arrive the same way as a form
    /// presented through `novaPopup`.
    func novaPopupCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(NovaPopupItemPresentation(item: item, onDismiss: onDismiss, popupContent: content))
    }
    func novaPopupCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(NovaPopupFlagPresentation(isPresented: isPresented, onDismiss: onDismiss, popupContent: content))
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
