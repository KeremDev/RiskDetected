import XCTest
import SwiftUI
import CoreText
import UIKit

/// Rendering smoke tests, not screenshot-golden or VoiceOver/interaction acceptance.
/// The hostless target compiles only NOVA source and local fonts; no app services.
@MainActor
final class NovaRenderTests: XCTestCase {
    private func render(width: CGFloat, height: CGFloat, dark: Bool, large: Bool) throws {
        let bundle = Bundle(for: Self.self)
        for name in Set(NovaTypeToken.allCases.map { $0.spec.fontName }) {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "ttf"))
            if UIFont(name: name, size: 15) == nil {
                XCTAssertTrue(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil), name)
            }
            XCTAssertNotNil(UIFont(name: name, size: 15), "No silent system-font fallback")
        }
        // This hostless process can render pure SwiftUI content, not a UIKit ScrollView/window.
        // Share the exact gallery content; do not claim scroll, window or interaction coverage.
        let view = NovaComponentGalleryContent(taps: 0, onTap: {})
            .frame(width: width, alignment: .top)
            .frame(height: height, alignment: .top)
            .background(NovaColorToken.canvas.color(in: dark ? .dark : .light))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
            .clipped()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, width)
        XCTAssertEqual(image.size.height, height)
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 10_000)
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let distinct = Set(stride(from: 0, to: pixels.count, by: 4).map {
            "\(pixels[$0] / 16),\(pixels[$0 + 1] / 16),\(pixels[$0 + 2] / 16)"
        })
        XCTAssertGreaterThan(distinct.count, 12, "Blank/near-blank render cannot pass")
        let attachment = XCTAttachment(image: image)
        attachment.name = "nova-\(Int(width))-\(dark ? "dark" : "light")-\(large ? "ax3" : "normal")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_light_small() throws { try render(width: 320, height: 692, dark: false, large: false) }
    func test_dark_small() throws { try render(width: 320, height: 692, dark: true, large: false) }
    func test_light_medium() throws { try render(width: 393, height: 852, dark: false, large: false) }
    func test_dark_medium() throws { try render(width: 393, height: 852, dark: true, large: false) }
    func test_light_large() throws { try render(width: 440, height: 956, dark: false, large: false) }
    func test_dark_large() throws { try render(width: 440, height: 956, dark: true, large: false) }
    func test_light_small_ax3() throws { try render(width: 320, height: 692, dark: false, large: true) }
    func test_dark_small_ax3() throws { try render(width: 320, height: 692, dark: true, large: true) }
    func test_light_medium_ax3() throws { try render(width: 393, height: 852, dark: false, large: true) }
    func test_dark_medium_ax3() throws { try render(width: 393, height: 852, dark: true, large: true) }
    func test_light_large_ax3() throws { try render(width: 440, height: 956, dark: false, large: true) }
    func test_dark_large_ax3() throws { try render(width: 440, height: 956, dark: true, large: true) }
}
