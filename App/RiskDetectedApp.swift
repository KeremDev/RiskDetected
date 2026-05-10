import SwiftUI

@main
struct RiskDetectedApp: App {
    @UIApplicationDelegateAdaptor(RDAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        FirebaseBootstrap.configureIfAvailable()
        NotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(appState.themePreference.colorScheme)
        }
    }
}
