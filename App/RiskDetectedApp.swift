import SwiftUI
#if DEBUG
import UIKit
#endif

@main
struct RiskDetectedApp: App {
    @UIApplicationDelegateAdaptor(RDAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var networkMonitor = NetworkMonitor.shared

    init() {
        #if DEBUG
        if Self.isUITestLaunch {
            UIView.setAnimationsEnabled(false)
        }
        #endif
        NotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(networkMonitor)
                .preferredColorScheme(appState.themePreference.colorScheme)
                .onOpenURL { url in
                    if !GoogleSignInService.handle(url) {
                        SupabaseService.shared.handleAuthURL(url)
                    }
                }
        }
    }

    #if DEBUG
    private static var isUITestLaunch: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
    }
    #endif
}
