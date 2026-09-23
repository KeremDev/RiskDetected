#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

// MARK: - Reveal

/// "İSG Adasına Hoşgeldiniz" — the screen between the splash and intro 1
/// (`design_handoff_reveal_screen`). Module cards drift upward in an endless
/// loop behind a white sheet; one card at a time is lifted into focus.
struct NovaOBRevealScreen: View {
    @ObservedObject var controller: NovaOBController
    let onLogin: () -> Void

    @State private var mascotRaised = false
    @State private var mascotVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .zIndex(20)
            NovaOBRevealStage()
                .frame(maxHeight: .infinity)
                .zIndex(0)
            sheet
                .padding(.top, -26)
                .zIndex(10)
        }
        .background(NovaOBReveal.page.ignoresSafeArea())
        .transition(.opacity)
        .onAppear(perform: raiseMascot)
    }

    private var topBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button { controller.go(.intro1) } label: {
                Text("Geç")
                    .font(NovaOB.font(14))
                    .foregroundColor(Color(hex: 0x6A7379))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
            }
            .buttonStyle(NovaPressStyle())
        }
        .padding(.horizontal, 20)
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            Text("İSG Adasına Hoşgeldiniz")
                .font(NovaOB.font(29, 800))
                .tracking(-0.9)
                .foregroundColor(Color(hex: 0x141C24))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // `text-wrap: balance` breaks the line after "tüm" at the design
            // width; the break is fixed so every device shows the same two
            // highlighter strokes.
            VStack(spacing: NovaOB.lineSpacing(16.5, 1.4)) {
                markedLine("İş Güvenliğinin tüm")
                markedLine("süreçleri artık tek bir yerde.")
            }
            .padding(.top, 10)

            Text("Takiplerini kolaylaştır, dokümanlarına hızla ulaş, işlerini düzenle.\nDaha az operasyon, daha fazla kontrol.")
                .font(NovaOB.font(14.5))
                .foregroundColor(Color(hex: 0x5C6873))
                .multilineTextAlignment(.center)
                .lineSpacing(NovaOB.lineSpacing(14.5, 1.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            actions
                .padding(.top, 98)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 34)
        // The prototype measures 34 from the frame's bottom edge, home
        // indicator included; the safe area already covers that part.
        .padding(.bottom, NovaOB.padBottom(34))
        .background(alignment: .top) {
            // Only the top corners are rounded; the bottom ones run off screen.
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white)
                .padding(.bottom, -80)
                .shadow(color: Color(hex: 0x142030).opacity(0.1), radius: 22, y: -16)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func markedLine(_ text: String) -> some View {
        let em: CGFloat = 16.5
        return Text(text)
            .font(NovaOB.font(em, 700))
            .tracking(-0.2)
            .foregroundColor(Color(hex: 0x2A343E))
            .lineLimit(1)
            .background(
                NovaOBMarkerStroke()
                    .padding(EdgeInsets(top: -0.16 * em, leading: -0.36 * em, bottom: -0.2 * em, trailing: -0.42 * em))
            )
    }

    private var actions: some View {
        HStack(alignment: .center, spacing: 20) {
            NovaOBPillButton(title: "Başlayalım", height: 60, fontSize: 17, horizontalPadding: 40) {
                controller.go(.intro1)
            }
            .background(alignment: .topLeading) {
                // Peeks over the CTA's top-left corner with its chin tucked
                // behind the button: 80×80, left −8, bottom 50 from the CTA's
                // bottom edge, pivoting on its own bottom centre.
                Image("NovaOBMascotPeek")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(mascotRaised ? -12 : 0), anchor: .bottom)
                    .offset(x: -8, y: -70 + (mascotRaised ? 0 : 46))
                    .opacity(mascotVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)

            Button(action: onLogin) {
                (
                    Text("Hesabın var mı?\n").font(NovaOB.font(13.5)).foregroundColor(NovaOB.slate)
                    + Text("Giriş yap").font(NovaOB.font(13.5, 700)).foregroundColor(NovaOB.ink)
                )
                .multilineTextAlignment(.trailing)
                .lineSpacing(NovaOB.lineSpacing(13.5, 1.45))
            }
            .buttonStyle(NovaPressStyle())
        }
    }

    /// `isgPeek`: 700 ms `cubic-bezier(.3,1.4,.5,1)` after 350 ms; opacity
    /// reaches 1 at the 40% keyframe. Reduce Motion shows the resting pose.
    private func raiseMascot() {
        guard !reduceMotion else {
            mascotRaised = true
            mascotVisible = true
            return
        }
        withAnimation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.7).delay(0.35)) { mascotRaised = true }
        withAnimation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.28).delay(0.35)) { mascotVisible = true }
    }
}

// MARK: - Card loop

/// The endless card column. There is no timer: every row plays the same
/// looping track, offset by `index × step`, sampled from the display clock —
/// the same phase model as the prototype's `isgSlotN` / `isgHaloN` keyframes,
/// so the loop never jumps or restarts and the wrap happens fully transparent.
private struct NovaOBRevealStage: View {
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
                    let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(start)
                    list(elapsed: elapsed)
                }
                .frame(height: NovaOBReveal.listHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .offset(y: -24)
            }
            .accessibilityHidden(true)
    }

    private func list(elapsed: TimeInterval) -> some View {
        let rows = NovaOBReveal.rows
        let cycle = Double(rows.count) * NovaOBReveal.step
        return ZStack {
            ForEach(rows.indices, id: \.self) { index in
                let phase = NovaOBReveal.phase(elapsed: elapsed, index: index, cycle: cycle)
                let opacity = NovaOBReveal.haloOpacity(phase: phase)
                if opacity > 0 {
                    Ellipse()
                        .fill(Color(hex: rows[index].color))
                        .frame(width: 380, height: 260)
                        .blur(radius: NovaOBReveal.cssBlur(60))
                        .opacity(opacity)
                        .offset(y: NovaOBReveal.listHeight * (0.44 - 0.5))
                        .zIndex(0)
                }
            }

            ForEach(rows.indices, id: \.self) { index in
                let phase = NovaOBReveal.phase(elapsed: elapsed, index: index, cycle: cycle)
                let style = NovaOBReveal.style(phase: phase, tint: rows[index].color)
                NovaOBRevealRow(row: rows[index], style: style)
                    .zIndex(style.zIndex)
            }

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [NovaOBReveal.page, NovaOBReveal.page.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 26)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
            .zIndex(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NovaOBRevealRow: View {
    let row: NovaOBReveal.Row
    let style: NovaOBReveal.RowStyle

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        HStack(spacing: 10) {
            NovaOBIconPath(path: row.icon, size: 19, color: style.icon.color, lineWidth: 1.7)
            Text(row.name)
                .font(NovaOB.font(13.5, 600))
                .foregroundColor(Color(hex: 0x1B242E))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.meta)
                .font(NovaOB.font(12, 600))
                .foregroundColor(Color(hex: 0x7A848E))
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color(hex: 0xC3CAD2)).frame(width: 3, height: 3)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, style.verticalPadding)
        .background(
            shape
                .fill(style.background.color)
                .shadow(
                    color: Color(hex: 0x18263A).opacity(style.shadowAlpha),
                    radius: style.shadowBlur / 2, y: style.shadowY
                )
        )
        .overlay(shape.strokeBorder(style.border.color, lineWidth: 1))
        .background(
            // `box-shadow: 0 0 0 Npx` — a solid ring outside the border box.
            RoundedRectangle(cornerRadius: 16 + style.ring, style: .continuous)
                .fill(style.ringColor.color)
                .padding(-style.ring)
        )
        .scaleEffect(style.scale)
        .blur(radius: NovaOBReveal.cssBlur(style.blur))
        .opacity(style.opacity)
        .padding(.horizontal, 24)
        .offset(y: style.offsetY)
    }
}

// MARK: - Highlighter

/// `.isg-marker`: three offset, angled, translucent yellow strokes that never
/// quite cover the text, inside an irregular elliptical-corner box.
private struct NovaOBMarkerStroke: View {
    private struct Layer {
        let angle: Double
        let stops: [(Double, Double, UInt32)]
        let height: CGFloat
        let position: CGFloat
    }

    private static let layers: [Layer] = [
        Layer(angle: 100, stops: [
            (0, 0, 0xFFE496), (0.34, 0.03, 0xFFE496), (0.24, 0.30, 0xFFDE8C),
            (0.32, 0.52, 0xFFE496), (0.28, 0.62, 0xFFE496), (0, 0.66, 0xFFE496)
        ], height: 0.58, position: 0.92),
        Layer(angle: 96, stops: [
            (0, 0.38, 0xFFE292), (0.26, 0.43, 0xFFE292), (0.30, 0.70, 0xFFDC88),
            (0.22, 0.84, 0xFFE292), (0, 0.88, 0xFFE292)
        ], height: 0.50, position: 0.30),
        Layer(angle: 104, stops: [
            (0, 0.10, 0xFFE69C), (0.16, 0.16, 0xFFE69C), (0.12, 0.40, 0xFFE69C), (0, 0.48, 0xFFE69C)
        ], height: 0.34, position: 0.08)
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                ForEach(Self.layers.indices, id: \.self) { index in
                    let layer = Self.layers[index]
                    let height = size.height * layer.height
                    let points = Self.gradientPoints(angle: layer.angle, width: size.width, height: height)
                    LinearGradient(
                        stops: layer.stops.map {
                            Gradient.Stop(color: Color(hex: $0.2).opacity($0.0), location: $0.1)
                        },
                        startPoint: points.start, endPoint: points.end
                    )
                    .frame(width: size.width, height: height)
                    .offset(y: (size.height - height) * layer.position)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(NovaOBMarkerShape())
        }
    }

    /// CSS `linear-gradient(<angle>)` endpoints for a box, as unit points.
    private static func gradientPoints(angle: Double, width: CGFloat, height: CGFloat) -> (start: UnitPoint, end: UnitPoint) {
        let radians = angle * .pi / 180
        let dx = CGFloat(sin(radians)), dy = CGFloat(-cos(radians))
        let half = (abs(width * dx) + abs(height * dy)) / 2
        let sx = 0.5 - dx * half / max(width, 1), sy = 0.5 - dy * half / max(height, 1)
        return (UnitPoint(x: sx, y: sy), UnitPoint(x: 1 - sx, y: 1 - sy))
    }
}

/// `border-radius: 1.4em .35em 1.6em .5em / .7em 1.2em .45em 1em`, scaled
/// down the way CSS does when adjacent radii overflow the box.
private struct NovaOBMarkerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let em: CGFloat = 16.5
        var rx: [CGFloat] = [1.4, 0.35, 1.6, 0.5].map { $0 * em } // TL, TR, BR, BL
        var ry: [CGFloat] = [0.7, 1.2, 0.45, 1.0].map { $0 * em }
        let factor = min(
            1,
            rect.width / (rx[0] + rx[1]), rect.width / (rx[3] + rx[2]),
            rect.height / (ry[0] + ry[3]), rect.height / (ry[1] + ry[2])
        )
        rx = rx.map { $0 * factor }
        ry = ry.map { $0 * factor }

        let k: CGFloat = 0.5523
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rx[0], y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rx[1], y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + ry[1]),
            control1: CGPoint(x: rect.maxX - rx[1] * (1 - k), y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + ry[1] * (1 - k))
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - ry[2]))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rx[2], y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - ry[2] * (1 - k)),
            control2: CGPoint(x: rect.maxX - rx[2] * (1 - k), y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + rx[3], y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - ry[3]),
            control1: CGPoint(x: rect.minX + rx[3] * (1 - k), y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - ry[3] * (1 - k))
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + ry[0]))
        path.addCurve(
            to: CGPoint(x: rect.minX + rx[0], y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + ry[0] * (1 - k)),
            control2: CGPoint(x: rect.minX + rx[0] * (1 - k), y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Data + timing model

/// Tokens, card data and the slot/halo timing tables from `reveal-data.js`.
enum NovaOBReveal {
    static let page = Color(hex: 0xF5F7FA)
    static let listHeight: CGFloat = 412

    /// SwiftUI's blur radius spreads about twice as far as CSS `blur()`'s
    /// standard deviation; halving it matches the prototype side by side.
    static func cssBlur(_ css: CGFloat) -> CGFloat { css / 2 }
    /// Seconds each row spends per slot; one full loop is `rows.count × step`.
    static let step: Double = 1.55

    struct Row {
        let name: String
        let meta: String
        let color: UInt32
        let icon: String
    }

    static let rows: [Row] = [
        Row(name: "Risk Analizi Oluştur", meta: "12 Aktif Analiz", color: 0x3B82F6,
            icon: "M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6l7-3zM12 8v4.5M12 15.5h.01"),
        Row(name: "Açık Uygunsuzluklar", meta: "34 Açık", color: 0xE4572E,
            icon: "M12 4l8.5 15H3.5L12 4zM12 10v4M12 17h.01"),
        Row(name: "Firma Yönetimi", meta: "8 Firma", color: 0x4F46E5,
            icon: "M4 21V5l8-2v18M12 8h8v13M4 21h16M8 8h.01M8 12h.01M8 16h.01M16 12h.01M16 16h.01"),
        Row(name: "Gecikmiş Periyodik Kontrol", meta: "7 Gün", color: 0xD97706,
            icon: "M5 7h14v13H5zM5 12h14M10 4v3M14 4v3"),
        Row(name: "Kapatılan DÖF\u{2019}ler", meta: "↗ %18 · 46 Adet", color: 0x16A34A,
            icon: "M7 3h7l4 4v14H7zM14 3v4h4M10 14l2 2 3.5-3.5"),
        Row(name: "Acil Durum Eylem Planı", meta: "3 Güncelleme", color: 0xF97316,
            icon: "M13 3l-1.5 7H16l-5 11 1.2-7.5H8L13 3z"),
        Row(name: "Eğitimi Geçen Personel", meta: "128 Kişi", color: 0x0EA5A5,
            icon: "M9 11a3.2 3.2 0 100-6.4 3.2 3.2 0 000 6.4zM3.5 19.5c0-3 2.5-5 5.5-5s5.5 2 5.5 5M17 8.6a2.6 2.6 0 010 5.2M16.6 15c2.3.3 4 2.1 4 4.5"),
        Row(name: "AdamxSaat Eğitim Süresi", meta: "1.240 Saat", color: 0x6366F1,
            icon: "M12 3a9 9 0 100 18 9 9 0 000-18zM12 7.5V12l3.2 2"),
        Row(name: "Fotoğraf Analiz", meta: "56 Tespit", color: 0x0891B2,
            icon: "M4 8h3l2-3h6l2 3h3v11H4zM12 17a3.5 3.5 0 100-7 3.5 3.5 0 000 7z"),
        Row(name: "Tatbikat Yönetimi", meta: "2 Planlı", color: 0x7C3AED,
            icon: "M5 21V4M5 4h11l-2 4 2 4H5"),
        Row(name: "Yüksek Uygunsuzluk Oranı", meta: "↗ %12,4", color: 0xDB2777,
            icon: "M4 19h16M6 15l4-4 3 3 5-6M14 8h4v4"),
        Row(name: "Kritik Uygunsuzluk Oranı", meta: "%3,1", color: 0xDC2626,
            icon: "M8.5 3h7L21 8.5v7L15.5 21h-7L3 15.5v-7zM12 8v5M12 16h.01"),
        Row(name: "Firma Skoru", meta: "86 / 100", color: 0xCA8A04,
            icon: "M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.8l-5.2 2.8 1-5.8-4.3-4.1 5.9-.9z"),
        Row(name: "Firma Bazlı İstatistikler", meta: "8 Firma · 24 Rapor", color: 0x2563EB,
            icon: "M4 20V10M10 20V4M16 20v-7M22 20H2"),
        Row(name: "OSGB Bazlı İstatistikler", meta: "3 OSGB · %91", color: 0x0D9488,
            icon: "M12 3a9 9 0 109 9h-9V3zM15 3.5A8 8 0 0120.5 9H15V3.5z"),
        Row(name: "Uzman Atamaları", meta: "14 Uzman · 2 Bekleyen", color: 0x9333EA,
            icon: "M9 11a3.2 3.2 0 100-6.4 3.2 3.2 0 000 6.4zM3.5 19.5c0-3 2.5-5 5.5-5s5.5 2 5.5 5M16 11l2 2 4-4")
    ]

    /// Slot table, keyed by position relative to the active row
    /// (positive = below, negative = above): translateY, opacity, blur.
    private static let slots: [Int: (CGFloat, Double, CGFloat)] = [
        6: (288, 0, 1.2), 5: (240, 0, 1.2), 4: (192, 0.12, 3), 3: (144, 0.28, 2.2), 2: (96, 0.44, 1.6), 1: (48, 0.62, 0.9),
        -1: (-53, 0.36, 1.2), -2: (-106, 0.14, 2), -3: (-159, 0, 1.05), -4: (-212, 0, 1.2), -5: (-265, 0, 1.2)
    ]

    /// Share of each slot spent holding still; the rest is the slide.
    private static let hold = 0.672
    private static let slide = NovaOBCubicBezier(0.36, 0.02, 0.2, 1)
    private static let pop = NovaOBCubicBezier(0.2, 0.7, 0.3, 1)
    private static let settle = NovaOBCubicBezier(0.45, 0, 0.35, 1)

    struct RowStyle {
        var offsetY: CGFloat
        var scale: CGFloat
        var opacity: Double
        var blur: CGFloat
        var background: NovaOBRGBA
        var ring: CGFloat
        var ringColor: NovaOBRGBA
        var shadowY: CGFloat
        var shadowBlur: CGFloat
        var shadowAlpha: Double
        var border: NovaOBRGBA
        var icon: NovaOBRGBA
        var verticalPadding: CGFloat
        var zIndex: Double

        func mixed(with other: RowStyle, _ t: Double) -> RowStyle {
            let c = CGFloat(t)
            return RowStyle(
                offsetY: offsetY + (other.offsetY - offsetY) * c,
                scale: scale + (other.scale - scale) * c,
                opacity: opacity + (other.opacity - opacity) * t,
                blur: blur + (other.blur - blur) * c,
                background: background.mixed(with: other.background, t),
                ring: ring + (other.ring - ring) * c,
                ringColor: ringColor.mixed(with: other.ringColor, t),
                shadowY: shadowY + (other.shadowY - shadowY) * c,
                shadowBlur: shadowBlur + (other.shadowBlur - shadowBlur) * c,
                shadowAlpha: shadowAlpha + (other.shadowAlpha - shadowAlpha) * t,
                border: border.mixed(with: other.border, t),
                icon: icon.mixed(with: other.icon, t),
                verticalPadding: verticalPadding + (other.verticalPadding - verticalPadding) * c,
                zIndex: (zIndex + (other.zIndex - zIndex) * t).rounded()
            )
        }
    }

    /// Fraction of the loop a row is at, 0..<1.
    static func phase(elapsed: TimeInterval, index: Int, cycle: Double) -> Double {
        let raw = (elapsed + Double(index) * step) / cycle
        return raw - floor(raw)
    }

    private static func plain(_ slot: Int) -> RowStyle {
        let value = slots[slot] ?? (slot > 0 ? (288, 0, 1.2) : (-265 - CGFloat(abs(slot) - 5) * 53, 0, 1.2))
        return RowStyle(
            offsetY: value.0, scale: slot > 0 ? 0.97 : 0.92, opacity: value.1, blur: value.2,
            background: NovaOBRGBA(0xFFFFFF, alpha: 0),
            ring: 0, ringColor: NovaOBRGBA(0x18263A, alpha: 0),
            shadowY: 0, shadowBlur: 0, shadowAlpha: 0,
            border: NovaOBRGBA(0xEAEEF4, alpha: 0),
            icon: NovaOBRGBA(0x8E99A4),
            verticalPadding: 12, zIndex: 1
        )
    }

    private static func active(
        tint: UInt32, scale: CGFloat, ring: CGFloat, ringAlpha: Double,
        shadow: (CGFloat, CGFloat, Double), border: NovaOBRGBA
    ) -> RowStyle {
        RowStyle(
            offsetY: 0, scale: scale, opacity: 1, blur: 0,
            background: NovaOBRGBA(0xFFFFFF),
            ring: ring, ringColor: NovaOBRGBA(tint, alpha: ringAlpha),
            shadowY: shadow.0, shadowBlur: shadow.1, shadowAlpha: shadow.2,
            border: border,
            icon: NovaOBRGBA(tint),
            verticalPadding: 14, zIndex: 4
        )
    }

    /// Arrival (1.04) → pop (1.075) → settled (1.05), matching the three
    /// keyframes of the active slot.
    private static func activeStates(_ tint: UInt32) -> (RowStyle, RowStyle, RowStyle) {
        let color = NovaOBRGBA(tint)
        return (
            active(tint: tint, scale: 1.04, ring: 0, ringAlpha: 0, shadow: (12, 30, 0.16),
                   border: color.mixed(with: NovaOBRGBA(0xEAEEF4), 0.82)),
            active(tint: tint, scale: 1.075, ring: 5, ringAlpha: 0.14, shadow: (22, 44, 0.2),
                   border: color.mixed(with: NovaOBRGBA(0xFFFFFF), 0.55)),
            active(tint: tint, scale: 1.05, ring: 3, ringAlpha: 0.09, shadow: (16, 36, 0.17),
                   border: color.mixed(with: NovaOBRGBA(0xFFFFFF), 0.68))
        )
    }

    static func style(phase: Double, tint: UInt32) -> RowStyle {
        let count = rows.count
        let position = phase * Double(count)
        let step = min(count - 1, Int(position))
        let local = position - Double(step)
        let slot = 6 - step

        if slot == 0 {
            let (arrive, peak, settled) = activeStates(tint)
            if local < 0.228 { return arrive.mixed(with: peak, pop(local / 0.228)) }
            if local < hold { return peak.mixed(with: settled, settle((local - 0.228) / (hold - 0.228))) }
            return settled.mixed(with: plain(-1), slide((local - hold) / (1 - hold)))
        }
        // The last slot holds until the loop wraps, invisibly, to the bottom.
        if step == count - 1 || local < hold { return plain(slot) }
        let next = slot - 1 == 0 ? activeStates(tint).0 : plain(slot - 1)
        return plain(slot).mixed(with: next, slide((local - hold) / (1 - hold)))
    }

    /// `isgHaloN`: the glow starts slightly before its card slides in, so it
    /// never reads as trailing behind it.
    static func haloOpacity(phase: Double) -> Double {
        let unit = 100 / Double(rows.count)
        let start = 6 * unit
        let stops: [(Double, Double)] = [
            (0, 0), (start - 0.78 * unit, 0), (start - 0.42 * unit, 0.08), (start + 0.06 * unit, 0.09),
            (start + 0.42 * unit, 0.07), (start + 0.65 * unit, 0), (100, 0)
        ]
        let percent = phase * 100
        for index in 1..<stops.count where percent <= stops[index].0 {
            let (x0, y0) = stops[index - 1], (x1, y1) = stops[index]
            guard x1 > x0 else { return y1 }
            return y0 + (y1 - y0) * (percent - x0) / (x1 - x0)
        }
        return 0
    }
}

/// A colour that interpolates the way CSS does (premultiplied sRGB), so a
/// fully transparent end never tints the blend.
struct NovaOBRGBA {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    private init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    func mixed(with other: NovaOBRGBA, _ t: Double) -> NovaOBRGBA {
        let a = alpha + (other.alpha - alpha) * t
        guard a > 0 else { return NovaOBRGBA(red: 0, green: 0, blue: 0, alpha: 0) }
        func channel(_ from: Double, _ to: Double) -> Double {
            (from * alpha * (1 - t) + to * other.alpha * t) / a
        }
        return NovaOBRGBA(
            red: channel(red, other.red), green: channel(green, other.green),
            blue: channel(blue, other.blue), alpha: a
        )
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// CSS `cubic-bezier(x1, y1, x2, y2)` as a progress mapping.
struct NovaOBCubicBezier {
    let x1: Double, y1: Double, x2: Double, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    private func sample(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var low = 0.0, high = 1.0, t = x
        for _ in 0..<32 {
            let value = sample(t, x1, x2)
            if abs(value - x) < 1e-6 { break }
            if value < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sample(t, y1, y2)
    }
}
#endif
