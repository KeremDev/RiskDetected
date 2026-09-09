import SwiftUI

enum RDPhoneWidthClass: String, Sendable {
    case narrow
    case standard
    case wide
}

enum RDPhoneHeightClass: String, Sendable {
    case short
    case standard
    case tall
}

/// Describes the space a screen actually receives. It intentionally avoids
/// device model checks: sheets, Display Zoom and future phones can all expose
/// different containers on the same hardware.
struct RDLayoutProfile: Equatable, Sendable {
    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets
    let widthClass: RDPhoneWidthClass
    let heightClass: RDPhoneHeightClass
    let isAccessibilityText: Bool

    init(
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets = EdgeInsets(),
        dynamicTypeSize: DynamicTypeSize = .large
    ) {
        self.containerSize = containerSize
        self.safeAreaInsets = safeAreaInsets
        self.widthClass = switch containerSize.width {
        case ..<390: .narrow
        case ..<430: .standard
        default: .wide
        }

        let usableHeight = max(
            0,
            containerSize.height - safeAreaInsets.top - safeAreaInsets.bottom
        )
        self.heightClass = switch usableHeight {
        case ..<700: .short
        case ..<840: .standard
        default: .tall
        }
        self.isAccessibilityText = dynamicTypeSize.isAccessibilitySize
    }

    static let fallback = RDLayoutProfile(
        containerSize: CGSize(width: 390, height: 844)
    )

    var horizontalPadding: CGFloat {
        switch widthClass {
        case .narrow: 16
        case .standard: 20
        case .wide: 24
        }
    }

    var sectionSpacing: CGFloat {
        switch heightClass {
        case .short: 10
        case .standard: 14
        case .tall: 18
        }
    }

    var paywallHeroHeight: CGFloat {
        switch heightClass {
        case .short: 196
        case .standard: 220
        case .tall: 260
        }
    }

    /// Paywall'ın ilk görünümünde planlar ve bir üst paket geçişi için daha fazla
    /// alan bırakır. Erişilebilirlik yazı boyutlarında içerik sıkıştırılmaz; metinler
    /// doğal yüksekliğini alıp kaydırılabilir kalır.
    var usesCompactPaywallLayout: Bool {
        heightClass != .tall && !isAccessibilityText
    }

    var isCompact: Bool {
        widthClass == .narrow || heightClass == .short
    }

    var prefersStackedControls: Bool {
        widthClass == .narrow || isAccessibilityText
    }
}

private struct RDLayoutProfileKey: EnvironmentKey {
    static let defaultValue = RDLayoutProfile.fallback
}

extension EnvironmentValues {
    var rdLayoutProfile: RDLayoutProfile {
        get { self[RDLayoutProfileKey.self] }
        set { self[RDLayoutProfileKey.self] = newValue }
    }
}

/// Establishes a responsive environment from the current container rather
/// than from the physical screen. Use it at screen and sheet boundaries.
struct RDAdaptiveContainer<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder let content: (RDLayoutProfile) -> Content

    var body: some View {
        GeometryReader { proxy in
            let profile = RDLayoutProfile(
                containerSize: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets,
                dynamicTypeSize: dynamicTypeSize
            )

            content(profile)
                .environment(\.rdLayoutProfile, profile)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .top
                )
        }
    }
}
