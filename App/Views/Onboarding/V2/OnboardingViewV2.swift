import SwiftUI

// New 11-step onboarding flow ported from the Claude Design handoff bundle
// (riskdetected-onboard). Each step is a self-contained view; this coordinator
// owns the shared OnboardingV2State and transitions.
//
// Integration hooks (left for codex / app glue):
//   • onFinish      — called when user completes paywall (start trial) OR dismisses
//   • onAuth*       — wire to existing AuthService / AuthView
//   • onPurchase    — wire to existing PurchaseService / paywall
//
// Steps:
//   0 Splash · 1 PainPoint · 2 Certificate · 3 Hazard · 4 Sector
//   5 Frequency · 6 Loading (auto-advance) · 7 Personal Plan
//   8 Auth · 9 Trial Invite · 10 Push Permission · 11 Timeline Paywall (dismissible)

struct OnboardingViewV2: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var state: OnboardingV2State
    @State private var showSkipConfirmation = false
    @State private var paywallNoticeMessage: String?
    @State private var isPaywallWorking = false
    var isAuthenticated: Bool = false
    var currentTier: SubscriptionTier = .free
    var onFinish: () -> Void = {}
    var onAuthApple: () -> Void = {}
    var onAuthGoogle: () -> Void = {}
    var onAuthEmail: () -> Void = {}
    var onSignInExisting: () -> Void = {}
    var onPurchase: (OBPlan, @escaping () -> Void) -> Void = { _, complete in complete() }
    var onRestorePurchases: () async throws -> Bool = { false }

    init(
        initialStep: Int = 0,
        isAuthenticated: Bool = false,
        currentTier: SubscriptionTier = .free,
        onFinish: @escaping () -> Void = {},
        onAuthApple: @escaping () -> Void = {},
        onAuthGoogle: @escaping () -> Void = {},
        onAuthEmail: @escaping () -> Void = {},
        onSignInExisting: @escaping () -> Void = {},
        onPurchase: @escaping (OBPlan, @escaping () -> Void) -> Void = { _, complete in complete() },
        onRestorePurchases: @escaping () async throws -> Bool = { false }
    ) {
        _state = StateObject(wrappedValue: OnboardingV2State(step: initialStep))
        self.isAuthenticated = isAuthenticated
        self.currentTier = currentTier
        self.onFinish = onFinish
        self.onAuthApple = onAuthApple
        self.onAuthGoogle = onAuthGoogle
        self.onAuthEmail = onAuthEmail
        self.onSignInExisting = onSignInExisting
        self.onPurchase = onPurchase
        self.onRestorePurchases = onRestorePurchases
    }

    var body: some View {
        ZStack {
            currentScreen
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                .id(state.step)

            if showSkipConfirmation {
                OBSkipConfirmationView(
                    onCancel: {
                        withAnimation(.obSpring) {
                            showSkipConfirmation = false
                        }
                    },
                    onConfirm: {
                        OBHaptic.light()
                        OnboardingAnswersService.shared.clearPendingDraft()
                        withAnimation(.obSpring) {
                            showSkipConfirmation = false
                        }
                        onFinish()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(10)
            }

            if Self.isUITestLaunch {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("onboarding.v2")
            }
        }
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.42), value: state.step)
        .animation(.obSpring, value: showSkipConfirmation)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(state.step == 11 ? Color(hex: "#0B0D0E") : Color.rdPaper)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .onChange(of: isAuthenticated) { authenticated in
            guard authenticated else { return }
            persistCurrentDraft()
            PaywallEventService.shared.flushPendingIfPossible()
            Task {
                await OnboardingAnswersService.shared.syncPendingDraftIfPossible()
                await MainActor.run {
                    PaywallEventService.shared.flushPendingIfPossible()
                }
            }
            guard state.step == 8 else { return }
            withAnimation(.obSpring) {
                state.goTo(9)
            }
        }
        .onChange(of: currentTier) { tier in
            guard isAuthenticated, tier.isPaid, state.step >= 9 else { return }
            finishOnboarding()
        }
        .onChange(of: state.step) { step in
            persistCurrentDraft()
            if isAuthenticated, currentTier.isPaid, step >= 9 {
                finishOnboarding()
                return
            }
            #if DEBUG
            if step == 8 && Self.isUITestAuthBypassLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.obSpring) {
                        state.goTo(9)
                    }
                }
            }
            #endif
        }
        .onChange(of: state.certificate) { _ in persistCurrentDraft() }
        .onChange(of: state.hazards) { _ in persistCurrentDraft() }
        .onChange(of: state.sectors) { _ in persistCurrentDraft() }
        .onChange(of: state.frequency) { _ in persistCurrentDraft() }
        .onChange(of: state.selectedPlan) { _ in persistCurrentDraft() }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch state.step {
        case 0:
            OBSplashView { state.next() }
        case 1:
            OBPainPointView(
                onNext: { state.next() },
                onSkip: {
                    OBHaptic.soft()
                    withAnimation(.obSpring) {
                        showSkipConfirmation = true
                    }
                }
            )
        case 2:
            OBCertificateView(state: state, onBack: { state.back() }, onNext: { state.next() })
        case 3:
            OBHazardClassView(state: state, onBack: { state.back() }, onNext: { state.next() })
        case 4:
            OBSectorView(state: state, onBack: { state.back() }, onNext: { state.next() })
        case 5:
            OBFrequencyView(state: state, onBack: { state.back() }, onNext: { state.next() })
        case 6:
            OBLoadingView(state: state) { state.next() }
        case 7:
            OBPlanSummaryView(state: state) { state.next() }
        case 8:
            OBAuthView(
                state: state,
                onBack: { state.back() },
                onApple: { startAuth(onAuthApple) },
                onGoogle: { startAuth(onAuthGoogle) },
                onEmail: { startAuth(onAuthEmail) },
                onSignIn: { startAuth(onSignInExisting) }
            )
        case 9:
            OBTrialInviteView {
                state.goTo(10)
            }
        case 10:
            OBNotificationPermissionView {
                state.goTo(11)
            }
        case 11:
            OBTimelinePaywallView(
                isWorking: isPaywallWorking,
                noticeMessage: paywallNoticeMessage,
                onStart: { plan in
                    guard !isPaywallWorking else { return }
                    paywallNoticeMessage = nil
                    state.selectedPlan = plan
                    onPurchase(plan) {
                        finishOnboarding()
                    }
                },
                onRestore: {
                    restorePurchases()
                },
                onTerms: { openURL(RDConfig.Web.termsURL) },
                onPrivacy: { openURL(RDConfig.Web.privacyPolicyURL) },
                onDismiss: { finishOnboarding() }
            )
        default:
            Color.rdPaper.onAppear { onFinish() }
        }
    }

    private func persistCurrentDraft() {
        OnboardingAnswersService.shared.savePendingDraft(state.makeAnswersDraft())
    }

    private func startAuth(_ action: () -> Void) {
        persistCurrentDraft()
        action()
    }

    private func finishOnboarding() {
        persistCurrentDraft()
        Task {
            await OnboardingAnswersService.shared.syncPendingDraftIfPossible()
        }
        onFinish()
    }

    private func restorePurchases() {
        guard !isPaywallWorking else { return }
        isPaywallWorking = true
        paywallNoticeMessage = nil

        Task {
            do {
                let hasActiveSubscription = try await onRestorePurchases()
                await MainActor.run {
                    isPaywallWorking = false
                    if hasActiveSubscription {
                        finishOnboarding()
                    } else {
                        paywallNoticeMessage = "Geri yüklenecek aktif abonelik bulunamadı."
                    }
                }
            } catch {
                await MainActor.run {
                    isPaywallWorking = false
                    paywallNoticeMessage = error.localizedDescription
                }
            }
        }
    }

    #if DEBUG
    private static var isUITestAuthBypassLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_BYPASS_AUTH")
    }
    #endif

    private static var isUITestLaunch: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
    }
}

private struct OBSkipConfirmationView: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 18) {
                sadIcon
                    .padding(.bottom, 2)

                VStack(spacing: 8) {
                    Text("Sana özel sonuçlar veremeyeceğiz")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(Color.rdOnyx)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Birkaç kısa cevap, analizlerini sektörüne ve çalışma alanına göre daha isabetli hazırlamamıza yardım eder.")
                        .font(.system(size: 14))
                        .lineSpacing(2)
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    OBPrimaryButton(title: "Cevaplamaya devam et", trailingIcon: nil) {
                        onCancel()
                    }

                    Button {
                        onConfirm()
                    } label: {
                        Text("Yine de atla")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.rdSlate.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(OBPressStyle())
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: 340)
            .background(Color.rdWhite)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.rdOnyx.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 30, x: 0, y: 18)
            .padding(.horizontal, 24)
        }
    }

    private var sadIcon: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#FFF5E6"))
            Circle()
                .stroke(Color.rdHigh.opacity(0.22), lineWidth: 1)
            SadFaceShape()
                .stroke(Color.rdHigh, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 42, height: 34)
        }
        .frame(width: 76, height: 76)
    }
}

private struct SadFaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let leftEye = CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.26)
        let rightEye = CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.26)
        let eyeRadius = min(rect.width, rect.height) * 0.055

        path.addEllipse(in: CGRect(
            x: leftEye.x - eyeRadius,
            y: leftEye.y - eyeRadius,
            width: eyeRadius * 2,
            height: eyeRadius * 2
        ))
        path.addEllipse(in: CGRect(
            x: rightEye.x - eyeRadius,
            y: rightEye.y - eyeRadius,
            width: eyeRadius * 2,
            height: eyeRadius * 2
        ))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.78))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.78),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.52)
        )
        return path
    }
}

#Preview("00 Splash") {
    OnboardingViewV2(initialStep: 0)
}

#Preview("02 Certificate") {
    OnboardingViewV2(initialStep: 2)
}

#Preview("07 Personal Plan") {
    OnboardingViewV2(initialStep: 7)
        .environmentObject(AppState())
}

#Preview("11 Paywall") {
    OnboardingViewV2(initialStep: 11)
}
