import SwiftUI

struct OBSplashView: View {
    let onNext: () -> Void
    @State private var arrowOffset: CGFloat = -6
    @State private var arrowOpacity: Double = 0
    @State private var floatY: CGFloat = 0

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                Spacer(minLength: 40)
                hero
                    .offset(y: floatY)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                            floatY = -5
                        }
                        animateArrow()
                    }

                Spacer()

                VStack(spacing: 10) {
                    Text(attributedTitle)
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-1.0)
                        .multilineTextAlignment(.center)
                        .obStage(delay: 0.76)

                    Text("Sahada gördüğünü dakikalar içinde\ndenetime hazır rapora dönüştür.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 320)
                        .obStage(delay: 0.86)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)

                Button {
                    OBHaptic.light(); onNext()
                } label: {
                    HStack(spacing: 10) {
                        Text("Başlayalım")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .bold))
                            .offset(x: arrowOffset)
                            .opacity(arrowOpacity)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.rdOnyx)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color.rdOnyx.opacity(0.2), radius: 28, y: 10)
                }
                .buttonStyle(OBPressStyle())
                .padding(.horizontal, 24)
                .obStage(delay: 0.96)

                HStack(spacing: 6) {
                    Capsule().fill(Color.rdOnyx).frame(width: 20, height: 6)
                    Circle().fill(Color.rdOnyx.opacity(0.14)).frame(width: 6, height: 6)
                    Circle().fill(Color.rdOnyx.opacity(0.14)).frame(width: 6, height: 6)
                    Circle().fill(Color.rdOnyx.opacity(0.14)).frame(width: 6, height: 6)
                }
                .padding(.top, 16)
                .padding(.bottom, 28)
                .obStage(delay: 1.06)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var attributedTitle: AttributedString {
        var s = AttributedString("Profesyonel İSG\nasistanın")
        s.foregroundColor = .rdOnyx
        var dot = AttributedString(".")
        dot.foregroundColor = .rdGreen
        return s + dot
    }

    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#FCFCFB"), Color(hex: "#F7F8F6"), Color(hex: "#F1F3F0")],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: "#FFE0A8").opacity(0.35), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color.rdGreen.opacity(0.1), .clear], center: .bottomLeading, startRadius: 0, endRadius: 280)
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        ZStack {
            OBSplashCharacter()
                .frame(width: 280, height: 280)

            chip(text: "Yüksekte çalışma", dotColor: .rdCritical)
                .offset(x: -100, y: -130)
                .obStage(delay: 0.32)
            chipMono(text: "Fine-Kinney 240", dotColor: .rdHigh)
                .offset(x: 80, y: -150)
                .obStage(delay: 0.42)
            chipCheck(text: "Rapor hazır")
                .offset(x: 92, y: 110)
                .obStage(delay: 0.52)
        }
        .frame(width: 320, height: 320)
    }

    private func chip(text: String, dotColor: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
                .overlay(Circle().stroke(dotColor.opacity(0.18), lineWidth: 3))
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Color.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 18, y: 4)
    }

    private func chipMono(text: String, dotColor: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Color.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 18, y: 4)
    }

    private func chipCheck(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.rdGreen)
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.rdLow)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Color.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 18, y: 4)
    }

    private func animateArrow() {
        Task {
            while !Task.isCancelled {
                arrowOffset = -6; arrowOpacity = 0
                withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.4)) {
                    arrowOffset = 0; arrowOpacity = 1
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.6)) {
                    arrowOffset = 10; arrowOpacity = 0
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }
}

// MARK: - Splash character (Canvas port of original SVG illustration)
// İSG specialist with green hard hat, orange high-vis vest, holding phone
// that previews a Fine-Kinney 240 risk report. Drawn in a 280×280 box.
struct OBSplashCharacter: View {
    @State private var scanDash: CGFloat = 0
    @State private var sparkleAngle: Double = 0
    @State private var phoneScale: CGFloat = 0.92
    @State private var phoneOpacity: Double = 0

    var body: some View {
        Canvas { ctx, _ in
            // Background circles (clipped via clipPath circle in SVG — we just draw filled circles)
            ctx.fill(Path(ellipseIn: CGRect(x: 22, y: 22, width: 236, height: 236)),
                     with: .color(Color(hex: "#EAF8EE")))
            ctx.fill(Path(ellipseIn: CGRect(x: 32, y: 32, width: 136, height: 136)),
                     with: .color(Color(hex: "#F4FBF6")))

            // Ground ellipse (clipped to bg circle)
            var groundClip = ctx
            groundClip.clip(to: Path(ellipseIn: CGRect(x: 22, y: 22, width: 236, height: 236)))
            groundClip.fill(Path(ellipseIn: CGRect(x: 20, y: 226, width: 240, height: 28)),
                            with: .color(Color(hex: "#D8EFDF")))

            // Decorative dots (within bg)
            groundClip.fill(Path(ellipseIn: CGRect(x: 57.5, y: 77.5, width: 5, height: 5)),
                            with: .color(Color.rdGreen.opacity(0.4)))
            groundClip.fill(Path(ellipseIn: CGRect(x: 218, y: 58, width: 4, height: 4)),
                            with: .color(Color(hex: "#FFB300").opacity(0.5)))
            groundClip.fill(Path(ellipseIn: CGRect(x: 46, y: 178, width: 4, height: 4)),
                            with: .color(Color.rdCritical.opacity(0.35)))
            groundClip.fill(Path(ellipseIn: CGRect(x: 227.5, y: 197.5, width: 5, height: 5)),
                            with: .color(Color.rdGreen.opacity(0.4)))

            // CHARACTER (translate to 140, 138 like SVG)
            var cc = ctx
            cc.translateBy(x: 140, y: 138)
            drawCharacter(in: &cc)
        }
        // Phone overlaid as a separate View so animations are simpler (rotate + entry)
        .overlay(alignment: .topLeading) {
            phone
                .scaleEffect(phoneScale)
                .opacity(phoneOpacity)
                .rotationEffect(.degrees(-10), anchor: .center)
                .offset(x: 140 - 44 - 22, y: 138 + 36 - 30)
        }
        .overlay(scanBeam)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) {
                phoneScale = 1.0; phoneOpacity = 1.0
            }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                scanDash = -14
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                sparkleAngle = 360
            }
        }
    }

    private func drawCharacter(in ctx: inout GraphicsContext) {
        let skin = Color(hex: "#F0C49A")
        let dark = Color(hex: "#0B0D0E")
        let pants = Color(hex: "#1F2225")
        let vest = Color(hex: "#FFB300")
        let hat = Color.rdGreen
        let hatDark = Color(hex: "#008F24")

        // Pants left
        var pl = Path()
        pl.move(to: CGPoint(x: -22, y: 64))
        pl.addLine(to: CGPoint(x: -22, y: 100))
        pl.addQuadCurve(to: CGPoint(x: -16, y: 106), control: CGPoint(x: -22, y: 106))
        pl.addLine(to: CGPoint(x: -8, y: 106))
        pl.addQuadCurve(to: CGPoint(x: -2, y: 100), control: CGPoint(x: -2, y: 106))
        pl.addLine(to: CGPoint(x: -2, y: 64))
        pl.closeSubpath()
        ctx.fill(pl, with: .color(pants))

        // Pants right
        var pr = Path()
        pr.move(to: CGPoint(x: 22, y: 64))
        pr.addLine(to: CGPoint(x: 22, y: 100))
        pr.addQuadCurve(to: CGPoint(x: 16, y: 106), control: CGPoint(x: 22, y: 106))
        pr.addLine(to: CGPoint(x: 8, y: 106))
        pr.addQuadCurve(to: CGPoint(x: 2, y: 100), control: CGPoint(x: 2, y: 106))
        pr.addLine(to: CGPoint(x: 2, y: 64))
        pr.closeSubpath()
        ctx.fill(pr, with: .color(pants))

        // Shoes
        ctx.fill(Path(ellipseIn: CGRect(x: -25, y: 102, width: 20, height: 8)), with: .color(dark))
        ctx.fill(Path(ellipseIn: CGRect(x: 5, y: 102, width: 20, height: 8)), with: .color(dark))

        // Vest (orange safety vest)
        var body = Path()
        body.move(to: CGPoint(x: -38, y: -16))
        body.addQuadCurve(to: CGPoint(x: -32, y: -24), control: CGPoint(x: -38, y: -22))
        body.addLine(to: CGPoint(x: -10, y: -32))
        body.addLine(to: CGPoint(x: 10, y: -32))
        body.addLine(to: CGPoint(x: 32, y: -24))
        body.addQuadCurve(to: CGPoint(x: 38, y: -16), control: CGPoint(x: 38, y: -22))
        body.addLine(to: CGPoint(x: 38, y: 60))
        body.addQuadCurve(to: CGPoint(x: 30, y: 68), control: CGPoint(x: 38, y: 68))
        body.addLine(to: CGPoint(x: -30, y: 68))
        body.addQuadCurve(to: CGPoint(x: -38, y: 60), control: CGPoint(x: -38, y: 68))
        body.closeSubpath()
        ctx.fill(body, with: .color(vest))

        // White shirt under V
        var shirt = Path()
        shirt.move(to: CGPoint(x: -10, y: -32))
        shirt.addLine(to: CGPoint(x: 0, y: -8))
        shirt.addLine(to: CGPoint(x: 10, y: -32))
        shirt.addLine(to: CGPoint(x: 10, y: -16))
        shirt.addLine(to: CGPoint(x: 0, y: -4))
        shirt.addLine(to: CGPoint(x: -10, y: -16))
        shirt.closeSubpath()
        ctx.fill(shirt, with: .color(.white))

        // Reflective stripes
        ctx.fill(Path(CGRect(x: -38, y: 30, width: 76, height: 4)),
                 with: .color(.white.opacity(0.9)))
        ctx.fill(Path(CGRect(x: -38, y: 40, width: 76, height: 2)),
                 with: .color(.white.opacity(0.55)))

        // Vest sparkle badge
        ctx.fill(Path(ellipseIn: CGRect(x: 16, y: 0, width: 12, height: 12)),
                 with: .color(Color.rdGreen))
        var spark = Path()
        spark.move(to: CGPoint(x: 22, y: 2))
        spark.addLine(to: CGPoint(x: 23, y: 5))
        spark.addLine(to: CGPoint(x: 26, y: 6))
        spark.addLine(to: CGPoint(x: 23, y: 7))
        spark.addLine(to: CGPoint(x: 22, y: 10))
        spark.addLine(to: CGPoint(x: 21, y: 7))
        spark.addLine(to: CGPoint(x: 18, y: 6))
        spark.addLine(to: CGPoint(x: 21, y: 5))
        spark.closeSubpath()
        ctx.fill(spark, with: .color(.white))

        // Right arm (holding phone forward)
        var arm1 = Path()
        arm1.move(to: CGPoint(x: -36, y: -18))
        arm1.addQuadCurve(to: CGPoint(x: -52, y: 22), control: CGPoint(x: -52, y: -8))
        arm1.addQuadCurve(to: CGPoint(x: -36, y: 42), control: CGPoint(x: -52, y: 40))
        arm1.addLine(to: CGPoint(x: -22, y: 36))
        arm1.addLine(to: CGPoint(x: -22, y: -8))
        arm1.closeSubpath()
        ctx.fill(arm1, with: .color(skin))

        // Left arm by side
        var arm2 = Path()
        arm2.move(to: CGPoint(x: 36, y: -18))
        arm2.addQuadCurve(to: CGPoint(x: 52, y: 22), control: CGPoint(x: 52, y: -8))
        arm2.addQuadCurve(to: CGPoint(x: 44, y: 40), control: CGPoint(x: 52, y: 36))
        arm2.addQuadCurve(to: CGPoint(x: 38, y: 30), control: CGPoint(x: 38, y: 38))
        arm2.addLine(to: CGPoint(x: 38, y: -8))
        arm2.closeSubpath()
        ctx.fill(arm2, with: .color(skin))

        // Hand (oval)
        ctx.fill(Path(ellipseIn: CGRect(x: -51, y: 30, width: 14, height: 12)),
                 with: .color(skin))

        // Neck
        ctx.fill(Path(CGRect(x: -8, y: -46, width: 16, height: 14)),
                 with: .color(skin))

        // Face circle
        ctx.fill(Path(ellipseIn: CGRect(x: -22, y: -80, width: 44, height: 44)),
                 with: .color(skin))

        // Ears
        ctx.fill(Path(ellipseIn: CGRect(x: -25, y: -63, width: 6, height: 10)),
                 with: .color(skin))
        ctx.fill(Path(ellipseIn: CGRect(x: 19, y: -63, width: 6, height: 10)),
                 with: .color(skin))

        // Eyebrows
        var br1 = Path()
        br1.move(to: CGPoint(x: -10, y: -68))
        br1.addQuadCurve(to: CGPoint(x: -4, y: -68), control: CGPoint(x: -7, y: -70))
        ctx.stroke(br1, with: .color(Color(hex: "#2A2D2F")),
                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        var br2 = Path()
        br2.move(to: CGPoint(x: 4, y: -68))
        br2.addQuadCurve(to: CGPoint(x: 10, y: -68), control: CGPoint(x: 7, y: -70))
        ctx.stroke(br2, with: .color(Color(hex: "#2A2D2F")),
                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

        // Eyes
        ctx.fill(Path(ellipseIn: CGRect(x: -8.8, y: -63.8, width: 3.6, height: 3.6)),
                 with: .color(dark))
        ctx.fill(Path(ellipseIn: CGRect(x: 5.2, y: -63.8, width: 3.6, height: 3.6)),
                 with: .color(dark))

        // Smile
        var smile = Path()
        smile.move(to: CGPoint(x: -6, y: -50))
        smile.addQuadCurve(to: CGPoint(x: 6, y: -50), control: CGPoint(x: 0, y: -45))
        ctx.stroke(smile, with: .color(dark),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Cheek blush
        ctx.fill(Path(ellipseIn: CGRect(x: -16, y: -58, width: 6, height: 6)),
                 with: .color(Color(hex: "#FF9B7C").opacity(0.4)))
        ctx.fill(Path(ellipseIn: CGRect(x: 10, y: -58, width: 6, height: 6)),
                 with: .color(Color(hex: "#FF9B7C").opacity(0.4)))

        // Hair under hat
        var hair = Path()
        hair.move(to: CGPoint(x: -22, y: -68))
        hair.addQuadCurve(to: CGPoint(x: -16, y: -78), control: CGPoint(x: -22, y: -76))
        hair.addLine(to: CGPoint(x: 16, y: -78))
        hair.addQuadCurve(to: CGPoint(x: 22, y: -68), control: CGPoint(x: 22, y: -76))
        hair.addLine(to: CGPoint(x: 16, y: -72))
        hair.addLine(to: CGPoint(x: -16, y: -72))
        hair.closeSubpath()
        ctx.fill(hair, with: .color(Color(hex: "#2A2D2F")))

        // Hard hat dome
        var dome = Path()
        dome.move(to: CGPoint(x: -26, y: -76))
        dome.addQuadCurve(to: CGPoint(x: 0, y: -102), control: CGPoint(x: -26, y: -100))
        dome.addQuadCurve(to: CGPoint(x: 26, y: -76), control: CGPoint(x: 26, y: -100))
        dome.closeSubpath()
        ctx.fill(dome, with: .color(hat))

        // Hat crest
        var crest = Path()
        crest.move(to: CGPoint(x: -3, y: -100))
        crest.addQuadCurve(to: CGPoint(x: 3, y: -100), control: CGPoint(x: 0, y: -106))
        crest.addLine(to: CGPoint(x: 3, y: -84))
        crest.addLine(to: CGPoint(x: -3, y: -84))
        crest.closeSubpath()
        ctx.fill(crest, with: .color(hatDark))

        // Brim
        var brim = Path()
        brim.move(to: CGPoint(x: -30, y: -76))
        brim.addLine(to: CGPoint(x: 30, y: -76))
        brim.addLine(to: CGPoint(x: 28, y: -72))
        brim.addLine(to: CGPoint(x: -28, y: -72))
        brim.closeSubpath()
        ctx.fill(brim, with: .color(hatDark))

        // Hat highlight
        var hl = Path()
        hl.move(to: CGPoint(x: -20, y: -90))
        hl.addQuadCurve(to: CGPoint(x: 0, y: -98), control: CGPoint(x: -10, y: -98))
        ctx.stroke(hl, with: .color(Color(hex: "#5EE285").opacity(0.7)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // Magnifier accent on hat
        ctx.stroke(Path(ellipseIn: CGRect(x: 10, y: -86, width: 8, height: 8)),
                   with: .color(dark), lineWidth: 1.5)
        var handle = Path()
        handle.move(to: CGPoint(x: 17, y: -79))
        handle.addLine(to: CGPoint(x: 21, y: -75))
        ctx.stroke(handle, with: .color(dark),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: 12.8, y: -83.2, width: 2.4, height: 2.4)),
                 with: .color(Color(hex: "#FFB300")))
    }

    // Phone (44x60 in character coords, anchored at (-44, 36), rotated -10°)
    private var phone: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color.rdOnyx)
            RoundedRectangle(cornerRadius: 4).fill(.white)
                .padding(3)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Color.rdGreen).frame(width: 14, height: 3)
                Capsule().fill(Color.rdOnyx).frame(width: 22, height: 2.5)
                Capsule().fill(Color.rdLine).frame(width: 18, height: 2.5)
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(Color.rdHighBg).frame(width: 30, height: 9)
                    Text("240")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Color.rdHigh)
                }
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.rdFog).frame(width: 30, height: 14)
                    HStack(spacing: 3) {
                        Circle().fill(Color.rdGreen).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Capsule().fill(Color.rdOnyx).frame(width: 14, height: 2)
                            Capsule().fill(Color.rdSlate).frame(width: 10, height: 1.5)
                        }
                    }
                    .padding(.leading, 3)
                }
            }
            .padding(7)
        }
        .frame(width: 44, height: 60)
    }

    // Animated scanning beam between phone and detected target
    private var scanBeam: some View {
        Canvas { ctx, _ in
            var p = Path()
            p.move(to: CGPoint(x: 88, y: 174))
            p.addQuadCurve(to: CGPoint(x: 130, y: 178), control: CGPoint(x: 110, y: 168))
            ctx.stroke(p, with: .color(Color.rdGreen.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4], dashPhase: scanDash))
        }
        .allowsHitTesting(false)
    }
}
