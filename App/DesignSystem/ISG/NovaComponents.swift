import SwiftUI

private struct NovaSuccessKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}

extension EnvironmentValues {
    var novaCelebrate: (String) -> Void {
        get { self[NovaSuccessKey.self] }
        set { self[NovaSuccessKey.self] = newValue }
    }
}

/// Dismiss on a non-input tap inside this form, including its empty scroll area.
/// Does not consume button taps or steal focus from text fields / the keyboard.
struct NovaKeyboardDismissArea: UIViewRepresentable {
    func makeUIView(context: Context) -> Surface { Surface() }
    func updateUIView(_ uiView: Surface, context: Context) {}
    static func dismantleUIView(_ uiView: Surface, coordinator: ()) { uiView.detach() }

    final class Surface: UIView, UIGestureRecognizerDelegate {
        private weak var attachedWindow: UIWindow?
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(endInput))
        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            isUserInteractionEnabled = false
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            attachedWindow = window
        }
        func detach() { attachedWindow?.removeGestureRecognizer(tap); attachedWindow = nil }
        @objc private func endInput() { attachedWindow?.endEditing(true) }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard bounds.contains(touch.location(in: self)) else { return false }
            var candidate = touch.view
            while let view = candidate {
                if view is UITextField || view is UITextView { return false }
                candidate = view.superview
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

// Additive expert-only primitives. No global appearance, services or app route changes.
extension NovaRGBA {
    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255,
              blue: Double(blue) / 255, opacity: alpha)
    }
}

extension NovaColorToken {
    func color(in scheme: ColorScheme) -> Color { rgba(dark: scheme == .dark).color }
}

struct NovaText: View {
    let text: String
    var style: NovaTypeToken = .body
    var color: Color?
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .body) private var scale = 1.0

    var body: some View {
        let spec = style.spec
        Text(verbatim: text)
            .font(.custom(spec.fontName, size: spec.size, relativeTo: .body))
            .tracking(spec.tracking * scale)
            // Native font leading differs from RN lineHeight; visual acceptance remains open.
            .lineSpacing(max(0, spec.lineHeight - spec.size) * scale)
            .foregroundStyle(color ?? NovaColorToken.text.color(in: scheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct NovaCard<Content: View>: View {
    var padding: CGFloat = 11
    var border: Color = .clear
    var tint: Color? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: NovaDimensionToken.radiusCard.value)
                    .fill(tint ?? NovaColorToken.surface.color(in: scheme))
                    .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 2)
            }
            .overlay(RoundedRectangle(cornerRadius: NovaDimensionToken.radiusCard.value)
                .strokeBorder(border, lineWidth: 1.5))
    }
}

/// Every NOVA root and pushed destination owns an opaque canvas, not a system-white page.
/// White belongs to NovaCard/content surfaces; List/Form defaults must not cover the canvas.
struct NovaPageSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isNovaPopup) private var isNovaPopup

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: isNovaPopup ? nil : .infinity, alignment: .topLeading)
            .scrollContentBackground(.hidden)
            .background(NovaColorToken.canvas.color(in: scheme).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar, .tabBar)
    }
}

/// Consistent 44-point hit target with a compact, theme-aware icon.
struct NovaBackButton: View {
    var isEnabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NovaColorToken.text.color(in: scheme))
                .frame(width: 44, height: 44)
                .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
        }.buttonStyle(.plain).disabled(!isEnabled)
            .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.shell.back", table: .localizable, fallback: "Geri")))
    }
}

/// Brief purpose copy: outline icon, never a decorative icon tile.
struct NovaHelpHint: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            NovaIcon(symbol: "lightbulb", size: 15)
                .foregroundStyle(NovaColorToken.statusWarningInk.color(in: scheme))
                .accessibilityHidden(true)
            NovaText(text: text, style: .metaQuiet,
                color: NovaColorToken.textSecondary.color(in: scheme))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }
}

struct NovaPageHeading: View {
    let title: String
    var subtitle = ""
    var isBackEnabled = true
    let onBack: () -> Void
    @Environment(\.isNovaPopup) private var isNovaPopup
    var body: some View {
        HStack(spacing: 12) {
            if !isNovaPopup { NovaBackButton(isEnabled: isBackEnabled, action: onBack) }
            VStack(alignment: .leading, spacing: 3) {
                NovaText(text: title, style: .sectionTitle)
                if !subtitle.isEmpty { NovaText(text: subtitle, style: .metaQuiet) }
            }
            Spacer(minLength: 0)
        }
    }
}

enum NovaStatus: CaseIterable {
    case success, warning, danger, info, neutral

    var tokens: (background: NovaColorToken, ink: NovaColorToken) {
        switch self {
        case .success: return (.statusSuccessBg, .statusSuccessInk)
        case .warning: return (.statusWarningBg, .statusWarningInk)
        case .danger: return (.statusDangerBg, .statusDangerInk)
        case .info: return (.statusInfoBg, .statusInfoInk)
        case .neutral: return (.statusNeutralBg, .statusNeutralInk)
        }
    }
}

struct NovaStatusPill: View {
    let label: String
    let status: NovaStatus
    var showsDot = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tone = status.tokens
        HStack(spacing: 5) {
            if showsDot {
                Circle().fill(tone.ink.color(in: scheme)).frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            NovaText(text: label, style: .badge, color: tone.ink.color(in: scheme))
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(tone.background.color(in: scheme), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
    }
}

enum NovaButtonVariant { case primary, surface, muted, danger }

struct NovaButton: View {
    let label: String
    var symbol: String?
    var variant: NovaButtonVariant = .primary
    var isEnabled = true
    var isLoading = false
    var loadingDescription = RDLocalization.string("localizable.nova.components.loading.description", table: .localizable, fallback: "İşlem sürüyor")
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var palette: (Color, Color) {
        if !isEnabled || isLoading {
            return (NovaColorToken.surfaceMuted.color(in: scheme), NovaColorToken.textSecondary.color(in: scheme))
        }
        switch variant {
        case .primary:
            // Recorded accessibility adaptation: white on #2ed256 is only ~2:1.
            return (NovaColorToken.accent.color(in: scheme), NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
        case .surface: return (NovaColorToken.surface.color(in: scheme), NovaColorToken.text.color(in: scheme))
        case .muted: return (NovaColorToken.surfaceMuted.color(in: scheme), NovaColorToken.textSecondary.color(in: scheme))
        case .danger: return (NovaColorToken.statusDangerBg.color(in: scheme), NovaColorToken.statusDangerInk.color(in: scheme))
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    NovaSpinner(color: palette.1).accessibilityHidden(true)
                } else if let symbol {
                    Image(systemName: symbol).foregroundStyle(palette.1).accessibilityHidden(true)
                }
                NovaText(text: label, style: .button, color: palette.1)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(palette.0, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(NovaPressStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: isLoading ? loadingDescription : ""))
    }
}

private struct NovaPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Pure SwiftUI ring also renders in hostless snapshots; motion respects Reduce Motion.
private struct NovaSpinner: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        Circle().stroke(color.opacity(0.2), lineWidth: 2)
            .overlay(Circle().trim(from: 0.2, to: 0.9).stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round)))
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .frame(width: 16, height: 16)
            .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = !reduceMotion }
            .onChange(of: reduceMotion) { spinning = !$0 }
    }
}

#if DEBUG
/// Isolated fixture gallery: no Auth, live services, analytics or production navigation.
struct NovaComponentGallery: View {
    @Environment(\.colorScheme) private var scheme
    @State private var taps = 0

    var body: some View {
        ScrollView {
            NovaComponentGalleryContent(taps: taps) { taps += 1 }
        }.background(NovaColorToken.canvas.color(in: scheme))
    }
}

/// The same content without the platform-backed scrolling container, for deterministic renders.
struct NovaComponentGalleryContent: View {
    let taps: Int
    let onTap: () -> Void

    var body: some View {
            VStack(alignment: .leading, spacing: NovaDimensionToken.spaceLg.value) {
                NovaText(text: "İSG Adası · Tasarım laboratuvarı", style: .screenTitle)
                NovaText(text: "Sentetik örnekler — canlı kayıt içermez", style: .metaQuiet)
                NovaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        NovaText(text: "Örnek çalışma alanı", style: .cardTitle)
                        NovaText(text: "Uzun açıklamalar ve büyük metin boyutları için kart yüksekliği içeriğe göre büyür.")
                        NovaStatusPill(label: "İşlem tamamlandı", status: .success)
                        NovaStatusPill(label: "İnceleme bekliyor", status: .warning)
                        NovaStatusPill(label: "İşlem tamamlanamadı", status: .danger)
                        NovaStatusPill(label: "Bilgilendirme", status: .info)
                        NovaStatusPill(label: "Henüz kayıt yok", status: .neutral)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                NovaButton(label: "Örnek eylem (\(taps))", symbol: "plus", action: onTap)
                NovaButton(label: "İkincil eylem", variant: .surface) {}
                NovaButton(label: "İşlem sürüyor", isLoading: true) {}
                NovaButton(label: "Kullanılamıyor", isEnabled: false) {}
            }.padding(NovaDimensionToken.spaceScreenX.value)
    }
}

struct NovaComponentGallery_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NovaComponentGallery().preferredColorScheme(.light).previewDisplayName("Light")
            NovaComponentGallery().preferredColorScheme(.dark).previewDisplayName("Dark")
            NovaComponentGallery().environment(\.dynamicTypeSize, .accessibility3)
                .previewDisplayName("Large text")
        }
    }
}
#endif
