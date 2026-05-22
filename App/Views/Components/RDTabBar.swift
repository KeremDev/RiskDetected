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
    var onQuickScan: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            tabButton(.home)
            tabButton(.analyses)
            quickScanButton
            tabButton(.reports)
            tabButton(.profile)
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 24)
        .frame(height: 96)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(Color.rdPaper)
                    .frame(width: 72, height: 72)
                    .offset(y: -27)
                    .shadow(color: Color.rdOnyx.opacity(0.06), radius: 12, x: 0, y: 2)
            }
        }
        .overlay(alignment: .top) {
            HStack(spacing: 78) {
                Rectangle().fill(Color.rdLine).frame(height: 0.5)
                Rectangle().fill(Color.rdLine).frame(height: 0.5)
            }
        }
    }

    private func tabButton(_ tab: RDTab) -> some View {
        let isActive = active == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { active = tab }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: isActive ? .bold : .regular, design: .rounded))
                    .foregroundStyle(isActive ? Color.rdGreen : Color.rdBlack)
                    .frame(width: 26, height: 26)
                Text(tab.label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }

    private var quickScanButton: some View {
        Button(action: onQuickScan) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(Color.rdGreen)
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.rdGreen.opacity(0.35), radius: 18, x: 0, y: 8)
                    Circle()
                        .stroke(Color.rdWhite.opacity(0.92), lineWidth: 4)
                        .frame(width: 56, height: 56)
                    Image(systemName: "viewfinder.circle.fill")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdWhite)
                }

                Text("Analiz")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74, alignment: .top)
            .offset(y: -18)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel("Hızlı tarama başlat")
        .accessibilityIdentifier("tab.quick_scan")
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
