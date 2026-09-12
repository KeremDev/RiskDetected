import Foundation
import CoreText

// Mechanical extraction of the two original Feather glyphs used by OSGB PhotoBackdrop.
// No redraw: preserve the bundled source font outline and normalize its em box to 24.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let provider = CGDataProvider(url: url as CFURL)!
let font = CTFontCreateWithGraphicsFont(CGFont(provider)!, 24, nil, nil)
var output: [String: String] = [:]
for (name, code) in [("photo", UInt16(61829)), ("camera", UInt16(61736))] {
    var character = code
    var glyph: CGGlyph = 0
    precondition(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CTFontGetAscent(font))
    let path = CTFontCreatePathForGlyph(font, glyph, &transform)!
    var commands: [String] = []
    func point(_ p: CGPoint) -> String { "\(p.x),\(p.y)" }
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: commands.append("M" + point(e.points[0]))
        case .addLineToPoint: commands.append("L" + point(e.points[0]))
        case .addQuadCurveToPoint: commands.append("Q" + point(e.points[0]) + " " + point(e.points[1]))
        case .addCurveToPoint: commands.append("C" + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2]))
        case .closeSubpath: commands.append("Z")
        @unknown default: fatalError("Unsupported font outline")
        }
    }
    output[name] = commands.joined(separator: " ")
}
print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), encoding: .utf8)!)
