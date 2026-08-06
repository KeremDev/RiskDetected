import SwiftUI
#if DEBUG
import UIKit
#endif

@main
struct RiskDetectedApp: App {
    @UIApplicationDelegateAdaptor(RDAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
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
            Group {
                #if DEBUG
                if Self.isPDFReportLocalizationSelfTestLaunch {
                    PDFReportLocalizationSelfTestView()
                } else {
                    RootView()
                }
                #else
                RootView()
                #endif
            }
                .environmentObject(appState)
                .environmentObject(networkMonitor)
                .preferredColorScheme(appState.themePreference.colorScheme)
                .onOpenURL { url in
                    if !GoogleSignInService.handle(url) {
                        SupabaseService.shared.handleAuthURL(url)
                    }
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task {
                        await NotificationService.shared.handleAppBecameActive()
                        await appState.refreshNativeLanguageContext()
                    }
                }
        }
    }

    #if DEBUG
    private static var isUITestLaunch: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
    }

    private static var isPDFReportLocalizationSelfTestLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_PDF_REPORT_LOCALIZATION")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_PDF_REPORT_LOCALIZATION"] == "1"
    }
    #endif
}

#if DEBUG
private struct PDFReportLocalizationSelfTestView: View {
    @State private var status = "PDF_REPORT_LOCALIZATION_RUNNING"

    var body: some View {
        Text(status)
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .padding()
            .accessibilityIdentifier("pdf_report_localization.status")
            .task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try PDFReportService.runEnglishExtractionSelfTest()
                    }.value
                    status = "PDF_REPORT_LOCALIZATION_OK"
                } catch {
                    status = "PDF_REPORT_LOCALIZATION_FAILED: \(error.localizedDescription)"
                }
            }
    }
}
#endif
