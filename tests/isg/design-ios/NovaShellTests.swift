import XCTest
import SwiftUI
import CoreText
import UIKit

/// Pure header/tab content render + state checks. No hosted NavigationStack/modal/VoiceOver claim.
@MainActor final class NovaShellTests: XCTestCase {
    private func render(tab: NovaTab, dark: Bool, large: Bool = false) throws {
        for name in Set(NovaTypeToken.allCases.map { $0.spec.fontName }) where UIFont(name: name, size: 15) == nil {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "ttf"))
            XCTAssertTrue(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
        }
        let view = VStack(spacing: 24) {
            NovaShellTopBar(current: tab.root, userName: "Örnek Uzman", hasUnread: true,
                canGoBack: false, notificationsAvailable: true, send: { _ in })
            if large {
                // Render the same expanded strip's leading content, not the hostless ScrollView.
                // Horizontal scrolling/auto-reveal still needs a hosted iOS interaction test.
                NovaShellTabStrip(selected: tab, canOpen: { _ in true }, send: { _ in }, expanded: true)
                    .fixedSize().frame(width: 292, alignment: .leading).clipped()
            } else {
                NovaShellTabBar(selected: tab, canOpen: { _ in true }, send: { _ in }).padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 24).frame(width: 320)
        .background(NovaColorToken.canvas.color(in: dark ? .dark : .light))
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, 320)
        XCTAssertGreaterThan(image.size.height, 150)
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 64, height: 64,
                bitsPerComponent: 8, bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let distinct = Set(stride(from: 0, to: pixels.count, by: 4).map { "\(pixels[$0] / 16),\(pixels[$0 + 1] / 16),\(pixels[$0 + 2] / 16)" })
        XCTAssertGreaterThan(distinct.count, 12, "Blank header/tab render must fail")
        let attachment = XCTAttachment(image: image)
        attachment.name = "nova-shell-\(tab.rawValue)-\(dark ? "dark" : "light")-\(large ? "ax3" : "normal")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testHeaderAndFourTabSelectionsInBothThemes() throws {
        for dark in [false, true] { for tab in NovaTab.allCases { try render(tab: tab, dark: dark) } }
    }
    func testLargeTypeHeaderAndTabsInBothThemes() throws {
        for dark in [false, true] { try render(tab: .home, dark: dark, large: true) }
    }
    func testAccountResetRejectsCapturedEventAndBackPath() {
        var state = NovaNavigationState(epoch: "a", available: Set(NovaDestination.allCases))
        state.apply(.navigate(.memory), from: "a")
        state.apply(.open(.drawer), from: "a")
        let captured = state.epoch
        state.resetAccount(to: "b", available: [])
        state.apply(.navigate(.notifications), from: captured)
        state.apply(.open(.quickAdd), from: captured)
        state.acceptBackPath([.memory], tab: .home, from: captured)
        XCTAssertEqual(state, NovaNavigationState(epoch: "b", available: []))
    }
    func testTabHistoryAndPanelBackOrder() {
        var state = NovaNavigationState(epoch: "a", available: Set(NovaDestination.allCases))
        state.apply(.navigate(.memory), from: "a")
        state.apply(.navigate(.newFinding), from: "a")
        state.apply(.open(.quickAdd), from: "a")
        state.apply(.back, from: "a")
        XCTAssertNil(state.overlay)
        XCTAssertEqual(state.current, .newFinding)
        state.apply(.select(.home), from: "a")
        XCTAssertEqual(state.current, .memory)
        state.apply(.select(.home), from: "a")
        XCTAssertEqual(state.current, .home)
        XCTAssertEqual(state.paths[.findings], [.newFinding])
    }
    func testUnavailableParentRejectsChildAndRevocationClearsHistory() {
        var state = NovaNavigationState(epoch: "a", available: [.newFinding])
        state.apply(.navigate(.newFinding), from: "a")
        XCTAssertEqual(state.current, .home)
        state.updateAvailability(Set(NovaDestination.allCases), from: "a")
        state.apply(.navigate(.memory), from: "a")
        state.apply(.navigate(.documents), from: "a")
        state.updateAvailability([.documents], from: "a")
        XCTAssertEqual(state.current, .home)
        XCTAssertEqual(state.paths[.home], [])
    }
    func testBackPathCannotInjectOrReorderDestinations() {
        var state = NovaNavigationState(epoch: "a", available: Set(NovaDestination.allCases))
        state.apply(.navigate(.memory), from: "a")
        state.apply(.navigate(.documents), from: "a")
        state.acceptBackPath([.documents], tab: .home, from: "a")
        state.acceptBackPath([.memory, .documents, .reports], tab: .home, from: "a")
        XCTAssertEqual(state.paths[.home], [.memory, .documents])
        state.acceptBackPath([.memory], tab: .home, from: "a")
        XCTAssertEqual(state.current, .memory)
    }
}
