import SwiftUI

// MARK: - Spring & motion

extension Animation {
    static var obSpring: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.36) }
    static var obSpringSlow: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.7) }
    static var obSnap: Animation { .timingCurve(0.32, 0.72, 0, 1, duration: 0.1) }
}

// MARK: - Stage entry modifier (rises in from below with delay)

struct OBStageModifier: ViewModifier {
    let delay: Double
    @State private var shown: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 20)
            .onAppear {
                withAnimation(.obSpring.delay(delay)) { shown = true }
            }
    }
}

extension View {
    func obStage(delay: Double = 0) -> some View { modifier(OBStageModifier(delay: delay)) }
}

// MARK: - Adaptive screen scaffold

/// Onboarding ekranlarının kendi container ölçüsünden beslenen ortak iskeleti.
/// Header sabit kalır, uzun içerik kayar ve ana aksiyon home indicator ile çakışmaz.
struct OBScreenScaffold<Header: View, Content: View, Footer: View>: View {
    var background: Color = .rdPaper
    private let header: (RDLayoutProfile) -> Header
    private let content: (RDLayoutProfile) -> Content
    private let footer: (RDLayoutProfile) -> Footer

    init(
        background: Color = .rdPaper,
        @ViewBuilder header: @escaping (RDLayoutProfile) -> Header,
        @ViewBuilder content: @escaping (RDLayoutProfile) -> Content,
        @ViewBuilder footer: @escaping (RDLayoutProfile) -> Footer
    ) {
        self.background = background
        self.header = header
        self.content = content
        self.footer = footer
    }

    var body: some View {
        RDAdaptiveContainer { profile in
            VStack(spacing: 0) {
                header(profile)

                ScrollView(showsIndicators: false) {
                    content(profile)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, profile.sectionSpacing)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer(profile)
                    .padding(.horizontal, profile.horizontalPadding)
                    .padding(.vertical, profile.isCompact ? 8 : 12)
                    .background(background.shadow(.drop(color: .black.opacity(0.06), radius: 8, y: -3)))
            }
            .background(background)
        }
    }
}

// MARK: - Top bar (back + progress)

struct OBTopBar: View {
    var showBack: Bool = true
    var step: Int               // 1-indexed
    var total: Int = 5
    var trailingLabel: String?  // "01 / 05" or "HAZIR"
    var trailingDone: Bool = false
    var onBack: (() -> Void)?
    @Environment(\.rdLayoutProfile) private var layoutProfile

    var body: some View {
        HStack(spacing: 14) {
            if showBack, let onBack {
                Button {
                    OBHaptic.soft(); onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(RDTypography.font(size: RDFontScale.size(17), weight: .semibold))
                        .foregroundStyle(Color.rdOnyx)
                        .frame(width: 40, height: 40)
                        .background(Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.leading, -8)
            } else {
                Color.clear.frame(width: 32, height: 40)
            }

            OBProgress(step: step, total: total)
                .frame(height: 18)

            if let trailingLabel {
                if trailingDone {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(RDTypography.font(size: RDFontScale.size(10), weight: .bold))
                        Text(trailingLabel)
                            .font(RDTypography.font(size: RDFontScale.size(11), weight: .semibold))
                            .tracking(0.6)
                    }
                    .foregroundStyle(Color.rdGreenDark)
                } else {
                    Text(trailingLabel)
                        .font(RDTypography.font(size: RDFontScale.size(11), weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Color.rdSlate)
                }
            }
        }
        .padding(.horizontal, layoutProfile.horizontalPadding)
        .padding(.top, layoutProfile.isCompact ? 8 : 16)
        .padding(.bottom, layoutProfile.isCompact ? 12 : 20)
    }
}

// MARK: - Progress segments

struct OBProgress: View {
    let step: Int   // 1-indexed
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                segment(index: i)
            }
        }
    }

    @ViewBuilder
    private func segment(index: Int) -> some View {
        let isDone = (index + 1) < step
        let isCurrent = (index + 1) == step
        ZStack(alignment: .leading) {
            Capsule().fill(Color.rdOnyx.opacity(0.08))
            GeometryReader { geo in
                Capsule()
                    .fill(isDone ? Color.rdGreen : Color.rdOnyx)
                    .frame(width: (isDone || isCurrent) ? geo.size.width : 0)
                    .animation(.obSpringSlow, value: step)
            }
            if isDone {
                ZStack {
                    Circle().fill(Color.rdGreen)
                    Image(systemName: "checkmark")
                        .font(RDTypography.font(size: RDFontScale.size(7), weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.rdPaper, lineWidth: 2))
                .offset(x: -8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Hero illustration tile

enum OBHeroTint {
    case neutral, green, warm, cool, dusk

    var bg: LinearGradient {
        switch self {
        case .neutral:
            return LinearGradient(colors: [Color.white, Color.rdCloud, Color.rdFog], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .green:
            return LinearGradient(colors: [Color.white, Color(hex: "#F0FAF3"), Color(hex: "#E1F4E8")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .warm:
            return LinearGradient(colors: [Color.white, Color(hex: "#FCF6EE"), Color(hex: "#F7EDDA")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .cool:
            return LinearGradient(colors: [Color.white, Color(hex: "#F1F4F9"), Color(hex: "#E6ECF4")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dusk:
            return LinearGradient(colors: [Color(hex: "#1B1E20"), Color(hex: "#131516"), Color(hex: "#0B0D0E")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var border: Color {
        switch self {
        case .neutral: return Color.black.opacity(0.05)
        case .green: return Color.rdGreen.opacity(0.14)
        case .warm: return Color.rdHigh.opacity(0.14)
        case .cool: return Color.rdInfo.opacity(0.14)
        case .dusk: return Color.white.opacity(0.08)
        }
    }
}

struct OBHeroTile<Content: View>: View {
    var tint: OBHeroTint = .neutral
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(tint.bg)
            RoundedRectangle(cornerRadius: 20).stroke(tint.border, lineWidth: 1)
            content
                .padding(10)
        }
        .frame(width: 108, height: 80)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

// MARK: - Card / select row

struct OBCard<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    var multi: Bool = false
    var accessibilityID: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        multi: Bool = false,
        accessibilityID: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.multi = multi
        self.accessibilityID = accessibilityID
        self.leading = leading()
        self.trailing = trailing()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(RDTypography.font(size: RDFontScale.size(16), weight: .semibold))
                        .foregroundStyle(Color.rdOnyx)
                    if let subtitle {
                        Text(subtitle)
                            .font(RDTypography.font(size: RDFontScale.size(13)))
                            .foregroundStyle(Color.rdSlate)
                    }
                }
                Spacer(minLength: 0)
                indicator
                trailing
            }
            .padding(isSelected ? 15 : 16)
            .frame(minHeight: 64)
            .background(Color.rdWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.rdOnyx : Color.rdOnyx.opacity(0.06),
                            lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(isSelected ? 0.08 : 0.05), radius: isSelected ? 14 : 8, y: isSelected ? 8 : 4)
        }
        .buttonStyle(OBPressStyle())
        .accessibilityIdentifier(accessibilityID ?? "ob.card.\(obIdentifierSlug(title))")
    }

    @ViewBuilder
    private var indicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: multi ? 7 : 999, style: .continuous)
                .fill(isSelected ? Color.rdOnyx : Color.clear)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: multi ? 7 : 999, style: .continuous)
                        .stroke(isSelected ? Color.rdOnyx : Color.rdOnyx.opacity(0.18), lineWidth: 1.5)
                )
            if isSelected {
                Image(systemName: "checkmark")
                    .font(RDTypography.font(size: RDFontScale.size(12), weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.obSpring, value: isSelected)
    }
}

// MARK: - Press style

extension OBCard where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        multi: Bool = false,
        accessibilityID: String? = nil,
        @ViewBuilder leading: () -> Leading,
        action: @escaping () -> Void
    ) {
        self.init(title: title, subtitle: subtitle, isSelected: isSelected, multi: multi,
                  accessibilityID: accessibilityID, leading: leading, trailing: { EmptyView() }, action: action)
    }
}

struct OBPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.obSnap, value: configuration.isPressed)
    }
}

// MARK: - Primary button

struct OBPrimaryButton: View {
    let title: String
    var trailingIcon: String? = "arrow.right"
    var enabled: Bool = true
    var isLoading: Bool = false
    var loadingTitle: String?
    var style: Style = .onyx
    var accessibilityID: String?
    let action: () -> Void

    enum Style { case onyx, green }

    @State private var arrowOffset: CGFloat = -6
    @State private var arrowOpacity: Double = 0

    var body: some View {
        let resolvedAccessibilityID = accessibilityID ?? "ob.primary.\(obIdentifierSlug(title))"
        let displayTitle = isLoading ? (loadingTitle ?? title) : title

        Button {
            if enabled && !isLoading { OBHaptic.light(); action() }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(textColor)
                }

                Text(displayTitle)
                    .font(RDTypography.font(size: RDFontScale.size(16), weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let trailingIcon, !isLoading {
                    Image(systemName: trailingIcon)
                        .font(RDTypography.font(size: RDFontScale.size(15), weight: .semibold))
                        .offset(x: enabled ? arrowOffset : 0)
                        .opacity(enabled ? arrowOpacity : 1)
                }
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(minHeight: 56)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: shadowColor, radius: 16, y: 6)
            .opacity(enabled ? 1 : 1)
        }
        .buttonStyle(OBPressStyle())
        .disabled(!enabled || isLoading)
        .accessibilityLabel(displayTitle)
        .accessibilityIdentifier(resolvedAccessibilityID)
        .onAppear {
            guard enabled, !isLoading else { return }
            animateArrow()
        }
        .onChange(of: enabled) { newValue in
            if newValue, !isLoading { animateArrow() }
        }
        .onChange(of: isLoading) { newValue in
            if !newValue, enabled { animateArrow() }
        }
    }

    private func animateArrow() {
        Task { @MainActor in
            while !Task.isCancelled, enabled {
                arrowOffset = -6
                arrowOpacity = 0
                withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.4)) {
                    arrowOffset = 0
                    arrowOpacity = 1
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
                withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.6)) {
                    arrowOffset = 10
                    arrowOpacity = 0
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    private var bgColor: Color {
        if !enabled { return Color.rdOnyx.opacity(0.08) }
        switch style {
        case .onyx: return Color.rdOnyx
        case .green: return Color.rdGreen
        }
    }

    private var textColor: Color {
        if !enabled { return Color.rdOnyx.opacity(0.35) }
        return .white
    }

    private var shadowColor: Color {
        if !enabled { return .clear }
        switch style {
        case .onyx: return Color.rdOnyx.opacity(0.14)
        case .green: return Color.rdGreen.opacity(0.32)
        }
    }
}

private func obIdentifierSlug(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .autoupdatingCurrent)
        .lowercased(with: Locale(identifier: "en_US_POSIX"))
        .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
}

// MARK: - Footer container

struct OBFooter<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.rdLayoutProfile) private var layoutProfile
    var body: some View {
        VStack(spacing: 12) { content }
            .padding(.horizontal, layoutProfile.horizontalPadding)
            .padding(.top, layoutProfile.isCompact ? 8 : 12)
            .padding(.bottom, layoutProfile.isCompact ? 12 : 20)
    }
}

// MARK: - Selection counter

struct OBSelectionCounter: View {
    let count: Int
    let suffix: String   // RDLocalization.string("onboarding.obcomponents.sinif.secildi.af68ecbf", table: .onboarding, fallback: "sınıf seçildi") / RDLocalization.string("onboarding.obcomponents.sektor.secildi.985a1dab", table: .onboarding, fallback: "sektör seçildi")
    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(RDTypography.font(size: RDFontScale.size(13)))
                .foregroundStyle(Color.rdSlate)
            HStack(spacing: 4) {
                Text("\(count)")
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.rdOnyx)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                Text(suffix)
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .medium))
                    .foregroundStyle(Color.rdSlate)
            }
        }
        .opacity(count > 0 ? 1 : 0)
        .animation(.obSpring, value: count)
        .onChange(of: count) { _ in
            withAnimation(.obSpring) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                withAnimation(.obSpring) { pulse = false }
            }
        }
    }
}

// MARK: - Hero illustrations (SF Symbol compositions standing in for SVG)

struct OBHeroSplashChar: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "#EAF8EE")).frame(width: 88, height: 88)
            Image(systemName: "person.fill.badge.plus")
                .font(RDTypography.font(size: RDFontScale.size(36), weight: .bold))
                .foregroundStyle(Color.rdGreen)
        }
    }
}

struct OBHeroCertificate: View {
    var body: some View {
        // Hard hat illustration ported from design SVG (viewBox 116x92).
        Canvas { ctx, size in
            let sx = size.width / 116
            let sy = size.height / 92
            ctx.scaleBy(x: sx, y: sy)

            let orange = Color(hex: "#C76A00")
            let amber = Color(hex: "#FFB300")
            let dark = Color(hex: "#9A5300")
            let shadow = Color(hex: "#0B0D0E")

            // Shadow under helmet
            ctx.fill(Path(ellipseIn: CGRect(x: 26, y: 75, width: 64, height: 6)),
                     with: .color(shadow.opacity(0.08)))

            // Hat body (back/dark side)
            var hat = Path()
            hat.move(to: CGPoint(x: 22, y: 60))
            hat.addQuadCurve(to: CGPoint(x: 58, y: 24), control: CGPoint(x: 22, y: 30))
            hat.addQuadCurve(to: CGPoint(x: 94, y: 60), control: CGPoint(x: 94, y: 30))
            hat.addLine(to: CGPoint(x: 96, y: 64))
            hat.addQuadCurve(to: CGPoint(x: 89, y: 70), control: CGPoint(x: 96, y: 70))
            hat.addLine(to: CGPoint(x: 27, y: 70))
            hat.addQuadCurve(to: CGPoint(x: 20, y: 64), control: CGPoint(x: 20, y: 70))
            hat.closeSubpath()
            ctx.fill(hat, with: .color(orange))

            // Highlight top
            var hl = Path()
            hl.move(to: CGPoint(x: 28, y: 50))
            hl.addQuadCurve(to: CGPoint(x: 58, y: 28), control: CGPoint(x: 30, y: 32))
            hl.addQuadCurve(to: CGPoint(x: 88, y: 50), control: CGPoint(x: 86, y: 32))
            hl.addQuadCurve(to: CGPoint(x: 58, y: 32), control: CGPoint(x: 88, y: 38))
            hl.addQuadCurve(to: CGPoint(x: 28, y: 50), control: CGPoint(x: 28, y: 38))
            hl.closeSubpath()
            ctx.fill(hl, with: .color(amber.opacity(0.55)))

            // Ridge
            ctx.fill(Path(roundedRect: CGRect(x: 56, y: 24, width: 4, height: 38), cornerRadius: 1.6),
                     with: .color(dark))

            // Brim shadow
            ctx.fill(Path(roundedRect: CGRect(x: 20, y: 62, width: 76, height: 3), cornerRadius: 1.5),
                     with: .color(dark.opacity(0.6)))

            // Side vents
            ctx.fill(Path(ellipseIn: CGRect(x: 37, y: 44, width: 6, height: 12)),
                     with: .color(dark.opacity(0.5)))
            ctx.fill(Path(ellipseIn: CGRect(x: 73, y: 44, width: 6, height: 12)),
                     with: .color(dark.opacity(0.5)))

            // Front logo plate
            ctx.fill(Path(roundedRect: CGRect(x: 50, y: 50, width: 16, height: 9), cornerRadius: 2),
                     with: .color(.white.opacity(0.92)))
            ctx.fill(Path(roundedRect: CGRect(x: 52, y: 53, width: 12, height: 1.4), cornerRadius: 0.7),
                     with: .color(shadow))
            ctx.fill(Path(roundedRect: CGRect(x: 52, y: 56, width: 9, height: 1.2), cornerRadius: 0.6),
                     with: .color(shadow.opacity(0.5)))

            // Cert star badge top-right
            ctx.fill(Path(ellipseIn: CGRect(x: 82, y: 8, width: 22, height: 22)),
                     with: .color(Color.rdGreen))
            ctx.stroke(
                Path(ellipseIn: CGRect(x: 82, y: 8, width: 22, height: 22)),
                with: .color(.white),
                style: StrokeStyle(lineWidth: 1.5, dash: [1.5, 2.2])
            )
            var star = Path()
            let cx: CGFloat = 93, cy: CGFloat = 19
            star.move(to: CGPoint(x: cx, y: cy - 5.5))
            star.addLine(to: CGPoint(x: cx + 1.4, y: cy - 2))
            star.addLine(to: CGPoint(x: cx + 5, y: cy - 1.7))
            star.addLine(to: CGPoint(x: cx + 2.2, y: cy + 0.6))
            star.addLine(to: CGPoint(x: cx + 3.1, y: cy + 4))
            star.addLine(to: CGPoint(x: cx, y: cy + 2.2))
            star.addLine(to: CGPoint(x: cx - 3.1, y: cy + 4))
            star.addLine(to: CGPoint(x: cx - 2.2, y: cy + 0.6))
            star.addLine(to: CGPoint(x: cx - 5, y: cy - 1.7))
            star.addLine(to: CGPoint(x: cx - 1.4, y: cy - 2))
            star.closeSubpath()
            ctx.fill(star, with: .color(.white))
        }
        .frame(width: 88, height: 64)
    }
}

struct OBHeroHazard: View {
    var body: some View {
        HStack(spacing: -8) {
            triangle(.rdLow, size: 24)
            triangle(.rdHigh, size: 34)
            triangle(.rdCritical, size: 44)
        }
    }

    private func triangle(_ c: Color, size: CGFloat) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(RDTypography.font(size: size, weight: .bold))
            .foregroundStyle(c)
    }
}

struct OBHeroSector: View {
    var body: some View {
        // Skyline of sectors (crane, factory, office tower, hospital) — SVG port viewBox 116x92.
        Canvas { ctx, size in
            let sx = size.width / 116
            let sy = size.height / 92
            ctx.scaleBy(x: sx, y: sy)

            let dark = Color(hex: "#0B0D0E")
            let factoryFill = Color(hex: "#1B1E20")
            let officeFill = Color(hex: "#2A2D2F")
            let amber = Color(hex: "#FFB300")
            let green = Color.rdGreen
            let greenWin = Color(hex: "#4FE07E")
            let blueWin = Color(hex: "#2F6FED")
            let red = Color.rdCritical
            let paper = Color(hex: "#F8F7F3")

            // Sun
            ctx.fill(Path(ellipseIn: CGRect(x: 83, y: 13, width: 18, height: 18)),
                     with: .color(amber.opacity(0.22)))
            ctx.fill(Path(ellipseIn: CGRect(x: 86, y: 16, width: 12, height: 12)),
                     with: .color(amber.opacity(0.55)))

            // Crane (background, stroked)
            let craneStyle = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            var crane = Path()
            crane.move(to: CGPoint(x: 14, y: 78)); crane.addLine(to: CGPoint(x: 14, y: 30))
            crane.move(to: CGPoint(x: 14, y: 30)); crane.addLine(to: CGPoint(x: 46, y: 30))
            crane.move(to: CGPoint(x: 14, y: 30)); crane.addLine(to: CGPoint(x: 6, y: 38))
            crane.move(to: CGPoint(x: 38, y: 30)); crane.addLine(to: CGPoint(x: 38, y: 44))
            ctx.stroke(crane, with: .color(dark), style: craneStyle)
            ctx.fill(Path(CGRect(x: 36, y: 44, width: 4, height: 3)), with: .color(dark))
            var diag = Path()
            diag.move(to: CGPoint(x: 14, y: 38)); diag.addLine(to: CGPoint(x: 20, y: 30))
            diag.move(to: CGPoint(x: 14, y: 44)); diag.addLine(to: CGPoint(x: 26, y: 30))
            ctx.stroke(diag, with: .color(dark.opacity(0.5)), style: craneStyle)

            // Factory
            var fac = Path()
            fac.move(to: CGPoint(x: 26, y: 78))
            fac.addLine(to: CGPoint(x: 26, y: 56))
            fac.addLine(to: CGPoint(x: 40, y: 56))
            fac.addLine(to: CGPoint(x: 40, y: 50))
            fac.addLine(to: CGPoint(x: 52, y: 56))
            fac.addLine(to: CGPoint(x: 52, y: 78))
            fac.closeSubpath()
            ctx.fill(fac, with: .color(factoryFill))
            // Windows
            let facWins: [(CGFloat, CGFloat, Double)] = [
                (30, 62, 0.9), (35, 62, 0.4), (44, 64, 0.9),
                (30, 70, 0.4), (44, 70, 0.9)
            ]
            for w in facWins {
                ctx.fill(Path(CGRect(x: w.0, y: w.1, width: 3, height: 3)),
                         with: .color(amber.opacity(w.2)))
            }
            // Chimney + smoke
            ctx.fill(Path(CGRect(x: 42, y: 44, width: 4, height: 12)), with: .color(dark))
            ctx.fill(Path(ellipseIn: CGRect(x: 41.6, y: 37.6, width: 4.8, height: 4.8)),
                     with: .color(.white.opacity(0.85)))
            ctx.fill(Path(ellipseIn: CGRect(x: 45.7, y: 34.2, width: 3.6, height: 3.6)),
                     with: .color(.white.opacity(0.7)))
            ctx.fill(Path(ellipseIn: CGRect(x: 40.6, y: 32.6, width: 2.8, height: 2.8)),
                     with: .color(.white.opacity(0.55)))

            // Office tower
            ctx.fill(Path(CGRect(x: 56, y: 40, width: 20, height: 38)), with: .color(officeFill))
            ctx.fill(Path(CGRect(x: 65, y: 32, width: 2, height: 8)), with: .color(dark))
            ctx.fill(Path(ellipseIn: CGRect(x: 64.6, y: 28.6, width: 2.8, height: 2.8)),
                     with: .color(green))
            // Window grid (4 rows × 3 cols)
            let opacities: [Double] = [0.85, 0.45, 0.85, 0.45, 0.85, 0.45, 0.85, 0.45, 0.85, 0.45, 0.85, 0.45]
            var idx = 0
            for yRow in stride(from: CGFloat(44), through: 62, by: 6) {
                for xCol in [CGFloat(59), 64, 69] {
                    ctx.fill(Path(CGRect(x: xCol, y: yRow, width: 3, height: 3)),
                             with: .color(greenWin.opacity(opacities[idx])))
                    idx += 1
                }
            }

            // Hospital
            ctx.fill(Path(CGRect(x: 80, y: 50, width: 22, height: 28)), with: .color(paper))
            ctx.stroke(Path(CGRect(x: 80, y: 50, width: 22, height: 28)),
                       with: .color(dark), lineWidth: 1.2)
            // Red cross
            ctx.fill(Path(CGRect(x: 88, y: 56, width: 6, height: 2)), with: .color(red))
            ctx.fill(Path(CGRect(x: 90, y: 54, width: 2, height: 6)), with: .color(red))
            // Hospital windows
            for col in [CGFloat(83), 88, 93, 98] {
                for row in [CGFloat(65), 71] {
                    ctx.fill(Path(CGRect(x: col, y: row, width: 3, height: 3)),
                             with: .color(blueWin.opacity(0.4)))
                }
            }

            // Ground line + shadow
            var ground = Path()
            ground.move(to: CGPoint(x: 4, y: 78.5)); ground.addLine(to: CGPoint(x: 112, y: 78.5))
            ctx.stroke(ground, with: .color(dark), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: 10, y: 80, width: 96, height: 4)),
                     with: .color(dark.opacity(0.08)))
        }
        .frame(width: 88, height: 64)
    }
}

struct OBHeroFrequency: View {
    var body: some View {
        // Weekly calendar with rhythm dots — SVG port viewBox 116x92.
        Canvas { ctx, size in
            let sx = size.width / 116
            let sy = size.height / 92
            ctx.scaleBy(x: sx, y: sy)

            let dark = Color(hex: "#0B0D0E")
            let green = Color.rdGreen
            let brightGreen = Color(hex: "#4FE07E")

            // Ambient
            ctx.fill(Path(ellipseIn: CGRect(x: 102.8, y: 18.8, width: 2.4, height: 2.4)),
                     with: .color(green.opacity(0.45)))
            ctx.fill(Path(ellipseIn: CGRect(x: 99.2, y: 73.2, width: 1.6, height: 1.6)),
                     with: .color(dark.opacity(0.2)))

            // Calendar shadow back
            ctx.fill(Path(roundedRect: CGRect(x: 14, y: 22, width: 68, height: 58), cornerRadius: 8),
                     with: .color(dark.opacity(0.08)))

            // Calendar main card
            ctx.fill(Path(roundedRect: CGRect(x: 12, y: 18, width: 68, height: 58), cornerRadius: 8),
                     with: .color(.white))
            ctx.stroke(Path(roundedRect: CGRect(x: 12, y: 18, width: 68, height: 58), cornerRadius: 8),
                       with: .color(dark.opacity(0.08)), lineWidth: 0.8)

            // Header bar (dark, rounded top only — draw rect with top-rounded clip via clip path)
            var header = Path()
            header.move(to: CGPoint(x: 12, y: 26))
            header.addArc(center: CGPoint(x: 20, y: 26), radius: 8, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            header.addLine(to: CGPoint(x: 72, y: 18))
            header.addArc(center: CGPoint(x: 72, y: 26), radius: 8, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            header.addLine(to: CGPoint(x: 80, y: 32))
            header.addLine(to: CGPoint(x: 12, y: 32))
            header.closeSubpath()
            ctx.fill(header, with: .color(dark))

            // Binder rings
            ctx.fill(Path(roundedRect: CGRect(x: 22, y: 12, width: 3, height: 12), cornerRadius: 1.5),
                     with: .color(Color(hex: "#1F2224")))
            ctx.fill(Path(roundedRect: CGRect(x: 68, y: 12, width: 3, height: 12), cornerRadius: 1.5),
                     with: .color(Color(hex: "#1F2224")))

            // Title strip in header
            ctx.fill(Path(roundedRect: CGRect(x: 20, y: 24, width: 14, height: 2), cornerRadius: 1),
                     with: .color(.white.opacity(0.85)))

            // Empty (dim) day dots
            let dim: [(CGFloat, CGFloat)] = [
                (20, 50), (40, 50), (60, 50), (70, 50),
                (30, 60), (50, 60), (70, 60),
                (20, 70), (40, 70)
            ]
            for d in dim {
                ctx.fill(Path(ellipseIn: CGRect(x: d.0 - 2, y: d.1 - 2, width: 4, height: 4)),
                         with: .color(dark.opacity(0.12)))
            }

            // Active inspection days
            let active: [(CGFloat, CGFloat, CGFloat)] = [
                (30, 50, 3.2), (50, 50, 3.2),
                (20, 60, 3.2), (40, 60, 3.2), (60, 60, 3.2),
                (50, 70, 3.2), (60, 70, 3.2), (70, 70, 3.2)
            ]
            for a in active {
                ctx.fill(Path(ellipseIn: CGRect(x: a.0 - a.2, y: a.1 - a.2, width: a.2 * 2, height: a.2 * 2)),
                         with: .color(green))
            }

            // Today highlighted (dark ring + bright green core)
            ctx.fill(Path(ellipseIn: CGRect(x: 25.8, y: 65.8, width: 8.4, height: 8.4)),
                     with: .color(dark))
            ctx.fill(Path(ellipseIn: CGRect(x: 27.8, y: 67.8, width: 4.4, height: 4.4)),
                     with: .color(brightGreen))
            // Pulse ring on today
            ctx.stroke(Path(ellipseIn: CGRect(x: 24, y: 64, width: 12, height: 12)),
                       with: .color(dark.opacity(0.25)), lineWidth: 1)

            // Clock badge top-right (translate 82, 44)
            ctx.fill(Path(ellipseIn: CGRect(x: 83, y: 45, width: 26, height: 26)),
                     with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: 83, y: 45, width: 26, height: 26)),
                       with: .color(dark), lineWidth: 1.4)
            // Green arc (40 of 100 dasharray, rotated -90)
            var arc = Path()
            arc.addArc(center: CGPoint(x: 96, y: 58), radius: 13,
                       startAngle: .degrees(-90), endAngle: .degrees(40),
                       clockwise: false)
            ctx.stroke(arc, with: .color(green),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            // Clock hands
            var hands = Path()
            hands.move(to: CGPoint(x: 96, y: 51)); hands.addLine(to: CGPoint(x: 96, y: 58))
            hands.addLine(to: CGPoint(x: 101, y: 61))
            ctx.stroke(hands, with: .color(dark),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: 94.9, y: 56.9, width: 2.2, height: 2.2)),
                     with: .color(dark))

            // Tick badge bottom-left
            ctx.fill(Path(ellipseIn: CGRect(x: 3, y: 57, width: 14, height: 14)),
                     with: .color(green))
            var check = Path()
            check.move(to: CGPoint(x: 7, y: 64))
            check.addLine(to: CGPoint(x: 9, y: 66))
            check.addLine(to: CGPoint(x: 13, y: 62))
            ctx.stroke(check, with: .color(.white),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 88, height: 64)
    }
}

// RDLocalization.string("onboarding.obcomponents.planin.hazir.simdi.kilitleyelim.b6f352e1", table: .onboarding, fallback: "Planın hazır, şimdi kilitleyelim") metaforu:
// Kilit sürekli açılıp kapanan döngü + iç yeşil check her kapanışta belirir.
struct OBHeroAuth: View {
    @State private var isClosed: Bool = false
    @State private var checkScale: CGFloat = 0
    @State private var checkOpacity: Double = 0

    var body: some View {
        ZStack {
            Image(systemName: isClosed ? "lock.fill" : "lock.open.fill")
                .font(RDTypography.font(size: RDFontScale.size(46), weight: .bold))
                .foregroundStyle(Color.rdOnyx)
                .id(isClosed)

            Image(systemName: "checkmark")
                .font(RDTypography.font(size: RDFontScale.size(16), weight: .heavy))
                .foregroundStyle(Color(hex: "#4FE07E"))
                .scaleEffect(checkScale)
                .opacity(checkOpacity)
                .offset(y: 6)
        }
        .onAppear { runLoop() }
    }

    private func runLoop() {
        Task {
            while !Task.isCancelled {
                // Closed phase
                await MainActor.run {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                        isClosed = true
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                await MainActor.run {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                        checkScale = 1
                        checkOpacity = 1
                    }
                }
                try? await Task.sleep(nanoseconds: 1_800_000_000)

                // Open phase
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        checkScale = 0.6
                        checkOpacity = 0
                    }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                        isClosed = false
                    }
                }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            }
        }
    }
}
