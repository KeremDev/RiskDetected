import SwiftUI
import UIKit

/// App-wide typography contract. The finding/result flow established Mulish as
/// the product typeface; every user-facing screen now resolves its existing
/// sizes and weights through this single mapping.
enum RDTypography {
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(
            postScriptName(for: weight),
            size: size,
            relativeTo: relativeTextStyle(for: size)
        )
    }

    static func font(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design _: Font.Design = .default
    ) -> Font {
        font(size, weight)
    }

    static func font(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        .custom(postScriptName(for: weight), size: size, relativeTo: textStyle)
    }

    static func font(
        _ style: Font.TextStyle,
        design _: Font.Design = .default
    ) -> Font {
        font(pointSize(for: style), defaultWeight(for: style))
    }

    static func uiFont(
        size: CGFloat,
        weight: UIFont.Weight = .regular
    ) -> UIFont {
        UIFont(name: postScriptName(for: weight), size: size)
            ?? UIFont.systemFont(ofSize: size, weight: weight)
    }

    private static func postScriptName(for weight: Font.Weight) -> String {
        if weight == .black { return "Mulish-Black" }
        if weight == .heavy { return "Mulish-ExtraBold" }
        if weight == .bold { return "Mulish-Bold" }
        if weight == .semibold { return "Mulish-SemiBold" }
        if weight == .medium { return "Mulish-Medium" }
        return "Mulish-Regular"
    }

    private static func postScriptName(for weight: UIFont.Weight) -> String {
        switch weight.rawValue {
        case UIFont.Weight.black.rawValue...: return "Mulish-Black"
        case UIFont.Weight.heavy.rawValue..<UIFont.Weight.black.rawValue: return "Mulish-ExtraBold"
        case UIFont.Weight.bold.rawValue..<UIFont.Weight.heavy.rawValue: return "Mulish-Bold"
        case UIFont.Weight.semibold.rawValue..<UIFont.Weight.bold.rawValue: return "Mulish-SemiBold"
        case UIFont.Weight.medium.rawValue..<UIFont.Weight.semibold.rawValue: return "Mulish-Medium"
        default: return "Mulish-Regular"
        }
    }

    private static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    private static func defaultWeight(for style: Font.TextStyle) -> Font.Weight {
        switch style {
        case .largeTitle, .title, .title2: return .bold
        case .title3, .headline: return .semibold
        default: return .regular
        }
    }

    private static func relativeTextStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 28...: return .largeTitle
        case 22..<28: return .title2
        case 20..<22: return .title3
        case 17..<20: return .body
        case 15..<17: return .subheadline
        case 13..<15: return .footnote
        case 12..<13: return .caption
        default: return .caption2
        }
    }
}

enum RDFontStyle {
    case largeTitle
    case title1
    case title2
    case title3
    case body
    case callout
    case subheadline
    case footnote
    case caption
    case data
    case sectionHeader

    var size: CGFloat {
        switch self {
        case .largeTitle:    return 34
        case .title1:        return 28
        case .title2:        return 22
        case .title3:        return 20
        case .body:          return 17
        case .callout:       return 16
        case .subheadline:   return 15
        case .footnote:      return 13
        case .caption:       return 12
        case .data:          return 13
        case .sectionHeader: return 13
        }
    }

    var weight: Font.Weight {
        switch self {
        case .largeTitle, .title1: return .bold
        case .title2:              return .bold
        case .title3:              return .semibold
        case .body:                return .regular
        case .callout:             return .medium
        case .subheadline:         return .regular
        case .footnote:            return .medium
        case .caption:             return .medium
        case .data:                return .medium
        case .sectionHeader:       return .semibold
        }
    }

    var design: Font.Design {
        switch self {
        case .data: return .monospaced
        default:    return .rounded
        }
    }
}

extension View {
    func rdFont(_ style: RDFontStyle) -> some View {
        self.font(
            RDTypography.font(
                size: RDFontScale.size(style.size),
                weight: style.weight,
                design: style.design
            )
        )
    }
}

extension Text {
    func rdMono(size: CGFloat = 12, weight: Font.Weight = .medium) -> Text {
        self.font(RDTypography.font(size: RDFontScale.size(size), weight: weight))
    }
}
