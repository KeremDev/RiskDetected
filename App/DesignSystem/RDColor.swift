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
        case .critical: return "Kritik"
        case .high:     return "Yüksek"
        case .medium:   return "Orta"
        case .low:      return "Düşük"
        case .unknown:  return "Bilinmiyor"
        }
    }

    var shortLabel: String {
        switch self {
        case .critical: return "KRT"
        case .high:     return "YÜK"
        case .medium:   return "ORT"
        case .low:      return "DÜŞ"
        case .unknown:  return "?"
        }
    }
}
