import SwiftUI

enum RDTab: String, CaseIterable, Identifiable {
    case home = "home"
    case analyses = "analyses"
    case reports = "reports"
    case profile = "profile"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .analyses: return "Analizler"
        case .reports: return "Raporlar"
        case .profile: return "Profil"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .analyses: return "viewfinder"
        case .reports: return "doc.text"
        case .profile: return "person"
        }
    }
}

struct RDTabBar: View {
    @Binding var active: RDTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RDTab.allCases) { tab in
                let isActive = active == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { active = tab }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22, weight: isActive ? .bold : .regular))
                            .foregroundStyle(isActive ? Color.rdGreen : Color.rdSlate)
                            .frame(width: 26, height: 26)
                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isActive ? Color.rdBlack : Color.rdSlate)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(height: 84)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.rdLine).frame(height: 0.5)
        }
    }
}

private struct RDTabBarPreviewWrapper: View {
    @State var tab: RDTab = .home
    var body: some View {
        VStack { Spacer(); RDTabBar(active: $tab) }
            .background(Color.rdPaper)
    }
}

#Preview {
    RDTabBarPreviewWrapper()
}
