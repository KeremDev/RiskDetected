import SwiftUI

// New 10-step onboarding flow ported from the Claude Design handoff bundle
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
//   5 Frequency · 6 Loading (auto-advance) · 7 PlanSummary
//   8 Auth · 9 Paywall (dismissible)

struct OnboardingViewV2: View {
    @StateObject private var state = OnboardingV2State()
    var isAuthenticated: Bool = false
    var onFinish: () -> Void = {}
    var onAuthApple: () -> Void = {}
    var onAuthGoogle: () -> Void = {}
    var onAuthEmail: () -> Void = {}
    var onSignInExisting: () -> Void = {}
    var onPurchase: (OBPlan, @escaping () -> Void) -> Void = { _, complete in complete() }

    var body: some View {
        ZStack {
            currentScreen
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                    removal: .opacity.combined(with: .move(edge: .leading))
                ))
                .id(state.step)
        }
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.42), value: state.step)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(state.step == 9 ? Color(hex: "#0B0D0E") : Color.rdPaper)
        .onChange(of: isAuthenticated) { authenticated in
            guard authenticated, state.step == 8 else { return }
            withAnimation(.obSpring) {
                state.goTo(9)
            }
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch state.step {
        case 0:
            OBSplashView { state.next() }
        case 1:
            OBPainPointView(
                onNext: { state.next() },
                onSkip: { state.goTo(6) }   // jump to loading
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
                onApple: { onAuthApple() },
                onGoogle: { onAuthGoogle() },
                onEmail: { onAuthEmail() },
                onSignIn: { onSignInExisting() }
            )
        case 9:
            OnboardingPaywallV2View(
                onClose: { onFinish() },
                onSubscribe: { onFinish() }
            )
        default:
            Color.rdPaper.onAppear { onFinish() }
        }
    }
}

#Preview {
    OnboardingViewV2()
}
