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

/// The product surfaces use the slightly deeper neutral from the mobile
/// reference. Keeping this as an environment style leaves the pinned İSGADA
/// reference tokens untouched for the hostless design harness.
enum NovaCanvasStyle {
    case reference
    case product

    func color(in scheme: ColorScheme) -> Color {
        switch self {
        case .reference:
            return NovaColorToken.canvas.color(in: scheme)
        case .product:
            return (scheme == .dark
                ? NovaRGBA(red: 17, green: 17, blue: 20, alpha: 1)
                : NovaRGBA(red: 233, green: 233, blue: 233, alpha: 1)).color
        }
    }
}

private struct NovaCanvasStyleKey: EnvironmentKey {
    static let defaultValue = NovaCanvasStyle.reference
}

extension EnvironmentValues {
    var novaCanvasStyle: NovaCanvasStyle {
        get { self[NovaCanvasStyleKey.self] }
        set { self[NovaCanvasStyleKey.self] = newValue }
    }
}

/// All İSGADA surfaces use the same bundled font family, including previews.
enum NovaTypographyFamily {
    case reference
    case product

    func fontName(for weight: Int) -> String? {
        guard self == .product else { return nil }
        switch weight {
        case 800...: return "PlusJakartaSans-ExtraBold"
        case 700..<800: return "PlusJakartaSans-Bold"
        case 600..<700: return "PlusJakartaSans-SemiBold"
        case 500..<600: return "PlusJakartaSans-Medium"
        default: return "PlusJakartaSans-Regular"
        }
    }
}

private struct NovaTypographyFamilyKey: EnvironmentKey {
    static let defaultValue = NovaTypographyFamily.reference
}

extension EnvironmentValues {
    var novaTypographyFamily: NovaTypographyFamily {
        get { self[NovaTypographyFamilyKey.self] }
        set { self[NovaTypographyFamilyKey.self] = newValue }
    }
}

/// The floating tab bar sits over the scroll view, so a scrolling page owes it
/// this much clearance or its last control is unreachable.
let novaTabBarInset = NovaDimensionToken.layoutScrollBottomInset.value - NovaDimensionToken.spaceScreenX.value

struct NovaText: View {
    let text: String
    var style: NovaTypeToken = .body
    var color: Color?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.novaTypographyFamily) private var typographyFamily
    @ScaledMetric(relativeTo: .body) private var scale = 1.0

    var body: some View {
        let spec = NovaFont.spec(style)
        Text(verbatim: text)
            .font(.custom(typographyFamily.fontName(for: spec.weight) ?? spec.fontName,
                         size: spec.size, relativeTo: .body))
            .tracking(spec.tracking * scale)
            // Native font leading differs from RN lineHeight; visual acceptance remains open.
            .lineSpacing(max(0, spec.lineHeight - spec.size) * scale)
            .foregroundStyle(NovaFont.ink(color, role: style, scheme: scheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct NovaCard<Content: View>: View {
    var padding: CGFloat = 11
    var border: Color = .clear
    var tint: Color? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isNovaPopup) private var inPopup

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: NovaDimensionToken.radiusCard.value)
                    .fill(tint ?? NovaPopupStyle.controlBackground(in: scheme, inPopup: inPopup))
                    .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 2)
            }
            .overlay(RoundedRectangle(cornerRadius: NovaDimensionToken.radiusCard.value)
                .strokeBorder(border, lineWidth: 1.5))
    }
}

/// Every İSGADA root and pushed destination owns an opaque canvas, not a system-white page.
/// White belongs to NovaCard/content surfaces; List/Form defaults must not cover the canvas.
struct NovaPageSurface<Content: View>: View {
    var onEdgeBack: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isNovaPopup) private var isNovaPopup
    @Environment(\.novaCanvasStyle) private var canvasStyle
    @Environment(\.novaHasHeader) private var hasHeader

    init(onEdgeBack: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.onEdgeBack = onEdgeBack
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hasHeader && !isNovaPopup { NovaStandaloneHeader() }
            content().environment(\.novaHasHeader, true)
                .frame(maxWidth: .infinity, maxHeight: isNovaPopup ? nil : .infinity, alignment: .topLeading)
        }
            .font(NovaFont.font(.body))
            .foregroundStyle(NovaColorToken.text.color(in: scheme))
            .tint(NovaColorToken.text.color(in: scheme))
            .scrollContentBackground(.hidden)
            .background((isNovaPopup ? NovaPopupStyle.background(in: scheme) : canvasStyle.color(in: scheme)).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar, .tabBar)
            .novaEdgeBackGesture(isEnabled: !isNovaPopup && onEdgeBack != nil) {
                onEdgeBack?()
            }
    }
}

/// Mirrors the native iPhone back gesture for pages that own custom routing.
/// It only accepts a rightward drag that begins at the physical left edge, so
/// charts, horizontal lists, date controls and ordinary scrolling keep their
/// own gestures.
private struct NovaEdgeBackGestureModifier: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 14, coordinateSpace: .global)
                .onEnded { value in
                    guard isEnabled,
                          value.startLocation.x <= 28,
                          value.translation.width >= 72,
                          value.predictedEndTranslation.width >= 96,
                          abs(value.translation.width) > abs(value.translation.height) * 1.25
                    else { return }
                    action()
                },
            including: isEnabled ? .all : .none
        )
    }
}

extension View {
    func novaEdgeBackGesture(isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(NovaEdgeBackGestureModifier(isEnabled: isEnabled, action: action))
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
                .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(NovaPressStyle()).disabled(!isEnabled)
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
                NovaText(text: title, style: .screenTitle)
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
    var compact = false
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
        .padding(.vertical, compact ? 4 : 6).padding(.horizontal, compact ? 9 : 10)
        .frame(minHeight: compact ? 30 : 0)
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
    var compact = false
    var loadingDescription = RDLocalization.string("localizable.nova.components.loading.description", table: .localizable, fallback: "İşlem sürüyor")
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isNovaPopup) private var inPopup

    private var palette: (Color, Color) {
        if !isEnabled || isLoading {
            return (NovaColorToken.surfaceMuted.color(in: scheme), NovaColorToken.textSecondary.color(in: scheme))
        }
        switch variant {
        case .primary:
            // Recorded accessibility adaptation: white on #2ed256 is only ~2:1.
            return (NovaColorToken.accent.color(in: scheme), NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
        case .surface: return (NovaPopupStyle.controlBackground(in: scheme, inPopup: inPopup), NovaColorToken.text.color(in: scheme))
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
                    Image(systemName: symbol).font(.system(size: compact ? 14 : (inPopup ? 16 : 18), weight: .regular)).foregroundStyle(palette.1).accessibilityHidden(true)
                }
                NovaText(text: label, style: (compact || inPopup) ? .buttonSm : .button, color: palette.1)
                    .multilineTextAlignment(.center).lineLimit((compact || inPopup) ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, (compact || inPopup) ? 12 : 18).padding(.vertical, compact ? 8 : (inPopup ? 10 : 12))
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 44 : (inPopup ? 46 : 52))
            .background(palette.0, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(NovaPressStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: isLoading ? loadingDescription : ""))
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

/// Shared loading state for İSGADA pages. Motion respects the accessibility setting.
struct NovaLoadingView: View {
    var message: String = RDLocalization.string("localizable.nova.components.loading", table: .localizable, fallback: "Yükleniyor…")
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(NovaColorToken.text.color(in: scheme).opacity(0.08), lineWidth: 2)
                Circle().trim(from: 0, to: 0.22)
                    .stroke(NovaColorToken.text.color(in: scheme).opacity(0.65), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(rotating ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 1.8).repeatForever(autoreverses: false), value: rotating)
                NovaIcon(symbol: "viewfinder", size: 24)
            }.frame(width: 64, height: 64).accessibilityHidden(true)
            NovaText(text: message, style: .metaQuiet)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nova.loading")
        .onAppear { rotating = !reduceMotion }
        .onChange(of: reduceMotion) { rotating = !$0 }
    }
}
