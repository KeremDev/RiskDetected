import SwiftUI

extension Color {
    // Brand
    static let rdBlack = Color(hex: "#0B0D0E")
    static let rdGraphite = Color(hex: "#1A1D1F")
    static let rdGreen = Color(hex: "#00B82E")
    static let rdGreenDark = Color(hex: "#008F24")
    static let rdGreenSoft = Color(hex: "#EAF8EE")
    static let rdPaper = Color(hex: "#FAFBFA")
    static let rdWhite = Color(hex: "#FFFFFF")

    // Secondary
    static let rdInk = Color(hex: "#202427")
    static let rdCharcoal = Color(hex: "#343A40")
    static let rdSlate = Color(hex: "#6B7280")
    static let rdLine = Color(hex: "#DDE3E0")
    static let rdFog = Color(hex: "#F1F4F2")
    static let rdCloud = Color(hex: "#F6F7F6")

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
