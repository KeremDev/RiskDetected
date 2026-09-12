import Foundation
import CoreText

@main
struct NovaTokenCheck {
    static func main() throws {
        precondition(CommandLine.arguments.count == 3, "Usage: nova-check corpus.json font-directory")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        var checks = 0
        for (name, dark) in [("light", false), ("dark", true)] {
            let colors = root[name] as! [String: [NSNumber]]
            precondition(colors.count == NovaColorToken.allCases.count)
            for token in NovaColorToken.allCases {
                let value = token.rgba(dark: dark), expected = colors[token.rawValue]!
                precondition([Double(value.red), Double(value.green), Double(value.blue), value.alpha] == expected.map(\.doubleValue), token.rawValue)
                checks += 1
            }
        }
        let dimensions = root["dimensions"] as! [String: NSNumber]
        precondition(dimensions.count == NovaDimensionToken.allCases.count)
        for token in NovaDimensionToken.allCases {
            precondition(token.value == dimensions[token.rawValue]!.doubleValue, token.rawValue)
            checks += 1
        }
        let typography = root["typography"] as! [String: [String: Any]]
        precondition(typography.count == NovaTypeToken.allCases.count)
        for token in NovaTypeToken.allCases {
            let s = token.spec, e = typography[token.rawValue]!
            precondition(s.fontName == e["fontName"] as! String)
            precondition(s.weight == (e["weight"] as! NSNumber).intValue)
            precondition(s.size == (e["size"] as! NSNumber).doubleValue)
            precondition(s.tracking == (e["tracking"] as! NSNumber).doubleValue)
            precondition(s.lineHeight == (e["lineHeight"] as! NSNumber).doubleValue)
            checks += 1
        }
        let names = Set(NovaTypeToken.allCases.map { $0.spec.fontName })
        precondition(names.count == 5)
        for name in names.sorted() {
            let url = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent(name + ".ttf")
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as! [CTFontDescriptor]
            precondition(descriptors.count == 1)
            let font = CTFontCreateWithFontDescriptor(descriptors[0], 15, nil)
            precondition(CTFontCopyPostScriptName(font) as String == name, "Wrong PostScript name: \(name)")
            let characters = Array("İıŞşĞğÇçÖöÜü".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            precondition(CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count))
            precondition(glyphs.allSatisfy { $0 != 0 })
            checks += 1
        }
        print("PASS: \(checks) native Swift token/font checks; token values, PostScript names and Turkish glyph coverage. Not UI rendering.")
    }
}
