import XCTest

final class NovaPilotUITests: XCTestCase {
    func testCompanyDetailShowsCompactSectionsWithoutTrackingCard() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_LIGHT_MODE"]
        app.launch(); defer { app.terminate() }

        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        XCTAssertTrue(app.staticTexts["Firma Detayı"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Dosya Ekle"].exists)
        XCTAssertFalse(app.buttons["Evrak Takibi"].exists)
        XCTAssertFalse(app.staticTexts["Evrak süreleri"].exists)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Personel,")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["Uygunsuzluk, 1"].waitForExistence(timeout: 8))
        let nonconformities = app.buttons["company.section.nonconformities"]
        XCTAssertTrue(nonconformities.waitForExistence(timeout: 8)); nonconformities.tap()
        XCTAssertTrue(app.descendants(matching: .any)["company.section.nonconformities.stats"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Korkuluk eksik"].exists)

        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "İSGADA-company-detail-summary"
        top.lifetime = .keepAlways
        add(top)

        XCTAssertFalse(app.staticTexts["Firma Takibi"].exists)
        let inspections = app.buttons["company.section.inspections"]
        for _ in 0..<10 where !inspections.exists { app.swipeUp() }
        XCTAssertTrue(inspections.exists); inspections.tap()
        XCTAssertTrue(app.descendants(matching: .any)["company.section.equipment.stats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["company.section.equipment.add"].exists)
        XCTAssertTrue(app.buttons["company.section.equipment.open"].exists)
        XCTAssertFalse(app.staticTexts["Süreçler ve Takip"].exists)

        let bottom = XCTAttachment(screenshot: app.screenshot())
        bottom.name = "İSGADA-company-detail-tracking-bottom"
        bottom.lifetime = .keepAlways
        add(bottom)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testPeriodicControlUsesCompactAccordion() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_PERIODIC", "RD_UI_TEST_LIGHT_MODE"]
        app.launch(); defer { app.terminate() }

        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "equipment.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "equipment.stat.")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Ekipman ekle"].exists)
        XCTAssertTrue(app.buttons["Kontrol süreleri"].exists)
        let addButton = app.buttons["equipment.inspection.new"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 8)); addButton.tap()
        XCTAssertTrue(app.staticTexts["Periyodik kontrol ekle"].waitForExistence(timeout: 8))
        let serials = app.staticTexts.matching(NSPredicate(format: "label == %@", "KRN-001"))
        XCTAssertTrue(serials.firstMatch.waitForExistence(timeout: 8))
        guard let serial = serials.allElementsBoundByIndex.min(by: { $0.frame.minY < $1.frame.minY }) else {
            XCTFail("No equipment choice")
            return
        }
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: serial.frame.midX, dy: serial.frame.midY)).tap()

        let dateButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Tarih Seçici"))
        XCTAssertTrue(dateButtons.firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(dateButtons.count, 2)
        let dates = dateButtons.allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
        let performed = dates[0]
        let due = dates[1]
        XCTAssertLessThan(abs(performed.frame.midY - due.frame.midY), 12)
        XCTAssertLessThanOrEqual(due.frame.maxX, app.frame.maxX - 12)
        XCTAssertTrue(app.staticTexts["2 · Detaylar"].exists)
        XCTAssertTrue(app.staticTexts["3 · Rapor"].exists)
        XCTAssertFalse(app.buttons["Düzenle"].exists)
        XCTAssertFalse(app.buttons["Envanterden çıkar"].exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "İSGADA-periodic-control-accordion"
        shot.lifetime = .keepAlways
        add(shot)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testCompanyCardExposesDirectLogoPickerAndLargePopupCloseTarget() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        app.buttons["company.section.info"].tap()
        XCTAssertTrue(app.buttons["company.logo.picker"].waitForExistence(timeout: 5))
        let logo = XCTAttachment(screenshot: app.screenshot()); logo.name = "İSGADA-company-direct-logo-picker"; logo.lifetime = .keepAlways; add(logo)
        app.buttons["company.edit"].tap()
        let close = app.buttons["nova.popup.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(close.frame.width, 47)
        XCTAssertGreaterThanOrEqual(close.frame.height, 47)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "İSGADA-company-editor"; shot.lifetime = .keepAlways; add(shot)
        close.tap()
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
        let section = app.buttons["company.section.personnel"]
        XCTAssertTrue(section.waitForExistence(timeout: 5)); section.tap()
        XCTAssertTrue(app.textFields["company.personnel.search"].waitForExistence(timeout: 5))
        let create = app.buttons["company.personnel.add"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(app.textFields["personnel.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["personnel.job"].exists)
        XCTAssertTrue(app.buttons["nova.popup.close"].exists)
        let popup = XCTAttachment(screenshot: app.screenshot()); popup.name = "İSGADA-centered-personnel-popup"; popup.lifetime = .keepAlways; add(popup)
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
        let directory = XCTAttachment(screenshot: app.screenshot()); directory.name = "İSGADA-compact-directory"; directory.lifetime = .keepAlways; add(directory)
        let search = app.textFields["directory.search"]
        search.tap(); search.typeText("bulunamayan")
        XCTAssertTrue(app.staticTexts["Aramanızla eşleşen kayıt yok."].waitForExistence(timeout: 5))
        app.buttons["directory.back"].tap()
        app.buttons["company.section.personnel"].tap()
        app.buttons["Tüm personel"].tap()
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
        let form = XCTAttachment(screenshot: app.screenshot()); form.name = "İSGADA-personnel-sheet"; form.lifetime = .keepAlways; self.add(form)
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
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "İSGADA-success"; shot.lifetime = .keepAlways; add(shot)
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
        let form = XCTAttachment(screenshot: app.screenshot()); form.name = "İSGADA-company-form"; form.lifetime = .keepAlways; add(form)
        app.buttons["Geri"].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Firma Detayı"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Personel · 1")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Sektör · Metal sanayi")).firstMatch.exists)
        let company = XCTAttachment(screenshot: app.screenshot()); company.name = "İSGADA-company-summary"; company.lifetime = .keepAlways; add(company)
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
        XCTAssertTrue(app.alerts["İSGADA pilot"].waitForExistence(timeout: 5))
        app.alerts.buttons["Tamam"].tap()
        app.buttons["nova.tab.companies"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Yeni tasarım hazır.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nova.pilot.company.create"].exists)
        XCTAssertFalse(app.buttons["Firma ekle / düzenle"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "İSGADA-pilot-unavailable-company-state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["nova.tab.profile"].tap()
        XCTAssertTrue(app.staticTexts["İSGADA · özel pilot build"].waitForExistence(timeout: 5))
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

/// Screenshot-only audit of the current analysis surfaces. The review build
/// supplies deterministic fixture data and never writes to a live account.
final class NovaDesignAuditUITests: XCTestCase {
    private let analysisID = "00000000-0000-4000-8000-000000000006"

    func testLegacyAnalysisOpensFromSavedFindingsWithoutProjection() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = [
            "RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_AUDIT_ANALYSIS",
            "RD_UI_TEST_LEGACY_ANALYSIS_DETAIL", "RD_UI_TEST_RESULT_HUB_MISSING", "RD_UI_TEST_LIGHT_MODE"
        ]
        app.launch()
        defer { app.terminate() }

        let row = app.buttons["analysis.list.row.\(analysisID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(app.staticTexts["UI Test Saha Analizi"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[
            "Bu eski analiz kayıtlı bulgularından gösteriliyor; bazı ek öneri bölümleri bulunmayabilir."
        ].exists)
        XCTAssertTrue(app.staticTexts["3 Bulgu"].exists)
        XCTAssertTrue(app.staticTexts["2 Görüş"].exists)
        XCTAssertTrue(app.buttons["analysis.detail.select.all"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "İSGADA-legacy-analysis-fallback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testAnalysisResultAndSectionSurfaces() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_AUDIT_ANALYSIS", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }

        let row = app.buttons["analysis.list.row.\(analysisID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        capture(app, name: "01-analysis-list")
        row.tap()
        XCTAssertTrue(app.staticTexts["Analiz Sonucu"].waitForExistence(timeout: 10))
        capture(app, name: "02-analysis-result-risk")
        XCTAssertTrue(app.buttons["analysis.detail.method.fine_kinney"].exists)
        XCTAssertTrue(app.buttons["analysis.detail.select.all"].exists)
        XCTAssertFalse(app.buttons["analysis.detail.section.approved_notebook"].exists)

        let findingMore = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "analysis.finding.", ".more")).firstMatch
        XCTAssertTrue(findingMore.waitForExistence(timeout: 5))
        findingMore.tap()
        XCTAssertTrue(app.staticTexts["Korkuluk eksik"].waitForExistence(timeout: 10))
        capture(app, name: "04-analysis-finding-detail")
        app.buttons["nova.popup.close"].tap()

        for section in ["expert_recommendations", "training_recommendations"] {
            let tab = app.buttons["analysis.detail.section.\(section)"]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing analysis section tab: \(section)")
            tab.tap()
            capture(app, name: "03-analysis-\(section)")
        }
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testFindingDetailSurface() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_AUDIT_FINDING", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }

        let row = app.buttons["nonconformity.row.\(analysisID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        capture(app, name: "05-findings-list")
        row.tap()
        XCTAssertTrue(app.staticTexts["Kayıt detayı"].waitForExistence(timeout: 10))
        capture(app, name: "06-finding-detail")
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    #if NOVA_PILOT_BUILD
    private func capture(_ app: XCUIApplication, name: String, file: StaticString = #filePath, line: UInt = #line) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #endif
}
