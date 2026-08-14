import SwiftUI

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
        self.font(.system(size: RDFontScale.size(style.size), weight: style.weight, design: style.design))
    }
}

extension Text {
    func rdMono(size: CGFloat = 12, weight: Font.Weight = .medium) -> Text {
        self.font(.system(size: RDFontScale.size(size), weight: weight, design: .monospaced))
    }
}
