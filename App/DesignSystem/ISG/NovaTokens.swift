// Generated from the pinned OSGB expert reference by scripts/isg/nova_tokens.mjs.
// No other-role themes, backend rules or runtime activation. Do not edit by hand.
import Foundation

struct NovaRGBA: Equatable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Double
}

enum NovaColorToken: String, CaseIterable {
    case canvas
    case canvasSheet
    case surface
    case surfacePressed
    case surfaceMuted
    case glass
    case glassBorder
    case text
    case textSecondary
    case textTertiary
    case textMuted
    case textSubtle
    case textPlaceholder
    case onDark
    case hairline
    case border
    case borderStrong
    case borderMuted
    case inverse
    case onInverse
    case scrim
    case accent
    case accentInk
    case accentSoft
    case onAccent
    case statusSuccessBg
    case statusSuccessInk
    case statusSuccessDot
    case statusWarningBg
    case statusWarningInk
    case statusWarningDot
    case statusDangerBg
    case statusDangerInk
    case statusDangerDot
    case statusInfoBg
    case statusInfoInk
    case statusInfoDot
    case statusNeutralBg
    case statusNeutralInk
    case statusNeutralDot

    func rgba(dark: Bool) -> NovaRGBA {
        switch self {
        case .canvas: return dark ? NovaRGBA(red: 17, green: 17, blue: 20, alpha: 1.0) : NovaRGBA(red: 240, green: 240, blue: 240, alpha: 1.0)
        case .canvasSheet: return dark ? NovaRGBA(red: 23, green: 23, blue: 27, alpha: 1.0) : NovaRGBA(red: 247, green: 247, blue: 248, alpha: 1.0)
        case .surface: return dark ? NovaRGBA(red: 28, green: 28, blue: 33, alpha: 1.0) : NovaRGBA(red: 255, green: 255, blue: 255, alpha: 1.0)
        case .surfacePressed: return dark ? NovaRGBA(red: 35, green: 35, blue: 41, alpha: 1.0) : NovaRGBA(red: 250, green: 250, blue: 250, alpha: 1.0)
        case .surfaceMuted: return dark ? NovaRGBA(red: 38, green: 38, blue: 43, alpha: 1.0) : NovaRGBA(red: 244, green: 244, blue: 245, alpha: 1.0)
        case .glass: return dark ? NovaRGBA(red: 28, green: 28, blue: 33, alpha: 0.62) : NovaRGBA(red: 255, green: 255, blue: 255, alpha: 0.62)
        case .glassBorder: return dark ? NovaRGBA(red: 255, green: 255, blue: 255, alpha: 0.09) : NovaRGBA(red: 255, green: 255, blue: 255, alpha: 0.7)
        case .text: return dark ? NovaRGBA(red: 245, green: 245, blue: 247, alpha: 1.0) : NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1.0)
        case .textSecondary: return dark ? NovaRGBA(red: 201, green: 201, blue: 208, alpha: 1.0) : NovaRGBA(red: 75, green: 75, blue: 82, alpha: 1.0)
        case .textTertiary: return dark ? NovaRGBA(red: 168, green: 168, blue: 174, alpha: 1.0) : NovaRGBA(red: 107, green: 107, blue: 114, alpha: 1.0)
        case .textMuted: return dark ? NovaRGBA(red: 139, green: 139, blue: 143, alpha: 1.0) : NovaRGBA(red: 139, green: 139, blue: 143, alpha: 1.0)
        case .textSubtle: return dark ? NovaRGBA(red: 111, green: 111, blue: 119, alpha: 1.0) : NovaRGBA(red: 168, green: 168, blue: 174, alpha: 1.0)
        case .textPlaceholder: return dark ? NovaRGBA(red: 124, green: 124, blue: 132, alpha: 1.0) : NovaRGBA(red: 154, green: 154, blue: 159, alpha: 1.0)
        case .onDark: return dark ? NovaRGBA(red: 255, green: 255, blue: 255, alpha: 1.0) : NovaRGBA(red: 255, green: 255, blue: 255, alpha: 1.0)
        case .hairline: return dark ? NovaRGBA(red: 255, green: 255, blue: 255, alpha: 0.08) : NovaRGBA(red: 17, green: 17, blue: 17, alpha: 0.07)
        case .border: return dark ? NovaRGBA(red: 255, green: 255, blue: 255, alpha: 0.12) : NovaRGBA(red: 17, green: 17, blue: 17, alpha: 0.1)
        case .borderStrong: return dark ? NovaRGBA(red: 58, green: 58, blue: 66, alpha: 1.0) : NovaRGBA(red: 213, green: 213, blue: 218, alpha: 1.0)
        case .borderMuted: return dark ? NovaRGBA(red: 43, green: 43, blue: 49, alpha: 1.0) : NovaRGBA(red: 236, green: 236, blue: 239, alpha: 1.0)
        case .inverse: return dark ? NovaRGBA(red: 245, green: 245, blue: 247, alpha: 1.0) : NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1.0)
        case .onInverse: return dark ? NovaRGBA(red: 17, green: 17, blue: 20, alpha: 1.0) : NovaRGBA(red: 255, green: 255, blue: 255, alpha: 1.0)
        case .scrim: return dark ? NovaRGBA(red: 0, green: 0, blue: 0, alpha: 0.55) : NovaRGBA(red: 15, green: 15, blue: 17, alpha: 0.38)
        case .accent: return dark ? NovaRGBA(red: 46, green: 210, blue: 86, alpha: 1.0) : NovaRGBA(red: 46, green: 210, blue: 86, alpha: 1.0)
        case .accentInk: return dark ? NovaRGBA(red: 15, green: 122, blue: 52, alpha: 1.0) : NovaRGBA(red: 15, green: 122, blue: 52, alpha: 1.0)
        case .accentSoft: return dark ? NovaRGBA(red: 21, green: 58, blue: 36, alpha: 1.0) : NovaRGBA(red: 234, green: 251, blue: 239, alpha: 1.0)
        case .onAccent: return dark ? NovaRGBA(red: 255, green: 255, blue: 255, alpha: 1.0) : NovaRGBA(red: 255, green: 255, blue: 255, alpha: 1.0)
        case .statusSuccessBg: return dark ? NovaRGBA(red: 21, green: 58, blue: 36, alpha: 1.0) : NovaRGBA(red: 234, green: 251, blue: 239, alpha: 1.0)
        case .statusSuccessInk: return dark ? NovaRGBA(red: 95, green: 224, blue: 138, alpha: 1.0) : NovaRGBA(red: 15, green: 122, blue: 52, alpha: 1.0)
        case .statusSuccessDot: return dark ? NovaRGBA(red: 46, green: 210, blue: 86, alpha: 1.0) : NovaRGBA(red: 31, green: 168, blue: 69, alpha: 1.0)
        case .statusWarningBg: return dark ? NovaRGBA(red: 61, green: 47, blue: 20, alpha: 1.0) : NovaRGBA(red: 255, green: 246, blue: 232, alpha: 1.0)
        case .statusWarningInk: return dark ? NovaRGBA(red: 240, green: 190, blue: 106, alpha: 1.0) : NovaRGBA(red: 164, green: 112, blue: 15, alpha: 1.0)
        case .statusWarningDot: return dark ? NovaRGBA(red: 232, green: 161, blue: 58, alpha: 1.0) : NovaRGBA(red: 214, green: 139, blue: 25, alpha: 1.0)
        case .statusDangerBg: return dark ? NovaRGBA(red: 61, green: 30, blue: 28, alpha: 1.0) : NovaRGBA(red: 255, green: 238, blue: 236, alpha: 1.0)
        case .statusDangerInk: return dark ? NovaRGBA(red: 255, green: 139, blue: 129, alpha: 1.0) : NovaRGBA(red: 201, green: 56, blue: 44, alpha: 1.0)
        case .statusDangerDot: return dark ? NovaRGBA(red: 224, green: 69, blue: 59, alpha: 1.0) : NovaRGBA(red: 224, green: 69, blue: 59, alpha: 1.0)
        case .statusInfoBg: return dark ? NovaRGBA(red: 32, green: 36, blue: 74, alpha: 1.0) : NovaRGBA(red: 238, green: 240, blue: 255, alpha: 1.0)
        case .statusInfoInk: return dark ? NovaRGBA(red: 154, green: 164, blue: 255, alpha: 1.0) : NovaRGBA(red: 63, green: 75, blue: 196, alpha: 1.0)
        case .statusInfoDot: return dark ? NovaRGBA(red: 91, green: 140, blue: 247, alpha: 1.0) : NovaRGBA(red: 75, green: 87, blue: 214, alpha: 1.0)
        case .statusNeutralBg: return dark ? NovaRGBA(red: 38, green: 38, blue: 43, alpha: 1.0) : NovaRGBA(red: 244, green: 244, blue: 245, alpha: 1.0)
        case .statusNeutralInk: return dark ? NovaRGBA(red: 168, green: 168, blue: 174, alpha: 1.0) : NovaRGBA(red: 92, green: 92, blue: 99, alpha: 1.0)
        case .statusNeutralDot: return dark ? NovaRGBA(red: 107, green: 107, blue: 114, alpha: 1.0) : NovaRGBA(red: 180, green: 180, blue: 186, alpha: 1.0)
        }
    }
}

struct NovaTypeSpec {
    let fontName: String
    let weight: Int
    let size: Double
    let tracking: Double
    let lineHeight: Double
}

enum NovaTypeToken: String, CaseIterable {
    case screenTitle
    case sheetTitle
    case dialogTitle
    case brand
    case sectionTitle
    case cardTitle
    case button
    case buttonSm
    case body
    case bodyStrong
    case label
    case meta
    case metaQuiet
    case badge
    case tab
    case overline
    case micro

    var spec: NovaTypeSpec {
        switch self {
        case .screenTitle: return NovaTypeSpec(fontName: "PlusJakartaSans-ExtraBold", weight: 800, size: 22.0, tracking: -0.5, lineHeight: 28.0)
        case .sheetTitle: return NovaTypeSpec(fontName: "PlusJakartaSans-ExtraBold", weight: 800, size: 19.0, tracking: -0.4, lineHeight: 25.0)
        case .dialogTitle: return NovaTypeSpec(fontName: "PlusJakartaSans-ExtraBold", weight: 800, size: 16.5, tracking: -0.3, lineHeight: 22.0)
        case .brand: return NovaTypeSpec(fontName: "PlusJakartaSans-ExtraBold", weight: 800, size: 18.0, tracking: -0.3, lineHeight: 23.0)
        case .sectionTitle: return NovaTypeSpec(fontName: "PlusJakartaSans-ExtraBold", weight: 800, size: 14.0, tracking: -0.1, lineHeight: 19.0)
        case .cardTitle: return NovaTypeSpec(fontName: "PlusJakartaSans-Bold", weight: 700, size: 14.0, tracking: -0.2, lineHeight: 17.5)
        case .button: return NovaTypeSpec(fontName: "PlusJakartaSans-Bold", weight: 700, size: 15.0, tracking: 0.0, lineHeight: 20.0)
        case .buttonSm: return NovaTypeSpec(fontName: "PlusJakartaSans-Bold", weight: 700, size: 13.5, tracking: 0.0, lineHeight: 18.0)
        case .body: return NovaTypeSpec(fontName: "PlusJakartaSans-Medium", weight: 500, size: 13.0, tracking: 0.0, lineHeight: 18.0)
        case .bodyStrong: return NovaTypeSpec(fontName: "PlusJakartaSans-SemiBold", weight: 600, size: 12.5, tracking: 0.0, lineHeight: 17.0)
        case .label: return NovaTypeSpec(fontName: "PlusJakartaSans-Bold", weight: 700, size: 12.0, tracking: 0.0, lineHeight: 16.0)
        case .meta: return NovaTypeSpec(fontName: "PlusJakartaSans-SemiBold", weight: 600, size: 11.5, tracking: 0.0, lineHeight: 15.5)
        case .metaQuiet: return NovaTypeSpec(fontName: "PlusJakartaSans-Regular", weight: 400, size: 12.0, tracking: 0.0, lineHeight: 16.0)
        case .badge: return NovaTypeSpec(fontName: "PlusJakartaSans-Bold", weight: 700, size: 10.5, tracking: 0.0, lineHeight: 14.0)
        case .tab: return NovaTypeSpec(fontName: "PlusJakartaSans-Bold", weight: 700, size: 9.5, tracking: 0.1, lineHeight: 13.0)
        case .overline: return NovaTypeSpec(fontName: "PlusJakartaSans-ExtraBold", weight: 800, size: 10.5, tracking: 0.5, lineHeight: 14.0)
        case .micro: return NovaTypeSpec(fontName: "PlusJakartaSans-ExtraBold", weight: 800, size: 9.5, tracking: 0.6, lineHeight: 13.0)
        }
    }
}

enum NovaDimensionToken: String, CaseIterable {
    case radiusXs
    case radiusSm
    case radiusMd
    case radiusControl
    case radiusField
    case radiusChip
    case radiusCard
    case radiusPopover
    case radiusDialog
    case radiusSheet
    case radiusTabBar
    case radiusPill
    case spaceScreenX
    case spaceXs
    case spaceSm
    case spaceMd
    case spaceLg
    case spaceXl
    case space2xl
    case layoutTabBarHeight
    case layoutTabBarInset
    case layoutTabBarBottom
    case layoutScrollBottomInset
    case layoutScrollTopInset
    case layoutDeviceWidth
    case layoutDeviceHeight

    var value: Double {
        switch self {
        case .radiusXs: return 5.0
        case .radiusSm: return 7.0
        case .radiusMd: return 12.0
        case .radiusControl: return 14.0
        case .radiusField: return 16.0
        case .radiusChip: return 22.0
        case .radiusCard: return 22.0
        case .radiusPopover: return 26.0
        case .radiusDialog: return 28.0
        case .radiusSheet: return 32.0
        case .radiusTabBar: return 34.0
        case .radiusPill: return 999.0
        case .spaceScreenX: return 20.0
        case .spaceXs: return 4.0
        case .spaceSm: return 7.0
        case .spaceMd: return 10.0
        case .spaceLg: return 14.0
        case .spaceXl: return 18.0
        case .space2xl: return 24.0
        case .layoutTabBarHeight: return 66.0
        case .layoutTabBarInset: return 14.0
        case .layoutTabBarBottom: return 26.0
        case .layoutScrollBottomInset: return 122.0
        case .layoutScrollTopInset: return 58.0
        case .layoutDeviceWidth: return 402.0
        case .layoutDeviceHeight: return 874.0
        }
    }
}
