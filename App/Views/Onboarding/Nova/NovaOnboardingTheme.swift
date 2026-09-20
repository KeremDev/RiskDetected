#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

/// Design tokens transcribed from the Claude Design prototype
/// (`İSGADA Onboarding.dc.html` / `İSGADA Giriş.dc.html`). Values are the
/// prototype's literal CSS values so the native screens stay pixel-faithful.
enum NovaOB {
    // MARK: colours
    static let ink = Color(hex: 0x000000)
    static let inkSoft = Color(hex: 0x2C3336)
    static let slate = Color(hex: 0x3A4548)
    static let muted = Color(hex: 0x5A5A5A)
    static let muted2 = Color(hex: 0x767676)
    static let disabled = Color(hex: 0x9A9A9A)
    static let line = Color(hex: 0xE4E4E4)
    static let line2 = Color(hex: 0xC9C9C9)
    static let surface = Color(hex: 0xFFFFFF)
    static let fill = Color(hex: 0xF1F1F1)
    static let fill2 = Color(hex: 0xF4F4F4)
    static let fill3 = Color(hex: 0xF7F7F7)
    static let errorInk = Color(hex: 0xA4453C)
    static let errorBg = Color(hex: 0xFBECEA)
    static let errorBorder = Color(hex: 0xC97A72)
    static let gold = Color(hex: 0xC8873F)

    static let intro1Bg = Color(hex: 0xF6DCD6)
    static let intro2Bg = Color(hex: 0xEAF5CE)
    static let intro3Bg = Color(hex: 0xFBE1CD)
    static let socialBg = Color(hex: 0xDCE9F6)

    /// Experience slider tints, one per stop.
    static let stopTint = [Color(hex: 0x000000), Color(hex: 0x8A6B4F), Color(hex: 0xC06A3A), Color(hex: 0xC0392B)]

    // MARK: type
    /// Plus Jakarta Sans at a fixed point size. The prototype's layout is tight
    /// enough that Dynamic Type scaling would break the composition, so the
    /// sizes are literal — same call shape the rest of Nova uses.
    static func font(_ size: CGFloat, _ weight: Int = 400) -> Font {
        .custom(faceName(weight), size: size)
    }

    private static func faceName(_ weight: Int) -> String {
        switch weight {
        case 800...: return "PlusJakartaSans-ExtraBold"
        case 700..<800: return "PlusJakartaSans-Bold"
        case 600..<700: return "PlusJakartaSans-SemiBold"
        case 500..<600: return "PlusJakartaSans-Medium"
        default: return "PlusJakartaSans-Regular"
        }
    }

    /// CSS `line-height: N` against a font size, expressed as SwiftUI line spacing.
    static func lineSpacing(_ size: CGFloat, _ ratio: CGFloat) -> CGFloat {
        max(0, size * ratio - size * 1.18)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Shared primitives

/// The black pill CTA used on every marketing screen (intro, card, push, trial).
struct NovaOBPillButton: View {
    let title: String
    var height: CGFloat = 60
    var fontSize: CGFloat = 17.5
    var horizontalPadding: CGFloat? = nil
    var fixedWidth: CGFloat? = nil
    var showsArrow = false
    var background: Color = NovaOB.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title)
                    .font(NovaOB.font(fontSize, 700))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if showsArrow { NovaOBArrowRight(size: 18, color: .white) }
            }
            .padding(.horizontal, horizontalPadding ?? 0)
            .frame(maxWidth: fixedWidth == nil && horizontalPadding == nil ? .infinity : nil)
            .frame(width: fixedWidth, height: height)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The squared 56 pt / radius 16 primary button used on form screens.
struct NovaOBPrimaryButton: View {
    let title: String
    var enabled = true
    var showsArrow = false
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title).font(NovaOB.font(17, 600))
                if showsArrow { NovaOBArrowRight(size: 18, color: enabled ? .white : NovaOB.disabled) }
            }
            .foregroundColor(enabled ? .white : NovaOB.disabled)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(enabled ? NovaOB.ink : Color(hex: 0xDDDDDD), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
    }
}

/// White button with a 2 pt black border — the Giriş screen's mail CTA.
struct NovaOBOutlineButton: View {
    let title: String
    var busy = false
    var icon: AnyView? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { icon }
                Text(title).font(NovaOB.font(17, 700)).foregroundColor(NovaOB.ink)
                if busy { NovaOBSpinner(size: 17, track: NovaOB.line, head: NovaOB.ink) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(NovaOB.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NovaOB.ink, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The 26×3 progress pills at the top of the three intro screens.
struct NovaOBDots: View {
    let active: Int
    var count = 4
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == active ? NovaOB.ink : NovaOB.ink.opacity(0.2))
                    .frame(width: 26, height: 3)
            }
        }
    }
}

struct NovaOBBackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            NovaOBChevronLeft()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NovaOBChevronLeft: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 9, y: 1))
            path.addLine(to: CGPoint(x: 2, y: 9))
            path.addLine(to: CGPoint(x: 9, y: 17))
        }
        .stroke(NovaOB.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(width: 11, height: 18)
    }
}

struct NovaOBChevronRight: View {
    var color: Color = NovaOB.line2
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: 7, y: 7))
            path.addLine(to: CGPoint(x: 1, y: 13))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(width: 8, height: 14)
    }
}

struct NovaOBArrowRight: View {
    var size: CGFloat = 18
    var color: Color = .white
    var body: some View {
        NovaOBIconPath(path: "M4 12h15|M13 6l6 6-6 6", size: size, color: color, lineWidth: 2)
    }
}

struct NovaOBSpinner: View {
    var size: CGFloat = 16
    var track: Color = NovaOB.line
    var head: Color = NovaOB.ink
    @State private var spinning = false
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(
                AngularGradient(colors: [head, track], center: .center),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.72).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

/// The prototype's inline error card (red ink on a tinted surface).
struct NovaOBErrorNote: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            NovaOBIconPath(
                path: "circle:12,12,9.2|M12 7.6v6|M12 16.4h.01",
                size: 17, color: NovaOB.errorInk, lineWidth: 1.9
            )
            .padding(.top, 1)
            Text(text)
                .font(NovaOB.font(14))
                .foregroundColor(NovaOB.errorInk)
                .lineSpacing(NovaOB.lineSpacing(14, 1.4))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(NovaOB.errorBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Neutral confirmation card (used for OTP success / reset-sent states).
struct NovaOBInfoNote: View {
    let text: String
    var icon: String? = nil
    var background: Color = NovaOB.fill2
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let icon {
                NovaOBIconPath(path: icon, size: 18, color: NovaOB.ink, lineWidth: 2).padding(.top, 1)
            }
            Text(text)
                .font(NovaOB.font(14.5))
                .foregroundColor(NovaOB.ink)
                .lineSpacing(NovaOB.lineSpacing(14.5, 1.45))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Text-field chrome shared by every input in both prototypes.
struct NovaOBFieldStyle: ViewModifier {
    var height: CGFloat = 54
    var radius: CGFloat = 14
    var leadingInset: CGFloat = 16
    var trailingInset: CGFloat = 16
    var border: Color = NovaOB.line
    var background: Color = NovaOB.surface
    var fontSize: CGFloat = 16.5

    func body(content: Content) -> some View {
        content
            .font(NovaOB.font(fontSize))
            .foregroundColor(NovaOB.ink)
            .tint(NovaOB.ink)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .frame(height: height)
            .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1.5)
            )
    }
}

extension View {
    func novaOBField(
        height: CGFloat = 54,
        radius: CGFloat = 14,
        leadingInset: CGFloat = 16,
        trailingInset: CGFloat = 16,
        border: Color = NovaOB.line,
        background: Color = NovaOB.surface,
        fontSize: CGFloat = 16.5
    ) -> some View {
        modifier(NovaOBFieldStyle(
            height: height, radius: radius, leadingInset: leadingInset, trailingInset: trailingInset,
            border: border, background: background, fontSize: fontSize
        ))
    }
}

// MARK: - SVG-ish path renderer

/// Draws the prototype's inline SVG icons. Segments are separated by `|`;
/// `circle:cx,cy,r` draws a circle, everything else is an SVG path string in a
/// 24×24 viewBox. Only the subset of commands the prototype actually uses is
/// supported (M, L, H, V, A-as-circle, Z, and their relative forms).
struct NovaOBIconPath: View {
    let path: String
    var size: CGFloat = 24
    var color: Color = NovaOB.ink
    var lineWidth: CGFloat = 1.5
    var viewBox: CGFloat = 24
    var filled = false

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / viewBox
            for segment in path.split(separator: "|") {
                let shape = Self.makePath(String(segment), scale: scale)
                if filled {
                    context.fill(shape, with: .color(color))
                } else {
                    context.stroke(
                        shape,
                        with: .color(color),
                        style: StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .frame(width: size, height: size)
    }

    static func makePath(_ segment: String, scale: CGFloat) -> Path {
        if segment.hasPrefix("circle:") {
            let parts = segment.dropFirst(7).split(separator: ",").compactMap { Double($0) }
            guard parts.count == 3 else { return Path() }
            let r = CGFloat(parts[2]) * scale
            return Path(ellipseIn: CGRect(
                x: CGFloat(parts[0]) * scale - r,
                y: CGFloat(parts[1]) * scale - r,
                width: r * 2, height: r * 2
            ))
        }
        return NovaOBSVGParser.path(segment, scale: scale)
    }
}

/// SVG `d` parser covering the commands the prototype's icon set uses:
/// M/L/H/V/C/S/Q/T/A/Z and their relative forms, including true elliptical arcs.
enum NovaOBSVGParser {
    static func path(_ d: String, scale: CGFloat) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var lastQuadControl: CGPoint?
        var numbers: [CGFloat] = []
        var command: Character = "M"
        var token = ""

        func flush() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }

        func apply() {
            defer { numbers = [] }
            let relative = command.isLowercase
            let kind = Character(command.lowercased())
            guard !numbers.isEmpty || kind == "z" else { return }

            switch kind {
            case "m":
                var index = 0
                while index + 1 < numbers.count {
                    let point = resolve(numbers[index], numbers[index + 1], relative, current)
                    if index == 0 {
                        path.move(to: point.scaled(scale))
                        start = point
                    } else {
                        path.addLine(to: point.scaled(scale))
                    }
                    current = point
                    index += 2
                }
                lastControl = nil; lastQuadControl = nil
            case "l":
                var index = 0
                while index + 1 < numbers.count {
                    let point = resolve(numbers[index], numbers[index + 1], relative, current)
                    path.addLine(to: point.scaled(scale))
                    current = point
                    index += 2
                }
                lastControl = nil; lastQuadControl = nil
            case "h":
                for value in numbers {
                    current = CGPoint(x: relative ? current.x + value : value, y: current.y)
                    path.addLine(to: current.scaled(scale))
                }
                lastControl = nil; lastQuadControl = nil
            case "v":
                for value in numbers {
                    current = CGPoint(x: current.x, y: relative ? current.y + value : value)
                    path.addLine(to: current.scaled(scale))
                }
                lastControl = nil; lastQuadControl = nil
            case "c":
                var index = 0
                while index + 5 < numbers.count {
                    let c1 = resolve(numbers[index], numbers[index + 1], relative, current)
                    let c2 = resolve(numbers[index + 2], numbers[index + 3], relative, current)
                    let end = resolve(numbers[index + 4], numbers[index + 5], relative, current)
                    path.addCurve(to: end.scaled(scale), control1: c1.scaled(scale), control2: c2.scaled(scale))
                    current = end
                    lastControl = c2
                    index += 6
                }
                lastQuadControl = nil
            case "s":
                var index = 0
                while index + 3 < numbers.count {
                    let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    let c2 = resolve(numbers[index], numbers[index + 1], relative, current)
                    let end = resolve(numbers[index + 2], numbers[index + 3], relative, current)
                    path.addCurve(to: end.scaled(scale), control1: c1.scaled(scale), control2: c2.scaled(scale))
                    current = end
                    lastControl = c2
                    index += 4
                }
                lastQuadControl = nil
            case "q":
                var index = 0
                while index + 3 < numbers.count {
                    let control = resolve(numbers[index], numbers[index + 1], relative, current)
                    let end = resolve(numbers[index + 2], numbers[index + 3], relative, current)
                    path.addQuadCurve(to: end.scaled(scale), control: control.scaled(scale))
                    current = end
                    lastQuadControl = control
                    index += 4
                }
                lastControl = nil
            case "t":
                var index = 0
                while index + 1 < numbers.count {
                    let control = lastQuadControl
                        .map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    let end = resolve(numbers[index], numbers[index + 1], relative, current)
                    path.addQuadCurve(to: end.scaled(scale), control: control.scaled(scale))
                    current = end
                    lastQuadControl = control
                    index += 2
                }
                lastControl = nil
            case "a":
                var index = 0
                while index + 6 < numbers.count {
                    let end = resolve(numbers[index + 5], numbers[index + 6], relative, current)
                    appendArc(
                        to: &path, from: current, to: end,
                        rx: abs(numbers[index]), ry: abs(numbers[index + 1]),
                        rotation: numbers[index + 2],
                        largeArc: numbers[index + 3] != 0, sweep: numbers[index + 4] != 0,
                        scale: scale
                    )
                    current = end
                    index += 7
                }
                lastControl = nil; lastQuadControl = nil
            case "z":
                path.closeSubpath()
                current = start
                lastControl = nil; lastQuadControl = nil
            default: break
            }
        }

        for character in d {
            if character.isLetter && character != "e" {
                flush(); apply(); command = character
            } else if character == "," || character == " " {
                flush()
            } else if character == "-" && !token.isEmpty && token.last != "e" {
                flush(); token = "-"
            } else if character == "." && token.contains(".") {
                flush(); token = "."
            } else if isArcFlagPosition(command, numbers.count, token) && character.isNumber {
                // Arc flags are single digits and are usually written without a
                // separator ("a4 4 0 018 0"), so they must not merge into the
                // following coordinate.
                numbers.append(character == "0" ? 0 : 1)
            } else {
                token.append(character)
            }
        }
        flush(); apply()
        return path
    }

    private static func resolve(_ x: CGFloat, _ y: CGFloat, _ relative: Bool, _ current: CGPoint) -> CGPoint {
        relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    /// Positions 3 and 4 of every 7-value arc set are the large-arc / sweep flags.
    private static func isArcFlagPosition(_ command: Character, _ count: Int, _ token: String) -> Bool {
        guard command == "a" || command == "A", token.isEmpty else { return false }
        let position = count % 7
        return position == 3 || position == 4
    }

    /// Endpoint-to-centre arc conversion (SVG implementation notes F.6),
    /// emitted as ≤90° cubic segments.
    private static func appendArc(
        to path: inout Path, from p0: CGPoint, to p1: CGPoint,
        rx: CGFloat, ry: CGFloat, rotation: CGFloat,
        largeArc: Bool, sweep: Bool, scale: CGFloat
    ) {
        guard rx > 0, ry > 0 else {
            path.addLine(to: p1.scaled(scale))
            return
        }
        if abs(p0.x - p1.x) < .ulpOfOne && abs(p0.y - p1.y) < .ulpOfOne { return }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy

        var radiusX = rx, radiusY = ry
        let lambda = (x1 * x1) / (radiusX * radiusX) + (y1 * y1) / (radiusY * radiusY)
        if lambda > 1 {
            radiusX *= sqrt(lambda)
            radiusY *= sqrt(lambda)
        }

        let numerator = max(0, radiusX * radiusX * radiusY * radiusY
                            - radiusX * radiusX * y1 * y1 - radiusY * radiusY * x1 * x1)
        let denominator = radiusX * radiusX * y1 * y1 + radiusY * radiusY * x1 * x1
        let factor = denominator == 0 ? 0 : sqrt(numerator / denominator) * (largeArc == sweep ? -1 : 1)

        let cx1 = factor * radiusX * y1 / radiusY
        let cy1 = -factor * radiusY * x1 / radiusX
        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            guard length > 0 else { return 0 }
            let value = max(-1, min(1, dot / length))
            return (ux * vy - uy * vx < 0 ? -1 : 1) * acos(value)
        }

        let startAngle = angle(1, 0, (x1 - cx1) / radiusX, (y1 - cy1) / radiusY)
        var sweepAngle = angle((x1 - cx1) / radiusX, (y1 - cy1) / radiusY,
                               (-x1 - cx1) / radiusX, (-y1 - cy1) / radiusY)
        if !sweep && sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep && sweepAngle < 0 { sweepAngle += 2 * .pi }

        let segments = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let delta = sweepAngle / CGFloat(segments)
        let alpha = 4.0 / 3.0 * tan(delta / 4)
        var theta = startAngle
        var from = p0

        for _ in 0..<segments {
            let theta2 = theta + delta
            let cosT1 = cos(theta), sinT1 = sin(theta)
            let cosT2 = cos(theta2), sinT2 = sin(theta2)

            let end = CGPoint(
                x: cosPhi * radiusX * cosT2 - sinPhi * radiusY * sinT2 + cx,
                y: sinPhi * radiusX * cosT2 + cosPhi * radiusY * sinT2 + cy
            )
            let d1 = CGPoint(
                x: -cosPhi * radiusX * sinT1 - sinPhi * radiusY * cosT1,
                y: -sinPhi * radiusX * sinT1 + cosPhi * radiusY * cosT1
            )
            let d2 = CGPoint(
                x: -cosPhi * radiusX * sinT2 - sinPhi * radiusY * cosT2,
                y: -sinPhi * radiusX * sinT2 + cosPhi * radiusY * cosT2
            )
            path.addCurve(
                to: end.scaled(scale),
                control1: CGPoint(x: from.x + alpha * d1.x, y: from.y + alpha * d1.y).scaled(scale),
                control2: CGPoint(x: end.x - alpha * d2.x, y: end.y - alpha * d2.y).scaled(scale)
            )
            from = end
            theta = theta2
        }
    }
}

private extension CGPoint {
    func scaled(_ factor: CGFloat) -> CGPoint { CGPoint(x: x * factor, y: y * factor) }
}
#endif
