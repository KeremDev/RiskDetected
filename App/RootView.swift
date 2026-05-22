import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var appleSignInService = AppleSignInService()
    private let googleSignInService = GoogleSignInService()

    var body: some View {
        ZStack {
            Color.rdPaper.ignoresSafeArea()

            switch app.flow {
            case .splash:
                SplashView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingViewV2(
                    isAuthenticated: app.auth.isAuthenticated,
                    onFinish: { app.finishOnboarding() },
                    onAuthApple: { runAppleSignIn() },
                    onAuthGoogle: { runGoogleSignIn() },
                    onAuthEmail: {},
                    onSignInExisting: {},
                    onPurchase: { plan, complete in purchaseOnboardingPlan(plan, onComplete: complete) }
                )
                    .transition(.opacity)
            case .auth:
                AuthView()
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: app.flow)
        .accessibilityIdentifier("root.\(flowIdentifier)")
    }

    private var flowIdentifier: String {
        switch app.flow {
        case .splash: return "splash"
        case .onboarding: return "onboarding"
        case .auth: return "auth"
        case .main: return "main"
        }
    }

    private func runAppleSignIn() {
        Task {
            do {
                let result = try await appleSignInService.signIn()
                try await app.auth.signInWithApple(
                    idToken: result.idToken,
                    nonce: result.nonce,
                    email: result.email,
                    fullName: result.fullName
                )
                await app.auth.refreshProfile()
            } catch {
                guard !isUserCancelledAuth(error) else { return }
                let message = AppErrorMessage.make(
                    error,
                    context: "Apple ile giriş yapılamadı",
                    fallbackTitle: "Apple ile giriş yapılamadı"
                )
                AuthService.logAuthError(message, operation: "apple_sign_in")
                app.authError = message.message
            }
        }
    }

    private func runGoogleSignIn() {
        Task {
            do {
                let result = try await googleSignInService.signIn()
                try await app.auth.signInWithGoogle(
                    idToken: result.idToken,
                    accessToken: result.accessToken,
                    nonce: result.nonce,
                    emailFallback: result.email,
                    fullNameFallback: result.fullName
                )
                await app.auth.refreshProfile()
            } catch {
                guard !isUserCancelledAuth(error) else { return }
                let message = AppErrorMessage.make(
                    error,
                    context: "Google ile giriş yapılamadı",
                    fallbackTitle: "Google ile giriş yapılamadı"
                )
                AuthService.logAuthError(message, operation: "google_sign_in")
                app.authError = message.message
            }
        }
    }

    private func purchaseOnboardingPlan(_ plan: OBPlan, onComplete: @escaping () -> Void) {
        Task {
            do {
                if app.subscriptionPackages.isEmpty {
                    await app.refreshSubscriptionOfferings()
                }
                guard let package = onboardingPackage(for: plan) else {
                    app.authError = "Seçilen abonelik paketi şu an alınamadı. İnternet bağlantını kontrol edip tekrar dene."
                    return
                }
                try await app.purchaseSubscription(packageID: package.id)
                onComplete()
            } catch {
                app.authError = AppErrorMessage.make(
                    error,
                    context: "Abonelik başlatılamadı",
                    fallbackTitle: "Abonelik başlatılamadı"
                ).message
            }
        }
    }

    private func onboardingPackage(for plan: OBPlan) -> SubscriptionPlanPackage? {
        app.subscriptionPackages
            .filter { $0.tier == .plus }
            .first { package in
                package.matchesOnboardingBilling(plan)
            }
    }

    private func isUserCancelledAuth(_ error: Error) -> Bool {
        let nsError = error as NSError
        let lower = error.localizedDescription.lowercased(with: Locale(identifier: "tr_TR"))
        return nsError.code == 1 && nsError.domain.contains("WebAuthenticationSession") ||
            lower.contains("cancel") ||
            lower.contains("vazgeç") ||
            lower.contains("canceled") ||
            lower.contains("cancelled") ||
            lower.contains("authentication session error 1") ||
            lower.contains("webauthenticationsession")
    }
}

private extension SubscriptionPlanPackage {
    func matchesOnboardingBilling(_ plan: OBPlan) -> Bool {
        let token = [
            id,
            productIdentifier,
            title,
            subtitle
        ]
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
        .lowercased(with: Locale(identifier: "tr_TR"))

        switch plan {
        case .yearly:
            return token.contains("annual") ||
                token.contains("year") ||
                token.contains("yearly") ||
                token.contains("yillik") ||
                token.contains("yıllık") ||
                token.contains("yılık") ||
                token.contains("yil")
        case .monthly:
            return token.contains("monthly") ||
                token.contains("month") ||
                token.contains("aylik") ||
                token.contains("aylık") ||
                token.contains("ay")
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            RDLogo(size: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView().environmentObject(AppState())
}
