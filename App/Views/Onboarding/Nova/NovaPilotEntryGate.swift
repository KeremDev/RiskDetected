#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

/// Entry point for the pilot bundles: the Nova onboarding funnel until it has
/// been completed once, the Nova sign-in surface afterwards. Production keeps
/// `OnboardingViewV2` / `AuthView`; this file is compiled only into the
/// `NOVA_PILOT_BUILD` debug bundles.
struct NovaPilotEntryGate: View {
    @EnvironmentObject private var app: AppState
    @AppStorage("nova.pilot.onboarding.completed.v1") private var onboardingCompleted = false
    @State private var showLogin = false
    @State private var appleService = AppleSignInService()
    @State private var googleService = GoogleSignInService()

    private var showsLogin: Bool { onboardingCompleted || showLogin }

    var body: some View {
        Group {
            if showsLogin {
                NovaLoginScreen(auth: bridge)
            } else {
                NovaOnboardingFlow(auth: bridge, onOpenLogin: { openLogin() })
            }
        }
        .onAppear { app.novaPilotOnboardingActive = !showsLogin }
        .onChange(of: showsLogin) { isLogin in
            app.novaPilotOnboardingActive = !isLogin
        }
        .onDisappear { app.novaPilotOnboardingActive = false }
    }

    private func openLogin() {
        app.novaPilotOnboardingActive = false
        showLogin = true
    }

    private var bridge: NovaOBAuthBridge {
        NovaOBAuthBridge(
            signIn: { email, password in
                try await app.auth.signInWithPassword(email: email, password: password)
                await app.auth.refreshProfile()
            },
            signUp: { email, password in
                try await app.auth.signUpWithPassword(email: email, password: password)
            },
            sendCode: { email in
                try await app.auth.sendEmailOTP(email: email)
            },
            verifyCode: { email, code in
                try await app.auth.verifyEmailOTP(email: email, token: code)
                await app.auth.refreshProfile()
            },
            recoverPassword: { email in
                try await app.auth.requestPasswordRecovery(email: email)
            },
            appleSignIn: {
                let result = try await appleService.signIn()
                try await app.auth.signInWithApple(
                    idToken: result.idToken, nonce: result.nonce,
                    email: result.email, fullName: result.fullName
                )
                await app.auth.refreshProfile()
            },
            googleSignIn: {
                let result = try await googleService.signIn()
                try await app.auth.signInWithGoogle(
                    idToken: result.idToken, accessToken: result.accessToken, nonce: result.nonce,
                    emailFallback: result.email, fullNameFallback: result.fullName
                )
                await app.auth.refreshProfile()
            },
            requestPush: {
                await NotificationService.shared.requestPermissionAndRegisterFromOnboarding()
            },
            saveDraft: { answers in
                // Stored locally now; AppState's session observer syncs it the
                // moment the account exists.
                OnboardingAnswersService.shared.savePendingDraft(answers.makeDraft())
            },
            finish: { answers in
                if let answers {
                    OnboardingAnswersService.shared.savePendingDraft(answers.makeDraft())
                }
                onboardingCompleted = true
                app.novaPilotOnboardingActive = false
                if app.auth.isAuthenticated {
                    Task { await OnboardingAnswersService.shared.syncPendingDraftIfPossible() }
                    app.signIn()
                } else {
                    showLogin = true
                }
            }
        )
    }
}
#endif
