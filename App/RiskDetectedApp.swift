import SwiftUI

@main
struct RiskDetectedApp: App {
    @UIApplicationDelegateAdaptor(RDAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        NotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(appState.themePreference.colorScheme)
                .onOpenURL { url in
                    if !GoogleSignInService.handle(url) {
                        SupabaseService.shared.handleAuthURL(url)
                    }
                }
        }
    }
}
