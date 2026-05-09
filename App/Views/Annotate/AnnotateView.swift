import SwiftUI
import PencilKit

struct AnnotateView: View {
    var initialImage: UIImage? = nil
    var onCancel: () -> Void
    var onAnalyze: (UIImage) -> Void

    @State private var tool: AnnotationTool = .rect
    @State private var color: AnnotationColor = .green
    @State private var shapes: [ShapeAnnotation] = []
    @State private var pkCanvas = PKCanvasView()
    @State private var photoSize: CGSize = .zero

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
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(RDPressableButtonStyle())

            Spacer()
            Text("İşaretleme")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()

            Button(action: undoLast) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
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
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { photoSize = g.size }
                        .onChange(of: g.size) { photoSize = $0 }
                }
            )
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
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text(t.label)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
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
            onAnalyze(flattenedImage())
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

    // MARK: - Flatten annotated image

    /// `.scaledToFit` ile aynı aspect-fit rect — fotoğrafın ekranda göründüğü alan.
    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let imageAR     = imageSize.width / imageSize.height
        let containerAR = container.width / container.height
        if imageAR > containerAR {
            let h = container.width / imageAR
            return CGRect(x: 0, y: (container.height - h) / 2,
                          width: container.width, height: h)
        } else {
            let w = container.height * imageAR
            return CGRect(x: (container.width - w) / 2, y: 0,
                          width: w, height: container.height)
        }
    }

    private func flattenedImage() -> UIImage {
        let size = photoSize.width > 0 ? photoSize : CGSize(width: 1080, height: 1080)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // 0. Siyah arka plan (letterbox alanı)
            cgCtx.setFillColor(UIColor.black.cgColor)
            cgCtx.fill(CGRect(origin: .zero, size: size))

            // 1. Base photo — ekrandaki scaledToFit ile aynı rect
            if let img = initialImage {
                let fitRect = aspectFitRect(imageSize: img.size, in: size)
                img.draw(in: fitRect)
            }

            // 2. PK drawing (pen strokes) — container koordinatlarında
            let pkImg = pkCanvas.drawing.image(from: CGRect(origin: .zero, size: size),
                                               scale: UIScreen.main.scale)
            pkImg.draw(in: CGRect(origin: .zero, size: size))

            // 3. Shape annotations
            for s in shapes {
                let sx = s.start.x * size.width, sy = s.start.y * size.height
                let ex = s.end.x * size.width, ey = s.end.y * size.height
                let start = CGPoint(x: sx, y: sy)
                let end   = CGPoint(x: ex, y: ey)
                let rect  = CGRect(x: min(sx, ex), y: min(sy, ey),
                                   width: abs(ex - sx), height: abs(ey - sy))
                let uiColor = s.color.uiColor

                switch s.tool {
                case .rect:
                    cgCtx.setFillColor(uiColor.withAlphaComponent(0.12).cgColor)
                    cgCtx.setStrokeColor(uiColor.cgColor)
                    cgCtx.setLineWidth(3)
                    let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
                    cgCtx.addPath(path.cgPath)
                    cgCtx.drawPath(using: .fillStroke)

                case .circle:
                    cgCtx.setFillColor(uiColor.withAlphaComponent(0.10).cgColor)
                    cgCtx.setStrokeColor(uiColor.cgColor)
                    cgCtx.setLineWidth(3)
                    cgCtx.addEllipse(in: rect)
                    cgCtx.drawPath(using: .fillStroke)

                case .arrow:
                    cgCtx.setStrokeColor(uiColor.cgColor)
                    cgCtx.setLineWidth(3)
                    cgCtx.setLineCap(.round)
                    cgCtx.move(to: start)
                    cgCtx.addLine(to: end)
                    cgCtx.strokePath()
                    // Arrowhead
                    let angle = atan2(end.y - start.y, end.x - start.x)
                    let arrowSize: CGFloat = 12
                    let a1 = angle + .pi - .pi / 7
                    let a2 = angle + .pi + .pi / 7
                    cgCtx.setFillColor(uiColor.cgColor)
                    let head = UIBezierPath()
                    head.move(to: end)
                    head.addLine(to: CGPoint(x: end.x + cos(a1) * arrowSize,
                                             y: end.y + sin(a1) * arrowSize))
                    head.addLine(to: CGPoint(x: end.x + cos(a2) * arrowSize,
                                             y: end.y + sin(a2) * arrowSize))
                    head.close()
                    cgCtx.addPath(head.cgPath)
                    cgCtx.fillPath()

                case .pen:
                    break
                }
            }
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
    AnnotateView(onCancel: {}, onAnalyze: { _ in })
}
