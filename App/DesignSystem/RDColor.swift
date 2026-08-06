import SwiftUI
import UIKit

extension Color {
    // Brand
    static let rdBlack = Color.dynamic(light: "#0B0D0E", dark: "#F4F7F5")
    static let rdGraphite = Color.dynamic(light: "#1A1D1F", dark: "#E6ECE8")
    static let rdOnyx = Color(hex: "#0B0D0E")
    static let rdGreen = Color(hex: "#00B82E")
    static let rdGreenDark = Color(hex: "#008F24")
    static let rdGreenSoft = Color.dynamic(light: "#EAF8EE", dark: "#092F15")
    static let rdPlanPro = Color.rdGreen
    static let rdPlanProDark = Color.rdGreenDark
    static let rdPlanProSoft = Color.rdGreenSoft
    static let rdPlanPlus = Color(hex: "#F0A400")
    static let rdPlanPlusDark = Color(hex: "#9A5B00")
    static let rdPlanPlusSoft = Color.dynamic(light: "#FFF3D0", dark: "#3A2605")
    static let rdPaper = Color.dynamic(light: "#FAFBFA", dark: "#0B0D0E")
    static let rdWhite = Color.dynamic(light: "#FFFFFF", dark: "#151819")
    static let rdSelected = Color.dynamic(light: "#0B0D0E", dark: "#00B82E")
    static let rdCTA = Color.dynamic(light: "#0B0D0E", dark: "#00B82E")
    static let rdCompactCTA = Color.dynamic(light: "#F1F4F2", dark: "#00B82E")

    // Secondary
    static let rdInk = Color.dynamic(light: "#202427", dark: "#F0F4F1")
    static let rdCharcoal = Color.dynamic(light: "#343A40", dark: "#CAD3CE")
    static let rdSlate = Color.dynamic(light: "#6B7280", dark: "#9AA3AD")
    static let rdLine = Color.dynamic(light: "#DDE3E0", dark: "#2B3032")
    static let rdFog = Color.dynamic(light: "#F1F4F2", dark: "#202526")
    static let rdCloud = Color.dynamic(light: "#F6F7F6", dark: "#111415")

    // Risk semantic
    static let rdCritical = Color(hex: "#B42318")
    static let rdHigh = Color(hex: "#C76A00")
    static let rdMedium = Color(hex: "#D4A106")
    static let rdLow = Color(hex: "#237A3B")
    static let rdInfo = Color(hex: "#2F6FED")
    static let rdUnknown = Color(hex: "#94A3B8")

    // Risk semantic backgrounds
    static let rdCriticalBg = Color(hex: "#FDECEC")
    static let rdHighBg = Color(hex: "#FFF4DE")
    static let rdMediumBg = Color(hex: "#FEF9C3")
    static let rdLowBg = Color(hex: "#E8F5EF")
    static let rdUnknownBg = Color(hex: "#F1F4F2")

    // Risk semantic text colors (for chips)
    static let rdCriticalText = Color(hex: "#9F2623")
    static let rdHighText = Color(hex: "#A45A00")
    static let rdMediumText = Color(hex: "#854D0E")
    static let rdLowText = Color(hex: "#1F6B4A")
}

extension SubscriptionTier {
    var badgeLabel: String {
        switch self {
        case .free: return "FREE"
        case .plus: return "PLUS"
        case .pro: return "PRO"
        }
    }

    var badgeIcon: String {
        switch self {
        case .free: return "checkmark.circle.fill"
        case .plus: return "crown.fill"
        case .pro: return "star.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .free: return .rdSlate
        case .plus: return .rdPlanPlus
        case .pro: return .rdPlanPro
        }
    }

    var accentTextColor: Color {
        switch self {
        case .free: return .rdSlate
        case .plus: return .rdPlanPlusDark
        case .pro: return .rdPlanProDark
        }
    }

    var accentSoftColor: Color {
        switch self {
        case .free: return .rdFog
        case .plus: return .rdPlanPlusSoft
        case .pro: return .rdPlanProSoft
        }
    }
}

private extension Color {
    static func dynamic(light: String, dark: String) -> Color {
        Color(UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)

        let r, g, b, a: CGFloat
        switch cleaned.count {
        case 6:
            r = CGFloat((rgb >> 16) & 0xFF) / 255.0
            g = CGFloat((rgb >> 8) & 0xFF) / 255.0
            b = CGFloat(rgb & 0xFF) / 255.0
            a = 1.0
        case 8:
            r = CGFloat((rgb >> 24) & 0xFF) / 255.0
            g = CGFloat((rgb >> 16) & 0xFF) / 255.0
            b = CGFloat((rgb >> 8) & 0xFF) / 255.0
            a = CGFloat(rgb & 0xFF) / 255.0
        default:
            r = 0
            g = 0
            b = 0
            a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

enum RiskLevel: String, CaseIterable {
    case critical, high, medium, low, unknown

    var color: Color {
        switch self {
        case .critical: return .rdCritical
        case .high:     return .rdHigh
        case .medium:   return .rdMedium
        case .low:      return .rdLow
        case .unknown:  return .rdUnknown
        }
    }

    var bgColor: Color {
        switch self {
        case .critical: return .rdCriticalBg
        case .high:     return .rdHighBg
        case .medium:   return .rdMediumBg
        case .low:      return .rdLowBg
        case .unknown:  return .rdUnknownBg
        }
    }

    var textColor: Color {
        switch self {
        case .critical: return .rdCriticalText
        case .high:     return .rdHighText
        case .medium:   return .rdMediumText
        case .low:      return .rdLowText
        case .unknown:  return .rdSlate
        }
    }

    var label: String {
        switch self {
        case .critical: return RDLocalization.string("localizable.rdcolor.kritik.7e9236f2", table: .localizable, fallback: "Kritik")
        case .high:     return RDLocalization.string("localizable.rdcolor.yuksek.a9622121", table: .localizable, fallback: "Yüksek")
        case .medium:   return RDLocalization.string("localizable.rdcolor.orta.176aca81", table: .localizable, fallback: "Orta")
        case .low:      return RDLocalization.string("localizable.rdcolor.dusuk.41464c0c", table: .localizable, fallback: "Düşük")
        case .unknown:  return RDLocalization.string("localizable.rdcolor.bilinmiyor.9c217d6e", table: .localizable, fallback: "Bilinmiyor")
        }
    }

    var shortLabel: String {
        switch self {
        case .critical:
            return RDLanguage.current == .english ? "CRIT" : "KRT"
        case .high:     return RDLocalization.string("localizable.rdcolor.yuk.d70f8614", table: .localizable, fallback: "YÜK")
        case .medium:
            return RDLanguage.current == .english ? "MED" : "ORT"
        case .low:      return RDLocalization.string("localizable.rdcolor.dus.3e9b9792", table: .localizable, fallback: "DÜŞ")
        case .unknown:  return RDLocalization.string("localizable.rdcolor.copy.19ccae13", table: .localizable, fallback: "?")
        }
    }
}
