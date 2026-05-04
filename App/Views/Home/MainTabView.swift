import SwiftUI

struct MainTabView: View {
    @State private var active: RDTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.rdPaper.ignoresSafeArea()

            switch active {
            case .home:     HomeView()
            case .analyses: HistoryView()
            case .reports:  ReportView()
            case .profile:  ProfileView()
            }

            RDTabBar(active: $active)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
