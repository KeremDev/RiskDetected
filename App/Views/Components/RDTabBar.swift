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
        case .analyses: return "clock.arrow.circlepath"
        case .reports: return "doc.text"
        case .profile: return "person"
        }
    }
}

struct RDTabBar: View {
    static let contentClearance: CGFloat = 104

    private static let containerHeight: CGFloat = 86
    private static let horizontalPadding: CGFloat = 18
    private static let itemSpacing: CGFloat = 10
    private static let pillHeight: CGFloat = 52
    private static let quickScanSize: CGFloat = 52

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var activeHighlight

    @Binding var active: RDTab
    var onQuickScan: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: Self.itemSpacing) {
            tabPill
            quickScanButton
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(height: Self.containerHeight, alignment: .top)
    }

    private var tabPill: some View {
        HStack(spacing: 4) {
            ForEach(RDTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .frame(height: Self.pillHeight)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(pillStroke, lineWidth: 1)
        }
        .rdCardShadow(colorScheme: colorScheme, radius: 4, x: 5, y: 7)
    }

    private func tabButton(_ tab: RDTab) -> some View {
        let isActive = active == tab
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                active = tab
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            ZStack {
                if isActive {
                    Capsule()
                        .fill(activeHighlightFill)
                        .matchedGeometryEffect(id: "rd-tab-active-highlight", in: activeHighlight)
                }

                Image(systemName: tab.icon)
                    .font(.system(size: RDFontScale.size(21), weight: isActive ? .semibold : .regular, design: .rounded))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isActive ? Color.rdBlack : inactiveIconColor)
                    .opacity(isActive ? 1 : 0.82)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.label)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
        .accessibilityAddTraits(.isButton)
    }

    private var quickScanButton: some View {
        Button(action: onQuickScan) {
            ZStack {
                Circle()
                    .fill(quickScanFill)
                Circle()
                    .stroke(quickScanStroke, lineWidth: 1)
                Image(systemName: "viewfinder")
                    .font(.system(size: RDFontScale.size(23), weight: .semibold, design: .rounded))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.rdGreen)
            }
            .frame(width: Self.quickScanSize, height: Self.quickScanSize)
            .contentShape(Circle())
            .rdCardShadow(colorScheme: colorScheme, radius: 4, x: 5, y: 7)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hızlı tarama başlat")
        .accessibilityIdentifier("tab.quick_scan")
        .accessibilityAddTraits(.isButton)
    }

    private var pillStroke: Color {
        Color.white.opacity(colorScheme == .dark ? 0.12 : 0.72)
    }

    private var activeHighlightFill: Color {
        Color.white.opacity(colorScheme == .dark ? 0.10 : 0.74)
    }

    private var inactiveIconColor: Color {
        colorScheme == .dark ? Color.rdSlate : Color.rdGraphite
    }

    private var quickScanFill: Color {
        Color.white.opacity(colorScheme == .dark ? 0.96 : 1)
    }

    private var quickScanStroke: Color {
        Color.white.opacity(colorScheme == .dark ? 0.14 : 0.82)
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
