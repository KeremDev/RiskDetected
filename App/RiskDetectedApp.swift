import SwiftUI
#if DEBUG
import Combine
import UIKit
#endif

@main
struct RiskDetectedApp: App {
    @UIApplicationDelegateAdaptor(RDAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState
    @StateObject private var networkMonitor = NetworkMonitor.shared

    init() {
        #if DEBUG
        if Self.isPDFSelfTestLaunch {
            _appState = StateObject(
                wrappedValue: AppState(subscriptions: PDFSelfTestSubscriptionManager())
            )
        } else {
            _appState = StateObject(wrappedValue: AppState())
        }
        if Self.isUITestLaunch {
            UIView.setAnimationsEnabled(false)
        }
        #else
        _appState = StateObject(wrappedValue: AppState())
        #endif
        NotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if Self.isResultHubPDFSelfTestLaunch {
                    ResultHubPDFSelfTestView()
                } else if Self.isPDFReportLocalizationSelfTestLaunch {
                    PDFReportLocalizationSelfTestView()
                } else {
                    RootView()
                }
                #else
                RootView()
                #endif
            }
                .font(RDTypography.font(17, .regular))
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
                    PaywallEventService.shared.flushPendingIfPossible()
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

    private static var isPDFSelfTestLaunch: Bool {
        isPDFReportLocalizationSelfTestLaunch || isResultHubPDFSelfTestLaunch
    }

    private static var isPDFReportLocalizationSelfTestLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_PDF_REPORT_LOCALIZATION")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_PDF_REPORT_LOCALIZATION"] == "1"
    }

    private static var isResultHubPDFSelfTestLaunch: Bool {
        CommandLine.arguments.contains("RD_UI_TEST_RESULT_HUB_PDF")
            || ProcessInfo.processInfo.environment["RD_UI_TEST_RESULT_HUB_PDF"] == "1"
    }
    #endif
}

#if DEBUG
@MainActor
private final class PDFSelfTestSubscriptionManager: SubscriptionManaging {
    private let stateSubject = CurrentValueSubject<SubscriptionState, Never>(.free)
    private let packagesSubject = CurrentValueSubject<[SubscriptionPlanPackage], Never>([])

    var state: SubscriptionState { stateSubject.value }
    var statePublisher: AnyPublisher<SubscriptionState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    var packages: [SubscriptionPlanPackage] { packagesSubject.value }
    var packagesPublisher: AnyPublisher<[SubscriptionPlanPackage], Never> {
        packagesSubject.eraseToAnyPublisher()
    }

    func configure() {}
    func identify(userID: UUID?) async {}
    func loadOfferings() async {}
    func purchase(packageID: String) async throws -> SubscriptionState { .free }
    func refreshCustomerInfo() async {}
    func restorePurchases() async throws -> SubscriptionState { .free }
}

private struct PDFReportLocalizationSelfTestView: View {
    @State private var status = "PDF_REPORT_LOCALIZATION_RUNNING"

    var body: some View {
        Text(status)
            .font(RDTypography.font(.body, design: .monospaced))
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

private struct ResultHubPDFSelfTestView: View {
    @State private var status = "RESULT_HUB_PDF_RUNNING"

    var body: some View {
        Text(status)
            .font(RDTypography.font(.body, design: .monospaced))
            .multilineTextAlignment(.center)
            .padding()
            .accessibilityIdentifier("result_hub_pdf.status")
            .task {
                do {
                    let urls = try await Task.detached(priority: .userInitiated) {
                        try AnalysisResultHubPDFService.runResultHubVisualSelfTest()
                    }.value
                    status = urls.count == 4 ? "RESULT_HUB_PDF_OK" : "RESULT_HUB_PDF_FAILED: count"
                } catch {
                    status = "RESULT_HUB_PDF_FAILED: \(error.localizedDescription)"
                }
            }
    }
}
#endif
