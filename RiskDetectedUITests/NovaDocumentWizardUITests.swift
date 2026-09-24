import XCTest

final class NovaDocumentWizardUITests: XCTestCase {
    /// V6 risk wizard: one question per page, no company required, ends on the result page with exports.
    func testRiskWizardReachesResultWithoutCompany() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_RISK_LIST"]
        app.launch(); defer { app.terminate() }
        let start = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sihirbaz ile")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 30)); start.tap()
        let next = app.buttons["riskWizard.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 20)); next.tap()
        let sector = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Su kuyusu sondajı")).firstMatch
        XCTAssertTrue(sector.waitForExistence(timeout: 10)); sector.tap()
        for _ in 0..<30 {
            guard next.waitForExistence(timeout: 5) else { break }
            let generate = next.label.contains("Analizi oluştur")
            next.tap()
            if generate { break }
        }
        XCTAssertTrue(app.buttons["riskWizard.excel"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Word"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    /// V6 emergency plan wizard: same questions, then scenarios, teams and site facts; ends on the plan page.
    func testEmergencyWizardReachesPlanWithoutCompany() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_EMERGENCY_LIST"]
        app.launch(); defer { app.terminate() }
        let start = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Sihirbaz ile")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 30)); start.tap()
        let employees = app.textFields["emergencyWizard.employees"]
        XCTAssertTrue(employees.waitForExistence(timeout: 20)); employees.tap(); employees.typeText("65")
        let next = app.buttons["riskWizard.next"]
        next.tap()
        let sector = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Akaryakıt istasyonu")).firstMatch
        let search = app.textFields["riskWizard.sectorSearch"]
        if !sector.waitForExistence(timeout: 5), search.exists { search.tap(); search.typeText("akaryakıt") }
        XCTAssertTrue(sector.waitForExistence(timeout: 10)); sector.tap()
        var sawCards = false
        for _ in 0..<30 {
            guard next.waitForExistence(timeout: 5) else { break }
            if app.buttons["emergencyWizard.card.AD-001"].exists { sawCards = true }
            let generate = next.label.contains("Planı oluştur")
            next.tap()
            if generate { break }
        }
        XCTAssertTrue(sawCards, "the scenario page lists the core fire scenario")
        XCTAssertTrue(app.buttons["emergencyWizard.docx"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["emergencyWizard.cards"].exists)
        XCTAssertFalse(app.buttons["emergencyWizard.save"].isEnabled, "saving needs a company")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }
}
