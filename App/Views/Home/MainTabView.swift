import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQuotaAlert = false
    @State private var showPaywall = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.rdPaper.ignoresSafeArea()

            switch app.activeTab {
            case .home:     HomeView()
            case .analyses: HistoryView()
            case .reports:  ReportView()
            case .profile:  ProfileView()
            }

            RDTabBar(active: $app.activeTab) {
                Task {
                    await handleQuickScanTap()
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }

            if Self.isUITestLaunch {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("main_tab.\(app.activeTab.rawValue)")
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .alert("Ücretsiz hak doldu", isPresented: $showQuotaAlert) {
            Button("Yükselt") {
                showPaywall = true
            }
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Günde 1 ücretsiz analiz hakkınızı kullandınız. Plus veya Pro ile devam edebilirsiniz.")
        }
        .fullScreenCover(isPresented: $showPaywall) {
            FreeAwarePaywallView(
                onClose: { showPaywall = false },
                onSubscribe: {
                    showPaywall = false
                    Task { await app.refreshPlanState() }
                }
            )
            .preferredColorScheme(preferredModalColorScheme)
        }
    }

    private func handleQuickScanTap() async {
        if !app.currentTier.isPaid {
            do {
                let usage = try await AnalysisService.shared.dailyQuotaUsage()
                if usage.isExhausted {
                    showQuotaAlert = true
                    return
                }
            } catch {
                // Kota kontrolü geçici olarak alınamazsa HomeView kendi korumasını yine çalıştırır.
            }
        }
        app.activeTab = .home
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            app.requestQuickScan(source: .chooser)
        }
    }

    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }

    private static var isUITestLaunch: Bool {
        #if DEBUG
        CommandLine.arguments.contains { $0.hasPrefix("RD_UI_TEST_") }
            || ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("RD_UI_TEST_") }
        #else
        false
        #endif
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
