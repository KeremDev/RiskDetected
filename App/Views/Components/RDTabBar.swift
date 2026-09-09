import SwiftUI

enum RDTab: String, CaseIterable, Identifiable {
    case home = "home"
    case analyses = "analyses"
    case reports = "reports"
    case profile = "profile"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return RDLocalization.string("localizable.rdtab.bar.ana.sayfa.5c57e0e6", table: .localizable, fallback: "Ana Sayfa")
        case .analyses: return RDLocalization.string("localizable.rdtab.bar.analizler.55bc5133", table: .localizable, fallback: "Analizler")
        case .reports: return RDLocalization.string("localizable.rdtab.bar.raporlar.ecfc0748", table: .localizable, fallback: "Raporlar")
        case .profile: return RDLocalization.string("localizable.rdtab.bar.profil.2d7788f8", table: .localizable, fallback: "Profil")
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
    private static let horizontalPadding: CGFloat = 18
    private static let itemSpacing: CGFloat = 10

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.rdLayoutProfile) private var layoutProfile
    @ScaledMetric(relativeTo: .body) private var scaledPillHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var scaledQuickScanSize: CGFloat = 52
    @Namespace private var activeHighlight

    @Binding var active: RDTab
    var onQuickScan: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: Self.itemSpacing) {
            tabPill
            quickScanButton
        }
        .padding(.horizontal, layoutProfile.widthClass == .narrow ? 12 : Self.horizontalPadding)
        .padding(.vertical, 8)
        .background(Color.clear)
    }

    private var tabPill: some View {
        HStack(spacing: 4) {
            ForEach(RDTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .frame(height: pillHeight)
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
                    .font(RDTypography.font(size: RDFontScale.size(21), weight: isActive ? .semibold : .regular, design: .rounded))
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
                    .font(RDTypography.font(size: RDFontScale.size(23), weight: .semibold, design: .rounded))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.rdGreen)
            }
            .frame(width: quickScanSize, height: quickScanSize)
            .contentShape(Circle())
            .rdCardShadow(colorScheme: colorScheme, radius: 4, x: 5, y: 7)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RDLocalization.string("localizable.rdtab.bar.hizli.tarama.baslat.f3589e86", table: .localizable, fallback: "Hızlı tarama başlat"))
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

    private var pillHeight: CGFloat {
        max(52, min(scaledPillHeight, 68))
    }

    private var quickScanSize: CGFloat {
        max(52, min(scaledQuickScanSize, 68))
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
