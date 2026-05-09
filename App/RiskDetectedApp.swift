import SwiftUI

@main
struct RiskDetectedApp: App {
    @StateObject private var appState = AppState()

    init() {
        FirebaseBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
        }
    }
}
