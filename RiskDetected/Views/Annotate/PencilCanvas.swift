import SwiftUI
import PencilKit

/// PKCanvasView'ı SwiftUI içinde sarmalayan ince bir wrapper.
/// `isActive=false` olduğunda dokunmaları geçirir (alttaki şekil çizimi gesture'ları çalışsın).
struct PencilCanvas: UIViewRepresentable {
    @Binding var canvas: PKCanvasView
    var inkColor: UIColor
    var isActive: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: inkColor, width: 6)
        canvas.alwaysBounceVertical = false
        canvas.alwaysBounceHorizontal = false
        return canvas
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        view.tool = PKInkingTool(.pen, color: inkColor, width: 6)
        view.isUserInteractionEnabled = isActive
    }
}
