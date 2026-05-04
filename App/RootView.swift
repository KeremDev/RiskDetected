import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Color.rdPaper.ignoresSafeArea()

            switch app.flow {
            case .splash:
                SplashView()
                    .transition(.opacity)
            case .onboarding:
                OnboardingView()
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
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            RDLogo(size: 28)
            Text("Detect risk before it grows.")
                .rdFont(.subheadline)
                .foregroundStyle(Color.rdSlate)
            Spacer()
        }
    }
}

#Preview {
    RootView().environmentObject(AppState())
}
