import SwiftUI

struct OBPlanSummaryView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var state: OnboardingV2State
    let onNext: () -> Void

    @State private var checkScale: CGFloat = 0
    @State private var funnelSessionID = UUID()
    @State private var didLogView = false
    @State private var revealedTimelineStepCount = 0
    @State private var didAnimateTimeline = false
    @State private var showConfetti = false

    private var personalContext: OnboardingPersonalPlanContext {
        OnboardingPersonalPlanContext.make(from: state)
    }

    var body: some View {
        let context = personalContext
        let accent = Color.rdGreen

        ZStack {
            OBPersonalPlanConfettiView(isActive: showConfetti)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(2)

            VStack(spacing: 0) {
                OBTopBar(showBack: false, step: 6, total: 5, trailingLabel: "HAZIR", trailingDone: true)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        hero(context: context, accent: accent)
                            .padding(.top, 4)
                            .obStage(delay: 0.08)

                        timeline(context: context, accent: accent)
                            .obStage(delay: 0.22)

                        trustRow
                            .obStage(delay: 0.42)

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 24)
                }

                OBFooter {
                    OBPrimaryButton(title: "Hesabımı Oluştur", accessibilityID: "onboarding.personal_plan.create_account") {
                        record(.personalPlanContinue, context: context)
                        onNext()
                    }
                    .obStage(delay: 0.62)
                }
            }
            .zIndex(1)
        }
        .background(Color.rdPaper)
        .onAppear {
            logViewIfNeeded(context)
            animateTimelineSteps(count: context.steps.count)
            showConfetti = true
        }
        .accessibilityIdentifier("onboarding.personal_plan")
    }

    private func hero(
        context: OnboardingPersonalPlanContext,
        accent: Color
    ) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.rdWhite)
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.rdOnyx.opacity(0.06), lineWidth: 1)

                VStack(spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.rdGreenSoft.opacity(0.58))
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.rdGreen.opacity(0.16), lineWidth: 1)
                        Image(systemName: context.heroIcon)
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(Color.rdOnyx)
                    }
                    .frame(width: 56, height: 56)
                    .scaleEffect(checkScale)
                    .onAppear {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.52)) {
                            checkScale = 1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            OBHaptic.success()
                        }
                    }

                    VStack(spacing: 7) {
                        Text(context.eyebrow)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.rdGreenDark)
                            .lineLimit(1)

                        Text(context.headline)
                            .font(.system(size: 24, weight: .semibold))
                            .tracking(-0.6)
                            .foregroundStyle(Color.rdOnyx)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.78)

                        Text(context.subtitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color.rdSlate)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .lineLimit(4)
                            .minimumScaleFactor(0.82)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .overlay(alignment: .topTrailing) {
                metadataTags(context.chips)
                    .padding(.top, 24)
            }
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
        }
    }

    private func metadataTags(_ values: [String]) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .padding(.leading, 9)
                    .padding(.trailing, 10)
                    .frame(height: 22)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(Color(hex: "#FFF6D8"))
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 10,
                            bottomLeadingRadius: 10,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                    )
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 10,
                            bottomLeadingRadius: 10,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        )
                        .stroke(Color.rdOnyx.opacity(0.08), lineWidth: 1)
                    )
            }
        }
    }

    private func timeline(
        context: OnboardingPersonalPlanContext,
        accent: Color
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(context.steps.enumerated()), id: \.offset) { index, step in
                let isVisible = revealedTimelineStepCount > index

                timelineRow(
                    index: index,
                    step: step,
                    isLast: index == context.steps.count - 1,
                    accent: accent
                )
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 14)
                .scaleEffect(isVisible ? 1 : 0.96, anchor: .leading)
                .animation(
                    .spring(response: 0.58, dampingFraction: 0.82, blendDuration: 0.05),
                    value: revealedTimelineStepCount
                )
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdOnyx.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        .accessibilityIdentifier("onboarding.personal_plan.timeline")
    }

    private func timelineRow(
        index: Int,
        step: OnboardingPersonalPlanStep,
        isLast: Bool,
        accent: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.rdGreenSoft.opacity(0.54))
                    Image(systemName: step.icon)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.rdGreenDark)
                }
                .frame(width: 30, height: 30)

                if !isLast {
                    Rectangle()
                        .fill(Color.rdLine)
                        .frame(width: 2, height: 34)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color.rdOnyx)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(step.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, index == 0 ? 3 : 0)
        .padding(.bottom, isLast ? 3 : 0)
    }

    private var trustRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.rdGreenDark)
            Text("Planını hesabına kaydedelim, 7 gün ücretsiz denemeyi başlat.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.rdSlate)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdFog.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdLine, lineWidth: 1)
        )
    }

    private func logViewIfNeeded(_ context: OnboardingPersonalPlanContext) {
        guard !didLogView else { return }
        didLogView = true
        record(.personalPlanView, context: context)
    }

    private func animateTimelineSteps(count: Int) {
        guard !didAnimateTimeline else { return }
        didAnimateTimeline = true
        revealedTimelineStepCount = 0

        for index in 0..<count {
            let delay = 0.34 + (Double(index) * 0.18)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.82, blendDuration: 0.05)) {
                    revealedTimelineStepCount = index + 1
                }
            }
        }
    }

    private func record(_ event: PaywallEventName, context: OnboardingPersonalPlanContext) {
        PaywallEventService.shared.record(
            event,
            funnelSessionID: funnelSessionID,
            source: .onboardingV2,
            variantID: OnboardingPersonalPlanContext.variantID,
            segmentKey: context.segmentKey,
            selectedTier: nil,
            billing: nil,
            productIdentifier: nil,
            metadata: PaywallEventMetadata(
                layout: "onboarding_personal_plan",
                currentTier: app.currentTier.rawValue,
                selectedPackageID: nil,
                noticePresent: false,
                errorMessage: nil,
                contextHeadline: context.headline,
                purchaseError: nil
            )
        )
    }
}

private struct OBPersonalPlanConfettiView: View {
    let isActive: Bool

    @State private var startDate = Date()

    private let pieces: [OBPersonalPlanConfettiPiece] = [
        .init(x: 0.04, delay: 0.00, duration: 5.8, drift: 24, size: CGSize(width: 7, height: 15), color: Color.rdGreen, rotation: 220),
        .init(x: 0.11, delay: 1.35, duration: 6.6, drift: -18, size: CGSize(width: 9, height: 9), color: Color.rdHigh, rotation: -180),
        .init(x: 0.18, delay: 0.72, duration: 5.4, drift: 30, size: CGSize(width: 6, height: 16), color: Color.rdInfo, rotation: 260),
        .init(x: 0.26, delay: 2.10, duration: 6.1, drift: -28, size: CGSize(width: 8, height: 8), color: Color.rdMedium, rotation: -240),
        .init(x: 0.34, delay: 0.28, duration: 6.9, drift: 20, size: CGSize(width: 6, height: 14), color: Color.rdGreenDark, rotation: 190),
        .init(x: 0.43, delay: 1.76, duration: 5.7, drift: -22, size: CGSize(width: 10, height: 10), color: Color.rdLow, rotation: -210),
        .init(x: 0.51, delay: 0.96, duration: 6.4, drift: 26, size: CGSize(width: 7, height: 16), color: Color.rdPlanPlus, rotation: 250),
        .init(x: 0.59, delay: 2.42, duration: 5.6, drift: -20, size: CGSize(width: 8, height: 8), color: Color.rdCritical, rotation: -170),
        .init(x: 0.67, delay: 0.44, duration: 6.7, drift: 32, size: CGSize(width: 6, height: 15), color: Color.rdGreen, rotation: 235),
        .init(x: 0.75, delay: 1.20, duration: 5.9, drift: -26, size: CGSize(width: 9, height: 9), color: Color.rdHigh, rotation: -230),
        .init(x: 0.83, delay: 0.12, duration: 6.3, drift: 18, size: CGSize(width: 7, height: 14), color: Color.rdInfo, rotation: 210),
        .init(x: 0.92, delay: 1.92, duration: 5.5, drift: -30, size: CGSize(width: 10, height: 10), color: Color.rdMedium, rotation: -260),
        .init(x: 0.98, delay: 2.70, duration: 6.8, drift: -24, size: CGSize(width: 6, height: 16), color: Color.rdGreenDark, rotation: 275)
    ]

    private let burstPieces: [OBPersonalPlanConfettiBurstPiece] = [
        .init(angle: -142, distance: 132, size: CGSize(width: 7, height: 15), color: Color.rdGreen, rotation: -260),
        .init(angle: -119, distance: 104, size: CGSize(width: 9, height: 9), color: Color.rdHigh, rotation: 220),
        .init(angle: -96, distance: 118, size: CGSize(width: 6, height: 16), color: Color.rdInfo, rotation: -190),
        .init(angle: -72, distance: 92, size: CGSize(width: 8, height: 8), color: Color.rdMedium, rotation: 180),
        .init(angle: -48, distance: 126, size: CGSize(width: 7, height: 14), color: Color.rdPlanPlus, rotation: -240),
        .init(angle: -24, distance: 106, size: CGSize(width: 10, height: 10), color: Color.rdCritical, rotation: 210),
        .init(angle: 12, distance: 118, size: CGSize(width: 6, height: 15), color: Color.rdGreenDark, rotation: -210),
        .init(angle: 36, distance: 98, size: CGSize(width: 8, height: 8), color: Color.rdLow, rotation: 175),
        .init(angle: 62, distance: 128, size: CGSize(width: 7, height: 16), color: Color.rdHigh, rotation: -230),
        .init(angle: 86, distance: 108, size: CGSize(width: 9, height: 9), color: Color.rdInfo, rotation: 190)
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { proxy in
                let elapsed = max(0, timeline.date.timeIntervalSince(startDate))

                ForEach(burstPieces) { piece in
                    burstPiece(piece, elapsed: elapsed, size: proxy.size)
                }

                ForEach(pieces) { piece in
                    confettiPiece(piece, elapsed: elapsed, size: proxy.size)
                }
            }
        }
        .opacity(isActive ? 1 : 0)
        .onAppear {
            startDate = Date()
        }
    }

    private func confettiPiece(
        _ piece: OBPersonalPlanConfettiPiece,
        elapsed: TimeInterval,
        size: CGSize
    ) -> some View {
        let progress = progress(for: piece, elapsed: elapsed)
        let sway = sin((progress * .pi * 2) + piece.delay) * 12
        let x = (size.width * piece.x) + (piece.drift * progress) + sway
        let y = -36 + ((size.height + 96) * progress)

        return RoundedRectangle(cornerRadius: min(piece.size.width, piece.size.height) * 0.32, style: .continuous)
            .fill(piece.color.opacity(0.88))
            .frame(width: piece.size.width, height: piece.size.height)
            .rotationEffect(.degrees((piece.rotation * progress) + piece.delay * 70))
            .position(x: x, y: y)
            .opacity(edgeOpacity(progress))
    }

    private func burstPiece(
        _ piece: OBPersonalPlanConfettiBurstPiece,
        elapsed: TimeInterval,
        size: CGSize
    ) -> some View {
        let duration = 1.22
        let progress = min(max(elapsed / duration, 0), 1)
        let radians = piece.angle * .pi / 180
        let eased = 1 - pow(1 - progress, 3)
        let origin = CGPoint(x: size.width * 0.5, y: max(88, size.height * 0.16))
        let x = origin.x + (cos(radians) * piece.distance * eased)
        let y = origin.y + (sin(radians) * piece.distance * eased) + (42 * progress * progress)
        let opacity = max(0, min(progress / 0.12, (1 - progress) / 0.28))

        return RoundedRectangle(cornerRadius: min(piece.size.width, piece.size.height) * 0.32, style: .continuous)
            .fill(piece.color.opacity(0.9))
            .frame(width: piece.size.width, height: piece.size.height)
            .rotationEffect(.degrees(piece.rotation * progress))
            .position(x: x, y: y)
            .opacity(opacity)
    }

    private func progress(for piece: OBPersonalPlanConfettiPiece, elapsed: TimeInterval) -> Double {
        let elapsed = elapsed + piece.delay
        return elapsed.truncatingRemainder(dividingBy: piece.duration) / piece.duration
    }

    private func edgeOpacity(_ progress: Double) -> Double {
        let fadeIn = min(progress / 0.08, 1)
        let fadeOut = min((1 - progress) / 0.12, 1)
        return max(0, min(fadeIn, fadeOut))
    }
}

private struct OBPersonalPlanConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let delay: Double
    let duration: Double
    let drift: CGFloat
    let size: CGSize
    let color: Color
    let rotation: Double
}

private struct OBPersonalPlanConfettiBurstPiece: Identifiable {
    let id = UUID()
    let angle: Double
    let distance: CGFloat
    let size: CGSize
    let color: Color
    let rotation: Double
}

#Preview {
    OBPlanSummaryView(
        state: OnboardingV2State.previewSample(step: 7),
        onNext: {}
    )
    .environmentObject(AppState())
}
