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

    private var personalContext: OnboardingPersonalPlanContext {
        OnboardingPersonalPlanContext.make(from: state)
    }

    var body: some View {
        let context = personalContext
        let accent = Color.rdGreen

        VStack(spacing: 0) {
            OBTopBar(showBack: false, step: 6, total: 5, trailingLabel: "HAZIR", trailingDone: true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
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
        .background(Color.rdPaper)
        .onAppear {
            logViewIfNeeded(context)
            animateTimelineSteps(count: context.steps.count)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
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
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.rdGreenSoft.opacity(0.54))
                    Image(systemName: step.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.rdGreenDark)
                }
                .frame(width: 32, height: 32)

                if !isLast {
                    Rectangle()
                        .fill(Color.rdLine)
                        .frame(width: 2, height: 46)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rdOnyx)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(step.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
            .padding(.top, 1)

            Spacer(minLength: 0)
        }
        .padding(.top, index == 0 ? 5 : 0)
        .padding(.bottom, isLast ? 5 : 0)
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
