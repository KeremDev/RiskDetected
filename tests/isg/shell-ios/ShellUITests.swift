import XCTest

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

    private func launchDesign(_ args: [String] = []) {
        app = XCUIApplication(bundleIdentifier: "com.riskdetected.isgshellharness")
        app.launchArguments = ["--design"] + args
        app.launch()
        XCTAssertTrue(app.buttons["nova.menu"].waitForExistence(timeout: 8))
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
        }
        for route in ["newFinding", "newDocument", "newVisit", "newTraining"] {
            home(); tap("nova.add")
            if route == "newFinding" { screenshot(dark ? "hosted-add-dark" : "hosted-add-light") }
            choose(route)
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
