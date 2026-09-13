import XCTest
import UIKit

@MainActor final class ShellUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate() }

    private func launch(_ args: [String] = []) {
        app = XCUIApplication(bundleIdentifier: "com.riskdetected.isgshellharness")
        app.launchArguments = args + ["--qa-toolbar"]
        app.launch()
        XCTAssertTrue(app.staticTexts["qa.state"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["qa.state"].label.contains("fonts=ok"), "All five bundled font names must register")
    }
    private func visible(_ destination: String) {
        let node = app.staticTexts["qa.content.\(destination)"]
        XCTAssertTrue(node.exists || node.waitForExistence(timeout: 4), app.debugDescription)
        XCTAssertTrue(node.isHittable, "Content must actually be visible, not only present in the router")
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.exists || button.waitForExistence(timeout: 4), id)
        if !button.isHittable {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed, "\(id): \(app.debugDescription)")
        }
        button.tap()
    }
    private func home() {
        tap("nova.tab.home")
        if app.buttons["nova.back"].exists { tap("nova.tab.home") }
        visible("home")
    }
    private func choose(_ route: String) {
        let node = app.buttons["nova.destination.\(route)"]
        for _ in 0..<12 {
            if node.exists && node.isHittable { break }
            app.scrollViews["nova.panel.scroll"].swipeUp()
        }
        tap("nova.destination.\(route)")
        visible(route)
        XCTAssertFalse(app.buttons["nova.panel.close"].exists)
    }
    private func screenshot(_ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot())
        item.name = name; item.lifetime = .keepAlways; add(item)
    }

    private func personnelAdd(_ department: String? = nil) {
        tap("personnel.add")
        let name = app.textFields["personnel.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 4)); name.tap(); name.typeText("Ada Kaya")
        if let department {
            let field = app.textFields["personnel.department"]
            field.tap(); field.typeText(department)
        }
        app.swipeUp()
        tap("personnel.save")
    }
    private func directoryScroll(_ node: XCUIElement) {
        for _ in 0..<10 { if node.exists && node.isHittable { return }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(node.isHittable, app.debugDescription)
    }
    private func replaceDirectory(_ key: String, _ value: String) {
        let field = app.textFields["directory.field.\(key)"]
        directoryScroll(field); field.tap()
        let text = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count) + value + "\n")
    }
    func testDirectoryEngagementDateGuardAndImmutableKeys() {
        launch(["--directory"])
        tap("directory.edit.33333333-3333-4333-8333-333333333333")
        XCTAssertFalse(app.buttons["directory.field.organization_id"].isEnabled)
        XCTAssertFalse(app.buttons["directory.field.workplace_id"].isEnabled)
        replaceDirectory("ends_before", "2025-12-31")
        directoryScroll(app.buttons["directory.save"]); tap("directory.save")
        XCTAssertTrue(app.staticTexts["directory.error"].label.contains("başlangıç tarihinden sonra"))
        XCTAssertEqual(app.staticTexts["qa.directory.saves"].label, "saves=0")
        app.swipeDown(); replaceDirectory("ends_before", "2026-12-31")
        directoryScroll(app.buttons["directory.save"]); tap("directory.save")
        XCTAssertTrue(app.buttons["directory.add"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["qa.directory.saves"].label, "saves=1")
    }
    func testDirectoryHierarchyExcludesSelfAndDescendant() {
        launch(["--directory", "--directory-departments"])
        tap("directory.edit.33333333-3333-4333-8333-333333333333")
        let parent = app.buttons["directory.field.parent_id"]
        directoryScroll(parent); tap("directory.field.parent_id")
        XCTAssertFalse(app.buttons["directory.option.parent_id.33333333-3333-4333-8333-333333333333"].exists)
        XCTAssertFalse(app.buttons["directory.option.parent_id.55555555-5555-4555-8555-555555555555"].exists)
        directoryScroll(app.buttons["directory.save"]); tap("directory.save")
        XCTAssertTrue(app.buttons["directory.add"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["qa.directory.saves"].label, "saves=1")
    }
    func testDirectoryOptionFailureRequiresRetryWithoutLosingForm() {
        launch(["--directory", "--directory-option-retry"])
        tap("directory.edit.33333333-3333-4333-8333-333333333333")
        directoryScroll(app.buttons["directory.save"])
        XCTAssertFalse(app.buttons["directory.save"].isEnabled)
        tap("directory.options.retry")
        XCTAssertTrue(app.buttons["directory.save"].isEnabled)
        tap("directory.save")
        XCTAssertTrue(app.buttons["directory.add"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["qa.directory.saves"].label, "saves=1")
    }
    func testPersonnelAdvancedRoutesReturnToSameEmployee() {
        launch(["--personnel"])
        personnelAdd()
        tap("personnel.assignments")
        XCTAssertTrue(app.staticTexts["Görevlendirme Geçmişi"].waitForExistence(timeout: 4))
        tap("directory.back")
        XCTAssertTrue(app.staticTexts["Ada Kaya"].waitForExistence(timeout: 4))
        tap("personnel.employers")
        XCTAssertTrue(app.staticTexts["Personelin İşvereni"].waitForExistence(timeout: 4))
        tap("directory.back")
        XCTAssertTrue(app.buttons["personnel.edit"].waitForExistence(timeout: 4))
    }
    func testArchivedEmployeeCanBeExplicitlyReactivated() {
        launch(["--personnel"]); personnelAdd()
        tap("personnel.edit"); app.swipeUp(); tap("personnel.archive"); tap("personnel.archive.confirm")
        let toggle = app.switches["personnel.archived"]
        XCTAssertTrue(toggle.waitForExistence(timeout:4))
        // SwiftUI exposes the whole labeled row as a switch; target its trailing thumb.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let row = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'personnel.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:4), app.debugDescription); row.tap()
        tap("personnel.restore")
        XCTAssertFalse(app.textFields["personnel.name"].exists)
        XCTAssertFalse(app.buttons["personnel.archive"].exists)
        tap("personnel.save")
        XCTAssertTrue(app.buttons["personnel.edit"].waitForExistence(timeout:4), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Ada Kaya"].exists)
    }
    func testReadOnlyPersonnelCanReadHistoryButCannotWrite() {
        launch(["--personnel", "--personnel-readonly"])
        XCTAssertTrue(app.buttons["personnel.add"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["personnel.add"].isEnabled)
        tap("personnel.row.22222222-2222-4222-8222-222222222222")
        XCTAssertFalse(app.buttons["personnel.edit"].exists)
        tap("personnel.assignments")
        XCTAssertTrue(app.buttons["Yeni kayıt"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["Yeni kayıt"].isEnabled)
        tap("directory.back"); tap("personnel.employers")
        XCTAssertTrue(app.buttons["İşveren ilişkisini düzenle"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["İşveren ilişkisini düzenle"].isEnabled)
    }

    func testPersonnelNameOnlyCreateAndArchiveConfirmation() {
        launch(["--personnel"])
        personnelAdd()
        XCTAssertTrue(app.staticTexts["Ada Kaya"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Departman seçilmedi"].exists)
        XCTAssertEqual(app.datePickers.count, 0)
        screenshot("personnel-name-only-detail")
        tap("personnel.edit")
        app.swipeUp(); tap("personnel.archive")
        XCTAssertTrue(app.buttons["personnel.archive.confirm"].waitForExistence(timeout: 4))
        screenshot("personnel-archive-popup")
        tap("personnel.archive.cancel")
        XCTAssertFalse(app.buttons["personnel.archive.confirm"].exists)
        tap("personnel.archive"); tap("personnel.archive.confirm")
        XCTAssertTrue(app.staticTexts["Henüz personel yok."].waitForExistence(timeout: 4))
    }

    func testPersonnelInlineDepartmentAndCommittedResponseLossRetry() {
        launch(["--personnel", "--personnel-retry"])
        personnelAdd("Bakım")
        XCTAssertTrue(app.buttons["personnel.retry"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["personnel.back"].isEnabled)
        tap("personnel.retry")
        XCTAssertTrue(app.staticTexts["Ada Kaya"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Bakım"].exists)
        tap("personnel.back")
        XCTAssertTrue(app.staticTexts["Ada Kaya"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Ada Kaya").count, 1)
        screenshot("personnel-inline-department-list")
    }

    /// Check rendered pixels, including pushed UIKit navigation destinations (not just token values).
    private func assertLightPageSurface(_ route: String) {
        XCTAssertFalse(app.navigationBars.firstMatch.exists, "NOVA owns the back button: \(route)")
        guard let image = app.screenshot().image.cgImage else { return XCTFail("Missing screenshot") }
        let scale = CGFloat(image.width) / app.frame.width
        func assertPixel(_ point: CGPoint, value: Int, label: String) {
            guard let pixel = image.cropping(to: CGRect(x: point.x * scale, y: point.y * scale, width: 1, height: 1)) else {
                return XCTFail("Pixel outside viewport: \(label)")
            }
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
                context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            for channel in bytes.prefix(3) {
                XCTAssertLessThanOrEqual(abs(Int(channel) - value), 2, "\(route) \(label): \(bytes)")
            }
        }
        for y in [200, 350, 500, 650] {
            assertPixel(CGPoint(x: 3, y: y), value: 240, label: "continuous gray gutter y=\(y)")
        }
        let card = app.otherElements["qa.card"]
        XCTAssertTrue(card.exists, "A separate rounded content card is required: \(route)")
        assertPixel(CGPoint(x: card.frame.midX, y: card.frame.minY + 5), value: 255, label: "white card")
    }

    private func launchDesign(_ args: [String] = []) {
        app = XCUIApplication(bundleIdentifier: "com.riskdetected.isgshellharness")
        app.launchArguments = ["--design"] + args
        app.launch()
        XCTAssertTrue(app.buttons["nova.menu"].waitForExistence(timeout: 8))
    }

    func testOwnedCompanyLoaderDisplaysRowsAndNavigates() {
        launch(["--company-loader", "--companies"])
        XCTAssertTrue(app.staticTexts["Firma A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 firma"].exists)
        screenshot("owned-company-loaded")
        tap("nova.company.11111111-1111-4111-8111-111111111111")
        visible("memory")
    }

    func testOwnedCompanyLoaderRetriesWithoutLeakingRawError() {
        launch(["--company-loader", "--companies", "--company-loader-failure"])
        XCTAssertTrue(app.buttons["Tekrar dene"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.debugDescription.contains("synthetic-private-body-must-not-appear"))
        tap("Tekrar dene")
        XCTAssertTrue(app.staticTexts["Firma A"].waitForExistence(timeout: 5))
    }

    func testOwnedCompanyLoaderReplacesPreviousAccountRows() {
        launch(["--company-loader", "--companies"])
        XCTAssertTrue(app.staticTexts["Firma A"].waitForExistence(timeout: 5))
        let search = app.textFields["nova.companies.search"]
        search.tap()
        search.typeText("Firma A")
        tap("qa.company.switch")
        XCTAssertTrue(app.staticTexts["Firma B"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Firma A"].exists)
        XCTAssertNotEqual(app.textFields["nova.companies.search"].value as? String, "Firma A")
        screenshot("owned-company-account-b")
    }

    func testFiveReferenceScreensAndNotificationActions() {
        launchDesign()
        XCTAssertTrue(app.buttons["nova.home.photo"].isHittable)
        screenshot("reference-home")
        tap("nova.notifications")
        XCTAssertTrue(app.buttons["nova.notice.overdue"].isHittable)
        screenshot("reference-notifications")
        tap("nova.notices.read")
        XCTAssertTrue(app.buttons["nova.notice.active"].isHittable)
        tap("nova.notices.clear")
        XCTAssertTrue(app.staticTexts["Yeni bildirim yok"].exists)
        XCTAssertFalse(app.buttons["nova.notice.active"].exists)
        tap("nova.panel.close")
        screenshot("reference-notifications-dismissed")
        XCTAssertFalse(app.buttons["nova.panel.close"].exists, app.debugDescription)
        tap("nova.menu"); screenshot("reference-drawer"); tap("nova.panel.close")
        tap("nova.add"); screenshot("reference-add")
        let first = app.buttons["nova.destination.newFinding"].frame
        let last = app.buttons["nova.panel.close"].frame
        XCTAssertGreaterThan(first.minY, 140, "Popup must be vertically centered, not a tall sheet")
        XCTAssertLessThan(last.maxY - first.minY, 430, "Popup must wrap the four actions")
        tap("nova.panel.close")
        tap("nova.tab.companies")
        XCTAssertTrue(app.buttons["nova.company.fixture-company"].isHittable)
        screenshot("reference-companies")
    }

    func testCompanySearchAndHomeActions() {
        launchDesign()
        tap("nova.metric.companies")
        let search = app.textFields["nova.companies.search"]
        XCTAssertTrue(search.isHittable)
        search.tap(); search.typeText("bulunmayan")
        XCTAssertTrue(app.staticTexts["Firma bulunamadı"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["nova.company.fixture-company"].exists)
        tap("nova.companies.clear")
        XCTAssertTrue(app.buttons["nova.company.fixture-company"].isHittable)
        tap("nova.company.fixture-company"); visible("memory")
        tap("nova.tab.home"); tap("nova.home.addFinding"); visible("newFinding")
    }

    func testTabHistoryReselectionAndQuickAdd() {
        launch()
        visible("home")
        tap("nova.notifications"); tap("nova.notices.center"); visible("notifications")
        tap("nova.tab.companies"); visible("companies")
        tap("nova.add")
        XCTAssertTrue(app.buttons["nova.panel.close"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["qa.state"].label.contains("companies · companies"))
        // XCUI can retain structural nodes even with accessibilityHidden; existence is not a VoiceOver audit.
        XCTAssertFalse(app.buttons["nova.tab.home"].isHittable, "Modal background must not accept interaction")
        tap("nova.panel.close"); visible("companies")
        tap("nova.tab.home"); visible("notifications")
        tap("nova.tab.home"); visible("home")
        tap("nova.add"); choose("newFinding")
        tap("nova.back"); visible("findings")
        screenshot("hosted-tab-history")
    }

    private func everyMenuEntry(dark: Bool) {
        launch(dark ? ["--dark"] : [])
        let drawer = ["home", "newFinding", "findings", "companies", "memory", "documentChecklist", "documents", "visits", "statistics", "training", "reports", "reportArchive", "notifications"]
        for route in drawer {
            home(); tap("nova.menu")
            if route == "home" { screenshot(dark ? "hosted-drawer-dark" : "hosted-drawer-light") }
            choose(route)
            if !dark { assertLightPageSurface(route) }
        }
        for route in ["newFinding", "newDocument", "newVisit", "newTraining"] {
            home(); tap("nova.add")
            if route == "newFinding" { screenshot(dark ? "hosted-add-dark" : "hosted-add-light") }
            choose(route)
            if !dark {
                assertLightPageSurface(route)
                if route == "newVisit" { screenshot("canvas-newVisit") }
            }
        }
        if !dark {
            tap("nova.tab.findings"); tap("nova.tab.findings")
            assertLightPageSurface("findings"); screenshot("canvas-findings")
            tap("nova.tab.profile"); assertLightPageSurface("profile")
        }
        screenshot(dark ? "hosted-dark" : "hosted-light")
    }
    func testEveryDrawerAndQuickAddEntryLight() { everyMenuEntry(dark: false) }
    func testEveryDrawerAndQuickAddEntryDark() { everyMenuEntry(dark: true) }

    func testDisabledRoutesCannotBeOpened() {
        launch(["--locked"])
        visible("home")
        XCTAssertFalse(app.buttons["nova.tab.findings"].isEnabled)
        XCTAssertFalse(app.buttons["nova.tab.companies"].isEnabled)
        XCTAssertFalse(app.buttons["nova.notifications"].isEnabled)
        tap("nova.add")
        for route in ["newFinding", "newDocument", "newVisit", "newTraining"] {
            XCTAssertFalse(app.buttons["nova.destination.\(route)"].isEnabled)
        }
        tap("nova.panel.close"); visible("home")
    }

    func testAccountResetClearsModalAndChildStateAndRejectsStaleCallback() {
        launch()
        tap("qa.counter"); XCTAssertTrue(app.buttons["qa.counter"].label.contains("1"))
        tap("qa.capture"); tap("nova.notifications"); tap("nova.notices.center"); tap("nova.add")
        tap("qa.reset")
        visible("home")
        XCTAssertFalse(app.buttons["nova.panel.close"].exists)
        XCTAssertTrue(app.buttons["qa.counter"].label.contains("0"))
        tap("qa.replay"); visible("home")
        XCTAssertTrue(app.staticTexts["qa.state"].label.contains("synthetic-b"))
    }

    func testRevocationUnwindsAnExistingNativeStack() {
        launch(["--stack"])
        visible("documents")
        tap("nova.back"); visible("memory")
        tap("qa.revoke"); visible("home")
        XCTAssertFalse(app.buttons["nova.back"].exists)
    }

    func testHostHidesContentDuringRefreshAndRejectsPreviousAccountResponse() {
        launch()
        visible("home")
        tap("qa.host.refresh")
        XCTAssertTrue(app.staticTexts["qa.host.unavailable"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["nova.menu"].exists)
        tap("qa.reset")
        visible("home")
        XCTAssertFalse(app.buttons["nova.tab.companies"].isEnabled)
        tap("qa.host.deliver")
        visible("home")
        XCTAssertTrue(app.staticTexts["qa.state"].label.contains("synthetic-b"))
        XCTAssertFalse(app.buttons["nova.tab.companies"].isEnabled)
        XCTAssertFalse(app.buttons["nova.notifications"].isEnabled)
    }

    func testLargeTypeCompactDrawerAndHorizontalTabReachability() {
        launch(["--compact", "--ax3", "--dark"])
        visible("home")
        screenshot("hosted-compact-ax3-home")
        tap("nova.menu")
        XCTAssertTrue(app.buttons["nova.panel.close"].isHittable)
        choose("notifications")
        XCTAssertTrue(app.buttons["nova.back"].isHittable)
        tap("nova.back"); visible("home")
        let profile = app.buttons["nova.tab.profile"]
        for _ in 0..<8 {
            if profile.exists && profile.isHittable { break }
            app.scrollViews.matching(identifier: "nova.tabs.scroll").firstMatch.swipeLeft()
        }
        tap("nova.tab.profile"); visible("profile")
        screenshot("hosted-compact-ax3-profile")
    }

    func testControlTargetsAndDrawerOutsideDismiss() {
        launch()
        for id in ["nova.menu", "nova.notifications", "nova.profile", "nova.tab.home", "nova.tab.findings", "nova.add", "nova.tab.companies", "nova.tab.profile"] {
            let frame = app.buttons[id].frame
            XCTAssertGreaterThanOrEqual(frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(frame.height, 44, id)
        }
        tap("nova.menu")
        let close = app.buttons["nova.panel.close"]
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        let window = app.windows.firstMatch.frame
        // Right edge is outside the 90%-width drawer; derive position from the actual test window.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.maxX - 4, dy: window.midY)).tap()
        XCTAssertFalse(close.exists)
        visible("home")
    }
}
