import XCTest

final class NovaKeyboardDismissUITests: XCTestCase {
    func testNumberPadDismissesInRiskPopupAndPreservesValue() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_RISK_POPUP", "RD_UI_TEST_POPUP_SELECTED", "RD_UI_TEST_POPUP_NEW"]
        app.launch(); defer { app.terminate() }
        let years = app.textFields["risk.quick.years"]
        XCTAssertTrue(years.waitForExistence(timeout: 20))
        years.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        years.typeText("3")
        let enteredValue = years.value as? String
        // A non-input label exercises the same background tap as blank form spacing.
        app.staticTexts["Risk değerlendirmesi ekle"].tap()
        assertKeyboardHidden(app)
        XCTAssertEqual(years.value as? String, enteredValue)
        years.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        years.typeText("4")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        // The same tap must continue to activate a button rather than being consumed.
        app.buttons["chevron.left"].tap()
        XCTAssertTrue(app.buttons["Çık"].waitForExistence(timeout: 5))
        app.buttons["Çık"].tap()
        XCTAssertFalse(years.exists)
        assertKeyboardHidden(app)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testPageSearchAndAnotherInputKeepWorking() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_RISK_LIST"]
        app.launch(); defer { app.terminate() }
        let search = app.textFields["nova.risk.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap(); search.typeText("Metal")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.staticTexts["Risk Değerlendirmesi"].tap()
        assertKeyboardHidden(app)
        XCTAssertEqual(search.value as? String, "Metal")
        app.buttons["nova.risk.chooser.company"].tap()
        let companySearch = app.textFields["nova.risk.panel.company.search"]
        XCTAssertTrue(companySearch.waitForExistence(timeout: 5))
        companySearch.tap(); companySearch.typeText("Örnek")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["nova.risk.panel.company.00000000-0000-4000-8000-000000000003"].tap()
        assertKeyboardHidden(app)
        XCTAssertFalse(companySearch.exists)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }
    private func assertKeyboardHidden(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed, file: file, line: line)
    }
}
