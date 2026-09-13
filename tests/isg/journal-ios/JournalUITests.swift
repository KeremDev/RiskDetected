import XCTest
@MainActor final class JournalUITests: XCTestCase {
    func testActualKeychainSurvivesProcessRestartAndCoreReconciles() {
        let app = XCUIApplication(bundleIdentifier:"com.riskdetected.isgjournalharness")
        app.launchArguments = ["--write"]; app.launch()
        let result = app.staticTexts["journal.result"]
        XCTAssertTrue(result.waitForExistence(timeout:10))
        let ready = NSPredicate(format:"label BEGINSWITH 'PASS'")
        expectation(for:ready,evaluatedWith:result); waitForExpectations(timeout:10)
        XCTAssertTrue(result.label.contains("durable-write"),result.label)
        app.terminate()
        app.launchArguments = ["--read"]; app.launch()
        XCTAssertTrue(result.waitForExistence(timeout:10))
        expectation(for:ready,evaluatedWith:result); waitForExpectations(timeout:10)
        XCTAssertTrue(result.label.contains("restart-rebind"),result.label)
        app.terminate()
    }
}
