import SwiftUI
import PencilKit

enum AnnotationTool: String, CaseIterable, Identifiable {
    case rect, circle, arrow, pen
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .rect:   return "square"
        case .circle: return "circle"
        case .arrow:  return "arrow.up.right"
        case .pen:    return "scribble"
        }
    }

    var label: String {
        switch self {
        case .rect:   return "Kutu"
        case .circle: return "Daire"
        case .arrow:  return "Ok"
        case .pen:    return "Çiz"
        }
    }
}

enum AnnotationColor: CaseIterable, Identifiable {
    case green, red, yellow
    var id: String { String(describing: self) }

    var color: Color {
        switch self {
        case .green:  return .rdGreen
        case .red:    return Color(hex: "#B42318")
        case .yellow: return Color(hex: "#FFD75A")
        }
    }

    var uiColor: UIColor {
        UIColor(color)
    }
}

/// Photo üzerinde çizilmiş kutu/daire/ok şekli (oransal koordinat).
struct ShapeAnnotation: Identifiable, Equatable {
    let id = UUID()
    let tool: AnnotationTool
    let color: AnnotationColor
    /// 0..1 oranında koordinat — photo frame'e göre.
    let start: CGPoint
    let end: CGPoint
}
