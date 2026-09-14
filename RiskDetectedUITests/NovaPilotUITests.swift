import XCTest

final class NovaPilotUITests: XCTestCase {
    func testVisualCompanyFormsResizeWithoutWriting() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        app.buttons["company.edit"].tap()
        let toggle = app.switches["Sorumlu personel"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let before = app.buttons["nova.popup.close"].frame.minY
        toggle.tap()
        XCTAssertTrue(app.textFields["Ad soyad"].waitForExistence(timeout: 5))
        XCTAssertLessThan(app.buttons["nova.popup.close"].frame.minY, before)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "NOVA-dynamic-company-preview"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["nova.popup.close"].tap()
        app.buttons["company.delete"].tap()
        XCTAssertTrue(app.buttons["Firmayı sil"].waitForExistence(timeout: 5))
        app.buttons["Firmayı sil"].tap()
        XCTAssertTrue(app.alerts["Tasarım önizlemesi"].waitForExistence(timeout: 5))
        app.alerts.buttons["Tamam"].tap()
        app.buttons["nova.popup.close"].tap()
        XCTAssertTrue(app.buttons["company.edit"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testDirectPersonnelSheetPreservesCompanyAccordion() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        XCTAssertEqual(app.buttons["company.accordion"].value as? String, "Kapalı")
        app.buttons["company.accordion"].tap()
        let section = app.buttons["company.section.personnel"]
        XCTAssertTrue(section.waitForExistence(timeout: 5)); section.tap()
        let create = app.buttons["company.personnel.add"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(app.textFields["personnel.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["personnel.job"].exists)
        XCTAssertTrue(app.buttons["nova.popup.close"].exists)
        let popup = XCTAttachment(screenshot: app.screenshot()); popup.name = "NOVA-centered-personnel-popup"; popup.lifetime = .keepAlways; add(popup)
        app.buttons["nova.popup.close"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertEqual(section.value as? String, "Açık")
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testDirectorySearchAndPersonnelSheet() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        app.buttons["company.accordion"].tap()
        for _ in 0..<5 { if app.buttons["İşyerleri"].exists { break }; app.swipeUp() }
        app.buttons["İşyerleri"].tap()
        XCTAssertTrue(app.textFields["directory.search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Merkez"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["W-hidden-internal-code"].exists)
        XCTAssertTrue(app.buttons["Bilgi geçmişi"].exists)
        let directory = XCTAttachment(screenshot: app.screenshot()); directory.name = "NOVA-compact-directory"; directory.lifetime = .keepAlways; add(directory)
        let search = app.textFields["directory.search"]
        search.tap(); search.typeText("bulunamayan")
        XCTAssertTrue(app.staticTexts["Aramanızla eşleşen kayıt yok."].waitForExistence(timeout: 5))
        app.buttons["directory.back"].tap()
        app.buttons["company.section.personnel"].tap()
        app.buttons["Personeller"].tap()
        let add = app.buttons["personnel.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        XCTAssertTrue(app.textFields["personnel.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["personnel.save"].isEnabled)
        app.buttons["personnel.save"].tap()
        XCTAssertTrue(app.staticTexts["personnel.message"].exists)
        let name = app.textFields["personnel.name"]
        name.tap(); name.typeText("Deneme")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.48)).tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(name.value as? String, "Deneme")
        let form = XCTAttachment(screenshot: app.screenshot()); form.name = "NOVA-personnel-sheet"; form.lifetime = .keepAlways; self.add(form)
        app.buttons["personnel.editor.back"].tap()
        XCTAssertTrue(app.buttons["personnel.add"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testConfirmedCompanySuccessAutoDismisses() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let create = app.buttons["nova.pilot.company.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20)); create.tap()
        let name = app.textFields["nova.pilot.company.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Yeni Firma")
        let sector = app.textFields["nova.pilot.company.sector"]
        sector.tap(); sector.typeText("Metal\n")
        app.buttons["nova.pilot.company.submit"].tap()
        let popup = app.descendants(matching: .any).matching(identifier: "nova.success").firstMatch
        XCTAssertTrue(popup.waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "NOVA-success"; shot.lifetime = .keepAlways; add(shot)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: popup)
        waitForExpectations(timeout: 5)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testCompactCompanyAndPersonnelScreens() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_DARK_MODE"]
        app.launch()
        defer { app.terminate() }
        let create = app.buttons["nova.pilot.company.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Panele dön"].exists)
        let companyRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertGreaterThan(create.frame.minY, companyRow.frame.maxY)
        XCTAssertLessThan(create.frame.minY - companyRow.frame.maxY, 30)
        create.tap()
        let name = app.textFields["nova.pilot.company.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nova.pilot.company.submit"].isEnabled)
        app.buttons["nova.pilot.company.submit"].tap()
        XCTAssertTrue(app.staticTexts["nova.pilot.company.error"].waitForExistence(timeout: 3))
        name.tap(); name.typeText("Yeni Firma")
        XCTAssertTrue(app.buttons["nova.pilot.company.submit"].isEnabled)
        let sector = app.textFields["nova.pilot.company.sector"]
        sector.tap(); sector.typeText("Metal")
        XCTAssertTrue(app.buttons["nova.pilot.company.submit"].isEnabled)
        let form = XCTAttachment(screenshot: app.screenshot()); form.name = "NOVA-company-form"; form.lifetime = .keepAlways; add(form)
        app.buttons["Geri"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Firma Detayı"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Personel · 1")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Sektör · Metal sanayi")).firstMatch.exists)
        let company = XCTAttachment(screenshot: app.screenshot()); company.name = "NOVA-company-summary"; company.lifetime = .keepAlways; add(company)
        app.buttons["company.accordion"].tap()
        app.buttons["company.section.personnel"].tap()
        app.buttons["Personeller"].tap()
        let person = app.buttons["personnel.row.00000000-0000-4000-8000-000000000004"]
        XCTAssertTrue(person.waitForExistence(timeout: 5)); person.tap()
        XCTAssertTrue(app.buttons["personnel.back"].isHittable)
        let archive = app.buttons["personnel.detail.archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5)); archive.tap()
        XCTAssertTrue(app.buttons["personnel.archive.confirm"].waitForExistence(timeout: 5))
        app.buttons["personnel.archive.cancel"].tap()
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }
    func testPilotDesignAndUnavailableCompanyState() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_PILOT", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["nova.pilot.root"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Özet verileri henüz bağlı değil."].exists)
        app.buttons["nova.home.assistant"].tap()
        XCTAssertTrue(app.alerts["NOVA pilot"].waitForExistence(timeout: 5))
        app.alerts.buttons["Tamam"].tap()
        app.buttons["nova.tab.companies"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Yeni tasarım hazır.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nova.pilot.company.create"].exists)
        XCTAssertFalse(app.buttons["Firma ekle / düzenle"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "NOVA-pilot-unavailable-company-state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["nova.tab.profile"].tap()
        XCTAssertTrue(app.staticTexts["NOVA · özel pilot build"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Requires the private NOVA_PILOT_BUILD configuration")
        #endif
    }

    func testNonPilotRetainsLegacyRoot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["root.main"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.otherElements["nova.pilot.root"].exists)
    }
}
