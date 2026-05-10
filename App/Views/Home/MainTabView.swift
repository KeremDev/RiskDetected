import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.rdPaper.ignoresSafeArea()

            switch app.activeTab {
            case .home:     HomeView()
            case .analyses: HistoryView()
            case .reports:  ReportView()
            case .profile:  ProfileView()
            }

            RDTabBar(active: $app.activeTab)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
