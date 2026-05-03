import SwiftUI
import PencilKit

struct AnnotateView: View {
    var initialImage: UIImage? = nil
    var onCancel: () -> Void
    var onAnalyze: ([ShapeAnnotation], PKDrawing) -> Void

    @State private var tool: AnnotationTool = .rect
    @State private var color: AnnotationColor = .green
    @State private var shapes: [ShapeAnnotation] = []
    @State private var pkCanvas = PKCanvasView()

    // İn-progress drag preview (oransal)
    @State private var dragStart: CGPoint? = nil
    @State private var dragEnd: CGPoint? = nil

    var body: some View {
        ZStack {
            Color(hex: "#0B0D0E").ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                photoArea
                toolbar
                bottomCTA
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(RDPressableButtonStyle())

            Spacer()
            Text("İşaretleme")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()

            Button(action: undoLast) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(RDPressableButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Photo + Annotation Layer

    private var photoArea: some View {
        GeometryReader { geo in
            ZStack {
                if let img = initialImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    RDPlaceholderPhoto(label: "Saha fotoğrafı", cornerRadius: 18)
                }

                // Önceki şekiller
                ForEach(shapes) { s in
                    AnnotationShape(
                        shape: s,
                        size: geo.size
                    )
                }

                // İn-progress preview
                if tool != .pen, let s = dragStart, let e = dragEnd {
                    AnnotationShape(
                        shape: ShapeAnnotation(tool: tool, color: color, start: s, end: e),
                        size: geo.size
                    )
                    .opacity(0.85)
                }

                // Pen layer (en üstte, sadece pen tool aktifken dokunma alır)
                PencilCanvas(canvas: $pkCanvas, inkColor: color.uiColor, isActive: tool == .pen)
                    .background(Color.clear)
                    .allowsHitTesting(tool == .pen)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .gesture(shapeDragGesture(size: geo.size))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases) { t in
                let active = tool == t
                Button {
                    tool = t
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(t.label)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .frame(width: 52, height: 44)
                    .foregroundStyle(active ? Color.white : Color.rdCharcoal)
                    .background(active ? Color.rdBlack : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(Color.rdLine)
                .frame(width: 1, height: 28)
                .padding(.horizontal, 4)

            HStack(spacing: 6) {
                ForEach(AnnotationColor.allCases) { c in
                    let active = color == c
                    Button {
                        color = c
                    } label: {
                        Circle()
                            .fill(c.color)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .overlay(
                                Circle().stroke(active ? Color.rdBlack : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        RDButton(title: "İşaretli alanları analiz et", style: .detect, icon: "sparkles") {
            onAnalyze(shapes, pkCanvas.drawing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Gestures

    private func shapeDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard tool != .pen, size.width > 0, size.height > 0 else { return }
                let s = CGPoint(x: value.startLocation.x / size.width,
                                y: value.startLocation.y / size.height)
                let e = CGPoint(x: value.location.x / size.width,
                                y: value.location.y / size.height)
                dragStart = s
                dragEnd = e
            }
            .onEnded { _ in
                if let s = dragStart, let e = dragEnd, tool != .pen {
                    let dx = abs(e.x - s.x), dy = abs(e.y - s.y)
                    if dx > 0.02 || dy > 0.02 {
                        shapes.append(ShapeAnnotation(tool: tool, color: color, start: s, end: e))
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
                dragStart = nil
                dragEnd = nil
            }
    }

    private func undoLast() {
        if !shapes.isEmpty {
            shapes.removeLast()
        } else {
            pkCanvas.undoManager?.undo()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Annotation Shape Renderer

private struct AnnotationShape: View {
    let shape: ShapeAnnotation
    let size: CGSize

    var body: some View {
        let s = CGPoint(x: shape.start.x * size.width, y: shape.start.y * size.height)
        let e = CGPoint(x: shape.end.x * size.width, y: shape.end.y * size.height)
        let rect = CGRect(
            x: min(s.x, e.x), y: min(s.y, e.y),
            width: abs(e.x - s.x), height: abs(e.y - s.y)
        )

        ZStack {
            switch shape.tool {
            case .rect:
                RoundedRectangle(cornerRadius: 6)
                    .fill(shape.color.color.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(shape.color.color, lineWidth: 3)
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            case .circle:
                Ellipse()
                    .fill(shape.color.color.opacity(0.10))
                    .overlay(Ellipse().stroke(shape.color.color, lineWidth: 3))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            case .arrow:
                Path { p in
                    p.move(to: s)
                    p.addLine(to: e)
                }
                .stroke(shape.color.color,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                ArrowHead(start: s, end: e, color: shape.color.color)
            case .pen:
                EmptyView()
            }
        }
    }
}

private struct ArrowHead: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color

    var body: some View {
        Path { p in
            let angle = atan2(end.y - start.y, end.x - start.x)
            let size: CGFloat = 12
            let a1 = angle + .pi - .pi / 7
            let a2 = angle + .pi + .pi / 7
            p.move(to: end)
            p.addLine(to: CGPoint(x: end.x + cos(a1) * size, y: end.y + sin(a1) * size))
            p.addLine(to: CGPoint(x: end.x + cos(a2) * size, y: end.y + sin(a2) * size))
            p.closeSubpath()
        }
        .fill(color)
    }
}

#Preview {
    AnnotateView(onCancel: {}, onAnalyze: { _, _ in })
}
