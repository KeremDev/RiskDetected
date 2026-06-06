import SwiftUI

struct OBNotificationPermissionView: View {
    @StateObject private var notifications = NotificationService.shared
    @State private var isContinuing = false

    let onContinue: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    headline
                        .padding(.top, proxy.safeAreaInsets.top + 52)
                        .padding(.horizontal, 34)
                        .obStage(delay: 0.08)

                    Spacer(minLength: 46)

                    VStack(spacing: 36) {
                        OBAnimatedReminderBell()
                        subcopy
                    }
                    .frame(maxWidth: .infinity)
                    .obStage(delay: 0.18)

                    Spacer(minLength: 28)

                    footer
                        .padding(.horizontal, 28)
                        .padding(.bottom, max(2, proxy.safeAreaInsets.bottom - 10))
                        .obStage(delay: 0.3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)

                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("onboarding.notification_permission")
            }
        }
    }

    private var headline: some View {
        Text("Ücretsiz denemeniz bitmeden önce size hatırlatacağız")
            .font(.system(size: RDFontScale.size(28), weight: .bold))
            .lineSpacing(2)
            .foregroundStyle(Color.rdOnyx)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var subcopy: some View {
        Text("Deneme süreniz bitmeden önce bir hatırlatma göndereceğiz. Sürpriz ücret yok.")
            .font(.system(size: RDFontScale.size(16)))
            .lineSpacing(3)
            .foregroundStyle(Color.rdSlate)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.rdGreenSoft)
                    Image(systemName: "checkmark")
                        .font(.system(size: RDFontScale.size(11), weight: .bold))
                        .foregroundStyle(Color.rdGreenDark)
                }
                .frame(width: 20, height: 20)

                Text("Şimdi ödeme alınmayacak")
                    .font(.system(size: RDFontScale.size(15), weight: .semibold))
                    .foregroundStyle(Color.rdGraphite)
            }

            Button {
                Task { await continueAfterPermissionRequest() }
            } label: {
                Text("Ücretsiz devam et")
                    .font(.system(size: RDFontScale.size(18), weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.rdOnyx)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.rdOnyx.opacity(0.20), radius: 22, y: 8)
            }
            .buttonStyle(OBPressStyle())
            .disabled(isContinuing)
            .accessibilityIdentifier("onboarding.notification_permission.cta")

            Text(OBTrialPriceCopy.yearlyFineprint)
                .font(.system(size: RDFontScale.size(13)))
                .foregroundStyle(Color.rdSlate)
                .multilineTextAlignment(.center)
        }
    }

    private func continueAfterPermissionRequest() async {
        guard !isContinuing else { return }
        isContinuing = true
        await notifications.requestPermissionAndRegisterFromOnboarding()
        onContinue()
    }
}

private struct OBAnimatedReminderBell: View {
    private let cycle: TimeInterval = 2.8

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = normalizedTime(for: timeline.date)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.rdGreen.opacity(0.16), Color.rdGreen.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 2)

                reminderWave(side: .left, size: 26, offsetX: -75, opacity: waveOpacity(t))
                reminderWave(side: .left, size: 44, offsetX: -88, opacity: waveOpacity(t) * 0.78)
                reminderWave(side: .right, size: 26, offsetX: 75, opacity: waveOpacity(t))
                reminderWave(side: .right, size: 44, offsetX: 88, opacity: waveOpacity(t) * 0.78)

                OBBellGlyph(clapperOffset: clapperOffset(t))
                    .frame(width: 168, height: 168)
                    .rotationEffect(.degrees(bellAngle(t)), anchor: UnitPoint(x: 0.5, y: 0.2))
            }
            .frame(width: 220, height: 220)
        }
    }

    private enum WaveSide {
        case left, right
    }

    private func reminderWave(side: WaveSide, size: CGFloat, offsetX: CGFloat, opacity: Double) -> some View {
        Circle()
            .trim(from: side == .left ? 0.56 : 0.06, to: side == .left ? 0.76 : 0.26)
            .stroke(Color.rdGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(side == .left ? 26 : -26))
            .offset(x: offsetX, y: -26)
            .opacity(opacity)
    }

    private func normalizedTime(for date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return elapsed / cycle
    }

    private func bellAngle(_ t: Double) -> Double {
        interpolate(t, points: [
            (0.00, 0), (0.09, 10), (0.18, -8), (0.27, 6),
            (0.36, -3), (0.45, 1.5), (0.58, 0), (1.00, 0)
        ])
    }

    private func clapperOffset(_ t: Double) -> CGFloat {
        interpolate(t, points: [
            (0.00, 0), (0.09, 5), (0.18, -4), (0.27, 3),
            (0.36, -2), (0.45, 1), (0.58, 0), (1.00, 0)
        ]).cgFloat
    }

    private func waveOpacity(_ t: Double) -> Double {
        interpolate(t, points: [
            (0.00, 0), (0.10, 0.9), (0.30, 0.25), (0.46, 0), (1.00, 0)
        ])
    }

    private func interpolate(_ t: Double, points: [(Double, Double)]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }

        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            guard t >= start.0, t <= end.0 else { continue }
            let progress = (t - start.0) / (end.0 - start.0)
            let eased = 0.5 - cos(progress * .pi) / 2
            return start.1 + (end.1 - start.1) * eased
        }
        return last.1
    }
}

private struct OBBellGlyph: View {
    let clapperOffset: CGFloat

    private var bellGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#2BD24F"), Color.rdGreen, Color.rdGreenDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(bellGradient)
                .frame(width: 22, height: 22)
                .position(x: 100, y: 42)

            OBBellBodyShape()
                .fill(bellGradient)

            OBBellHighlightShape()
                .fill(Color.white.opacity(0.22))

            Circle()
                .fill(bellGradient)
                .frame(width: 26, height: 26)
                .position(x: 100 + clapperOffset, y: 176)
        }
        .frame(width: 200, height: 200)
    }
}

private extension Double {
    var cgFloat: CGFloat { CGFloat(self) }
}

private struct OBBellBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 100, y: 50))
        path.addCurve(to: CGPoint(x: 143, y: 105), control1: CGPoint(x: 127, y: 50), control2: CGPoint(x: 143, y: 73))
        path.addCurve(to: CGPoint(x: 157, y: 154), control1: CGPoint(x: 143, y: 130), control2: CGPoint(x: 149, y: 144))
        path.addCurve(to: CGPoint(x: 153, y: 162), control1: CGPoint(x: 160, y: 157), control2: CGPoint(x: 158, y: 162))
        path.addLine(to: CGPoint(x: 47, y: 162))
        path.addCurve(to: CGPoint(x: 43, y: 154), control1: CGPoint(x: 42, y: 162), control2: CGPoint(x: 40, y: 157))
        path.addCurve(to: CGPoint(x: 57, y: 105), control1: CGPoint(x: 51, y: 144), control2: CGPoint(x: 57, y: 130))
        path.addCurve(to: CGPoint(x: 100, y: 50), control1: CGPoint(x: 57, y: 73), control2: CGPoint(x: 73, y: 50))
        path.closeSubpath()
        return path.applying(scaleTransform(for: rect))
    }

    private func scaleTransform(for rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 200, y: rect.height / 200)
    }
}

private struct OBBellHighlightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 100, y: 50))
        path.addCurve(to: CGPoint(x: 57, y: 105), control1: CGPoint(x: 73, y: 50), control2: CGPoint(x: 57, y: 73))
        path.addCurve(to: CGPoint(x: 43, y: 154), control1: CGPoint(x: 57, y: 130), control2: CGPoint(x: 51, y: 144))
        path.addCurve(to: CGPoint(x: 47, y: 162), control1: CGPoint(x: 40, y: 157), control2: CGPoint(x: 42, y: 162))
        path.addLine(to: CGPoint(x: 64, y: 162))
        path.addCurve(to: CGPoint(x: 68, y: 105), control1: CGPoint(x: 60, y: 150), control2: CGPoint(x: 68, y: 130))
        path.addCurve(to: CGPoint(x: 100, y: 50), control1: CGPoint(x: 68, y: 78), control2: CGPoint(x: 80, y: 58))
        path.closeSubpath()
        return path.applying(scaleTransform(for: rect))
    }

    private func scaleTransform(for rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 200, y: rect.height / 200)
    }
}

#Preview {
    OBNotificationPermissionView(onContinue: {})
}
