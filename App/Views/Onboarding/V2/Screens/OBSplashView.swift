import SwiftUI
import UIKit

struct OBSplashView: View {
    let onNext: () -> Void
    var onSkip: (() -> Void)?

    init(onNext: @escaping () -> Void, onSkip: (() -> Void)? = nil) {
        self.onNext = onNext
        self.onSkip = onSkip
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = OBSplashMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            ZStack(alignment: .bottom) {
                OBSplashColor.white
                    .ignoresSafeArea()

                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("onboarding.splash")

                VStack(spacing: 0) {
                    OBSplashHero(metrics: metrics)
                        .frame(height: metrics.heroHeight)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                OBSplashBottomSheet(metrics: metrics, onNext: onNext, onSkip: onSkip)
                    .frame(height: metrics.sheetHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct OBSplashMetrics {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    private let designWidth: CGFloat = 402
    private let designHeight: CGFloat = 874

    var width: CGFloat { size.width }
    var height: CGFloat { size.height }
    var scale: CGFloat { min(max(width / designWidth, 0.88), 1.12) }
    var heightScale: CGFloat { min(max(height / designHeight, 0.86), 1.12) }
    var overlap: CGFloat { 64 * scale }
    var sheetHeight: CGFloat { min(max(273 * heightScale, 252), height * 0.39) }
    var heroHeight: CGFloat { max(height - sheetHeight + overlap, 430 * scale) }
    var phoneWidth: CGFloat { min(250 * scale, width * 0.64, heroHeight * 0.54) }
}

private enum OBSplashColor {
    static let white = Color(hex: "#FFFFFF")
    static let hero = Color(hex: "#EEF0F2")
    static let cta = Color(hex: "#111418")
    static let title = Color(hex: "#0E1116")
    static let slate = Color(hex: "#6B7280")
    static let dot = Color(hex: "#A4ABB5")
    static let red = Color(hex: "#E5484D")
    static let redSoft = Color(hex: "#FDECEC")
    static let amber = Color(hex: "#F59E0B")
    static let amberSoft = Color(hex: "#FFF4E5")
}

private struct OBSplashHero: View {
    let metrics: OBSplashMetrics

    var body: some View {
        let phoneWidth = metrics.phoneWidth
        let phoneHeight = phoneWidth * 462 / 250
        let phoneTop = max(92 * metrics.scale, metrics.heroHeight - phoneHeight)
        let detectionWidth = 109 * metrics.scale
        let preparingWidth = 166 * metrics.scale
        let chipHeight = 42 * metrics.scale

        ZStack(alignment: .topLeading) {
            OBSplashColor.hero

            RadialGradient(
                colors: [Color.white.opacity(0.42), Color.white.opacity(0)],
                center: UnitPoint(x: 0.5, y: 0.12),
                startRadius: 0,
                endRadius: max(metrics.width, metrics.heroHeight) * 0.62
            )

            Image("OBSplashSafetyPattern")
                .resizable(resizingMode: .tile)
                .frame(width: metrics.width, height: metrics.heroHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            OBSplashPhoneFrame(width: phoneWidth)
                .position(x: metrics.width * 0.5, y: phoneTop + phoneHeight / 2)

            OBSplashFloatingChip(
                title: "12 Tehlike",
                subtitle: "tespit edildi",
                accent: OBSplashColor.red,
                iconBackground: OBSplashColor.redSoft,
                kind: .warning,
                accessibilityID: "onboarding.splash.chip.detection"
            )
            .frame(width: detectionWidth, height: chipHeight)
            .rotationEffect(.degrees(-5))
            .position(
                x: 12 * metrics.scale + detectionWidth / 2,
                y: 332 * metrics.heightScale + chipHeight / 2
            )

            OBSplashFloatingChip(
                title: "Kök Neden ve Mevzuat",
                subtitle: "bilgisi hazırlanıyor…",
                accent: OBSplashColor.amber,
                iconBackground: OBSplashColor.amberSoft,
                kind: .spinner,
                accessibilityID: "onboarding.splash.chip.preparing"
            )
            .frame(width: preparingWidth, height: chipHeight)
            .rotationEffect(.degrees(5))
            .position(
                x: metrics.width - 10 * metrics.scale - preparingWidth / 2,
                y: 300 * metrics.heightScale + chipHeight / 2
            )
        }
        .frame(width: metrics.width, height: metrics.heroHeight)
        .clipped()
    }
}

private struct OBSplashPhoneFrame: View {
    let width: CGFloat

    private var height: CGFloat { width * 462 / 250 }
    private var bezel: CGFloat { width * 0.028 }
    private var bodyRadius: CGFloat { width * 0.165 }
    private var screenWidth: CGFloat { width - bezel * 2 }
    private var screenHeight: CGFloat { height - bezel * 2 }
    private var screenRadius: CGFloat { bodyRadius - bezel * 0.7 }

    var body: some View {
        ZStack(alignment: .top) {
            OBSplashPhoneSideButtons(width: width, height: height)

            RoundedRectangle(cornerRadius: bodyRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#2C2C2F"), Color(hex: "#0B0B0D"), Color(hex: "#1A1A1C")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: bodyRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: bodyRadius - 1, style: .continuous)
                        .stroke(Color.black.opacity(0.45), lineWidth: max(1.4, width * 0.01))
                        .padding(width * 0.005)
                )
                .shadow(color: OBSplashColor.title.opacity(0.55), radius: 45, x: 0, y: 46)
                .shadow(color: OBSplashColor.title.opacity(0.42), radius: 22, x: 0, y: 22)
                .shadow(color: OBSplashColor.title.opacity(0.30), radius: 7, x: 0, y: 6)

            Image("OBSplashPreview")
                .resizable()
                .scaledToFill()
                .frame(width: screenWidth, height: screenHeight, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: screenRadius, style: .continuous))
                .padding(bezel)

            OBSplashDynamicIsland(width: width * 0.283, height: width * 0.074)
                .padding(.top, width * 0.032)
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("RiskDetected önizleme telefonu")
        .accessibilityIdentifier("onboarding.splash.preview_phone")
    }
}

private struct OBSplashPhoneSideButtons: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            sideButton(height: height * 0.045)
                .offset(x: -width * 0.014, y: height * 0.202)

            sideButton(height: height * 0.085)
                .offset(x: -width * 0.014, y: height * 0.302)

            sideButton(height: height * 0.085)
                .offset(x: -width * 0.014, y: height * 0.405)

            sideButton(height: height * 0.12)
                .offset(x: width - width * 0.002, y: height * 0.275)
        }
        .frame(width: width, height: height)
    }

    private func sideButton(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: width * 0.008, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "#1D1D20"), Color(hex: "#050506")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: max(2.8, width * 0.014), height: height)
    }
}

private struct OBSplashDynamicIsland: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .trailing) {
            Capsule()
                .fill(Color.black)

            Circle()
                .fill(Color(hex: "#1C2433"))
                .frame(width: height * 0.33, height: height * 0.33)
                .padding(.trailing, height * 0.22)
        }
        .frame(width: width, height: height)
    }
}

private struct OBSplashFloatingChip: View {
    enum Kind {
        case warning
        case spinner
    }

    let title: String
    let subtitle: String
    let accent: Color
    let iconBackground: Color
    let kind: Kind
    let accessibilityID: String

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(iconBackground)

                switch kind {
                case .warning:
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: RDFontScale.size(11), weight: .bold))
                        .foregroundStyle(accent)
                case .spinner:
                    OBSplashSpinnerIcon(color: accent)
                        .frame(width: 13, height: 13)
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: RDFontScale.size(10.5), weight: .heavy, design: .rounded))
                    .foregroundStyle(OBSplashColor.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(subtitle)
                    .font(.system(size: RDFontScale.size(9.2), weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(OBSplashColor.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: OBSplashColor.title.opacity(kind == .warning ? 0.28 : 0.26), radius: 15, x: 0, y: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct OBSplashSpinnerIcon: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: 1.6)
            Circle()
                .trim(from: 0.14, to: 0.82)
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(-36))
            Circle()
                .fill(color)
                .frame(width: 2.6, height: 2.6)
                .offset(x: 4.4, y: -2.3)
        }
    }
}

private struct OBSplashBottomSheet: View {
    let metrics: OBSplashMetrics
    let onNext: () -> Void
    let onSkip: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            OBSplashProgressDots()
                .padding(.top, 24)

            Text("Profesyonel İSG Asistanı")
                .rdFont(.title1)
                .foregroundStyle(OBSplashColor.title)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.top, 16)

            Text("Fotoğraf çek; yapay zekâ tehlikeleri otomatik tespit etsin, raporun anında oluşsun ve tek tıklama ile paylaş.")
                .font(.system(size: RDFontScale.size(14.5), weight: .regular, design: .rounded))
                .foregroundStyle(OBSplashColor.slate)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)

            OBSplashCTAButton(action: onNext)
                .padding(.top, 17)

            Button {
                onSkip?()
            } label: {
                Text("Atla")
                    .font(.system(size: RDFontScale.size(14.5), weight: .semibold, design: .rounded))
                    .foregroundStyle(OBSplashColor.slate)
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OBPressStyle())
            .accessibilityIdentifier("onboarding.splash.skip")
            .padding(.top, 10)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, max(24, 30 * metrics.scale))
        .padding(.bottom, max(18, metrics.safeAreaInsets.bottom * 0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            OBSplashTopCorners(radius: 30)
                .fill(OBSplashColor.white)
                .shadow(color: OBSplashColor.title.opacity(0.16), radius: 17, x: 0, y: -14)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct OBSplashProgressDots: View {
    var body: some View {
        HStack(spacing: 7) {
            Capsule()
                .fill(OBSplashColor.cta)
                .frame(width: 20, height: 6)

            ForEach(0..<5, id: \.self) { _ in
                Circle()
                    .fill(OBSplashColor.dot.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding ilerleme, 1 / 6")
        .accessibilityIdentifier("onboarding.splash.progress")
    }
}

private struct OBSplashCTAButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            OBHaptic.light()
            action()
        } label: {
            HStack(spacing: 8) {
                Text("Devam Et")
                    .font(.system(size: RDFontScale.size(16.5), weight: .bold, design: .rounded))

                Image(systemName: "arrow.right")
                    .font(.system(size: RDFontScale.size(15.5), weight: .bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(OBSplashColor.cta)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: OBSplashColor.cta.opacity(0.60), radius: 12, x: 0, y: 10)
        }
        .buttonStyle(OBPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Devam Et")
        .accessibilityIdentifier("onboarding.splash.start")
    }
}

private struct OBSplashTopCorners: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let bezierPath = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(bezierPath.cgPath)
    }
}

#Preview("Splash Classic") {
    OBSplashView(onNext: {}, onSkip: {})
}
