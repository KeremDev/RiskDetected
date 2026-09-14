import XCTest

final class NovaStatisticsUITests: XCTestCase {
    func testFiltersChartAndNavigation() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN","RD_UI_TEST_NOVA_REVIEW","RD_UI_TEST_STATISTICS"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["PORTFÖYÜNÜZ"].waitForExistence(timeout: 20))
        capture(app,"statistics-overview")
        app.segmentedControls["nova.statistics.period"].buttons["12 ay"].tap()
        XCTAssertTrue(app.staticTexts["01.10.2025 – 14.09.2026"].waitForExistence(timeout: 5))
        app.swipeUp()
        let annualChart = app.descendants(matching: .any).matching(identifier:"nova.statistics.chart").firstMatch
        XCTAssertTrue(annualChart.waitForExistence(timeout: 5))
        annualChart.swipeLeft()
        capture(app,"statistics-12-months")
        app.swipeDown()
        app.segmentedControls["nova.statistics.period"].buttons["3 ay"].tap()
        XCTAssertTrue(app.staticTexts["01.07.2026 – 14.09.2026"].waitForExistence(timeout: 5))
        app.buttons["nova.statistics.company"].tap()
        app.buttons["Atlas Metal Sanayi"].tap()
        XCTAssertTrue(app.staticTexts["48"].waitForExistence(timeout: 5))
        app.swipeUp()
        let chart = app.descendants(matching: .any).matching(identifier:"nova.statistics.chart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let september = app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Eyl 2026,")).firstMatch
        XCTAssertTrue(september.exists); september.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@", "Eyl 2026 ·")).firstMatch.exists)
        capture(app,"statistics-chart")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Uygunsuzluklar"].waitForExistence(timeout: 5))
        capture(app,"statistics-status")
        let open = app.buttons["Tüm uygunsuzlukları aç"]
        for _ in 0..<3 { if open.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(open.isHittable); open.tap()
        XCTAssertTrue(app.textFields["nonconformity.search"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }
    func testEmptyAndFailureStates() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN","RD_UI_TEST_NOVA_REVIEW","RD_UI_TEST_STATISTICS","RD_UI_TEST_STATISTICS_EMPTY"]
        app.launch()
        XCTAssertTrue(app.staticTexts["PORTFÖYÜNÜZ"].waitForExistence(timeout: 20))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Bu dönemde henüz kayıt yok."].waitForExistence(timeout: 5))
        capture(app,"statistics-empty"); app.terminate()
        app.launchArguments = ["RD_UI_TEST_MAIN","RD_UI_TEST_NOVA_REVIEW","RD_UI_TEST_STATISTICS","RD_UI_TEST_STATISTICS_ERROR"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Veriler alınamadı"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["PORTFÖYÜNÜZ"].exists)
        app.buttons["Tekrar dene"].tap()
        XCTAssertTrue(app.staticTexts["Veriler alınamadı"].waitForExistence(timeout: 5))
        capture(app,"statistics-error")
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name=name; image.lifetime = .keepAlways; add(image)
    }
}
