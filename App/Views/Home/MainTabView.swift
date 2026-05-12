import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var showQuickSourceSheet = false
    @State private var showQuotaAlert = false

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
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showQuickSourceSheet) {
            PhotoSourceSheet(
                onCamera: {
                    showQuickSourceSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        app.requestQuickScan(source: .camera)
                    }
                },
                onGallery: {
                    showQuickSourceSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        app.requestQuickScan(source: .gallery)
                    }
                },
                onClose: { showQuickSourceSheet = false }
            )
            .presentationDetents([.height(330)])
            .presentationDragIndicator(.hidden)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .alert("Günlük limit doldu", isPresented: $showQuotaAlert) {
            Button("Pro'ya geç") {
                app.activeTab = .profile
            }
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Günlük analiz limitinizi doldurdunuz. Pro'ya geçerek sınırsız analiz ve premium özelliklerin keyfini çıkarabilirsiniz.")
        }
    }

    private func handleQuickScanTap() async {
        if !app.isPro {
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
        showQuickSourceSheet = true
    }

    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
