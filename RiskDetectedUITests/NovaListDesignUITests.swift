import XCTest

final class NovaListDesignUITests: XCTestCase {
    func testRiskCompanySearchStatusAndReset() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_RISK_LIST"]
        app.launch(); defer { app.terminate() }
        let row = app.buttons["nova.risk.row.00000000-0000-4000-8000-000000000004"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let expired = app.buttons["nova.risk.stat.expired"]
        let current = app.buttons["nova.risk.stat.current"]
        XCTAssertEqual(expired.frame.minY, current.frame.minY, accuracy: 1)
        XCTAssertLessThan(expired.frame.height, 100)
        capture(app, "risk-list")
        app.buttons["nova.risk.chooser.company"].tap()
        let search = app.textFields["nova.risk.panel.company.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("bilinmeyen")
        let other = app.buttons["nova.risk.panel.company.00000000-0000-4000-8000-000000000004"]
        XCTAssertTrue(other.exists)
        XCTAssertFalse(app.buttons["nova.risk.panel.company.00000000-0000-4000-8000-000000000003"].exists)
        capture(app, "company-search")
        other.tap()
        XCTAssertFalse(search.exists)
        XCTAssertTrue(app.staticTexts["Kayıt yok"].waitForExistence(timeout: 5))
        app.buttons["nova.risk.chooser.company"].tap()
        app.buttons["nova.risk.panel.company.all"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.buttons["nova.risk.chooser.state"].tap()
        capture(app, "status-filter")
        app.buttons["nova.risk.panel.state.expired"].tap()
        XCTAssertTrue(app.staticTexts["Kayıt yok"].waitForExistence(timeout: 5))
        app.buttons["nova.risk.chooser.state"].tap()
        app.buttons["nova.risk.panel.state.all"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testEmergencyCompactHeadingAndCounters() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_EMERGENCY_LIST"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Plan Ekle"].waitForExistence(timeout: 20))
        let expired = app.buttons["nova.emergency.stat.expired"]
        XCTAssertTrue(expired.waitForExistence(timeout: 5))
        XCTAssertEqual(expired.frame.minY, app.buttons["nova.emergency.stat.current"].frame.minY, accuracy: 1)
        capture(app, "emergency-list")
        app.buttons["nova.emergency.chooser.company"].tap()
        XCTAssertTrue(app.textFields["nova.emergency.panel.company.search"].exists)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
